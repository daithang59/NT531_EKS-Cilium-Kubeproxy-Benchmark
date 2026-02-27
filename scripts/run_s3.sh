#!/usr/bin/env bash
# ==============================================================================
# run_s3.sh — Scenario 3: NetworkPolicy Overhead (off → on)
# ==============================================================================
# Measures the overhead of enabling NetworkPolicy enforcement.
#
# Phase 1 (policy OFF): delete policies → run benchmark (baseline for policy cost)
# Phase 2 (policy ON):  apply policies → run benchmark (measure enforcement overhead)
#
# Evidence goal: show that p95/p99 increases when policy is ON, and hubble flows
# confirm FORWARDED/DROPPED verdicts proving enforcement.
#
# Usage:
#   MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
#
# Environment variables: same as run_s1.sh
# ==============================================================================
set -euo pipefail

export SCENARIO="S3"
source "$(dirname "$0")/common.sh"

preflight_checks

echo ""
echo "=========================================="
echo " S3 — NetworkPolicy Overhead (off → on)"
echo " MODE=${MODE_LABEL}  LOAD=${LOAD}  REPEAT=${REPEAT}"
echo "=========================================="
echo ""

# ---------- Phase OFF: remove policies ----------------------------------------
echo "────────────────────────────────────"
echo " Phase OFF — removing NetworkPolicy"
echo "────────────────────────────────────"
kubectl -n "${NS}" delete -f "${REPO_ROOT}/workload/policies/" --ignore-not-found=true
sleep 5  # settle

for i in $(seq 1 "${REPEAT}"); do
  # Override OUTDIR to include phase
  export OUTDIR="${REPO_ROOT}/results/mode=${MODE_LABEL}/scenario=${SCENARIO}/load=${LOAD}/phase=off/run=R${i}_$(ts_dir)"
  execute_run "${i}"

  if [[ "${i}" -lt "${REPEAT}" ]]; then
    echo "[INFO] Resting ${REST_BETWEEN_RUNS}s..."
    sleep "${REST_BETWEEN_RUNS}"
  fi
done
unset OUTDIR

# ---------- Phase ON: apply policies -----------------------------------------
echo ""
echo "────────────────────────────────────"
echo " Phase ON — applying NetworkPolicy"
echo "────────────────────────────────────"
kubectl apply -f "${REPO_ROOT}/workload/policies/"
sleep 10  # let policy propagate

for i in $(seq 1 "${REPEAT}"); do
  export OUTDIR="${REPO_ROOT}/results/mode=${MODE_LABEL}/scenario=${SCENARIO}/load=${LOAD}/phase=on/run=R${i}_$(ts_dir)"
  execute_run "${i}"

  if [[ "${i}" -lt "${REPEAT}" ]]; then
    echo "[INFO] Resting ${REST_BETWEEN_RUNS}s..."
    sleep "${REST_BETWEEN_RUNS}"
  fi
done
unset OUTDIR

echo ""
echo "[DONE] S3 completed — ${REPEAT} run(s) × 2 phases for MODE=${MODE_LABEL} LOAD=${LOAD}"