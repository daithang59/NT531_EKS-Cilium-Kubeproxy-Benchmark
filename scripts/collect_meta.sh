#!/usr/bin/env bash
# ==============================================================================
# collect_meta.sh — Standalone evidence collector
# ==============================================================================
# Dumps kubectl state into OUTDIR following Results Contract.
# Normally called automatically by common.sh → collect_meta(); this script
# exists so it can also be run independently for ad-hoc snapshots.
#
# Usage:
#   ./scripts/collect_meta.sh <outdir>
# ==============================================================================
set -euo pipefail

OUTDIR="${1:?Usage: collect_meta.sh <outdir>}"
mkdir -p "${OUTDIR}"

echo "[collect_meta] Collecting kubectl evidence into ${OUTDIR}..."

# kubectl get all -A
echo "[collect_meta] kubectl get all -A"
kubectl get all -A > "${OUTDIR}/kubectl_get_all.txt" 2>&1 || true

# kubectl top nodes (requires metrics-server)
echo "[collect_meta] kubectl top nodes"
if kubectl top nodes > "${OUTDIR}/kubectl_top_nodes.txt" 2>&1; then
  echo "[collect_meta] kubectl_top_nodes.txt OK"
else
  echo "metrics-server not available — kubectl top nodes returned error" > "${OUTDIR}/kubectl_top_nodes.txt"
  echo "[collect_meta] kubectl_top_nodes.txt — metrics-server not available"
fi

# Events sorted by creation timestamp
echo "[collect_meta] kubectl get events"
kubectl get events -A --sort-by=.metadata.creationTimestamp > "${OUTDIR}/events.txt" 2>&1 || true

echo "[collect_meta] Done — files: kubectl_get_all.txt, kubectl_top_nodes.txt, events.txt"