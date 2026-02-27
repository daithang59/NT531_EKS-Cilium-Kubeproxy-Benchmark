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
CHURN_FLAGS=("-keepalive=false")

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

  local_pod="$(fortio_pod)"

  # ---- Phase 1: Ramp-up (50% QPS) ------------------------------------------
  echo "[S2] Phase 1/4 — RAMP-UP: ${RAMP_SEC}s @ QPS=${QPS_50PCT} CONNS=${BENCH_CONNS}"
  {
    echo "=== Phase 1: RAMP-UP ==="
    echo "Duration: ${RAMP_SEC}s  QPS: ${QPS_50PCT}  Conns: ${BENCH_CONNS}  Keepalive: false"
    echo ""
    kubectl -n "${NS}" exec "${local_pod}" -- \
      fortio load \
        -qps "${QPS_50PCT}" \
        -c "${BENCH_CONNS}" \
        -t "${RAMP_SEC}s" \
        -keepalive=false \
        "${SVC_URL}" 2>&1
  } > "${outdir}/bench_phase1_rampup.log"

  # ---- Phase 2: Sustained high (100% QPS, 2× connections) ------------------
  echo "[S2] Phase 2/4 — SUSTAINED HIGH: ${SUSTAINED_SEC}s @ QPS=${BENCH_QPS} CONNS=${CONNS_HIGH}"
  {
    echo "=== Phase 2: SUSTAINED HIGH ==="
    echo "Duration: ${SUSTAINED_SEC}s  QPS: ${BENCH_QPS}  Conns: ${CONNS_HIGH}  Keepalive: false"
    echo ""
    kubectl -n "${NS}" exec "${local_pod}" -- \
      fortio load \
        -qps "${BENCH_QPS}" \
        -c "${CONNS_HIGH}" \
        -t "${SUSTAINED_SEC}s" \
        -keepalive=false \
        "${SVC_URL}" 2>&1
  } > "${outdir}/bench_phase2_sustained.log"

  # ---- Phase 3: Bursts (150% QPS × N, with rest between) -------------------
  for b in $(seq 1 "${BURST_COUNT}"); do
    echo "[S2] Phase 3/4 — BURST ${b}/${BURST_COUNT}: ${BURST_SEC}s @ QPS=${QPS_150PCT} CONNS=${CONNS_HIGH}"
    {
      echo "=== Phase 3: BURST ${b}/${BURST_COUNT} ==="
      echo "Duration: ${BURST_SEC}s  QPS: ${QPS_150PCT}  Conns: ${CONNS_HIGH}  Keepalive: false"
      echo ""
      kubectl -n "${NS}" exec "${local_pod}" -- \
        fortio load \
          -qps "${QPS_150PCT}" \
          -c "${CONNS_HIGH}" \
          -t "${BURST_SEC}s" \
          -keepalive=false \
          "${SVC_URL}" 2>&1
    } >> "${outdir}/bench_phase3_bursts.log"

    if [[ "${b}" -lt "${BURST_COUNT}" ]]; then
      echo "[S2] Burst rest ${BURST_REST}s..."
      sleep "${BURST_REST}"
    fi
  done

  # ---- Phase 4: Cool-down (50% QPS) ----------------------------------------
  echo "[S2] Phase 4/4 — COOL-DOWN: ${COOLDOWN_SEC}s @ QPS=${QPS_50PCT} CONNS=${BENCH_CONNS}"
  {
    echo "=== Phase 4: COOL-DOWN ==="
    echo "Duration: ${COOLDOWN_SEC}s  QPS: ${QPS_50PCT}  Conns: ${BENCH_CONNS}  Keepalive: false"
    echo ""
    kubectl -n "${NS}" exec "${local_pod}" -- \
      fortio load \
        -qps "${QPS_50PCT}" \
        -c "${BENCH_CONNS}" \
        -t "${COOLDOWN_SEC}s" \
        -keepalive=false \
        "${SVC_URL}" 2>&1
  } > "${outdir}/bench_phase4_cooldown.log"

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