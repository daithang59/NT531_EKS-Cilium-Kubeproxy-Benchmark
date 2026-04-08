#!/usr/bin/env python3
"""
fill_metadata.py -- Post-process benchmark results to fill metadata.json
with actual Fortio metrics extracted from bench.log (text output).

Usage:
    python3 scripts/fill_metadata.py
    python3 scripts/fill_metadata.py --results-dir ./results
    python3 scripts/fill_metadata.py --results-dir ./results --dry-run
"""

import argparse
import glob
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class FortioMetrics:
    rps: Optional[float] = None
    requests: Optional[int] = None
    errors: Optional[int] = None
    avg_latency_ms: Optional[float] = None
    p50_ms: Optional[float] = None
    p75_ms: Optional[float] = None
    p90_ms: Optional[float] = None
    p99_ms: Optional[float] = None
    p999_ms: Optional[float] = None
    max_ms: Optional[float] = None
    error_rate_pct: Optional[float] = None
    http_200: Optional[int] = None
    http_other: Optional[int] = None
    target_qps: Optional[float] = None
    duration_sec: Optional[float] = None
    threads: Optional[int] = None
    connections: Optional[int] = None

    def to_dict(self) -> dict:
        return {
            "rps": self.rps,
            "requests": self.requests,
            "errors": self.errors,
            "error_rate_pct": self.error_rate_pct,
            "latency_ms": {
                "avg":   self.avg_latency_ms,
                "p50":   self.p50_ms,
                "p75":   self.p75_ms,
                "p90":   self.p90_ms,
                "p99":   self.p99_ms,
                "p99.9": self.p999_ms,
                "max":   self.max_ms,
            },
            "http_200":   self.http_200,
            "http_other": self.http_other,
        }


def parse_fortio_log(log_path: Path) -> FortioMetrics:
    """
    Parse a Fortio bench.log.

    Fortio v1.74.0 multi-threaded log structure:
      [1] JSON thread-end lines   (ignored)
      [2] "All done NNN calls (plus N warmup) X ms avg, Y qps"   <- once at end
      [3] "Sleep times : count ... avg ... max ..."   (values in SECONDS)
      [4] "# range," rows
      [5] "# target 50% X" .. "# target 99.9% X"   <- SLEEP histogram (SECONDS)
      [6] "Error cases : no data"
      [7] "Aggregated Function Time : count ... avg ... max ..."  (values in MILLISECONDS)
      [8] "# range," rows
      [9] "# target 50% X" .. "# target 99.9% X"   <- FUNCTION histogram (MILLISECONDS)
     [10] "Connection time histogram"

    Single-threaded runs have only ONE set of "# target" lines (sleep = function).

    Latency percentiles: we use the LAST "# target X%" per percentile.
    - Single-threaded: only last = sleep = function (SECONDS -> multiply by 1000)
    - Multi-threaded: last = function histogram (already in MILLISECONDS)
    We detect the unit by comparing with avg_ms: if p50 << avg_ms, it is in SECONDS.

    Max: no "max" in multi-threaded "All done" -> use p999_ms.
    """
    if not log_path.exists():
        return FortioMetrics()

    content = log_path.read_text(errors="replace")
    m = FortioMetrics()

    # -- QPS + total requests ----------------------------------------
    ad = re.search(r"All done (\d+) calls.*?([\d.]+)\s+qps", content)
    if ad:
        m.requests = int(ad.group(1))
        m.rps     = float(ad.group(2))

    # -- HTTP status codes -----------------------------------------
    for line in content.splitlines():
        mc = re.match(r"Code\s+(\d+)\s+:\s+(\d+)", line)
        if mc:
            code, cnt = int(mc.group(1)), int(mc.group(2))
            if code == 200:
                m.http_200 = cnt
            else:
                m.http_other = (m.http_other or 0) + cnt
    total_http = (m.http_200 or 0) + (m.http_other or 0)
    m.errors = (m.http_other or 0)
    m.error_rate_pct = round(m.errors / total_http * 100, 4) if total_http > 0 else 0.0

    # -- Average latency from "All done ... X ms avg" (ms) ---------------
    avg_m = re.search(r"All done \d+ calls.*?([\d.]+)\s+ms avg", content)
    if avg_m:
        m.avg_latency_ms = float(avg_m.group(1))

    # -- Latency percentiles: last "# target X%" per percentile --------
    # The last occurrence is:
    #   - Sleep histogram in single-threaded (seconds -> multiply by 1000)
    #   - Function histogram in multi-threaded (milliseconds)
    # We detect unit by comparing with avg_ms.
    pct_map = [
        ("50%",  "p50_ms"),
        ("75%",  "p75_ms"),
        ("90%",  "p90_ms"),
        ("99%",  "p99_ms"),
        ("99.9", "p999_ms"),
    ]
    for pct_str, field in pct_map:
        pat = rf"# target {re.escape(pct_str)}\s+([\d.]+)"
        hits = list(re.finditer(pat, content))
        if hits:
            raw = float(hits[-1].group(1))
            # If raw << avg_ms: it's in seconds -> convert
            # Sleep histogram is always much smaller than avg_ms (which is ms round-trip).
            if m.avg_latency_ms is not None and raw < m.avg_latency_ms * 0.05:
                raw *= 1000.0
            setattr(m, field, raw)

    # -- Max latency -----------------------------------------------
    # Multi-threaded: no "max" in "All done" -> use p999_ms
    # Single-threaded: no "max" in "All done" either -> use p999_ms
    m.max_ms = m.p999_ms

    # -- Run configuration -----------------------------------------
    hdr = re.search(
        r"running at ([\d.]+) queries per second,\s*(\d+)->(\d+) procs,\s*for ([\d.]+)s:",
        content
    )
    if hdr:
        m.target_qps    = float(hdr.group(1))
        m.duration_sec = float(hdr.group(4))

    tm = re.search(r'"threads"\s*:\s*(\d+)', content)
    if tm:
        m.threads = int(tm.group(1))

    sk = re.search(r"Sockets used:\s*(\d+)", content)
    if sk:
        m.connections = int(sk.group(1))

    return m


# -- Metadata Filler ---------------------------------------------

def load_meta(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def save_meta(path: Path, data: dict):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False))


def fill_meta(meta_path: Path, metrics: FortioMetrics, dry_run: bool) -> bool:
    if not meta_path.exists():
        return False
    data = load_meta(meta_path)
    data.setdefault("results", {})
    data["results"]["fortio"] = metrics.to_dict()
    if not data.get("timestamp_end_utc"):
        from datetime import datetime, timezone
        data["timestamp_end_utc"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if "notes" not in data.get("results", {}):
        data["results"]["notes"] = ""
    if not dry_run:
        save_meta(meta_path, data)
    return True


# -- Main ----------------------------------------------------

def main():
    try:
        _REPO = Path(__file__).parent.parent.resolve()
    except NameError:
        _REPO = Path.cwd().resolve()

    ap = argparse.ArgumentParser(description="Fill metadata.json with Fortio metrics")
    ap.add_argument(
        "--results-dir", type=Path, default=_REPO / "results",
        help="Root results directory"
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rd = args.results_dir
    if not rd.exists():
        print(f"ERROR: results dir not found: {rd}")
        sys.exit(1)

    logs = sorted(glob.glob(str(rd / "mode=*/scenario=*/load=*/run=*/bench.log")))
    if not logs:
        print("No bench.log files found.")
        sys.exit(0)

    print(f"Found {len(logs)} files  |  {'DRY RUN' if args.dry_run else 'LIVE'}")
    print()

    updated = 0
    for lp in logs:
        bp  = Path(lp)
        rd2 = bp.parent
        mp  = rd2 / "metadata.json"
        rel = rd2.relative_to(rd)

        print(f"Processing: {rel}")
        metrics = parse_fortio_log(bp)

        rps_v   = metrics.rps
        avg_v   = metrics.avg_latency_ms
        p50_v   = metrics.p50_ms
        p90_v   = metrics.p90_ms
        p99_v   = metrics.p99_ms
        max_v   = metrics.max_ms
        err_v   = metrics.error_rate_pct
        print(
            f"  -> QPS={rps_v}  avg={avg_v}ms  "
            f"p50={p50_v}ms  p90={p90_v}ms  "
            f"p99={p99_v}ms  max={max_v}ms  err={err_v}%"
        )

        if fill_meta(mp, metrics, dry_run=args.dry_run):
            updated += 1
            if args.dry_run:
                print(f"     [DRY RUN] Would write: {mp}")

    print()
    print(f"{'Would update' if args.dry_run else 'Updated'}: {updated}/{len(logs)} files")


if __name__ == "__main__":
    main()
