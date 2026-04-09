#!/usr/bin/env python3
"""
analyze_results.py -- Statistical analysis of benchmark results.

Reads bench.log files from the Results Contract directory structure and produces:
  1. Summary table (median, mean, std, CI) per (mode x scenario x load)
  2. A vs B comparison table with t-test p-values and D% for each metric
  3. CSV export of all aggregated results
  4. Calibration results table (from results/calibration/)

Usage:
  python3 scripts/analyze_results.py
  python3 scripts/analyze_results.py --results-dir ./results
  python3 scripts/analyze_results.py --output ./results_analysis/
"""

import argparse
import csv
import glob
import json
import os
import re
import statistics
import sys
import textwrap
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# --- Constants ---------------------------------------------------------------

METRICS = ["p50_ms", "p90_ms", "p99_ms", "p999_ms", "max_ms", "rps", "error_rate_pct"]
METRIC_LABELS = {
    "p50_ms": "p50 (ms)",
    "p90_ms": "p90 (ms)",
    "p99_ms": "p99 (ms)",
    "p999_ms": "p999 (ms)",
    "max_ms": "max (ms)",
    "rps": "RPS",
    "error_rate_pct": "ErrRate (%)",
}
ALPHA = 0.05   # significance level for t-tests
CI_LEVEL = 0.95  # confidence interval level


# --- Parsing -------------------------------------------------------------------

def parse_fortio_log(log_path: Path) -> dict:
    """Extract metrics from a Fortio bench.log file."""
    if not log_path.exists():
        return {}

    content = log_path.read_text(errors="replace")

    # Fortio 1.74.x format:
    #   # target 50% 0.000545751        <- percentile values in seconds
    #   # target 99% 0.00151233
    #   # target 99.9% 0.00195616
    #   Aggregated Function Time : count N avg X min Y max Z
    #   All done N calls ... X ms avg, QPS.0 qps
    #   Code 200 : N (M%)           <- HTTP codes (no colon after "Code")

    def get_target_pct(pct_str: str) -> Optional[float]:
        """Extract value from '# target PCT% VALUE' line."""
        m = re.search(rf"#\s*target\s+{re.escape(pct_str)}\s+([\d.e+-]+)", content, re.IGNORECASE)
        if m:
            return float(m.group(1)) * 1000.0  # convert s -> ms
        return None

    def get_aggregated_max() -> Optional[float]:
        """Extract max latency (ms) from 'Aggregated Function Time' line."""
        m = re.search(r"Aggregated Function Time\s*:\s*count\s+\d+\s+[^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+\s+([\d.e+-]+)", content)
        if m:
            return float(m.group(1)) * 1000.0
        return None

    def get_avg_ms() -> Optional[float]:
        """Extract avg ms from 'All done ... X ms avg' line."""
        m = re.search(r"All done\s+\d+\s+calls[^\d]*([\d.]+)\s+ms\s+avg", content)
        return float(m.group(1)) if m else None

    def get_qps() -> Optional[float]:
        """Extract actual QPS from 'All done ... QPS.0 qps' line."""
        m = re.search(r"All done\s+\d+\s+calls[^\d]*([\d.]+)\s+qps", content)
        return float(m.group(1)) if m else None

    # HTTP error breakdown: "Code 200 : N" (no colon after Code)
    http_errors: dict[int, int] = {}
    for m in re.finditer(r"Code\s+(\d+)\s+:\s+(\d+)", content):
        code, cnt = int(m.group(1)), int(m.group(2))
        http_errors[code] = http_errors.get(code, 0) + cnt

    total_requests = sum(http_errors.values())
    non_2xx = sum(cnt for code, cnt in http_errors.items() if code < 200 or code >= 300)
    error_rate = (non_2xx / total_requests * 100) if total_requests > 0 else 0.0

    # Try Fortio JSON export if available
    json_data = None
    json_path = log_path.with_suffix(".json")
    if json_path.exists():
        try:
            json_data = json.loads(json_path.read_text())
        except Exception:
            pass

    if json_data:
        h = json_data.get("Histogram", json_data.get("h", {}))
        rps = json_data.get("RequestedQPS", 0)
        return {
            "p50_ms":  h.get("Percentile", {}).get("50.0") or get_target_pct("50%"),
            "p90_ms":  h.get("Percentile", {}).get("90.0") or get_target_pct("90%"),
            "p99_ms":  h.get("Percentile", {}).get("99.0") or get_target_pct("99%"),
            "p999_ms": h.get("Percentile", {}).get("99.9") or get_target_pct("99.9%"),
            "max_ms":  h.get("Max") or get_aggregated_max(),
            "rps":     json_data.get("ActualQPS", rps) or get_qps(),
            "error_rate_pct": error_rate,
        }

    return {
        "p50_ms":  get_target_pct("50%"),
        "p90_ms":  get_target_pct("90%"),
        "p99_ms":  get_target_pct("99%"),
        "p999_ms": get_target_pct("99.9%"),
        "max_ms":  get_aggregated_max(),
        "rps":     get_qps(),
        "error_rate_pct": error_rate,
    }


def parse_metadata(meta_path: Path) -> dict:
    """Load metadata.json and extract key fields."""
    if not meta_path.exists():
        return {}
    try:
        return json.loads(meta_path.read_text())
    except Exception:
        return {}


# --- Statistics ---------------------------------------------------------------

def mean(values: list[float]) -> float:
    return statistics.mean(values) if values else float("nan")


def stdev(values: list[float]) -> float:
    return statistics.stdev(values) if len(values) > 1 else 0.0


def median(values: list[float]) -> float:
    return statistics.median(values) if values else float("nan")


def ci_tdist(values: list[float], level: float = CI_LEVEL) -> tuple[float, float, float]:
    """
    Compute mean +/- CI using Student's t-distribution.
    Returns (mean, ci_lower, ci_upper).
    """
    if not values:
        return float("nan"), float("nan"), float("nan")
    if len(values) == 1:
        return values[0], float("nan"), float("nan")

    import math
    n = len(values)
    m = statistics.mean(values)
    s = statistics.stdev(values)
    df = n - 1

    # Critical t value (two-tailed)
    t_crit = _t_critical[df]
    margin = t_crit * (s / math.sqrt(n))
    return m, m - margin, m + margin


def _bootstrap_ci(values: list[float], level: float = CI_LEVEL, n_iter: int = 10000) -> tuple[float, float, float]:
    """Bootstrap CI (used when n >= 10 for robustness)."""
    import math, random
    if not values or len(values) < 2:
        m = statistics.mean(values) if values else float("nan")
        return m, float("nan"), float("nan")

    rng = random.Random(42)
    boot_means = []
    vals = list(values)
    for _ in range(n_iter):
        sample = [rng.choice(vals) for _ in vals]
        boot_means.append(statistics.mean(sample))

    alpha = 1 - level
    lower = sorted(boot_means)[int(len(boot_means) * alpha / 2)]
    upper = sorted(boot_means)[int(len(boot_means) * (1 - alpha / 2))]
    m = statistics.mean(values)
    return m, lower, upper


def welch_ttest(a: list[float], b: list[float]) -> dict:
    """
    Welch's t-test (unequal variances, unequal n).
    Returns dict with t_stat, df, p_value.
    """
    import math

    if len(a) < 2 or len(b) < 2:
        return {"t_stat": float("nan"), "df": float("nan"), "p_value": float("nan"), "significant": False}

    n1, n2 = len(a), len(b)
    m1, m2 = statistics.mean(a), statistics.mean(b)
    v1 = statistics.variance(a) if n1 > 1 else 0.0
    v2 = statistics.variance(b) if n2 > 1 else 0.0

    se = math.sqrt(v1 / n1 + v2 / n2)
    if se == 0:
        return {"t_stat": float("nan"), "df": float("nan"), "p_value": float("nan"), "significant": False}

    t = (m1 - m2) / se

    # Welch-Satterthwaite degrees of freedom
    num = (v1 / n1 + v2 / n2) ** 2
    denom = (v1 / n1) ** 2 / (n1 - 1) + (v2 / n2) ** 2 / (n2 - 1)
    df = num / denom if denom > 0 else min(n1, n2) - 1

    p_value = _t_cdf_two_tailed(abs(t), df)
    return {
        "t_stat": t,
        "df": df,
        "p_value": p_value,
        "significant": p_value < ALPHA,
    }


def _t_cdf_two_tailed(t: float, df: int) -> float:
    """
    Two-tailed p-value for Student's t via numerical integration of the PDF.

    Integrates the t-distribution PDF from 0 to |t| using Simpson's rule (1001 points),
    then maps to a two-tailed p-value. Accurate across all |t| and df values.

    PDF: f(x) = Γ((df+1)/2) / (√(df·π) · Γ(df/2)) · (1 + x²/df)^(-(df+1)/2)
    CDF(0→|t|) = 0.5 + ∫₀^{|t|} f(x) dx
    Two-tailed p = 2 · (1 − CDF(|t|))
    """
    import math
    if t == 0:
        return 1.0
    if df < 1:
        return float("nan")

    try:
        t_abs = abs(t)
        half_df = df / 2.0
        # log-gamma is numerically stable for large parameters
        ln_coef = (
            math.lgamma(half_df + 0.5)
            - 0.5 * math.log(df * math.pi)
            - math.lgamma(half_df)
        )
        coef = math.exp(ln_coef)

        def pdf(x: float) -> float:
            return coef * math.pow(1.0 + x * x / df, -(half_df + 0.5))

        # Simpson's rule with 1001 points (1000 intervals) — sufficient for p < 0.05
        n = 1000
        h = t_abs / n
        s = pdf(0.0) + pdf(t_abs)
        for i in range(1, n):
            xi = i * h
            s += pdf(xi) * (4.0 if i % 2 == 1 else 2.0)
        cdf_upper = 0.5 + s * h / 3.0  # ∫₀^{|t|} pdf dx  (one-tailed)
        return 2.0 * (1.0 - cdf_upper)  # two-tailed
    except Exception:
        return float("nan")


# --- t-critical lookup (two-tailed, for n=2..30) ------------------------------
# Values for alpha=0.05, two-tailed: P(|T| > t) = 0.05
_T_CRITICAL = {
    1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447, 7: 2.365,
    8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179, 13: 2.160, 14: 2.145,
    15: 2.131, 16: 2.120, 17: 2.110, 18: 2.101, 19: 2.093, 20: 2.086,
    21: 2.080, 22: 2.074, 23: 2.069, 24: 2.064, 25: 2.060, 26: 2.056,
    27: 2.052, 28: 2.048, 29: 2.045, 30: 2.042,
}
_T_CRITICAL[999] = 1.96  # approx for n>30


def _t_critical_sample(n: int, level: float = CI_LEVEL) -> float:
    """Return t-critical for n samples at given confidence level."""
    import math
    df = max(1, n - 1)
    if df in _T_CRITICAL:
        return _T_CRITICAL[df]
    # Normal approximation for large df
    return _T_CRITICAL[999]


# Patch the module-level reference
_t_critical = _T_CRITICAL


# --- Data structures ----------------------------------------------------------

@dataclass
class RunResult:
    run_dir: Path
    mode: str
    scenario: str
    load: str
    phase: Optional[str]
    run_id: str
    n: int = 1
    p50_ms: list[float] = field(default_factory=list)
    p90_ms: list[float] = field(default_factory=list)
    p99_ms: list[float] = field(default_factory=list)
    p999_ms: list[float] = field(default_factory=list)
    max_ms: list[float] = field(default_factory=list)
    rps: list[float] = field(default_factory=list)
    error_rate_pct: list[float] = field(default_factory=list)

    def to_dict(self) -> dict:
        d = {
            "mode": self.mode, "scenario": self.scenario, "load": self.load,
            "phase": self.phase, "run_id": self.run_id, "n": len(self.p50_ms),
        }
        for m in METRICS:
            vals = getattr(self, m)
            d[f"{m}_n"] = len(vals)
            d[f"{m}_median"] = median(vals) if vals else float("nan")
            d[f"{m}_mean"] = mean(vals) if vals else float("nan")
            d[f"{m}_stdev"] = stdev(vals) if len(vals) > 1 else 0.0
            m_val, ci_lo, ci_hi = ci_tdist(vals)
            d[f"{m}_mean_val"] = m_val
            d[f"{m}_ci_lo"] = ci_lo
            d[f"{m}_ci_hi"] = ci_hi
        return d


# --- Directory scanning --------------------------------------------------------

def scan_results(results_dir: Path) -> list[RunResult]:
    """Walk results/ and collect all run results grouped by (mode x scenario x load x phase)."""
    runs: list[RunResult] = []

    # Pattern: results/mode=A_kube-proxy/scenario=S1/load=L1/run=R1_2026-02-27T14-30-00+07-00/
    # or with phase: results/mode=.../scenario=S3/load=.../phase=off/run=.../
    pattern = results_dir / "mode=*" / "scenario=*" / "load=*" / "run=*" / "bench.log"
    for bench_log in glob.glob(str(pattern), recursive=False):
        # Try both flat and phase-subdirectory layouts
        run_dir = Path(bench_log).parent

        # Parse directory name to infer mode/scenario/load
        parts = run_dir.parts
        try:
            mode = next(p.split("=")[1] for p in parts if p.startswith("mode="))
            scenario = next(p.split("=")[1] for p in parts if p.startswith("scenario="))
            load = next(p.split("=")[1] for p in parts if p.startswith("load="))
        except StopIteration:
            continue

        phase = None
        run_id = run_dir.name
        # Check if bench.log is inside a phase subdirectory
        if run_dir.parent.name.startswith("phase="):
            phase = run_dir.parent.name.split("=")[1]
            run_id = run_dir.name

        # Check for multiple repeats under run subdir (e.g. bench_R1.log, bench_R2.log)
        bench_files = list(run_dir.glob("bench*.log")) + list(run_dir.glob("*.log"))
        # Also look for bench_R{1,2,3}.log at run_dir level
        for bench_file in sorted(run_dir.glob("bench_R*.log")):
            sub_run_id = bench_file.stem  # e.g. "bench_R1"
            metrics = parse_fortio_log(bench_file)
            if metrics:
                rr = RunResult(run_dir=run_dir, mode=mode, scenario=scenario,
                               load=load, phase=phase, run_id=sub_run_id)
                for m in METRICS:
                    v = metrics.get(m)
                    if v is not None:
                        getattr(rr, m).append(v)
                runs.append(rr)

        # Single bench.log
        metrics = parse_fortio_log(Path(bench_log))
        if metrics:
            rr = RunResult(run_dir=run_dir, mode=mode, scenario=scenario,
                           load=load, phase=phase, run_id=run_id)
            for m in METRICS:
                v = metrics.get(m)
                if v is not None:
                    getattr(rr, m).append(v)
            # Merge if we already have a run with same run_id
            existing = next((r for r in runs
                             if r.run_dir == run_dir and r.run_id == run_id and r.mode == mode
                             and r.scenario == scenario and r.load == load), None)
            if existing:
                for m in METRICS:
                    vals = getattr(rr, m)
                    if vals:
                        getattr(existing, m).extend(vals)
            else:
                runs.append(rr)

    return runs


def scan_calibration(cal_dir: Path) -> dict:
    """Read calibration CSV files."""
    results: dict[tuple, dict] = {}
    for csv_path in sorted(cal_dir.rglob("calibration_*.csv")):
        mode = csv_path.parent.name  # e.g. "mode=A_kube-proxy"
        rows = []
        with open(csv_path) as f:
            reader = csv.DictReader(f)
            for row in reader:
                rows.append({k: (float(v) if v not in ("", "None", "n/a") else None)
                             for k, v in row.items()})
        results[mode] = {"csv": csv_path.name, "rows": rows}
    return results


# --- Aggregation --------------------------------------------------------------

def aggregate(runs: list[RunResult], group_by: str = "mode+scenario+load") -> dict:
    """
    Aggregate runs by group key and compute summary statistics.
    group_by: "mode+scenario+load", "scenario+load", "mode", etc.
    """
    groups: dict[str, list[RunResult]] = {}
    for r in runs:
        key = ""
        if "mode" in group_by:
            key += r.mode + "+"
        if "scenario" in group_by:
            key += r.scenario + "+"
        if "load" in group_by:
            key += r.load + "+"
        if "phase" in group_by and r.phase:
            key += r.phase + "+"
        key = key.rstrip("+")
        groups.setdefault(key, []).append(r)

    summaries = {}
    for key, grp in groups.items():
        # Flatten all metric values across runs in this group
        agg: dict[str, list[float]] = {m: [] for m in METRICS}
        for r in grp:
            for m in METRICS:
                agg[m].extend(getattr(r, m))

        s = {"group": key, "n_runs": len(grp), "n_total": sum(len(getattr(r, m)) for r in grp for m in METRICS[:1])}
        for m in METRICS:
            vals = agg[m]
            if not vals:
                continue
            m_val, ci_lo, ci_hi = ci_tdist(vals)
            s[f"{m}_median"] = median(vals)
            s[f"{m}_mean"] = m_val
            s[f"{m}_stdev"] = stdev(vals)
            s[f"{m}_n"] = len(vals)
            s[f"{m}_ci_lo"] = ci_lo
            s[f"{m}_ci_hi"] = ci_hi
            s[f"{m}_min"] = min(vals) if vals else float("nan")
            s[f"{m}_max"] = max(vals) if vals else float("nan")
        summaries[key] = s

    return summaries


# --- Comparison (A vs B) ------------------------------------------------------

def collect_raw_values(runs: list[RunResult], scenario: str, load: str,
                      metric: str, mode: str) -> list[float]:
    """
    Extract raw sample values from runs for a specific (scenario, load, metric, mode).
    Each RunResult may contain multiple measurements (e.g. from multiple bench_R*.log files).
    """
    vals: list[float] = []
    for r in runs:
        if r.mode == mode and r.scenario == scenario and r.load == load:
            m_vals = getattr(r, metric, [])
            vals.extend(m_vals)
    return vals


def compare_ab(summaries: dict, runs: list[RunResult],
               scenario: str, load: str, metric: str) -> dict:
    """Compare Mode A vs Mode B for a given (scenario, load, metric)."""
    key_a = f"A_kube-proxy+{scenario}+{load}"
    key_b = f"B_cilium-ebpfkpr+{scenario}+{load}"

    s_a = summaries.get(key_a, {})
    s_b = summaries.get(key_b, {})

    if not s_a or not s_b:
        return {}

    val_a = s_a.get(f"{metric}_mean")
    val_b = s_b.get(f"{metric}_mean")
    if val_a is None or val_b is None or (val_a == 0 and val_b == 0):
        return {}

    delta_pct = (val_b - val_a) / abs(val_a) * 100 if val_a != 0 else float("nan")
    improvement = val_a - val_b  # positive = A is slower = B is faster

    # Collect raw values for Welch's t-test
    a_vals = collect_raw_values(runs, scenario, load, metric, "A_kube-proxy")
    b_vals = collect_raw_values(runs, scenario, load, metric, "B_cilium-ebpfkpr")
    tt = welch_ttest(a_vals, b_vals)

    return {
        "scenario": scenario, "load": load, "metric": metric,
        "A_mean": val_a, "A_ci_lo": s_a.get(f"{metric}_ci_lo"),
        "A_ci_hi": s_a.get(f"{metric}_ci_hi"),
        "A_median": s_a.get(f"{metric}_median"),
        "A_stdev": s_a.get(f"{metric}_stdev"),
        "A_n": s_a.get(f"{metric}_n"),
        "B_mean": val_b, "B_ci_lo": s_b.get(f"{metric}_ci_lo"),
        "B_ci_hi": s_b.get(f"{metric}_ci_hi"),
        "B_median": s_b.get(f"{metric}_median"),
        "B_stdev": s_b.get(f"{metric}_stdev"),
        "B_n": s_b.get(f"{metric}_n"),
        "delta_pct": delta_pct,
        "improvement_ms": improvement,
        "winner": "B" if improvement > 0 else ("A" if improvement < 0 else "tie"),
        "t_stat": tt["t_stat"],
        "df": tt["df"],
        "p_value": tt["p_value"],
        "significant": tt["significant"],
    }


# --- Output formatting ---------------------------------------------------------

def fmt(v: float, decimals: int = 3) -> str:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "N/A"
    return f"{v:.{decimals}f}"


def fmt_ci(lo: float, hi: float, decimals: int = 3) -> str:
    if lo is None or hi is None:
        return "N/A"
    if math.isnan(lo) or math.isnan(hi):
        return "N/A"
    return f"[{lo:.{decimals}f}, {hi:.{decimals}f}]"


import math

def print_summary_table(summaries: dict, runs: list[RunResult],
                       scenarios: list[str], loads: list[str]):
    print("")
    print("=" * 120)
    print(" SUMMARY TABLE -- ALL RUNS")
    print(f" Confidence intervals: {CI_LEVEL*100:.0f}% using Student's t-distribution")
    print(f" Statistical significance: p < {ALPHA} (Welch's t-test, two-tailed)")
    print("=" * 120)

    for scenario in scenarios:
        for load in loads:
            if f"A_kube-proxy+{scenario}+{load}" not in summaries and f"B_cilium-ebpfkpr+{scenario}+{load}" not in summaries:
                continue

            print(f"\n  -- {scenario} x {load} -----------------------------------------------------")
            header = f"  {'Metric':<20} | {'Mode':<22} | {'n':>4} | {'Median':>10} | {'Mean+/-CI':>22} | {'StDev':>8}"
            print(header)
            print("  " + "-" * 104)

            for m in METRICS:
                label = METRIC_LABELS.get(m, m)
                for mk, ml in [("A_kube-proxy", "A (kube-proxy)"), ("B_cilium-ebpfkpr", "B (eBPF KPR)")]:
                    k = f"{mk}+{scenario}+{load}"
                    if k not in summaries:
                        continue
                    s = summaries[k]
                    n = s.get(f"{m}_n", 0) or 0
                    if n == 0:
                        continue
                    med_v = s.get(f"{m}_median")
                    m_v = s.get(f"{m}_mean")
                    ci_lo = s.get(f"{m}_ci_lo")
                    ci_hi = s.get(f"{m}_ci_hi")
                    std_v = s.get(f"{m}_stdev")
                    ci_str = fmt_ci(ci_lo, ci_hi)
                    print(f"  {label:<20} | {ml:<22} | {n:>4} | {fmt(med_v):>10} | {fmt(m_v):>7} +/- {ci_str:<12} | {fmt(std_v):>8}")

            # A vs B comparison for p99
            for m in ["p99_ms", "p50_ms", "error_rate_pct"]:
                comp = compare_ab(summaries, runs, scenario, load, m)
                if comp:
                    winner_icon = "[B]" if comp["winner"] == "B" else ("[A]" if comp["winner"] == "A" else "  tie")
                    delta_str = f"delta={fmt(comp['delta_pct'])}%  ({winner_icon})"
                    print(f"\n  {METRIC_LABELS.get(m,m)} A vs B: A={fmt(comp['A_mean'])} B={fmt(comp['B_mean'])} {delta_str}")


def print_comparison_table(summaries: dict, runs: list[RunResult],
                          scenarios: list[str], loads: list[str]):
    print("")
    print("=" * 130)
    print(" COMPARISON TABLE -- Mode A vs Mode B")
    print(" delta% = (B - A) / |A| x 100%  |  Positive = B improved over A")
    print(" CI = 95% confidence interval (Student's t-distribution)")
    print(" p  = Welch's t-test p-value (two-tailed, alpha=0.05)")
    print(" [sig] = statistically significant (p < 0.05)")
    print("=" * 130)

    all_comps = []
    for scenario in scenarios:
        for load in loads:
            for m in ["p50_ms", "p90_ms", "p99_ms", "p999_ms", "error_rate_pct", "rps"]:
                comp = compare_ab(summaries, runs, scenario, load, m)
                if comp:
                    all_comps.append(comp)

    # Grouped by metric
    by_metric: dict[str, list[dict]] = {}
    for c in all_comps:
        by_metric.setdefault(c["metric"], []).append(c)

    for metric, comps in by_metric.items():
        print(f"\n  -- {METRIC_LABELS.get(metric, metric)} --")
        print(f"  {'Scenario':<12} {'Load':<6} {'A_mean':>9} {'A_CI95':>22} {'B_mean':>9} {'B_CI95':>22} {'D%':>8} {'p-value':>10} {'Sig':>5}")
        print("  " + "-" * 115)
        for c in comps:
            sig = "[sig]" if c.get("significant") else " "
            print(
                f"  {c['scenario']:<12} {c['load']:<6} "
                f"{fmt(c['A_mean']):>9} {fmt_ci(c['A_ci_lo'], c['A_ci_hi']):>22} "
                f"{fmt(c['B_mean']):>9} {fmt_ci(c['B_ci_lo'], c['B_ci_hi']):>22} "
                f"{fmt(c['delta_pct']):>7}% {fmt(c.get('p_value'), 4):>10} {sig:>5}"
            )


def export_csv(summaries: dict, runs: list[RunResult],
              scenarios: list[str], loads: list[str], output_dir: Path):
    """Export aggregated results to CSV."""
    output_dir.mkdir(parents=True, exist_ok=True)

    # Per-group summary
    rows = []
    for key, s in summaries.items():
        row = {"group": key}
        for m in METRICS:
            for suf in ["median", "mean", "stdev", "n", "ci_lo", "ci_hi", "min", "max"]:
                v = s.get(f"{m}_{suf}")
                row[f"{m}_{suf}"] = fmt(v) if v is not None else "N/A"
        rows.append(row)

    if rows:
        cols = ["group"] + [f"{m}_{s}" for m in METRICS for s in ["median", "mean", "stdev", "n", "ci_lo", "ci_hi", "min", "max"]]
        with open(output_dir / "aggregated_summary.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
            w.writeheader()
            w.writerows(rows)
        print(f"\n  [CSV] Aggregated summary -> {output_dir / 'aggregated_summary.csv'}")

    # A vs B comparison
    comp_rows = []
    for scenario in scenarios:
        for load in loads:
            for m in METRICS:
                comp = compare_ab(summaries, runs, scenario, load, m)
                if comp:
                    comp_rows.append({
                        "scenario": scenario, "load": load, "metric": m,
                        "A_mean": fmt(comp.get("A_mean")),
                        "A_ci_lo": fmt(comp.get("A_ci_lo")),
                        "A_ci_hi": fmt(comp.get("A_ci_hi")),
                        "A_stdev": fmt(comp.get("A_stdev")),
                        "A_n": comp.get("A_n"),
                        "B_mean": fmt(comp.get("B_mean")),
                        "B_ci_lo": fmt(comp.get("B_ci_lo")),
                        "B_ci_hi": fmt(comp.get("B_ci_hi")),
                        "B_stdev": fmt(comp.get("B_stdev")),
                        "B_n": comp.get("B_n"),
                        "delta_pct": fmt(comp.get("delta_pct")),
                        "p_value": fmt(comp.get("p_value"), 4),
                        "significant": "YES" if comp.get("significant") else "NO",
                        "winner": comp.get("winner", "N/A"),
                    })

    if comp_rows:
        with open(output_dir / "comparison_AB.csv", "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(comp_rows[0].keys()))
            w.writeheader()
            w.writerows(comp_rows)
        print(f"  [CSV] A vs B comparison -> {output_dir / 'comparison_AB.csv'}")


def print_calibration_table(cal_results: dict):
    if not cal_results:
        return
    print("")
    print("=" * 80)
    print(" CALIBRATION RESULTS")
    print("=" * 80)

    for mode, data in cal_results.items():
        rows = data["rows"]
        if not rows:
            continue
        print(f"\n  -- {mode} --")
        print(f"  {'QPS':>6} {'Conns':>6} {'Run':>4} {'p50_ms':>8} {'p90_ms':>8} {'p99_ms':>8} {'p999_ms':>8} {'ErrRate%':>8} {'RPS':>8}")
        print("  " + "-" * 70)
        for r in rows:
            def g(k): v = r.get(k); return fmt(v) if v is not None else "--"
            print(
                f"  {int(r['qps']):>6} {int(r['conns']):>6} {int(r['run']):>4} "
                f"{g('p50_ms'):>8} {g('p90_ms'):>8} {g('p99_ms'):>8} {g('p999_ms'):>8} {g('error_rate_pct'):>8} {g('rps'):>8}"
            )


# --- Main ---------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Statistical analysis of benchmark results")
    parser.add_argument("--results-dir", type=Path, default=Path("results"),
                        help="Root results directory (default: ./results)")
    parser.add_argument("--output-dir", type=Path, default=Path("results_analysis"),
                        help="Where to write CSV outputs (default: ./results_analysis)")
    parser.add_argument("--ci-level", type=float, default=CI_LEVEL,
                        help=f"Confidence interval level (default: {CI_LEVEL})")
    parser.add_argument("--alpha", type=float, default=ALPHA,
                        help=f"Significance level for t-tests (default: {ALPHA})")
    args = parser.parse_args()

    results_dir = args.results_dir
    output_dir = args.output_dir

    print("=" * 80)
    print(" BENCHMARK STATISTICAL ANALYSIS")
    print(f" Results dir : {results_dir.resolve()}")
    print(f" Output dir  : {output_dir.resolve()}")
    print(f" CI level    : {CI_LEVEL*100:.0f}% (Student's t-distribution)")
    print(f" alpha (t-test)  : {ALPHA}")
    print("=" * 80)

    # Scan runs
    runs = scan_results(results_dir)
    if not runs:
        print("\n  [WARN] No benchmark results found.")
        print(f"  Expected structure: results/mode=A_kube-proxy/scenario=S1/load=L1/run=R1_*/bench.log")
        print(f"  Searched in: {results_dir}")
        sys.exit(0)

    print(f"\n  Found {len(runs)} run(s) across {len(set(r.run_id for r in runs))} unique run IDs")

    # Determine available scenarios and loads
    scenarios = sorted(set(r.scenario for r in runs))
    loads = sorted(set(r.load for r in runs))

    # Aggregate
    summaries = aggregate(runs)

    # Print tables
    print_summary_table(summaries, runs, scenarios, loads)
    print_comparison_table(summaries, runs, scenarios, loads)

    # Calibration
    cal_dir = results_dir / "calibration"
    if cal_dir.exists():
        cal_results = scan_calibration(cal_dir)
        print_calibration_table(cal_results)

    # Export CSVs
    export_csv(summaries, runs, scenarios, loads, output_dir)

    print("")
    print(f" Analysis complete. Results written to: {output_dir}")
    print("")


if __name__ == "__main__":
    main()
