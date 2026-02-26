#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:?outdir required}"

# Snapshot cluster state (basic)
./scripts/common.sh >/dev/null 2>&1 || true

# We'll just store kubectl outputs
mkdir -p "${OUTDIR}"
{
  echo "=== date ==="
  date
  echo
  echo "=== cilium status (if available) ==="
  kubectl -n kube-system exec ds/cilium -- cilium status 2>/dev/null || true
} > "${OUTDIR}/meta.txt"