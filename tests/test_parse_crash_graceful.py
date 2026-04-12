#!/usr/bin/env python3
"""
RED: parse_fortio_log() must return {} for a log file that ends with Fortio crash.
GREEN: It already does — verify.
"""
import sys
import tempfile, pathlib

sys.path.insert(0, "scripts")
from analyze_results import parse_fortio_log

# Write a simulated crash log
with tempfile.NamedTemporaryFile(mode="w", suffix=".log", delete=False) as f:
    f.write('=== Phase 1: RAMP-UP ===\n')
    f.write('{"ts":1234567890.0,"msg":"Starting"}\n')
    f.write('Fortio 1.74.0 running at 200 queries per second\n')
    f.write('Starting at 200 qps ...\n')
    f.write('{"ts":1234567900.0,"msg":"T001 ended"}\n')
    f.write('E wsarecv: connection forcibly closed\n')
    f.write('error: error reading from error stream\n')
    crash_log = pathlib.Path(f.name)

try:
    result = parse_fortio_log(crash_log)
    # All metric fields should be None / empty for a crash log
    has_data = any(v for k, v in result.items() if k != "error_rate_pct" and v is not None)
    if has_data:
        print(f"FAIL: crash log returned non-None metrics: {result}")
        sys.exit(1)
    print(f"PASS: crash log correctly returns all-None metrics")
    sys.exit(0)
finally:
    crash_log.unlink()
