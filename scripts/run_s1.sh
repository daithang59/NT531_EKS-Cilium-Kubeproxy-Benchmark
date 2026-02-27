#!/usr/bin/env bash
# ==============================================================================
# run_s1.sh — Scenario 1: Service Baseline
# ==============================================================================
# Measures baseline latency/throughput through ClusterIP Service.
# No NetworkPolicy; traffic: fortio → echo via Service.
#
# Differs from S2: S1 uses steady-state load (constant QPS/concurrency).
#                   S2 adds ramp-up phases and connection churn.
#
# Usage:
#   MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
#   MODE=B LOAD=L2 REPEAT=5 OUTDIR=/tmp/custom ./scripts/run_s1.sh
#
# Environment variables (all optional, defaults in common.sh):
#   MODE     — A (kube-proxy) or B (Cilium eBPF KPR)
#   LOAD     — L1, L2, or L3
#   REPEAT   — number of runs (default 3)
#   OUTDIR   — override output directory (skips auto-creation)
# ==============================================================================
set -euo pipefail

export SCENARIO="S1"
source "$(dirname "$0")/common.sh"

preflight_checks

echo ""
echo "=========================================="
echo " S1 — Service Baseline"
echo " MODE=${MODE_LABEL}  LOAD=${LOAD}  REPEAT=${REPEAT}"
echo "=========================================="
echo ""

for i in $(seq 1 "${REPEAT}"); do
  execute_run "${i}"

  # Rest between runs (skip after last)
  if [[ "${i}" -lt "${REPEAT}" ]]; then
    echo "[INFO] Resting ${REST_BETWEEN_RUNS}s before next run..."
    sleep "${REST_BETWEEN_RUNS}"
  fi
done

echo ""
echo "[DONE] S1 completed — ${REPEAT} run(s) for MODE=${MODE_LABEL} LOAD=${LOAD}"