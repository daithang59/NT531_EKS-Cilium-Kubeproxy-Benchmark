#!/usr/bin/env bash
# ==============================================================================
# collect_hubble.sh — Standalone Cilium/Hubble evidence collector
# ==============================================================================
# Collects cilium status, hubble status, and hubble flows for a benchmark run.
# Normally called automatically by common.sh → collect_cilium_hubble(); this
# script exists for ad-hoc/standalone use.
#
# Usage:
#   MODE=B NS=netperf ./scripts/collect_hubble.sh <outdir>
#
# Behavior:
#   - Mode A + non-S3: writes "skipped" and exits 0
#   - Mode B or S3: collects cilium_status.txt, hubble_status.txt, hubble_flows.jsonl
#   - If hubble CLI not found, attempts via cilium pod exec
# ==============================================================================
set -euo pipefail

OUTDIR="${1:?Usage: collect_hubble.sh <outdir>}"
MODE="${MODE:-A}"
SCENARIO="${SCENARIO:-S1}"
NS="${NS:-netperf}"

mkdir -p "${OUTDIR}"

if [[ "${MODE}" == "A" && "${SCENARIO}" != "S3" ]]; then
  echo "[collect_hubble] Mode A + non-S3 — skipping cilium/hubble collection"
  echo "skipped — Mode A, not S3" > "${OUTDIR}/cilium_status.txt"
  exit 0
fi

echo "[collect_hubble] Collecting Cilium/Hubble evidence into ${OUTDIR}..."

# --- cilium status ---
echo "[collect_hubble] cilium status"
if kubectl -n kube-system exec ds/cilium -- cilium status > "${OUTDIR}/cilium_status.txt" 2>&1; then
  echo "[collect_hubble] cilium_status.txt OK"
else
  echo "cilium status failed or not available" > "${OUTDIR}/cilium_status.txt"
  echo "[collect_hubble] WARN: cilium status failed"
fi

# --- hubble status ---
echo "[collect_hubble] hubble status"
if command -v hubble &>/dev/null; then
  hubble status > "${OUTDIR}/hubble_status.txt" 2>&1 || echo "hubble status failed" > "${OUTDIR}/hubble_status.txt"
elif kubectl -n kube-system exec ds/cilium -- hubble status > "${OUTDIR}/hubble_status.txt" 2>&1; then
  :
else
  echo "hubble not available" > "${OUTDIR}/hubble_status.txt"
  echo "[collect_hubble] WARN: hubble status not available"
fi

# --- hubble flows (jsonpb for machine parsing) ---
echo "[collect_hubble] hubble observe (last 5000 flows, namespace=${NS})"
if command -v hubble &>/dev/null; then
  hubble observe --namespace "${NS}" --last 5000 -o jsonpb > "${OUTDIR}/hubble_flows.jsonl" 2>&1 || true
elif kubectl -n kube-system exec ds/cilium -- hubble observe --namespace "${NS}" --last 5000 -o jsonpb > "${OUTDIR}/hubble_flows.jsonl" 2>&1; then
  :
else
  echo "hubble observe not available" > "${OUTDIR}/hubble_flows.jsonl"
  echo "[collect_hubble] WARN: hubble observe failed"
fi

echo "[collect_hubble] Done — files: cilium_status.txt, hubble_status.txt, hubble_flows.jsonl"