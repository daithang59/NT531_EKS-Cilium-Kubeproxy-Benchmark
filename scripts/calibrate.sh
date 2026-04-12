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
CAL_DURATION_SEC="${CAL_DURATION_SEC:-120}"
CAL_WARMUP_SEC="${CAL_WARMUP_SEC:-30}"
CAL_REST_SEC="${CAL_REST_SEC:-30}"

# QPS sweep range (will be combined with conns/profile)
# Default: 50 → 1600 QPS (multiplicative doubling: 50→100→200→400→800→1600)
# 1600 đủ cao để tìm saturation point thực sự (có errors) trên m5.large
CAL_QPS_START="${CAL_QPS_START:-50}"
CAL_QPS_END="${CAL_QPS_END:-1600}"
CAL_QPS_STEP="${CAL_QPS_STEP:-1}"           # linear step (used only when CAL_QPS_STEP_MULT=0)
CAL_QPS_STEP_MULT="${CAL_QPS_STEP_MULT:-2}" # multiplicative step; 0 = use linear steps
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
  kubectl --request-timeout=10s -n "${NS}" get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

# check_cluster_dns
# Validates kube-dns service contract and DNS resolution from fortio pod.
check_cluster_dns() {
  echo -n "[CHECK] kube-dns Service contract... "

  local dns_ip dns_ports dns_eps ep_count
  dns_ip="$(kubectl -n kube-system get svc kube-dns -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
  dns_ports="$(kubectl -n kube-system get svc kube-dns -o jsonpath='{range .spec.ports[*]}{.port}{"/"}{.protocol}{"\n"}{end}' 2>/dev/null || true)"
  dns_eps="$(kubectl -n kube-system get endpoints kube-dns -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{"\n"}{end}' 2>/dev/null || true)"

  if [[ -z "${dns_ip}" ]]; then
    echo "FAIL" >&2
    echo "[FATAL] kube-dns service not found in kube-system." >&2
    exit 1
  fi

  if ! printf '%s\n' "${dns_ports}" | grep -q '^53/UDP$' || ! printf '%s\n' "${dns_ports}" | grep -q '^53/TCP$'; then
    echo "FAIL" >&2
    echo "[FATAL] kube-dns must expose both 53/UDP and 53/TCP. Current ports:" >&2
    printf '%s\n' "${dns_ports}" >&2
    exit 1
  fi

  ep_count="$(printf '%s\n' "${dns_eps}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${ep_count}" -eq 0 ]]; then
    echo "FAIL" >&2
    echo "[FATAL] kube-dns has no ready endpoints." >&2
    exit 1
  fi

  echo "OK (clusterIP=${dns_ip}, endpoints=${ep_count})"

  echo -n "[CHECK] DNS resolution from fortio pod... "
  local pod
  pod="$(fortio_pod)"
  if ! kubectl --request-timeout=30s -n "${NS}" exec "${pod}" -- \
    fortio curl -timeout 5s "http://echo.${NS}.svc.cluster.local:80/echo" >/dev/null 2>&1; then
    echo "FAIL" >&2
    echo "[FATAL] DNS/Service probe failed from fortio pod." >&2
    exit 1
  fi
  echo "OK"
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
with open(log, encoding="utf-8") as f:
    content = f.read()

def get_percentile(key):
    # Fortio 1.74: "# target 50% 0.000573573" — extract ALL target lines and map percentile→value
    pct_map = {}
    for m in re.finditer(r'#\s*target\s+([\d.]+)%\s+([\d.e+-]+)', content):
        pct_map[float(m.group(1))] = float(m.group(2))
    # Map key names to percentile numbers
    key_map = {"p50": 50, "p75": 75, "p90": 90, "p99": 99, "p999": 99.9, "p99.9": 99.9}
    if key not in key_map:
        return None
    return pct_map.get(key_map[key])

def get_keyval(key):
    for sep in [': ', ':', '=']:
        m = re.search(re.escape(key) + sep + r'([\d.e+-]+)', content, re.IGNORECASE)
        if m:
            try: return float(m.group(1))
            except ValueError: pass
    return None

# Fortio summary section key names
p50  = get_percentile("p50")
p75  = get_percentile("p75")
p90  = get_percentile("p90")
p99  = get_percentile("p99")
p999 = get_percentile("p999")

# Max latency: upper bound of last histogram bucket in "Aggregated Function Time"
# Format: "# > 0.001 <= 0.001424 , 0.001212 , 100.00, 18" — extract 0.001424
# The last bucket (100% percentile) has the max request latency
buckets = re.findall(r'[<>=]+\s*([\d.e+-]+)\s*,', content)
max_l = float(buckets[-1]) if buckets else None

# QPS: achieved aggregate QPS from "All done ... N qps"
m_qps = re.search(r'All done\s+\d+\s+calls[^,]*,\s*([\d.]+)\s+qps', content)
rps = float(m_qps.group(1)) if m_qps else None

# Total requests: "All done NNNN calls"
m_total = re.search(r'All done\s+([\d.]+)\s+calls', content)
total_r = float(m_total.group(1)) if m_total else None

# Error count: "Error cases : N" (if N is a number) else 0
m_err = re.search(r'Error cases\s*:\s*(\d+|no data)', content)
errors = int(m_err.group(1)) if (m_err and m_err.group(1).isdigit()) else 0

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

def fmt(v):
    return "" if v is None else v

print(f"p50={fmt(p50)}")
print(f"p75={fmt(p75)}")
print(f"p90={fmt(p90)}")
print(f"p99={fmt(p99)}")
print(f"p999={fmt(p999)}")
print(f"max={fmt(max_l)}")
print(f"rps={fmt(rps)}")
print(f"errors={fmt(errors)}")
print(f"total={fmt(total_r)}")
print(f"error_rate_pct={fmt(error_rate)}")
PYEOF
}

# exec_with_retry <max_retries> <sleep_secs> _END_ <cmd...>
# Retries a command up to N times on failure (handles transient MINGW64/WSL network drops).
exec_with_retry() {
  # Consume fixed args: $1=retries, $2=sleep_secs, $3="_END_", then the actual cmd
  local max_retries="$1"
  local sleep_secs="$2"
  # Pass the rest of the arguments as the command to run
  shift 3   # skip max_retries, sleep_secs, and _END_ sentinel
  local attempt=1
  while [[ "${attempt}" -le "${max_retries}" ]]; do
    if [[ "${attempt}" -gt 1 ]]; then
      echo "    [RETRY] attempt ${attempt}/${max_retries} after ${sleep_secs}s..."
      sleep "${sleep_secs}"
    fi
    "$@" && return 0
    local exit_code=$?
    echo "    [RETRY] exit code ${exit_code}, attempt ${attempt}/${max_retries}"
    attempt=$((attempt + 1))
  done
  echo "    [WARN] all ${max_retries} retries failed"
  return "${exit_code}"
}

# run_single_calibration <qps> <conns>
run_single_calibration() {
  local qps="$1"
  local conns="$2"
  local pod

  # Get pod name; if empty (pod crashed under load), redeploy it
  pod="$(fortio_pod)"
  if [[ -z "${pod}" ]]; then
    echo "    [WARN] fortio pod missing, redeploying..."
    kubectl --request-timeout=30s -n "${NS}" rollout restart deployment/fortio 2>/dev/null || true
    sleep 5
    pod="$(fortio_pod)"
    echo "    [INFO] fortio pod redeployed: ${pod}"
  fi

  local outdir="${CAL_OUTDIR}/qps_${qps}_conns_${conns}"
  mkdir -p "${outdir}"

  echo "    [WARMUP] QPS=${qps} CONNS=${conns}"
  exec_with_retry 3 5 _END_ \
    kubectl --request-timeout=60s -n "${NS}" exec "${pod}" -- \
      fortio load -qps "${qps}" -c "${conns}" -t "${CAL_WARMUP_SEC}s" "${SVC_URL}" \
    >/dev/null 2>&1 || true

  echo "    [MEASURING] QPS=${qps} CONNS=${conns}"
  # Capture both stdout+stderr; retry on transient connection drops
  exec_with_retry 3 5 _END_ \
    kubectl --request-timeout=120s -n "${NS}" exec "${pod}" -- \
      fortio load -qps "${qps}" -c "${conns}" -t "${CAL_DURATION_SEC}s" "${SVC_URL}" \
    > "${outdir}/bench.log" 2>&1

  # Parse results (even if exec partially failed, try to parse what was captured)
  if [[ -f "${outdir}/bench.log" ]] && [[ -s "${outdir}/bench.log" ]]; then
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

  echo -n "[CHECK] Nodes Ready... "
  local not_ready
  not_ready=$(kubectl get nodes --no-headers | grep -v ' Ready' | wc -l | tr -d ' ' || true)
  if [[ -z "${not_ready}" ]]; then not_ready=0; fi
  if [[ "${not_ready}" -gt 0 ]]; then
    echo "FAIL (${not_ready} node(s) not Ready)" >&2
    kubectl get nodes >&2
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

  check_cluster_dns

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

  # Pure bash (no bc/Python dependency, works on MINGW64/WSL)
  # Multiplicative: START → *MULT → ... ≤ END
  local qps="${CAL_QPS_START}"
  while true; do
    echo "${qps}"
    if [[ "${CAL_QPS_STEP_MULT}" -gt 0 ]]; then
      qps=$(( qps * CAL_QPS_STEP_MULT ))
    else
      qps=$(( qps + CAL_QPS_STEP ))
    fi
    [[ "${qps}" -gt "${CAL_QPS_END}" ]] && break
  done
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

  # Output files
  local csv="${CAL_OUTDIR}/calibration_${ts}.csv"
  local report="${CAL_OUTDIR}/calibration_${ts}.txt"
  echo "qps,conns,run,p50,p75,p90,p99,p999,max,rps,error_rate_pct,total,errors" > "${csv}"

  # Write report header directly to file
  {
    echo "=============================================="
    echo " CALIBRATION REPORT"
    echo " Mode : ${MODE_LABEL}"
    echo " Date : $(ts_iso)"
    echo "=============================================="
    echo ""
    printf "%-8s %-6s %-5s %8s %8s %8s %8s %8s %8s %8s\n" \
      "QPS" "Conns" "Run" "p50_ms" "p90_ms" "p99_ms" "p999_ms" "max_ms" "RPS" "ErrRate%"
    echo "---------------------------------------------------------------------------"
  } > "${report}"

  local total_points=$((${#qps_list[@]} * REPEAT))
  local point_num=0

  for qps in "${qps_list[@]}"; do
    # Scale conns proportionally: conns ~ qps*8/100
    local conns=$(( qps * 8 / 100 ))
    [[ "${conns}" -lt 4 ]] && conns=4
    [[ "${conns}" -gt 64 ]] && conns=64

    for run in $(seq 1 "${REPEAT}"); do
      ((point_num++)) || true
      echo ""
      echo "[${point_num}/${total_points}] QPS=${qps} CONNS=${conns} RUN=${run}"

      run_single_calibration "${qps}" "${conns}"

      # Parse results and write to both CSV and report
      local parsed="${CAL_OUTDIR}/qps_${qps}_conns_${conns}/parsed.txt"
      if [[ -f "${parsed}" ]]; then
        # Read parsed values into local variables (avoids subshell issue with 'source')
        local p50_val p75_val p90_val p99_val p999_val max_val rps_val err_val total_val
        p50_val=$(grep '^p50=' "${parsed}" | cut -d= -f2 || echo "")
        p75_val=$(grep '^p75=' "${parsed}" | cut -d= -f2 || echo "")
        p90_val=$(grep '^p90=' "${parsed}" | cut -d= -f2 || echo "")
        p99_val=$(grep '^p99=' "${parsed}" | cut -d= -f2 || echo "")
        p999_val=$(grep '^p999=' "${parsed}" | cut -d= -f2 || echo "")
        max_val=$(grep '^max=' "${parsed}" | cut -d= -f2 || echo "")
        rps_val=$(grep '^rps=' "${parsed}" | cut -d= -f2 || echo "")
        err_val=$(grep '^error_rate_pct=' "${parsed}" | cut -d= -f2 || echo "")
        total_val=$(grep '^total=' "${parsed}" | cut -d= -f2 || echo "")

        local p50_n=${p50_val:-0} p90_n=${p90_val:-0} p99_n=${p99_val:-0}
        local p999_n=${p999_val:-0} max_n=${max_val:-0} rps_n=${rps_val:-0} err_n=${err_val:-0}

        # CSV row (shell printf not used for table — Python analysis handles all reporting)
        # Append CSV row
        echo "${qps},${conns},${run},${p50_val:-},${p75_val:-},${p90_val:-},${p99_val:-},${p999_val:-},${max_val:-},${rps_val:-},${err_val:-},${total_val:-}," >> "${csv}"
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

  # Python analysis: appends to report file
  python3 - "${csv}" "${report}" <<'PYEOF'
import sys, csv, statistics

csv_path = sys.argv[1]
report_path = sys.argv[2]

with open(report_path, "a", encoding="utf-8") as rp:
    rp.write("\n")

    by_qps = {}
    with open(csv_path, encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            qps = float(row['qps'])
            if qps not in by_qps:
                by_qps[qps] = {'p50': [], 'p90': [], 'p99': [], 'p999': [], 'error_rate_pct': [], 'rps': []}
            for col in ['p50', 'p90', 'p99', 'p999', 'error_rate_pct', 'rps']:
                val = row[col].strip()
                if val and val.lower() not in ('none', 'n/a', ''):
                    try: by_qps[qps][col].append(float(val))
                    except ValueError: pass

    def med(lst): return statistics.median(lst) if lst else float('nan')
    def avg(lst): return statistics.mean(lst) if lst else float('nan')

    rp.write(f"{'QPS':>6} | {'p50':>8} | {'p90':>8} | {'p99':>8} | {'p999':>8} | {'ErrRate%':>8} | {'RPS':>8}\n")
    rp.write("-" * 75 + "\n")
    for qps in sorted(by_qps.keys()):
        d = by_qps[qps]
        rp.write(f"{int(qps):>6} | {med(d['p50']):>8.3f} | {med(d['p90']):>8.3f} | "
                 f"{med(d['p99']):>8.3f} | {med(d['p999']):>8.3f} | "
                 f"{med(d['error_rate_pct']):>8.3f} | {avg(d['rps']):>8.1f}\n")

    rp.write("\n" + "=" * 75 + "\n")
    rp.write(" RECOMMENDED LOAD LEVELS\n")
    rp.write("=" * 75 + "\n\n")

    # Thresholds (in seconds, not ms):
    #   L1 (Light):   err < 0.1% and p99 < 0.001s (1ms)
    #   L2 (Medium):  err < 0.1% and p99 < 0.005s (5ms)
    #   L3 (High):    err < 1.0% and p99 < 0.050s (50ms) — relaxed from 20ms
    #                 because m5.large non-burstable CPU sustains stable p99 well above 20ms
    #                 under high-load; the 50ms threshold ensures saturation without errors.
    cl1, cl2, cl3 = [], [], []
    for qps in sorted(by_qps.keys()):
        d = by_qps[qps]
        err_med = med(d['error_rate_pct'])
        p99_med = med(d['p99'])
        if err_med < 0.1 and p99_med < 0.001:
            cl1.append((qps, p99_med, err_med))
        if err_med < 0.1 and p99_med < 0.005:
            cl2.append((qps, p99_med, err_med))
        if err_med < 1.0 and p99_med < 0.050:
            cl3.append((qps, p99_med, err_med))

    def write_rec(label, candidates, hint=""):
        rp.write(f" {label}:\n")
        if candidates:
            # Pick highest QPS that still satisfies the threshold.
            best = max(candidates, key=lambda x: x[0])
            rp.write(f"   QPS={int(best[0])}  p99={best[1] * 1000:.4f}ms  err={best[2]:.4f}%\n")
            rp.write(f"   Suggested CONNS={max(4, int(best[0] * 8 // 100))}\n")
        else:
            rp.write(f"   {hint}\n")
        rp.write("\n")

    write_rec("Recommended L1 (Light):", cl1,
              "No QPS point met L1 criteria (err<0.1%, p99<1ms).")
    write_rec("Recommended L2 (Medium):", cl2,
              "No QPS point met L2 criteria (err<0.1%, p99<5ms).")
    write_rec("Recommended L3 (High/near saturation):", cl3,
              "No QPS point met L3 criteria (err<1%, p99<20ms).")

    rp.write(" NOTE: All latency values in CSV are in SECONDS.\n")
    rp.write(" To freeze these values, edit common.sh:\n\n")
    rp.write("   # L1 (Light): stable, near-zero errors\n")
    rp.write("   L1_QPS=<RECOMMENDED>\n   L1_CONNS=<RECOMMENDED>\n\n")
    rp.write("   # L2 (Medium): visible tail, no saturation\n")
    rp.write("   L2_QPS=<RECOMMENDED>\n   L2_CONNS=<RECOMMENDED>\n\n")
    rp.write("   # L3 (High): near saturation\n")
    rp.write("   L3_QPS=<RECOMMENDED>\n   L3_CONNS=<RECOMMENDED>\n\n")
    rp.write(f" Calibration complete. Report: {report_path}\n")
    rp.write(f" CSV data: {csv_path}\n")
PYEOF

  # Show report on terminal
  cat "${report}"

  echo ""
  echo "[DONE] Calibration sweep complete."
  echo " Report: ${report}"
  echo " CSV:    ${csv}"
  echo ""
  echo " Next: review the RECOMMENDED LOAD LEVELS above,"
  echo " then update L1_QPS / L2_QPS / L3_QPS in scripts/common.sh"
}

main
