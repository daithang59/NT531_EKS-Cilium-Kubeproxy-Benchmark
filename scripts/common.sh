#!/usr/bin/env bash
# ==============================================================================
# common.sh — Shared library for all benchmark scripts
# ==============================================================================
# Sources this file from run_s1.sh / run_s2.sh / run_s3.sh.
# Provides:
#   - Environment variable defaults & validation (MODE, SCENARIO, LOAD, REPEAT)
#   - Fail-fast pre-checks (kubectl context, workload pods)
#   - OUTDIR auto-creation following Results Contract
#   - Standardised Fortio execution (run_fortio)
#   - Evidence collection helpers (collect_meta, collect_hubble, write_checklist)
#   - metadata.json generation from template
# ==============================================================================
set -euo pipefail

# ======================== Repo root detection =================================
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ======================== Tunables / Env Vars =================================
NS="${NS:-netperf}"

# MODE: A = kube-proxy baseline | B = Cilium eBPF kube-proxy replacement
MODE="${MODE:-A}"

# SCENARIO: S1 | S2 | S3 (set by each run_s*.sh)
SCENARIO="${SCENARIO:-S1}"

# LOAD: L1 (light) | L2 (medium) | L3 (high)
LOAD="${LOAD:-L1}"

# REPEAT: how many runs per (mode × scenario × load) combination
REPEAT="${REPEAT:-3}"

# Timing
WARMUP_SEC="${WARMUP_SEC:-30}"
DURATION_SEC="${DURATION_SEC:-120}"
REST_BETWEEN_RUNS="${REST_BETWEEN_RUNS:-30}"

# ---- Load-level profiles (Fortio params) -------------------------------------
# L1 — Light: low concurrency, moderate QPS
L1_QPS="${L1_QPS:-100}"
L1_CONNS="${L1_CONNS:-8}"
L1_THREADS="${L1_THREADS:-2}"

# L2 — Medium: higher concurrency + QPS
L2_QPS="${L2_QPS:-500}"
L2_CONNS="${L2_CONNS:-32}"
L2_THREADS="${L2_THREADS:-4}"

# L3 — High: near saturation
L3_QPS="${L3_QPS:-1000}"
L3_CONNS="${L3_CONNS:-64}"
L3_THREADS="${L3_THREADS:-8}"

# Target service (ClusterIP)
SVC_URL="${SVC_URL:-http://echo.${NS}.svc.cluster.local/}"

# ======================== Derived / Computed ==================================
MODE_LABEL=""
case "${MODE}" in
  A) MODE_LABEL="A_kube-proxy" ;;
  B) MODE_LABEL="B_cilium-ebpfkpr" ;;
  *)
    echo "[FATAL] Invalid MODE='${MODE}'. Must be A or B." >&2
    exit 1
    ;;
esac

case "${LOAD}" in
  L1) BENCH_QPS="${L1_QPS}"; BENCH_CONNS="${L1_CONNS}"; BENCH_THREADS="${L1_THREADS}" ;;
  L2) BENCH_QPS="${L2_QPS}"; BENCH_CONNS="${L2_CONNS}"; BENCH_THREADS="${L2_THREADS}" ;;
  L3) BENCH_QPS="${L3_QPS}"; BENCH_CONNS="${L3_CONNS}"; BENCH_THREADS="${L3_THREADS}" ;;
  *)
    echo "[FATAL] Invalid LOAD='${LOAD}'. Must be L1, L2, or L3." >&2
    exit 1
    ;;
esac

case "${SCENARIO}" in
  S1|S2|S3) ;; # valid
  *)
    echo "[FATAL] Invalid SCENARIO='${SCENARIO}'. Must be S1, S2, or S3." >&2
    exit 1
    ;;
esac

# ======================== Timestamp helpers ===================================
# ISO-like timestamp in +07:00, safe for directory names (: → -)
ts_dir() {
  TZ="Asia/Ho_Chi_Minh" date +"%Y-%m-%dT%H-%M-%S+07-00"
}
ts_iso() {
  TZ="Asia/Ho_Chi_Minh" date +"%Y-%m-%dT%H:%M:%S+07:00"
}

# ======================== OUTDIR creation =====================================
# Usage: make_outdir <run_number>
# If OUTDIR is already set by caller, use it; otherwise build from contract.
make_outdir() {
  local run_num="${1}"
  if [[ -n "${OUTDIR:-}" ]]; then
    mkdir -p "${OUTDIR}"
    echo "${OUTDIR}"
    return
  fi
  local ts
  ts="$(ts_dir)"
  local dir="${REPO_ROOT}/results/mode=${MODE_LABEL}/scenario=${SCENARIO}/load=${LOAD}/run=R${run_num}_${ts}"
  mkdir -p "${dir}"
  echo "${dir}"
}

# ======================== Fail-fast pre-checks ================================
preflight_checks() {
  echo "========================================"
  echo " Pre-flight checks"
  echo "========================================"

  # 1. kubectl context
  echo -n "[CHECK] kubectl context... "
  if ! kubectl cluster-info &>/dev/null; then
    echo "FAIL"
    echo "[FATAL] kubectl cannot reach cluster. Check kubeconfig / context." >&2
    exit 1
  fi
  echo "OK ($(kubectl config current-context))"

  # 2. Nodes Ready
  echo -n "[CHECK] Nodes Ready... "
  local not_ready
  not_ready=$(kubectl get nodes --no-headers | grep -v ' Ready' | wc -l)
  if [[ "${not_ready}" -gt 0 ]]; then
    echo "FAIL (${not_ready} node(s) not Ready)"
    kubectl get nodes >&2
    exit 1
  fi
  echo "OK"

  # 3. Workload pods Running
  echo -n "[CHECK] echo pod Running... "
  if ! kubectl -n "${NS}" get pod -l app=echo -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
    echo "FAIL"
    echo "[FATAL] echo pod not Running in namespace '${NS}'." >&2
    exit 1
  fi
  echo "OK"

  echo -n "[CHECK] fortio pod Running... "
  if ! kubectl -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
    echo "FAIL"
    echo "[FATAL] fortio pod not Running in namespace '${NS}'." >&2
    exit 1
  fi
  echo "OK"

  # 4. Mode B extras
  if [[ "${MODE}" == "B" ]]; then
    echo -n "[CHECK] cilium status... "
    if ! kubectl -n kube-system exec ds/cilium -- cilium status --brief &>/dev/null; then
      echo "WARN (cilium status failed — continuing)"
    else
      echo "OK"
    fi
  fi

  echo "========================================"
  echo " Config: MODE=${MODE} SCENARIO=${SCENARIO} LOAD=${LOAD} REPEAT=${REPEAT}"
  echo " Fortio: QPS=${BENCH_QPS} CONNS=${BENCH_CONNS} THREADS=${BENCH_THREADS}"
  echo " Timing: warmup=${WARMUP_SEC}s duration=${DURATION_SEC}s rest=${REST_BETWEEN_RUNS}s"
  echo "========================================"
}

# ======================== Fortio helpers ======================================
fortio_pod() {
  kubectl -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}'
}

# run_fortio <outdir> [extra_fortio_flags...]
# Runs warmup + measurement; output goes to <outdir>/bench.log
run_fortio() {
  local outdir="$1"; shift
  local extra_flags=("$@")
  local pod
  pod="$(fortio_pod)"

  echo "[INFO] Warmup ${WARMUP_SEC}s @ QPS=${BENCH_QPS} CONNS=${BENCH_CONNS}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load \
      -qps "${BENCH_QPS}" \
      -c "${BENCH_CONNS}" \
      -t "${WARMUP_SEC}s" \
      "${extra_flags[@]+"${extra_flags[@]}"}" \
      "${SVC_URL}" >/dev/null 2>&1 || true

  echo "[INFO] Measurement ${DURATION_SEC}s @ QPS=${BENCH_QPS} CONNS=${BENCH_CONNS}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load \
      -qps "${BENCH_QPS}" \
      -c "${BENCH_CONNS}" \
      -t "${DURATION_SEC}s" \
      "${extra_flags[@]+"${extra_flags[@]}"}" \
      "${SVC_URL}" \
    2>&1 | tee "${outdir}/bench.log"
}

# ======================== metadata.json generation ============================
write_metadata() {
  local outdir="$1"
  local run_num="${2:-1}"
  local ts_start ts_end
  ts_start="$(ts_iso)"

  # Use the template as base and fill in dynamic fields with sed
  sed \
    -e "s|\"run_id\": \"\"|\"run_id\": \"R${run_num}_$(ts_dir)\"|" \
    -e "s|\"timestamp_start_utc\": \"\"|\"timestamp_start_utc\": \"${ts_start}\"|" \
    -e "s|\"id\": \"A\"|\"id\": \"${MODE}\"|" \
    -e "s|\"name\": \"kube-proxy baseline\"|\"name\": \"${MODE_LABEL}\"|" \
    -e "s|\"id\": \"S1\"|\"id\": \"${SCENARIO}\"|" \
    -e "s|\"id\": \"L1\"|\"id\": \"${LOAD}\"|" \
    -e "s|\"qps\": 0|\"qps\": ${BENCH_QPS}|" \
    -e "s|\"concurrency\": 32|\"concurrency\": ${BENCH_CONNS}|" \
    -e "s|\"duration_seconds\": 120|\"duration_seconds\": ${DURATION_SEC}|" \
    -e "s|\"warmup_seconds\": 60|\"warmup_seconds\": ${WARMUP_SEC}|" \
    -e "s|\"output_dir\": \"\"|\"output_dir\": \"${outdir}\"|" \
    "${REPO_ROOT}/results/metadata.template.json.txt" \
    > "${outdir}/metadata.json"

  echo "[INFO] metadata.json written to ${outdir}"
}

# ======================== Evidence collection =================================

# collect_meta <outdir>
# Dumps kubectl state into standard artifact files
collect_meta() {
  local outdir="$1"

  echo "[INFO] Collecting kubectl evidence..."

  # kubectl get all -A
  kubectl get all -A > "${outdir}/kubectl_get_all.txt" 2>&1 || true

  # kubectl top nodes
  if kubectl top nodes > "${outdir}/kubectl_top_nodes.txt" 2>&1; then
    :
  else
    echo "metrics-server not available — kubectl top nodes returned error" > "${outdir}/kubectl_top_nodes.txt"
  fi

  # Events sorted by creation timestamp
  kubectl get events -A --sort-by=.metadata.creationTimestamp > "${outdir}/events.txt" 2>&1 || true

  echo "[INFO] kubectl evidence collected in ${outdir}"
}

# collect_cilium_hubble <outdir>
# For Mode B or S3: collect cilium/hubble status + flows
collect_cilium_hubble() {
  local outdir="$1"

  if [[ "${MODE}" == "A" && "${SCENARIO}" != "S3" ]]; then
    echo "[INFO] Mode A + non-S3 — skipping cilium/hubble collection"
    return 0
  fi

  echo "[INFO] Collecting Cilium/Hubble evidence..."

  # cilium status
  if kubectl -n kube-system exec ds/cilium -- cilium status > "${outdir}/cilium_status.txt" 2>&1; then
    echo "[INFO] cilium_status.txt written"
  else
    echo "cilium status failed or not available" > "${outdir}/cilium_status.txt"
    echo "[WARN] cilium status failed"
  fi

  # hubble status
  if command -v hubble &>/dev/null; then
    hubble status > "${outdir}/hubble_status.txt" 2>&1 || echo "hubble status failed" > "${outdir}/hubble_status.txt"
    echo "[INFO] hubble_status.txt written"
  elif kubectl -n kube-system exec ds/cilium -- cilium hubble status > "${outdir}/hubble_status.txt" 2>&1; then
    echo "[INFO] hubble_status.txt written (via cilium pod)"
  else
    echo "hubble not available" > "${outdir}/hubble_status.txt"
    echo "[WARN] hubble status not available"
  fi

  # hubble flows (last 5000 in namespace, jsonpb format)
  if command -v hubble &>/dev/null; then
    hubble observe --namespace "${NS}" --last 5000 -o jsonpb > "${outdir}/hubble_flows.jsonl" 2>&1 || true
    echo "[INFO] hubble_flows.jsonl written"
  elif kubectl -n kube-system exec ds/cilium -- cilium hubble observe --namespace "${NS}" --last 5000 -o jsonpb > "${outdir}/hubble_flows.jsonl" 2>&1; then
    echo "[INFO] hubble_flows.jsonl written (via cilium pod)"
  else
    echo "[WARN] hubble observe failed — hubble_flows.jsonl may be empty"
    echo "hubble observe not available" > "${outdir}/hubble_flows.jsonl"
  fi
}

# ======================== Checklist generation ================================
write_checklist() {
  local outdir="$1"
  local run_num="${2:-1}"

  cat > "${outdir}/checklist.txt" <<CHECKLIST
# Run Checklist — auto-generated $(ts_iso)
# Mode=${MODE_LABEL} Scenario=${SCENARIO} Load=${LOAD} Run=R${run_num}
# Runner / Checker: đánh [x] để xác nhận

## Pre-run
- [ ] kubectl context active and correct cluster
- [ ] All nodes Ready (kubectl get nodes)
- [ ] Workload pods Running (echo + fortio in namespace ${NS})
- [ ] Service reachable from fortio pod

## Configuration
- [ ] MODE=${MODE} matches expected
- [ ] SCENARIO=${SCENARIO} matches expected
- [ ] LOAD=${LOAD} matches expected
- [ ] REPEAT=${REPEAT} — this is run R${run_num}

## Stability
- [ ] No pod restarts during run
- [ ] No node NotReady events during run
- [ ] No OOM kills during run

## Artifacts present
- [ ] bench.log exists and non-empty
- [ ] metadata.json exists and valid JSON
- [ ] kubectl_get_all.txt exists
- [ ] kubectl_top_nodes.txt exists
- [ ] events.txt exists
- [ ] (Mode B / S3) cilium_status.txt exists
- [ ] (Mode B / S3) hubble_status.txt exists
- [ ] (Mode B / S3) hubble_flows.jsonl exists

## Post-run
- [ ] No anomalies noted (or documented in metadata.json → results.anomalies)
CHECKLIST
  echo "[INFO] checklist.txt written to ${outdir}"
}

# ======================== Full single-run pipeline ============================
# execute_run <run_number> [extra_fortio_flags...]
# Orchestrates: outdir → metadata → preflight → fortio → evidence → checklist
execute_run() {
  local run_num="$1"; shift
  local extra_flags=("$@")

  local outdir
  outdir="$(make_outdir "${run_num}")"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Run R${run_num} — MODE=${MODE_LABEL} SCENARIO=${SCENARIO} LOAD=${LOAD}"
  echo "║  Output: ${outdir}"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  write_metadata "${outdir}" "${run_num}"
  collect_meta "${outdir}"
  run_fortio "${outdir}" "${extra_flags[@]+"${extra_flags[@]}"}"
  collect_cilium_hubble "${outdir}"
  write_checklist "${outdir}" "${run_num}"

  echo "[INFO] Run R${run_num} complete. Artifacts in: ${outdir}"
}

# ======================== Summary =============================================
echo "[common.sh] Loaded — MODE=${MODE} SCENARIO=${SCENARIO} LOAD=${LOAD} REPEAT=${REPEAT}"