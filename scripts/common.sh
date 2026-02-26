#!/usr/bin/env bash
set -euo pipefail

# ====== Tunables ======
NS="${NS:-netperf}"
MODE="${MODE:-kubeproxy}"          # kubeproxy | ebpfkpr
REPEATS="${REPEATS:-3}"
WARMUP_SEC="${WARMUP_SEC:-10}"
DURATION_SEC="${DURATION_SEC:-30}"

# Load levels (adjust after calibration)
L1_QPS="${L1_QPS:-50}"
L2_QPS="${L2_QPS:-200}"
L3_QPS="${L3_QPS:-500}"

# Fortio connection settings
CONNS="${CONNS:-16}"               # parallel connections
THREADS="${THREADS:-4}"

# Target
SVC_URL="${SVC_URL:-http://echo.${NS}.svc.cluster.local/}"

# ====== Helpers ======
ts() { date +"%Y%m%d-%H%M%S"; }

fortio_pod() {
  kubectl -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}'
}

ensure_dirs() {
  local outdir="$1"
  mkdir -p "${outdir}/grafana"
}

write_metadata() {
  local outdir="$1"
  cat > "${outdir}/metadata.json" <<EOF
{
  "timestamp": "$(ts)",
  "mode": "${MODE}",
  "namespace": "${NS}",
  "svc_url": "${SVC_URL}",
  "repeats": ${REPEATS},
  "warmup_sec": ${WARMUP_SEC},
  "duration_sec": ${DURATION_SEC},
  "l1_qps": ${L1_QPS},
  "l2_qps": ${L2_QPS},
  "l3_qps": ${L3_QPS},
  "conns": ${CONNS},
  "threads": ${THREADS}
}
EOF
}

run_fortio() {
  local qps="$1"
  local outdir="$2"
  local pod
  pod="$(fortio_pod)"

  echo "[INFO] Warmup ${WARMUP_SEC}s @ qps=${qps}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load -qps "${qps}" -c "${CONNS}" -t "${WARMUP_SEC}s" -p "${THREADS}" "${SVC_URL}" >/dev/null

  echo "[INFO] Run ${DURATION_SEC}s @ qps=${qps}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load -qps "${qps}" -c "${CONNS}" -t "${DURATION_SEC}s" -p "${THREADS}" "${SVC_URL}" \
    | tee "${outdir}/bench.log"
}

collect_kubectl_state() {
  local outdir="$1"
  {
    echo "=== kubectl version ==="
    kubectl version --short || true
    echo
    echo "=== nodes ==="
    kubectl get nodes -o wide || true
    echo
    echo "=== pods (netperf) ==="
    kubectl -n "${NS}" get pods -o wide || true
  } > "${outdir}/cluster_state.txt"
}