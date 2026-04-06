#!/usr/bin/env bash
# ==============================================================================
# cluster_power.sh — Pause/Resume EKS benchmark cluster safely
# ==============================================================================
# Why this script exists:
# - Managed nodegroup names can be auto-generated (not always "benchmark")
# - Scaling to zero can be blocked by CoreDNS PDB during drain
#
# Actions:
#   ./scripts/cluster_power.sh pause
#   ./scripts/cluster_power.sh resume
#   ./scripts/cluster_power.sh status
#
# Optional env vars:
#   CLUSTER_NAME=nt531-bm
#   AWS_REGION=ap-southeast-1
#   NODEGROUP=<explicit-nodegroup-name>
#   TARGET_NODES=3                 # used when no state file exists for resume
#   RESUME_MIN/RESUME_MAX/RESUME_DESIRED
#   STATE_FILE=<custom-state-path>
#   COREDNS_NS=kube-system
#   COREDNS_DEPLOY=coredns
# ============================================================================== 
set -euo pipefail

ACTION="${1:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_NAME="${CLUSTER_NAME:-nt531-bm}"
AWS_REGION="${AWS_REGION:-ap-southeast-1}"
NODEGROUP="${NODEGROUP:-}"
TARGET_NODES="${TARGET_NODES:-3}"
COREDNS_NS="${COREDNS_NS:-kube-system}"
COREDNS_DEPLOY="${COREDNS_DEPLOY:-coredns}"
STATE_DIR="${STATE_DIR:-${REPO_ROOT}/results/ops}"
STATE_FILE="${STATE_FILE:-${STATE_DIR}/cluster_power_${CLUSTER_NAME}.env}"

log() {
  echo "[cluster_power] $*"
}

warn() {
  echo "[cluster_power][WARN] $*" >&2
}

fatal() {
  echo "[cluster_power][FATAL] $*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/cluster_power.sh pause
  ./scripts/cluster_power.sh resume
  ./scripts/cluster_power.sh status

Examples:
  ./scripts/cluster_power.sh pause
  ./scripts/cluster_power.sh resume
  CLUSTER_NAME=nt531-bm AWS_REGION=ap-southeast-1 ./scripts/cluster_power.sh status
USAGE
}

require_cmd() {
  local cmd
  for cmd in "$@"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      fatal "Missing required command: ${cmd}"
    fi
  done
}

ensure_kubectl_connectivity() {
  if ! kubectl cluster-info >/dev/null 2>&1; then
    fatal "kubectl cannot reach cluster. Check kubeconfig/context before running this action."
  fi
}

list_nodegroups() {
  local out
  out="$(aws eks list-nodegroups \
    --cluster-name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'nodegroups[]' \
    --output text 2>/dev/null || true)"

  if [[ -z "${out}" || "${out}" == "None" ]]; then
    return 0
  fi

  # Output can be tab-separated; normalize to one-per-line.
  tr '\t' '\n' <<< "${out}" | sed '/^$/d'
}

resolve_nodegroup() {
  local groups=()
  mapfile -t groups < <(list_nodegroups)

  if [[ "${#groups[@]}" -eq 0 ]]; then
    fatal "No managed nodegroups found in cluster ${CLUSTER_NAME}."
  fi

  if [[ -n "${NODEGROUP}" ]]; then
    local found=0
    local ng
    for ng in "${groups[@]}"; do
      if [[ "${ng}" == "${NODEGROUP}" ]]; then
        found=1
        break
      fi
    done
    if [[ "${found}" -eq 0 ]]; then
      fatal "NODEGROUP=${NODEGROUP} not found. Available: ${groups[*]}"
    fi
    return 0
  fi

  if [[ "${#groups[@]}" -gt 1 ]]; then
    fatal "Multiple nodegroups found (${groups[*]}). Set NODEGROUP explicitly."
  fi

  NODEGROUP="${groups[0]}"
}

read_scaling_config() {
  aws eks describe-nodegroup \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}" \
    --query 'nodegroup.scalingConfig.[minSize,maxSize,desiredSize]' \
    --output text
}

get_coredns_replicas() {
  kubectl -n "${COREDNS_NS}" get deploy "${COREDNS_DEPLOY}" -o jsonpath='{.spec.replicas}' 2>/dev/null || true
}

save_state() {
  local prev_min="$1"
  local prev_max="$2"
  local prev_desired="$3"
  local prev_coredns="$4"

  mkdir -p "${STATE_DIR}"
  cat > "${STATE_FILE}" <<EOF
STATE_CLUSTER_NAME=${CLUSTER_NAME}
STATE_AWS_REGION=${AWS_REGION}
STATE_NODEGROUP=${NODEGROUP}
STATE_PREV_MIN=${prev_min}
STATE_PREV_MAX=${prev_max}
STATE_PREV_DESIRED=${prev_desired}
STATE_PREV_COREDNS_REPLICAS=${prev_coredns}
STATE_SAVED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

  log "Saved state: ${STATE_FILE}"
}

scale_coredns() {
  local replicas="$1"

  if ! kubectl -n "${COREDNS_NS}" get deploy "${COREDNS_DEPLOY}" >/dev/null 2>&1; then
    warn "CoreDNS deployment not found (${COREDNS_NS}/${COREDNS_DEPLOY}); skipping CoreDNS scaling."
    return 0
  fi

  log "Scaling CoreDNS to replicas=${replicas}"
  kubectl -n "${COREDNS_NS}" scale deploy "${COREDNS_DEPLOY}" --replicas="${replicas}"
  kubectl -n "${COREDNS_NS}" rollout status deploy "${COREDNS_DEPLOY}" --timeout=10m
}

wait_nodes_ready() {
  local target_ready="$1"
  local timeout_sec="$2"

  if [[ "${target_ready}" -le 0 ]]; then
    return 0
  fi

  local started elapsed total ready
  started="$(date +%s)"

  while true; do
    total="$(kubectl get nodes --no-headers 2>/dev/null | sed '/^$/d' | wc -l | tr -d ' ' || true)"
    ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 ~ /^Ready/ {c++} END {print c+0}' || true)"

    if [[ -z "${total}" ]]; then total=0; fi
    if [[ -z "${ready}" ]]; then ready=0; fi

    if [[ "${ready}" -ge "${target_ready}" && "${total}" -ge "${target_ready}" ]]; then
      log "Node readiness reached (${ready}/${total} ready)."
      return 0
    fi

    elapsed=$(( $(date +%s) - started ))
    if [[ "${elapsed}" -ge "${timeout_sec}" ]]; then
      warn "Timed out waiting nodes ready (target=${target_ready}, ready=${ready}, total=${total})."
      return 1
    fi

    sleep 10
  done
}

pause_cluster() {
  require_cmd aws kubectl
  ensure_kubectl_connectivity
  resolve_nodegroup

  local prev_min prev_max prev_desired prev_coredns
  read -r prev_min prev_max prev_desired < <(read_scaling_config)
  prev_coredns="$(get_coredns_replicas)"

  if [[ -z "${prev_coredns}" ]]; then
    prev_coredns=2
  fi

  log "Cluster=${CLUSTER_NAME} Region=${AWS_REGION} Nodegroup=${NODEGROUP}"
  log "Current scaling: min=${prev_min} max=${prev_max} desired=${prev_desired}"
  log "Current CoreDNS replicas: ${prev_coredns}"

  save_state "${prev_min}" "${prev_max}" "${prev_desired}" "${prev_coredns}"

  # Reduce CoreDNS replicas to avoid PDB blocking nodegroup scale-to-zero.
  if [[ "${prev_coredns}" -gt 1 ]]; then
    scale_coredns 1
  fi

  log "Scaling nodegroup to zero"
  aws eks update-nodegroup-config \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --scaling-config "minSize=0,maxSize=${prev_max},desiredSize=0" \
    --region "${AWS_REGION}" >/dev/null

  aws eks wait nodegroup-active \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}"

  log "Pause complete. Current nodes:"
  kubectl get nodes -o wide || true
}

resume_cluster() {
  require_cmd aws kubectl
  ensure_kubectl_connectivity

  local runtime_nodegroup="${NODEGROUP}"
  local state_nodegroup=""
  local prev_min=""
  local prev_max=""
  local prev_desired=""
  local prev_coredns=""

  if [[ -f "${STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${STATE_FILE}"
    state_nodegroup="${STATE_NODEGROUP:-}"
    prev_min="${STATE_PREV_MIN:-}"
    prev_max="${STATE_PREV_MAX:-}"
    prev_desired="${STATE_PREV_DESIRED:-}"
    prev_coredns="${STATE_PREV_COREDNS_REPLICAS:-}"
  fi

  # Keep CLUSTER_NAME/AWS_REGION from env/default; prefer explicit NODEGROUP if provided.
  if [[ -n "${runtime_nodegroup}" ]]; then
    NODEGROUP="${runtime_nodegroup}"
  elif [[ -n "${state_nodegroup}" ]]; then
    NODEGROUP="${state_nodegroup}"
  fi

  resolve_nodegroup

  local min_size max_size desired_size
  min_size="${RESUME_MIN:-}"
  max_size="${RESUME_MAX:-}"
  desired_size="${RESUME_DESIRED:-}"

  if [[ -z "${min_size}" || -z "${max_size}" || -z "${desired_size}" ]]; then
    if [[ -n "${prev_min}" && -n "${prev_max}" && -n "${prev_desired}" ]]; then
      min_size="${prev_min}"
      max_size="${prev_max}"
      desired_size="${prev_desired}"
    else
      min_size="${TARGET_NODES}"
      max_size="${TARGET_NODES}"
      desired_size="${TARGET_NODES}"
    fi
  fi

  log "Cluster=${CLUSTER_NAME} Region=${AWS_REGION} Nodegroup=${NODEGROUP}"
  log "Resuming scaling: min=${min_size} max=${max_size} desired=${desired_size}"

  aws eks update-nodegroup-config \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --scaling-config "minSize=${min_size},maxSize=${max_size},desiredSize=${desired_size}" \
    --region "${AWS_REGION}" >/dev/null

  aws eks wait nodegroup-active \
    --cluster-name "${CLUSTER_NAME}" \
    --nodegroup-name "${NODEGROUP}" \
    --region "${AWS_REGION}"

  wait_nodes_ready "${desired_size}" 900 || true

  if [[ -z "${prev_coredns}" ]]; then
    prev_coredns=2
  fi

  if [[ "${prev_coredns}" -gt 0 ]]; then
    scale_coredns "${prev_coredns}"
  fi

  log "Resume complete. Current nodes:"
  kubectl get nodes -o wide || true
}

status_cluster() {
  require_cmd aws kubectl

  log "Cluster status"
  aws eks describe-cluster \
    --name "${CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --query 'cluster.{name:name,status:status,version:version}' \
    --output table

  local groups=()
  mapfile -t groups < <(list_nodegroups)

  if [[ "${#groups[@]}" -eq 0 ]]; then
    warn "No managed nodegroups found."
  else
    local ng
    for ng in "${groups[@]}"; do
      echo ""
      log "Nodegroup ${ng}"
      aws eks describe-nodegroup \
        --cluster-name "${CLUSTER_NAME}" \
        --nodegroup-name "${ng}" \
        --region "${AWS_REGION}" \
        --query 'nodegroup.{status:status,desired:scalingConfig.desiredSize,min:scalingConfig.minSize,max:scalingConfig.maxSize,health:health.issues}' \
        --output json
    done
  fi

  if kubectl cluster-info >/dev/null 2>&1; then
    echo ""
    log "Kubernetes nodes"
    kubectl get nodes -o wide || true

    echo ""
    log "CoreDNS and PDB"
    kubectl -n "${COREDNS_NS}" get deploy "${COREDNS_DEPLOY}" -o wide || true
    kubectl get pdb -n "${COREDNS_NS}" -o wide || true
  else
    echo ""
    warn "kubectl context is not reachable in this shell; skipping Kubernetes status section."
  fi

  if [[ -f "${STATE_FILE}" ]]; then
    echo ""
    log "Saved state file: ${STATE_FILE}"
    sed 's/^/[cluster_power][state] /' "${STATE_FILE}"
  fi
}

case "${ACTION}" in
  pause)
    pause_cluster
    ;;
  resume)
    resume_cluster
    ;;
  status)
    status_cluster
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    usage
    fatal "Unknown action: ${ACTION}"
    ;;
esac
