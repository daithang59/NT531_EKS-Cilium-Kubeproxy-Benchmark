#!/usr/bin/env python3
"""
run_fortio_rest.py — Trigger Fortio load test via REST API and save results.

This script replaces the fragile `kubectl exec > file` approach which suffers from
stream interleaving on Windows (HTTP headers appearing mid-JSON in the output file).

How it works:
  1. POST to /fortio/rest/run with load params
  2. Parse JSON response directly in Python (no shell redirection)
  3. Write formatted results to bench_<phase>.log and raw JSON to fortio_<phase>.json

Usage (called from run_s2.sh via bash _fortio_rest function):
  python3 scripts/run_fortio_rest.py \
    --pod    fortio-xxx \
    --ns     benchmark \
    --outdir results/.../run=R1 \
    --phase  phase1_rampup \
    --qps    200 \
    --conns  32 \
    --duration 30 \
    --url    http://echo.benchmark.svc.cluster.local/ \
    --keepalive false
"""

import argparse
import json
import subprocess
import sys
import time


def run_fortio(pod: str, ns: str, qps: int, conns: int,
                duration_sec: int, url: str, keepalive: bool) -> dict:
    """Trigger Fortio load test via REST API and return parsed result dict."""

    # Build REST URL (keepalive=false → new TCP per request = connection churn)
    rest_path = (
        f"http://localhost:8080/fortio/rest/run"
        f"?qps={qps}"
        f"&c={conns}"
        f"&t={duration_sec}s"
        f"&url={url}"
    )
    if not keepalive:
        rest_path += "&-keepalive=false"

    # Compute HTTP timeout: must be >= test duration + buffer
    http_timeout = duration_sec + 15

    cmd = [
        "kubectl", "-n", ns, "exec", "--request-timeout=0", pod, "--",
        "fortio", "curl", "-timeout", f"{http_timeout}s", rest_path
    ]

    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=http_timeout + 10,
    )

    combined = result.stdout + result.stderr

    # Fortio curl writes multiple JSON objects to stdout.
    # Use brace-depth scanning to find the one with "RunType" (the actual result).
    # Other objects are fortio internal log entries (ts + level + file + msg).
    depth = 0
    start = -1
    found = None
    for i, c in enumerate(combined):
        if c == "{":
            if depth == 0:
                start = i
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                try:
                    obj = json.loads(combined[start : i + 1])
                    if "RunType" in obj:
                        found = obj
                        break
                except json.JSONDecodeError:
                    pass
                start = -1

    if not found:
        # Write raw stdout/stderr to debug file for diagnosis
        debug_file = f"{json_file}.debug.txt"
        with open(debug_file, "w", encoding="utf-8", errors="replace") as df:
            df.write(f"=== kubectl exec exit: {result.returncode} ===\n")
            df.write(f"=== stdout ({len(result.stdout)} bytes) ===\n")
            df.write(result.stdout)
            df.write(f"\n=== stderr ({len(result.stderr)} bytes) ===\n")
            df.write(result.stderr)
        raise RuntimeError(
            f"No valid Fortio result JSON found. "
            f"exit={result.returncode} stdout={len(result.stdout)}B stderr={len(result.stderr)}B "
            f"debug={debug_file}"
        )

    return found


def parse_result(d: dict, qps: int, conns: int, duration_sec: int) -> str:
    """Format Fortio result dict into full human-readable text (mirrors fortio load output)."""
    dh = d.get("DurationHistogram", {})
    avg_s = dh.get("Avg", 0)
    avg_ms = avg_s * 1000

    pct_list = dh.get("Percentiles", [])
    pct_map = {p["Percentile"]: p["Value"] for p in pct_list}

    codes = d.get("RetCodes", {})
    total = sum(codes.values())
    ok200 = codes.get("200", 0)

    actual_ns = d.get("ActualDuration", 0)
    actual_s = actual_ns / 1e9
    err_count = total - ok200

    lines = []

    # === Core result line ===
    lines.append(
        f"All done {total} calls ({actual_s:.1f}s) qps={qps} "
        f"(target: {duration_sec}s, conns={conns})"
    )
    lines.append(f"  avg_ms={avg_ms:.3f}")
    for p in [50, 75, 90, 99, 99.9]:
        v = pct_map.get(p, 0)
        if v:
            lines.append(f"  p{p}={v*1000:.3f}ms")

    if err_count > 0:
        lines.append(f"  Errors: {err_count} ({round(100*err_count/total, 2) if total else 0}%)")

    # === HTTP code summary ===
    for code, count in sorted(codes.items()):
        pct = round(100 * count / total, 1) if total else 0
        lines.append(f"  Code {code}: {count} ({pct}%)")

    # === Error cases ===
    if err_count == 0:
        lines.append("Error cases : no data")

    # === Socket/IP distribution ===
    ip_map = d.get("IPCountMap", {})
    if ip_map:
        conn_stats = d.get("ConnectionStats", {})
        cs_avg = conn_stats.get("Avg", 0)
        cs_min = conn_stats.get("Min", 0)
        cs_max = conn_stats.get("Max", 0)
        lines.append("# Socket and IP used for each connection:")
        for idx, (endpoint, count) in enumerate(sorted(ip_map.items())):
            if cs_avg > 0:
                lines.append(
                    f"  [{idx}]  1 socket used, resolved to {endpoint}, "
                    f"connection timing : count {count} avg {cs_avg:.6f} "
                    f"+/- {conn_stats.get('StdDev', 0):.6f} min {cs_min:.6f} max {cs_max:.6f}"
                )
            else:
                lines.append(
                    f"  [{idx}]  1 socket used, resolved to {endpoint}, "
                    f"connection timing : count 1 avg N/A"
                )

    # === Response sizes ===
    header_sizes = d.get("HeaderSizes", {})
    if header_sizes:
        hs_count = header_sizes.get("Count", 0)
        hs_avg   = header_sizes.get("Avg", 0)
        hs_min   = header_sizes.get("Min", 0)
        hs_max   = header_sizes.get("Max", 0)
        hs_sum   = header_sizes.get("Sum", 0)
        lines.append(
            f"  Response Header Sizes : count {hs_count} avg {hs_avg:.0f} +/- 0 "
            f"min {hs_min:.0f} max {hs_max:.0f} sum {hs_sum:.0f}"
        )
    body_sizes = d.get("Sizes", {})
    if body_sizes and body_sizes.get("Count", 0) > 0:
        bs_count = body_sizes.get("Count", 0)
        bs_avg   = body_sizes.get("Avg", 0)
        bs_min   = body_sizes.get("Min", 0)
        bs_max   = body_sizes.get("Max", 0)
        bs_sum   = body_sizes.get("Sum", 0)
        lines.append(
            f"  Response Body/Total Sizes : count {bs_count} avg {bs_avg:.0f} +/- 0 "
            f"min {bs_min:.0f} max {bs_max:.0f} sum {bs_sum:.0f}"
        )

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="Run Fortio load test via REST API")
    ap.add_argument("--pod",      required=True)
    ap.add_argument("--ns",       required=True)
    ap.add_argument("--outdir",    required=True)
    ap.add_argument("--phase",     required=True)   # e.g. phase1_rampup
    ap.add_argument("--qps",       required=True,  type=int)
    ap.add_argument("--conns",     required=True,  type=int)
    ap.add_argument("--duration",  required=True,  type=int)
    ap.add_argument("--url",       required=True)
    ap.add_argument("--keepalive", default="true")

    args = ap.parse_args()
    keepalive = args.keepalive.lower() != "false"

    log_file = f"{args.outdir}/bench_{args.phase}.log"
    json_file = f"{args.outdir}/fortio_{args.phase}.json"

    # Ensure output directory exists
    import os
    os.makedirs(args.outdir, exist_ok=True)

    MAX_RETRIES = 3
    result = None
    last_error = None

    for attempt in range(1, MAX_RETRIES + 1):
        with open(log_file, "w", encoding="utf-8") as lf, \
             open(json_file, "w", encoding="utf-8") as jf:

            # Write phase header
            lf.write(f"=== Phase: {args.phase} ===\n")
            lf.write(
                f"Duration: {args.duration}s  QPS: {args.qps}  "
                f"Conns: {args.conns}  Keepalive: {'false' if not keepalive else 'true'}\n\n"
            )
            if attempt > 1:
                lf.write(f"[RETRY {attempt}/{MAX_RETRIES}]\n\n")

            try:
                result = run_fortio(
                    pod=args.pod,
                    ns=args.ns,
                    qps=args.qps,
                    conns=args.conns,
                    duration_sec=args.duration,
                    url=args.url,
                    keepalive=keepalive,
                )
            except Exception as exc:
                last_error = str(exc)
                lf.write(f"[ERROR] {exc}\n")
                jf.write(json.dumps({"error": str(exc)}))
                if attempt < MAX_RETRIES:
                    wait = attempt * 5
                    print(f"[RETRY] Phase {args.phase} attempt {attempt} failed: {exc} — retrying in {wait}s", flush=True)
                    import time
                    time.sleep(wait)
                    continue
                else:
                    print(f"[ERROR] Phase {args.phase} failed after {MAX_RETRIES} attempts: {exc}", file=sys.stderr)
                    sys.exit(0)  # Don't fail the whole run
            else:
                # Success
                json.dump(result, jf, indent=2)

                # Write startup banner (mirrors fortio load CLI output)
                ver = result.get("Version", "1.74.0")
                nproc = result.get("NumThreads", "?")
                lf.write(
                    f"Fortio {ver} running at {args.qps} queries per second, "
                    f"{nproc} procs, for {args.duration}s: {args.url}\n\n"
                )

                # Write histogram bins
                dh = result.get("DurationHistogram", {})
                hist_data = dh.get("Data", [])
                if hist_data:
                    lf.write("# range, mid point, percentile, count\n")
                    for bin in hist_data:
                        start = bin.get("Start", 0)
                        end   = bin.get("End", 0)
                        pct   = bin.get("Percent", 0)
                        count = bin.get("Count", 0)
                        mid = (start + end) / 2
                        if start < 0.001 and end <= 0.001:
                            lf.write(
                                f">= {start:.3e} <= {end:.3e} , {mid:.6f} , {pct:.2f}, {count}\n"
                            )
                        else:
                            lf.write(
                                f"> {start:.4f} <= {end:.4f} , {mid:.4f} , {pct:.2f}, {count}\n"
                            )
                    lf.write("\n")

                # Write target percentiles
                pct_list = dh.get("Percentiles", [])
                pct_map = {p["Percentile"]: p["Value"] for p in pct_list}
                for p in [50, 75, 90, 99, 99.9]:
                    v = pct_map.get(p, 0)
                    if v:
                        lf.write(f"# target {p}% {v:.6f}\n")
                lf.write("\n")

                # Write parsed summary (Code, Errors, Socket/IP, Response sizes)
                summary = parse_result(result, args.qps, args.conns, args.duration)
                lf.write(summary)
                lf.write("\n")
                if attempt > 1:
                    print(f"[OK after {attempt} retries] Phase {args.phase}: {summary.splitlines()[0]}", flush=True)
                else:
                    print(f"[OK] Phase {args.phase}: {summary.splitlines()[0]}", flush=True)
                break


if __name__ == "__main__":
    main()
