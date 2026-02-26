#!/usr/bin/env bash
set -euo pipefail

OUTDIR="${1:?outdir required}"
NS="${NS:-netperf}"

mkdir -p "${OUTDIR}"

# If hubble CLI installed locally:
if command -v hubble >/dev/null 2>&1; then
  echo "[INFO] Collect hubble observe..."
  hubble observe --namespace "${NS}" --last 2000 > "${OUTDIR}/hubble.log" || true
else
  echo "[WARN] hubble CLI not found; skipping hubble collection" > "${OUTDIR}/hubble.log"
fi