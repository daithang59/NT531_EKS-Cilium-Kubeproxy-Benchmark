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
NS="${NS:-benchmark}"

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
DURATION_SEC="${DURATION_SEC:-180}"
REST_BETWEEN_RUNS="${REST_BETWEEN_RUNS:-60}"

# ---- Load-level profiles (Fortio params) -------------------------------------
# L1 — Light: stable, near-zero errors
# Calibrated Mode A (2026-04-12): QPS=100, p99=0.385ms, err=0%, stable near-zero tail
L1_QPS="${L1_QPS:-100}"
L1_CONNS="${L1_CONNS:-8}"
L1_THREADS="${L1_THREADS:-2}"

# L2 — Medium: visible tail, no saturation
# Calibrated Mode A (2026-04-12): QPS=400, p99=2.11ms, err=0%, visible tail, no saturation
L2_QPS="${L2_QPS:-400}"
L2_CONNS="${L2_CONNS:-32}"
L2_THREADS="${L2_THREADS:-4}"

# L3 — High: near saturation (p99 spike ~15× vs L2)
# Calibrated Mode A (2026-04-12): QPS=800, p99=30-38ms, err=0%, p99 spike approaching saturation
L3_QPS="${L3_QPS:-800}"
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
  not_ready=$(kubectl get nodes --no-headers | grep -v ' Ready' | wc -l | tr -d ' ' || true)
  if [[ -z "${not_ready}" ]]; then not_ready=0; fi
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

  # 4. DNS service contract + in-cluster DNS probe
  check_cluster_dns

  # 5. Mode B extras
  if [[ "${MODE}" == "B" ]]; then
    echo -n "[CHECK] cilium status... "
    if ! kubectl -n kube-system exec ds/cilium -- cilium status --brief &>/dev/null; then
      echo "WARN (cilium status failed — continuing)"
    else
      echo "OK"
    fi
    # B5. kube-proxy MUST be absent for Mode B — silent coexistence corrupts results
    echo -n "[CHECK] kube-proxy absent (Mode B requirement)... "
    if kubectl -n kube-system get ds kube-proxy &>/dev/null; then
      echo "FAIL"
      echo "[FATAL] kube-proxy DaemonSet still exists. Delete it before Mode B:" >&2
      echo "[FATAL]   kubectl delete ds kube-proxy -n kube-system" >&2
      exit 1
    fi
    echo "OK (absent)"
    # B6. Verify live KubeProxyReplacement is enabled
    echo -n "[CHECK] KubeProxyReplacement enabled... "
    local kpr
    kpr="$(kubectl -n kube-system exec ds/cilium -- \
      cilium status --brief 2>/dev/null | grep -i 'kubeproxyreplacement' | awk '{print $2}' || true)"
    if [[ "${kpr}" != "True" && "${kpr}" != "Strict" ]]; then
      echo "WARN (KubeProxyReplacement=${kpr} — expected True/Strict)"
    else
      echo "OK (${kpr})"
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

# check_cluster_dns
# Validates kube-dns service contract and DNS resolution from fortio pod.
check_cluster_dns() {
  echo -n "[CHECK] kube-dns Service contract... "

  local dns_ip dns_ports dns_eps ep_count
  dns_ip="$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  dns_ports="$(kubectl -n kube-system get svc kube-dns -o jsonpath='{range .spec.ports[*]}{.port}{"/"}{.protocol}{"\n"}{end}' 2>/dev/null || true)"
  dns_eps="$(kubectl -n kube-system get endpoints kube-dns -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null || true)"

  if [[ -z "${dns_ip}" ]]; then
    echo "FAIL"
    echo "[FATAL] kube-dns service not found in kube-system." >&2
    exit 1
  fi

  if ! printf '%s\n' "${dns_ports}" | grep -q '^53/UDP$' || ! printf '%s\n' "${dns_ports}" | grep -q '^53/TCP$'; then
    echo "FAIL"
    echo "[FATAL] kube-dns must expose both 53/UDP and 53/TCP. Current ports:" >&2
    printf '%s\n' "${dns_ports}" >&2
    echo "[HINT] kubectl get svc -n kube-system kube-dns -o yaml" >&2
    exit 1
  fi

  ep_count="$(printf '%s\n' "${dns_eps}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${ep_count}" -eq 0 ]]; then
    echo "FAIL"
    echo "[FATAL] kube-dns has no ready endpoints." >&2
    echo "[HINT] kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide" >&2
    exit 1
  fi

  echo "OK (clusterIP=${dns_ip}, endpoints=${ep_count})"

  echo -n "[CHECK] DNS resolution from fortio pod... "
  local pod
  pod="$(fortio_pod)"
  if ! kubectl -n "${NS}" exec "${pod}" --request-timeout=30 -- \
    fortio curl -timeout 5s "http://echo.${NS}.svc.cluster.local:80/echo" >/dev/null 2>&1; then
    echo "FAIL"
    echo "[FATAL] DNS/Service probe failed from fortio pod." >&2
    echo "[HINT] Verify kube-dns/CoreDNS before benchmark." >&2
    exit 1
  fi
  echo "OK"
}

# run_fortio <outdir> [extra_fortio_flags...]
# Runs warmup + measurement; writes <outdir>/bench.log and <outdir>/fortio.json.
#
# FIX (wsarecv race): kubectl exec streaming over SSH/WebSocket on Windows is
# unreliable — the connection gets forcibly closed just as Fortio finishes and
# writes its JSON summary, causing JSON to be lost mid-stream.
#
# Strategy: Delegate to run_fortio_rest.py (same approach as S2/S3).
# The Python script uses subprocess.run(capture_output=True) to capture the REST
# response body in-memory — no shell pipes, no streaming truncation.
run_fortio() {
  local outdir="$1"; shift
  local extra_flags=("$@")  # currently unused; reserved for future flags

  echo "[INFO] Warmup ${WARMUP_SEC}s @ QPS=${BENCH_QPS} CONNS=${BENCH_CONNS}"

  # Warmup via REST API (fast path, no output file needed)
  python3 "${REPO_ROOT}/scripts/run_fortio_rest.py" \
    --pod    "$(fortio_pod)" \
    --ns     "${NS}" \
    --outdir "${outdir}" \
    --phase  "warmup" \
    --qps    "${BENCH_QPS}" \
    --conns  "${BENCH_CONNS}" \
    --duration "${WARMUP_SEC}" \
    --url    "${SVC_URL}" \
    --keepalive false \
    >/dev/null 2>&1 || true
  # Discard warmup artifacts (only keep measurement results)
  rm -f "${outdir}"/bench_warmup.* "${outdir}"/fortio_warmup.* 2>/dev/null || true

  echo "[INFO] Measurement ${DURATION_SEC}s @ QPS=${BENCH_QPS} CONNS=${BENCH_CONNS}"

  # Measurement: reuse run_fortio_rest.py.  It saves:
  #   <outdir>/bench_warmup.log  (warmup — discard)
  #   <outdir>/fortio_warmup.json (warmup — discard)
  #   <outdir>/bench.log          (measurement, human-readable)
  #   <outdir>/fortio.json        (measurement, machine-readable)
  python3 "${REPO_ROOT}/scripts/run_fortio_rest.py" \
    --pod    "$(fortio_pod)" \
    --ns     "${NS}" \
    --outdir "${outdir}" \
    --phase  "measurement" \
    --qps    "${BENCH_QPS}" \
    --conns  "${BENCH_CONNS}" \
    --duration "${DURATION_SEC}" \
    --url    "${SVC_URL}" \
    --keepalive false

  # Rename measurement output to expected names (bench.log + fortio.json)
  if [[ -f "${outdir}/bench_measurement.log" ]]; then
    mv "${outdir}/bench_measurement.log" "${outdir}/bench.log"
  fi
  if [[ -f "${outdir}/fortio_measurement.json" ]]; then
    mv "${outdir}/fortio_measurement.json" "${outdir}/fortio.json"
  fi
}

# ======================== metadata.json generation ============================

write_metadata() {
  local outdir="$1"
  local run_num="${2:-1}"
  local policy_meta="${POLICY_METADATA:-}"

  local policy_flag=()
  if [[ -n "${policy_meta}" ]]; then
    policy_flag=("--policy-metadata" "${policy_meta}")
  fi

  python3 "${REPO_ROOT}/scripts/write_metadata.py" \
    --outdir "${outdir}" \
    --run-num "${run_num}" \
    --mode "${MODE}" \
    --scenario "${SCENARIO}" \
    --load "${LOAD}" \
    --bench-qps "${BENCH_QPS}" \
    --bench-conns "${BENCH_CONNS}" \
    --duration-sec "${DURATION_SEC}" \
    --warmup-sec "${WARMUP_SEC}" \
    "${policy_flag[@]}" \
    --write "${outdir}/metadata.json"

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
  elif kubectl -n kube-system exec ds/cilium -c cilium-agent -- hubble status > "${outdir}/hubble_status.txt" 2>&1; then
    echo "[INFO] hubble_status.txt written (via cilium pod)"
  else
    echo "hubble not available" > "${outdir}/hubble_status.txt"
    echo "[WARN] hubble status not available"
  fi

  # hubble flows collection — 3 methods tried in order of preference:
  # 1. kubectl exec into cilium-agent container (hubble binary IS present in Cilium 1.18.x)
  # 2. kubectl exec exec + hubble observe via unix socket on localhost (port-forward)
  # 3. Give up — write empty placeholder
  _hpod="$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

  if [[ -n "${_hpod}" ]]; then
    # Method 1: exec hubble directly inside cilium-agent container
    if kubectl exec -n kube-system "ds/cilium" -c cilium-agent -- \
      hubble observe --namespace "${NS}" --last 5000 -o jsonpb \
      > "${outdir}/hubble_flows.jsonl" 2>/dev/null; then
      echo "[INFO] hubble_flows.jsonl written (via cilium-agent exec)"
    else
      echo "[WARN] cilium-agent hubble exec failed — trying port-forward"
      # Method 2: port-forward + hubble observe via relay
      local pf_port=4245
      kubectl -n kube-system port-forward svc/hubble-relay "${pf_port}:80" \
        >"${outdir}/hubble_relay_forward.log" 2>&1 &
      local _pf_pid=$!
      sleep 3
      if kill -0 "${_pf_pid}" 2>/dev/null && command -v hubble &>/dev/null; then
        hubble observe --server "localhost:${pf_port}" \
          --namespace "${NS}" --last 5000 -o jsonpb \
          > "${outdir}/hubble_flows.jsonl" 2>&1 || true
        echo "[INFO] hubble_flows.jsonl written (via relay port-forward)"
      else
        echo "hubble not available" > "${outdir}/hubble_flows.jsonl"
        echo "[WARN] hubble collection failed — GitHub download may be unreachable"
      fi
      kill "${_pf_pid}" 2>/dev/null || true
    fi
  else
    echo "hubble not available" > "${outdir}/hubble_flows.jsonl"
    echo "[WARN] Could not find cilium pod for hubble collection"
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