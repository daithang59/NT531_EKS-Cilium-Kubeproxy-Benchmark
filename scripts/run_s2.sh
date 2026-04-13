#!/usr/bin/env bash
# ==============================================================================
# run_s2.sh — Scenario 2: High-load + Connection Churn
# ==============================================================================
# PURPOSE:
#   Stress the datapath under high concurrency with connection churn to expose
#   tail-latency differences between Mode A (kube-proxy) and Mode B (Cilium eBPF).
#
# HOW IT DIFFERS FROM S1:
#   S1 = steady-state: constant QPS & concurrency for the full duration.
#   S2 = multi-phase stress profile with connection churn:
#     Phase 1 — RAMP-UP:         30s at 50% target QPS (warm caches/conntrack)
#     Phase 2 — SUSTAINED HIGH:  90s at 100% target QPS, high concurrency
#     Phase 3 — BURST ×3:        3 short 20s bursts at 150% QPS, 10s rest between
#     Phase 4 — COOL-DOWN:       30s at 50% QPS (observe recovery)
#
#   Additionally, S2 disables HTTP keepalive (`-keepalive=false`) to force
#   connection churn: every request opens a new TCP connection, stressing
#   conntrack/NAT/eBPF maps.
#
# WHAT IT MEASURES:
#   - Tail latency (p95/p99) under sustained high load
#   - Error rate / timeouts when connection churn is high
#   - Recovery behaviour after burst phases
#   - Difference between kube-proxy iptables conntrack vs eBPF socket maps
#
# Usage:
#   MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
#   MODE=B LOAD=L3 REPEAT=5 ./scripts/run_s2.sh
#
# Environment variables: same as run_s1.sh (MODE, LOAD, REPEAT, OUTDIR, etc.)
# ==============================================================================
set -euo pipefail

export SCENARIO="S2"
source "$(dirname "$0")/common.sh"

preflight_checks

echo ""
echo "=========================================="
echo " S2 — High-load + Connection Churn"
echo " MODE=${MODE_LABEL}  LOAD=${LOAD}  REPEAT=${REPEAT}"
echo "=========================================="
echo ""

# Churn flag: disable keepalive to force new TCP connections per request
# Passed via keepalive=false in REST API query string

# Derived QPS levels for phases
QPS_50PCT=$(( BENCH_QPS / 2 ))
QPS_150PCT=$(( BENCH_QPS * 3 / 2 ))
CONNS_HIGH=$(( BENCH_CONNS * 2 ))

# Phase durations
RAMP_SEC="${S2_RAMP_SEC:-30}"
SUSTAINED_SEC="${S2_SUSTAINED_SEC:-90}"
BURST_SEC="${S2_BURST_SEC:-20}"
BURST_COUNT="${S2_BURST_COUNT:-3}"
BURST_REST="${S2_BURST_REST:-10}"
COOLDOWN_SEC="${S2_COOLDOWN_SEC:-30}"

# ==============================================================================
# _fortio_rest <outdir> <phase_label> <qps> <conns> <duration_sec>
# Triggers a Fortio load test via REST API and writes formatted results to
# <outdir>/bench_<phase_label>.log
#
# Why REST API instead of `fortio load`?
#   kubectl exec + fortio load: On Windows/macOS the kubectl exec stream
#   gets TTY-truncated after ~60s, producing empty phase logs.
#   The REST API (/fortio/rest/run) streams the full JSON result body
#   in the HTTP response, which is captured cleanly via kubectl exec >
#   file redirection — no TTY stream truncation, no need for kubectl cp.
#
# Fortio server must already be running in the pod (args: ["server"]).
# ==============================================================================
_fortio_rest() {
  local outdir="${1}"; shift
  local phase_label="${1}"; shift   # e.g. "phase1_rampup"
  local qps="${1}"; shift
  local conns="${1}"; shift
  local duration_sec="${1}"; shift  # e.g. "30"

  # Keepalive=false forces new TCP connections per request (connection churn).
  # The Python script handles kubectl exec, JSON parsing, and file writing
  # in-process — avoiding Windows shell redirection and stream interleaving bugs.
  python3 "${REPO_ROOT}/scripts/run_fortio_rest.py" \
    --pod    "$(fortio_pod)" \
    --ns     "${NS}" \
    --outdir "${outdir}" \
    --phase  "${phase_label}" \
    --qps    "${qps}" \
    --conns  "${conns}" \
    --duration "${duration_sec}" \
    --url    "${SVC_URL}" \
    --keepalive false

  # Validate output
  local log_file="${outdir}/bench_${phase_label}.log"
  if ! grep -qE "^All done|^\\[OK\\]" "${log_file}" 2>/dev/null; then
    echo "[WARN] Phase ${phase_label} — no 'All done' in log. Check fortio pod health:"
    kubectl -n "${NS}" describe pod "$(fortio_pod)" | tail -15
  fi
}

# ==============================================================================
for run_num in $(seq 1 "${REPEAT}"); do
  outdir="$(make_outdir "${run_num}")"

  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  Run R${run_num} — S2 Multi-phase Stress + Churn"
  echo "║  Output: ${outdir}"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""

  write_metadata "${outdir}" "${run_num}"
  collect_meta "${outdir}"

  # ---- Phase 1: Ramp-up (50% QPS) ------------------------------------------
  echo "[S2] Phase 1/4 — RAMP-UP: ${RAMP_SEC}s @ QPS=${QPS_50PCT} CONNS=${BENCH_CONNS}"
  _fortio_rest "${outdir}" "phase1_rampup" "${QPS_50PCT}" "${BENCH_CONNS}" "${RAMP_SEC}"

  # ---- Phase 2: Sustained high (100% QPS, 2× connections) ------------------
  echo "[S2] Phase 2/4 — SUSTAINED HIGH: ${SUSTAINED_SEC}s @ QPS=${BENCH_QPS} CONNS=${CONNS_HIGH}"
  _fortio_rest "${outdir}" "phase2_sustained" "${BENCH_QPS}" "${CONNS_HIGH}" "${SUSTAINED_SEC}"

  # ---- Phase 3: Bursts (150% QPS × N, with rest between) -------------------
  for b in $(seq 1 "${BURST_COUNT}"); do
    echo "[S2] Phase 3/4 — BURST ${b}/${BURST_COUNT}: ${BURST_SEC}s @ QPS=${QPS_150PCT} CONNS=${CONNS_HIGH}"
    _fortio_rest "${outdir}" "phase3_burst${b}" "${QPS_150PCT}" "${CONNS_HIGH}" "${BURST_SEC}"

    if [[ "${b}" -lt "${BURST_COUNT}" ]]; then
      echo "[S2] Burst rest ${BURST_REST}s..."
      sleep "${BURST_REST}"
    fi
  done

  # ---- Phase 4: Cool-down (50% QPS) ----------------------------------------
  echo "[S2] Phase 4/4 — COOL-DOWN: ${COOLDOWN_SEC}s @ QPS=${QPS_50PCT} CONNS=${BENCH_CONNS}"
  _fortio_rest "${outdir}" "phase4_cooldown" "${QPS_50PCT}" "${BENCH_CONNS}" "${COOLDOWN_SEC}"

  # ---- Combine all phase logs into bench.log --------------------------------
  cat "${outdir}"/bench_phase*.log > "${outdir}/bench.log"

  # ---- Post-run evidence ----------------------------------------------------
  collect_cilium_hubble "${outdir}"
  write_checklist "${outdir}" "${run_num}"

  echo "[INFO] Run R${run_num} complete. Artifacts in: ${outdir}"

  # Rest between runs
  if [[ "${run_num}" -lt "${REPEAT}" ]]; then
    echo "[INFO] Resting ${REST_BETWEEN_RUNS}s before next run..."
    sleep "${REST_BETWEEN_RUNS}"
  fi
done

echo ""
echo "[DONE] S2 completed — ${REPEAT} run(s) for MODE=${MODE_LABEL} LOAD=${LOAD}"
echo "  Each run had 4 phases: ramp-up → sustained → ${BURST_COUNT}× burst → cool-down"
echo "  Connection churn enabled (keepalive=false)"
