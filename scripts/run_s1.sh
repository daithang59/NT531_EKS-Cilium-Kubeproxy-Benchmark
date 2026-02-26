#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

SCENARIO="s1"
for LOAD in L1 L2 L3; do
  case "${LOAD}" in
    L1) QPS="${L1_QPS}" ;;
    L2) QPS="${L2_QPS}" ;;
    L3) QPS="${L3_QPS}" ;;
  esac

  for i in $(seq -w 1 "${REPEATS}"); do
    OUTDIR="results/mode=${MODE}/scenario=${SCENARIO}/load=${LOAD}/run=${i}"
    ensure_dirs "${OUTDIR}"
    write_metadata "${OUTDIR}"
    collect_kubectl_state "${OUTDIR}"
    run_fortio "${QPS}" "${OUTDIR}"
    ./scripts/collect_hubble.sh "${OUTDIR}" || true
  done
done
echo "[DONE] S1 completed."