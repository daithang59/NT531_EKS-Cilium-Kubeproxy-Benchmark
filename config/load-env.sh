#!/usr/bin/env bash
# ==============================================================================
# load-env.sh — Load benchmark environment from .env
# ==============================================================================
# Usage:
#   source config/load-env.sh                  # interactive
#   source config/load-env.sh --mode A --load L2  # non-interactive
#
# After loading, run:
#   ./scripts/run_S1.sh   (S1 auto-detected from MODE/LOAD)
# ==============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${REPO_ROOT}/.env"

# ---- Defaults from .env ----
if [[ -f "${CONFIG}" ]]; then
  set -a; source "${CONFIG}"; set +a
fi

# Override defaults
MODE="${MODE:-A}"
LOAD="${LOAD:-L1}"
REPEAT="${REPEAT:-3}"

# ---- Interactive menu ----
if [[ "${1:-}" == "--interactive" ]] || [[ $# -eq 0 && -t 0 ]]; then
  echo ""
  echo "═══════════════════════════════════════════════"
  echo "  NT531 Benchmark — Environment Loader"
  echo "═══════════════════════════════════════════════"
  echo ""

  echo "  1) Mode A — kube-proxy baseline"
  echo "  2) Mode B — Cilium eBPF KPR"
  echo -n "  Mode [1]: "; read -r m; [[ "${m}" == "2" ]] && MODE="B" || MODE="A"

  echo ""
  echo "  1) S1 — Steady-state"
  echo "  2) S2 — Stress + Churn (L2, L3 only)"
  echo "  3) S3 — NetworkPolicy Overhead (L2, L3 only)"
  echo -n "  Scenario [1]: "; read -r s
  case "${s}" in
    2) SCENARIO="S2" ;;
    3) SCENARIO="S3" ;;
    *) SCENARIO="S1" ;;
  esac

  echo ""
  if [[ "${SCENARIO}" == "S1" ]]; then
    echo "  1) L1 — Light"
    echo "  2) L2 — Medium"
    echo "  3) L3 — High"
    echo -n "  Load [2]: "; read -r l
    case "${l}" in
      1) LOAD="L1" ;;
      3) LOAD="L3" ;;
      *) LOAD="L2" ;;
    esac
  else
    echo "  L1 unavailable for S2/S3 — using L2"
    LOAD="L2"
  fi

  echo ""
  echo -n "  Repeats [3]: "; read -r r; LOAD="${LOAD}" # keep LOAD
  REPEAT="${r:-3}"
  echo ""
fi

# ---- Parse CLI flags ----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)     MODE="$2";       shift 2 ;;
    --load)     LOAD="$2";       shift 2 ;;
    --repeat)  REPEAT="$2";     shift 2 ;;
    --scenario) SCENARIO="$2";   shift 2 ;;
    --help)    cat <<'EOF'
Usage: source config/load-env.sh [OPTIONS]

Options:
  --mode A|B           Mode (A=kube-proxy, B=eBPF KPR)
  --scenario S1|S2|S3  Scenario (default: S1)
  --load L1|L2|L3      Load level (default: L1)
  --repeat N           Repeats per combination (default: 3)
  --interactive         Show interactive menu

After loading, run:
  ./scripts/run_S1.sh   (S1 auto-detected)
  ./scripts/run_S2.sh
  ./scripts/run_S3.sh

EOF
      return 0 ;;
    *) shift ;;
  esac
done

# ---- Validate ----
if [[ "${SCENARIO:-S1}" != "S1" && "${LOAD}" == "L1" ]]; then
  echo "[WARN] L1 invalid for S2/S3 — switching to L2"
  LOAD="L2"
fi

# ---- Export ----
export MODE LOAD REPEAT SCENARIO

echo ""
echo "  ╔════════════════════════════════════╗"
echo "  ║  MODE=${MODE}  LOAD=${LOAD}  REPEAT=${REPEAT}       ║"
echo "  ╚════════════════════════════════════╝"
echo ""
echo "  Run: ./scripts/run_S1.sh"
echo ""
