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

  # NOTE: kubectl exec has a default --request-timeout of 60s on Windows/macOS.
  # Long phases (90s) would be killed at ~60s without --request-timeout=0.
  # keepalive=false + -keepalive=false are intentional: forces new TCP connections
  # per request, stressing conntrack/NAT tables.
  # Fortio JSON output is written to a tmp file in the pod, then copied out via
  # kubectl cp. This avoids the kubectl stream stdout truncation bug (Windows)
  # where long-running exec connections are forcibly closed at the TTY layer
  # after the last Fortio phase completes, truncating early phase logs in bench.log.
  KUBECTL_EXEC_FLAGS=(--request-timeout=0)
  FORTIO_JSON="/tmp/fortio_result.json"

  local_pod="$(fortio_pod)"

  # ---- Phase 1: Ramp-up (50% QPS) ------------------------------------------
  echo "[S2] Phase 1/4 — RAMP-UP: ${RAMP_SEC}s @ QPS=${QPS_50PCT} CONNS=${BENCH_CONNS}"
  {
    echo "=== Phase 1: RAMP-UP ==="
    echo "Duration: ${RAMP_SEC}s  QPS: ${QPS_50PCT}  Conns: ${BENCH_CONNS}  Keepalive: false"
    echo ""
    kubectl -n "${NS}" exec "${local_pod}" "${KUBECTL_EXEC_FLAGS[@]}" -- \
      fortio load \
        -qps "${QPS_50PCT}" \
        -c "${BENCH_CONNS}" \
        -t "${RAMP_SEC}s" \
        -keepalive=false \
        -json "${FORTIO_JSON}" \
        "${SVC_URL}" 2>&1 || true
    # Copy JSON result out of the pod so we have data even if stream truncates
    kubectl -n "${NS}" cp "${local_pod}:${FORTIO_JSON}" "${outdir}/fortio_phase1.json" \
      >/dev/null 2>&1 || true
  } > "${outdir}/bench_phase1_rampup.log"

  # Parse Fortio JSON → human-readable summary into the phase log.
  # If json2报告显示 is missing, the phase log still has the raw Fortio stderr for manual inspection.
  python3 -c "
import json, sys
f = '${outdir}/fortio_phase1.json'
try:
    with open(f) as fh:
        d = json.load(fh)
    run = d.get('RunResult', d.get('Results', {}))
    if not run: sys.exit(0)
    dur = run.get('Duration', 0)
    qps = run.get('RequestedQPS', 0)
    calls = run.get('NumThreads', 0)
    avg = run.get('AvgDuration', 0) * 1000
    pct = run.get('Percentiles', {})
    print(f'Fortio JSON parsed: {dur:.1f}s, qps={qps}, calls={run.get(\"RequestedDuration\",0)}', file=sys.stderr)
    print(f'  avg_ms={avg:.3f}', file=sys.stderr)
    for p in ['50', '75', '90', '99', '99.9']:
        v = pct.get(p, 0)
        if v: print(f'  p{p}={v*1000:.3f}ms', file=sys.stderr)
    print('All done', calls, 'calls', qps, 'qps avg', avg, 'ms', file=sys.stderr)
except: pass
" >> "${outdir}/bench_phase1_rampup.log" 2>/dev/null || true

  # Validate ramp-up output
  if ! grep -qE "All done|^Ended after [0-9.]+s : [0-9]+ calls|^\{[^}]+\"msg\":\"[^\"]+ ended after" "${outdir}/bench_phase1_rampup.log" 2>/dev/null; then
    echo "[WARN] Phase 1 ramp-up did not complete normally — check fortio pod health"
    kubectl -n "${NS}" describe pod "${local_pod}" | tail -20
  fi

  # ---- Phase 2: Sustained high (100% QPS, 2× connections) ------------------
  echo "[S2] Phase 2/4 — SUSTAINED HIGH: ${SUSTAINED_SEC}s @ QPS=${BENCH_QPS} CONNS=${CONNS_HIGH}"
  {
    echo "=== Phase 2: SUSTAINED HIGH ==="
    echo "Duration: ${SUSTAINED_SEC}s  QPS: ${BENCH_QPS}  Conns: ${CONNS_HIGH}  Keepalive: false"
    echo ""
    kubectl -n "${NS}" exec "${local_pod}" "${KUBECTL_EXEC_FLAGS[@]}" -- \
      fortio load \
        -qps "${BENCH_QPS}" \
        -c "${CONNS_HIGH}" \
        -t "${SUSTAINED_SEC}s" \
        -keepalive=false \
        -json "${FORTIO_JSON}" \
        "${SVC_URL}" 2>&1 || true
    kubectl -n "${NS}" cp "${local_pod}:${FORTIO_JSON}" "${outdir}/fortio_phase2.json" \
      >/dev/null 2>&1 || true
  } > "${outdir}/bench_phase2_sustained.log"
  python3 -c "
import json, sys
f = '${outdir}/fortio_phase2.json'
try:
    with open(f) as fh:
        d = json.load(fh)
    run = d.get('RunResult', d.get('Results', {}))
    if not run: sys.exit(0)
    dur = run.get('Duration', 0)
    qps = run.get('RequestedQPS', 0)
    avg = run.get('AvgDuration', 0) * 1000
    cnt = run.get('ActualDuration', 0)
    pct = run.get('Percentiles', {})
    print(f'All done {cnt:.0f} calls ({dur:.0f}s) qps={qps} avg_ms={avg:.3f}', file=sys.stderr)
    for p in ['50', '75', '90', '99', '99.9']:
        v = pct.get(p, 0)
        if v: print(f'  p{p}={v*1000:.3f}ms', file=sys.stderr)
    codes = d.get('RetCodes', {})
    total = sum(codes.values())
    print(f'  Code 200: {codes.get(\"200\",0)} ({100*codes.get(\"200\",0)/total:.1f}%)' if total else '', file=sys.stderr)
except: pass
" >> "${outdir}/bench_phase2_sustained.log" 2>/dev/null || true

  # ---- Phase 3: Bursts (150% QPS × N, with rest between) -------------------
  for b in $(seq 1 "${BURST_COUNT}"); do
    echo "[S2] Phase 3/4 — BURST ${b}/${BURST_COUNT}: ${BURST_SEC}s @ QPS=${QPS_150PCT} CONNS=${CONNS_HIGH}"
    {
      echo "=== Phase 3: BURST ${b}/${BURST_COUNT} ==="
      echo "Duration: ${BURST_SEC}s  QPS: ${QPS_150PCT}  Conns: ${CONNS_HIGH}  Keepalive: false"
      echo ""
      kubectl -n "${NS}" exec "${local_pod}" "${KUBECTL_EXEC_FLAGS[@]}" -- \
        fortio load \
          -qps "${QPS_150PCT}" \
          -c "${CONNS_HIGH}" \
          -t "${BURST_SEC}s" \
          -keepalive=false \
          -json "${FORTIO_JSON}" \
          "${SVC_URL}" 2>&1 || true
      kubectl -n "${NS}" cp "${local_pod}:${FORTIO_JSON}" \
        "${outdir}/fortio_phase3_burst${b}.json" >/dev/null 2>&1 || true
    } >> "${outdir}/bench_phase3_bursts.log"
    python3 -c "
import json, sys
f = '${outdir}/fortio_phase3_burst${b}.json'
try:
    with open(f) as fh:
        d = json.load(fh)
    run = d.get('RunResult', d.get('Results', {}))
    if not run: sys.exit(0)
    dur = run.get('Duration', 0)
    qps = run.get('RequestedQPS', 0)
    avg = run.get('AvgDuration', 0) * 1000
    cnt = run.get('ActualDuration', 0)
    pct = run.get('Percentiles', {})
    print(f'All done {cnt:.0f} calls ({dur:.0f}s) qps={qps} avg_ms={avg:.3f}', file=sys.stderr)
    for p in ['50', '75', '90', '99', '99.9']:
        v = pct.get(p, 0)
        if v: print(f'  p{p}={v*1000:.3f}ms', file=sys.stderr)
    codes = d.get('RetCodes', {})
    total = sum(codes.values())
    print(f'  Code 200: {codes.get(\"200\",0)} ({100*codes.get(\"200\",0)/total:.1f}%)' if total else '', file=sys.stderr)
except: pass
" >> "${outdir}/bench_phase3_bursts.log" 2>/dev/null || true

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
    kubectl -n "${NS}" exec "${local_pod}" "${KUBECTL_EXEC_FLAGS[@]}" -- \
      fortio load \
        -qps "${QPS_50PCT}" \
        -c "${BENCH_CONNS}" \
        -t "${COOLDOWN_SEC}s" \
        -keepalive=false \
        "${SVC_URL}" 2>&1 || true
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