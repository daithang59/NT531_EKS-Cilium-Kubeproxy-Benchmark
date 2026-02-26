#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# S2: high load + churn (skeleton)
# Idea: run fortio with higher QPS + shorter connections / more churn if you later add flags.
SCENARIO="s2"

# For skeleton, reuse L1-L3
./scripts/run_s1.sh
echo "[NOTE] S2 skeleton currently same as S1; extend with churn logic later."