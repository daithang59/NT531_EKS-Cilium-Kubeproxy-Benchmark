#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

SCENARIO="s3"

# Phase OFF: remove policy
kubectl -n "${NS}" delete -f workload/policies/ --ignore-not-found=true

for LOAD in L1 L2 L3; do
  case "${LOAD}" in
    L1) QPS="${L1_QPS}" ;;
    L2) QPS="${L2_QPS}" ;;
    L3) QPS="${L3_QPS}" ;;
  esac

  for i in $(seq -w 1 "${REPEATS}"); do
    OUTDIR="results/mode=${MODE}/scenario=${SCENARIO}/phase=off/load=${LOAD}/run=${i}"
    ensure_dirs "${OUTDIR}"
    write_metadata "${OUTDIR}"
    collect_kubectl_state "${OUTDIR}"
    run_fortio "${QPS}" "${OUTDIR}"
    ./scripts/collect_hubble.sh "${OUTDIR}" || true
  done
done

# Phase ON: apply policy back
kubectl apply -f workload/policies/

for LOAD in L1 L2 L3; do
  case "${LOAD}" in
    L1) QPS="${L1_QPS}" ;;
    L2) QPS="${L2_QPS}" ;;
    L3) QPS="${L3_QPS}" ;;
  esac

  for i in $(seq -w 1 "${REPEATS}"); do
    OUTDIR="results/mode=${MODE}/scenario=${SCENARIO}/phase=on/load=${LOAD}/run=${i}"
    ensure_dirs "${OUTDIR}"
    write_metadata "${OUTDIR}"
    collect_kubectl_state "${OUTDIR}"
    run_fortio "${QPS}" "${OUTDIR}"
    ./scripts/collect_hubble.sh "${OUTDIR}" || true
  done
done

echo "[DONE] S3 completed."