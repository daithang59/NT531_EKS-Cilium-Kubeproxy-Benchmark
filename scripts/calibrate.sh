#!/usr/bin/env bash
# ==============================================================================
# calibrate.sh — Calibration sweep for load level determination (L1 / L2 / L3)
# ==============================================================================
# Runs a progressive QPS sweep on a SINGLE mode to determine where L1 / L2 / L3
# should sit. Outputs a calibration report with p99/error-rate vs QPS table
# and recommended L1/L2/L3 parameters.
#
# Usage:
#   MODE=A LOAD=L1 REPEAT=2 ./scripts/calibrate.sh
#   MODE=B LOAD=L1 REPEAT=2 ./scripts/calibrate.sh
#
# Output:
#   results/calibration/mode=<A|B>/calibration_<timestamp>.txt
#   results/calibration/mode=<A|B>/calibration_<timestamp>.csv
#
# After running, review the report and freeze the recommended parameters in
# common.sh (L1_QPS / L2_QPS / L3_QPS).
# ==============================================================================
set -euo pipefail

# ---- Minimal source of common.sh (only defaults / helpers, no preflight) ----
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NS="${NS:-benchmark}"
MODE="${MODE:-A}"
REPEAT="${REPEAT:-2}"

# Overwrite common.sh defaults for calibration (shorter, more granular)
CAL_DURATION_SEC="${CAL_DURATION_SEC:-30}"
CAL_WARMUP_SEC="${CAL_WARMUP_SEC:-10}"
CAL_REST_SEC="${CAL_REST_SEC:-15}"

# QPS sweep range (will be combined with conns/profile)
# Default: 11 points from 50 → 1500 QPS
CAL_QPS_START="${CAL_QPS_START:-50}"
CAL_QPS_END="${CAL_QPS_END:-1500}"
CAL_QPS_STEP="${CAL_QPS_STEP:-1}"          # step multiplier; use STEP_LIST below for custom
CAL_QPS_STEP_MULT="${CAL_QPS_STEP_MULT:-1}" # multiplicative step; 0 = use STEP_LIST
CAL_QPS_LIST="${CAL_QPS_LIST:-}"            # comma-separated explicit list (overrides above)

# Concurrency profile per phase
CAL_CONNS_START="${CAL_CONNS_START:-8}"
CAL_CONNS_STEP="${CAL_CONNS_STEP:-8}"

SVC_URL="${SVC_URL:-http://echo.${NS}.svc.cluster.local/}"

# Derived
case "${MODE}" in
  A) MODE_LABEL="A_kube-proxy" ;;
  B) MODE_LABEL="B_cilium-ebpfkpr" ;;
  *) echo "[FATAL] Invalid MODE='${MODE}'. Must be A or B." >&2; exit 1 ;;
esac

ts_dir() {
  TZ="Asia/Ho_Chi_Minh" date +"%Y-%m-%dT%H-%M-%S+07-00"
}
ts_iso() {
  TZ="Asia/Ho_Chi_Minh" date +"%Y-%m-%dT%H:%M:%S+07:00"
}

# ======================== Helpers ==============================================

fortio_pod() {
  kubectl -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}'
}

# parse_fortio_latency <bench_log>
# Extracts latency percentiles from Fortio stdout.
# Fortio prints:  "Max latency ..." then "p50 ...", "p75 ...", "p90 ...", "p99 ..." lines.
# Also extracts:  "Duration ...", "Count ..." lines.
parse_fortio_latency() {
  local log="$1"
  python3 - "$log" <<'PYEOF'
import sys, re

log = sys.argv[1]
with open(log) as f:
    content = f.read()

def get(key):
    # Match lines like "  p99 :  1.234 ms"
    m = re.search(r'\b' + re.escape(key) + r'\s*[:\s=]+\s*([\d.]+)\s*(\w+)?', content, re.IGNORECASE)
    if m:
        val = float(m.group(1))
        unit = (m.group(2) or "ms").lower()
        if unit == "s":
            val *= 1000
        return val
    return None

def get_keyval(key):
    m = re.search(r'\b' + re.escape(key) + r'\s*[:\s]+\s*([\d.]+)', content, re.IGNORECASE)
    return float(m.group(1)) if m else None

# Fortio summary section key names
p50  = get("p50")
p75  = get("p75")
p90  = get("p90")
p99  = get("p99")
p999 = get("p999") or get("p99.9")
max_l = get("Max")

rps     = get_keyval("QPS") or get_keyval("Requests/s") or get_keyval("QPS")
errors  = get_keyval("Error") or get_keyval("Errors")
total_r = get_keyval("Count") or get_keyval("Total")

# Parse "HTTP codes: 200 xxx" block
http_2xx = 0
http_non2xx = 0
for m in re.finditer(r'HTTP code[s]?:\s*(\d+)\s+(\d+)', content):
    code = int(m.group(1))
    cnt = int(m.group(2))
    if 200 <= code < 300:
        http_2xx += cnt
    else:
        http_non2xx += cnt

error_rate = None
if total_r and total_r > 0:
    error_rate = http_non2xx / total_r * 100
elif errors is not None and total_r is not None and total_r > 0:
    error_rate = errors / total_r * 100

print(f"p50={p50}")
print(f"p75={p75}")
print(f"p90={p90}")
print(f"p99={p99}")
print(f"p999={p999}")
print(f"max={max_l}")
print(f"rps={rps}")
print(f"errors={errors}")
print(f"total={total_r}")
print(f"error_rate_pct={error_rate}")
PYEOF
}

# run_single_calibration <qps> <conns>
run_single_calibration() {
  local qps="$1"
  local conns="$2"
  local pod
  pod="$(fortio_pod)"

  local outdir
  outdir="${CAL_OUTDIR}/qps_${qps}_conns_${conns}"
  mkdir -p "${outdir}"

  echo "    [WARMUP] QPS=${qps} CONNS=${conns}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load \
      -qps "${qps}" \
      -c "${conns}" \
      -t "${CAL_WARMUP_SEC}s" \
      "${SVC_URL}" >/dev/null 2>&1 || true

  echo "    [MEASURING] QPS=${qps} CONNS=${conns}"
  kubectl -n "${NS}" exec "${pod}" -- \
    fortio load \
      -qps "${qps}" \
      -c "${conns}" \
      -t "${CAL_DURATION_SEC}s" \
      "${SVC_URL}" 2>&1 | tee "${outdir}/bench.log"

  # Parse results
  if [[ -f "${outdir}/bench.log" ]]; then
    parse_fortio_latency "${outdir}/bench.log" > "${outdir}/parsed.txt"
  else
    echo "p50=N/A" > "${outdir}/parsed.txt"
  fi
}

# ======================== Pre-flight ===========================================

preflight() {
  echo "=============================================="
  echo " Calibration — MODE=${MODE_LABEL}"
  echo " $(ts_iso)"
  echo "=============================================="

  echo -n "[CHECK] kubectl context... "
  if ! kubectl cluster-info &>/dev/null; then
    echo "FAIL" >&2
    echo "[FATAL] kubectl cannot reach cluster." >&2
    exit 1
  fi
  echo "OK"

  echo -n "[CHECK] echo pod Running... "
  if ! kubectl -n "${NS}" get pod -l app=echo -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
    echo "FAIL" >&2
    exit 1
  fi
  echo "OK"

  echo -n "[CHECK] fortio pod Running... "
  if ! kubectl -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q Running; then
    echo "FAIL" >&2
    exit 1
  fi
  echo "OK"

  echo ""
  echo "Calibration config:"
  echo "  Duration per point : ${CAL_DURATION_SEC}s (warmup ${CAL_WARMUP_SEC}s)"
  echo "  Repeats per point : ${REPEAT}"
  echo "  Rest between runs  : ${CAL_REST_SEC}s"
  echo ""
}

# ======================== Build QPS list ======================================

build_qps_list() {
  if [[ -n "${CAL_QPS_LIST}" ]]; then
    # Comma-separated explicit list
    echo "${CAL_QPS_LIST}" | tr ',' '\n'
    return
  fi

  local qps="${CAL_QPS_START}"
  if [[ "${CAL_QPS_STEP_MULT}" -gt 0 ]]; then
    # Multiplicative steps: 50, 100, 200, 400, 800, 1200, 1500
    while (( $(echo "${qps} <= ${CAL_QPS_END}" | bc -l) )); do
      echo "${qps}"
      qps=$(echo "${qps} * ${CAL_QPS_STEP_MULT}" | bc -l | xargs printf "%.0f")
    done
  else
    # Linear steps
    while [[ "${qps}" -le "${CAL_QPS_END}" ]]; do
      echo "${qps}"
      qps=$((qps + CAL_QPS_STEP))
    done
  fi
}

# ======================== Main =================================================

main() {
  local ts
  ts="$(ts_dir)"
  CAL_OUTDIR="${REPO_ROOT}/results/calibration/mode=${MODE_LABEL}"
  mkdir -p "${CAL_OUTDIR}"

  preflight

  echo ""
  echo "=============================================="
  echo " Starting calibration sweep"
  echo "=============================================="

  # Build QPS list
  local qps_list
  qps_list=($(build_qps_list))

  echo "QPS sweep points: ${qps_list[*]}"
  echo ""

  # CSV header
  local csv="${CAL_OUTDIR}/calibration_${ts}.csv"
  echo "qps,conns,run,p50_ms,p75_ms,p90_ms,p99_ms,p999_ms,max_ms,rps,error_rate_pct,total_requests,errors" > "${csv}"

  # txt report header
  local report="${CAL_OUTDIR}/calibration_${ts}.txt"
  exec > >(tee "${report}")
  exec 2>&1

  echo "=============================================="
  echo " CALIBRATION REPORT"
  echo " Mode : ${MODE_LABEL}"
  echo " Date : $(ts_iso)"
  echo "=============================================="
  echo ""
  printf "%-8s %-6s %-5s %8s %8s %8s %8s %8s %8s %8s\n" \
    "QPS" "Conns" "Run" "p50_ms" "p90_ms" "p99_ms" "p999_ms" "max_ms" "RPS" "ErrRate%"
  echo "---------------------------------------------------------------------------"

  local total_points=$((${#qps_list[@]} * REPEAT))
  local point_num=0

  for qps in "${qps_list[@]}"; do
    # Scale conns proportionally: conns ~ qps/12 (rough, keeps conns reasonable)
    local conns
    conns=$(( qps * 8 / 100 ))
    [[ "${conns}" -lt 4 ]] && conns=4
    [[ "${conns}" -gt 64 ]] && conns=64

    for run in $(seq 1 "${REPEAT}"); do
      ((point_num++))
      echo ""
      echo "[${point_num}/${total_points}] QPS=${qps} CONNS=${conns} RUN=${run}"

      run_single_calibration "${qps}" "${conns}"

      # Parse and write CSV row
      local parsed="${CAL_OUTDIR}/qps_${qps}_conns_${conns}/parsed.txt"
      if [[ -f "${parsed}" ]]; then
        source "${parsed}"
        printf "%-8s %-6s %-5s %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f %8.3f\n" \
          "${qps}" "${conns}" "${run}" \
          "${p50:-0}" "${p90:-0}" "${p99:-0}" "${p999:-0}" "${max:-0}" "${rps:-0}" "${error_rate_pct:-0}" \
          >> "${report}"

        echo "${qps},${conns},${run},${p50:-},${p75:-},${p90:-},${p99:-},${p999:-},${max:-},${rps:-},${error_rate_pct:-},${total:-},${errors:-}" \
          >> "${csv}"
      fi

      # Rest between runs
      if [[ "${run}" -lt "${REPEAT}" ]] || [[ "${qps}" != "${qps_list[-1]}" ]]; then
        echo "    [REST] sleeping ${CAL_REST_SEC}s..."
        sleep "${CAL_REST_SEC}"
      fi
    done
  done

  echo ""
  echo "=============================================="
  echo " CALIBRATION ANALYSIS"
  echo "=============================================="
  echo ""

  # Use Python for analysis + L1/L2/L3 recommendation
  python3 - "${csv}" "${report}" <<'PYEOF'
import sys
import csv
import statistics

csv_path = sys.argv[1]
report_path = sys.argv[2]

# Aggregate by QPS (average across repeats)
by_qps = {}
with open(csv_path) as f:
    reader = csv.DictReader(f)
    for row in reader:
        qps = float(row['qps'])
        if qps not in by_qps:
            by_qps[qps] = {'p50': [], 'p90': [], 'p99': [], 'p999': [], 'error_rate_pct': [], 'rps': []}
        for col in ['p50', 'p90', 'p99', 'p999', 'error_rate_pct', 'rps']:
            val = row[col].strip()
            if val and val.lower() != 'none' and val.lower() != 'n/a':
                try:
                    by_qps[qps][col].append(float(val))
                except ValueError:
                    pass

# Summary table
print(f"{'QPS':>6} | {'p50':>8} | {'p90':>8} | {'p99':>8} | {'p999':>8} | {'ErrRate%':>8} | {'RPS':>8}")
print("-" * 75)
for qps in sorted(by_qps.keys()):
    d = by_qps[qps]
    def med(lst): return statistics.median(lst) if lst else float('nan')
    def avg(lst): return statistics.mean(lst) if lst else float('nan')
    def stdev(lst):
        return statistics.stdev(lst) if len(lst) > 1 else 0.0
    print(f"{int(qps):>6} | {med(d['p50']):>8.3f} | {med(d['p90']):>8.3f} | {med(d['p99']):>8.3f} | {med(d['p999']):>8.3f} | {med(d['error_rate_pct']):>8.3f} | {avg(d['rps']):>8.1f}")

print("")

# ---- L1/L2/L3 Recommendation ----
# Strategy:
#   L1 (Light):      error_rate < 0.1% AND p99 < 5ms  → stable, low latency
#   L2 (Medium):     error_rate < 1%  AND p99 < 20ms  → visible tail but no saturation
#   L3 (High/near saturation): max error_rate < 5%    → approaching saturation, high tail

sorted_qps = sorted(by_qps.keys())
candidates_l1 = []
candidates_l2 = []
candidates_l3 = []

for qps in sorted_qps:
    d = by_qps[qps]
    def med(lst): return statistics.median(lst) if lst else float('nan')
    err_med = med(d['error_rate_pct'])
    p99_med = med(d['p99'])

    if err_med < 0.1 and p99_med < 5:
        candidates_l1.append((qps, p99_med, err_med))
    if err_med < 1.0 and p99_med < 20:
        candidates_l2.append((qps, p99_med, err_med))
    if err_med < 5.0:
        candidates_l3.append((qps, p99_med, err_med))

print("=" * 75)
print(" RECOMMENDED LOAD LEVELS")
print("=" * 75)
print("")
print(" Recommended L1 (Light):")
if candidates_l1:
    best = max(candidates_l1, key=lambda x: x[0])  # highest QPS still stable
    print(f"   QPS={int(best[0])}  p99={best[1]:.2f}ms  err={best[2]:.4f}%")
    print(f"   Suggested CONNS={max(4, int(best[0]*8//100))}")
else:
    print("   No QPS point met L1 criteria (err<0.1%, p99<5ms). Lower QPS may be needed.")

print("")
print(" Recommended L2 (Medium):")
if candidates_l2:
    best = min(candidates_l2, key=lambda x: abs(x[0] - candidates_l2[-1][0]*0.7))  # ~70% of max stable
    print(f"   QPS={int(best[0])}  p99={best[1]:.2f}ms  err={best[2]:.4f}%")
    print(f"   Suggested CONNS={max(4, int(best[0]*8//100))}")
else:
    print("   No QPS point met L2 criteria (err<1%, p99<20ms).")

print("")
print(" Recommended L3 (High/near saturation):")
if candidates_l3:
    best = max(candidates_l3, key=lambda x: x[0])  # highest QPS before 5% errors
    print(f"   QPS={int(best[0])}  p99={best[1]:.2f}ms  err={best[2]:.4f}%")
    print(f"   Suggested CONNS={max(4, int(best[0]*8//100))}")
else:
    print("   No QPS point met L3 criteria (err<5%).")

print("")
print(" To freeze these values, edit common.sh:")
print("")
print("   # L1 (Light): stable, near-zero errors")
print("   L1_QPS=<RECOMMENDED>")
print("   L1_CONNS=<RECOMMENDED>")
print("")
print("   # L2 (Medium): visible tail, no saturation")
print("   L2_QPS=<RECOMMENDED>")
print("   L2_CONNS=<RECOMMENDED>")
print("")
print("   # L3 (High): near saturation")
print("   L3_QPS=<RECOMMENDED>")
print("   L3_CONNS=<RECOMMENDED>")
print("")
print(f" Calibration complete. Report: {report_path}")
print(f" CSV data: {csv_path}")
PYEOF

  echo ""
  echo "[DONE] Calibration sweep complete."
  echo " Report: ${report}"
  echo " CSV:    ${csv}"
  echo ""
  echo " Next: review the RECOMMENDED LOAD LEVELS section above,"
  echo " then update L1_QPS / L2_QPS / L3_QPS in common.sh"
}

main
