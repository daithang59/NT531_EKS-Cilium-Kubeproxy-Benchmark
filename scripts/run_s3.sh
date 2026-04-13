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

# ── Cleanup trap ─────────────────────────────────────────────────────────────
# If the script is interrupted (Ctrl+C) during phase=on, NetworkPolicy remains
# active and blocks all subsequent benchmark runs.  This trap ensures policies
# are deleted on any exit path (normal, error, or signal).
cleanup_s3_policies() {
    echo "[TRAP] Cleaning up NetworkPolicy on exit..."
    kubectl -n "${NS}" delete -f "${REPO_ROOT}/workload/policies/" \
        --ignore-not-found=true >/dev/null 2>&1 || true
    echo "[TRAP] Done."
}
trap cleanup_s3_policies EXIT INT TERM

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
# Wait for Cilium datapath to fully remove policy rules before benchmarking.
# xDP policy removal can take 10-30s depending on node count.
sleep 15  # settle

# Verify no policy rules remain — check on the first cilium pod found.
# If any policy rules are present, the full delete may still be propagating.
echo "[VERIFY] Checking no residual policy enforcement..."
_first_pod="$(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "${_first_pod}" ]]; then
  _policy_lines="$(kubectl -n kube-system exec "${_first_pod}" -- \
    cilium policy get 2>/dev/null | grep -c "reserved:endpoint" || echo "0")"
  _policy_lines="$(echo "${_policy_lines}" | tr -d '[:space:]')"
  if [[ -n "${_policy_lines}" && "${_policy_lines}" -gt 0 ]]; then
    echo "[WARN] Residual policy rules detected (${_policy_lines} lines) — waiting 10s more"
    sleep 10
  else
    echo "[VERIFY] OK — no residual policy enforcement detected"
  fi
else
  echo "[WARN] Could not find cilium pod for verification — continuing"
fi

for i in $(seq 1 "${REPEAT}"); do
  # Override OUTDIR to include phase
  export OUTDIR="${REPO_ROOT}/results/mode=${MODE_LABEL}/scenario=${SCENARIO}/load=${LOAD}/phase=off/run=R${i}_$(ts_dir)"
  # No policy active — POLICY_METADATA unset so write_metadata uses template defaults
  unset POLICY_METADATA
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
# Wait for Cilium to compile and install policy into datapath.
# Policy installation involves xDP program update + conntrack table update.
sleep 20  # let policy propagate

# Verify policy is installed on at least one Cilium agent
echo "[VERIFY] Checking policy enforcement is active..."
if kubectl -n kube-system exec ds/cilium -- \
  cilium policy get 2>/dev/null | grep -q "reserved:endpoint"; then
  echo "[VERIFY] OK — policy enforcement active"
else
  echo "[WARN] cilium policy get returned no rules — policy may not be installed yet"
  echo "[WARN] Continuing anyway (benchmark will reveal if enforcement is active)"
fi

# Auto-count policy files for accurate metadata
POLICY_COUNT=$(find "${REPO_ROOT}/workload/policies/" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
export POLICY_METADATA="enabled=true,type=CiliumNetworkPolicy,complexity_level=simple,rule_count_estimate=${POLICY_COUNT}"
echo "[INFO] Policy metadata: rule_count_estimate=${POLICY_COUNT}"

for i in $(seq 1 "${REPEAT}"); do
  export OUTDIR="${REPO_ROOT}/results/mode=${MODE_LABEL}/scenario=${SCENARIO}/load=${LOAD}/phase=on/run=R${i}_$(ts_dir)"
  execute_run "${i}"

  if [[ "${i}" -lt "${REPEAT}" ]]; then
    echo "[INFO] Resting ${REST_BETWEEN_RUNS}s..."
    sleep "${REST_BETWEEN_RUNS}"
  fi
done
unset OUTDIR
unset POLICY_METADATA

# ---------- Cleanup: remove policies after S3 completes ----------------------
# IMPORTANT: Policies must be absent before running S1/S2 runs.
# Leaving them installed blocks Fortio traffic (ingressDeny: {} denies all).
echo ""
echo "────────────────────────────────────"
echo " Cleanup — removing NetworkPolicy"
echo "────────────────────────────────────"
kubectl -n "${NS}" delete -f "${REPO_ROOT}/workload/policies/" --ignore-not-found=true

echo ""
echo "[DONE] S3 completed — ${REPEAT} run(s) × 2 phases for MODE=${MODE_LABEL} LOAD=${LOAD}"