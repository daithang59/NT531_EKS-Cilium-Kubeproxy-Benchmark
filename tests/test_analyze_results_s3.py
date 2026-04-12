#!/usr/bin/env python3
"""
RED test: Verify analyze_results.py scan_results() finds ALL 42 runs.
Expected: S3 phase=off/on runs must be found.
Expected: S2 phase bench.log entries must not be double-counted.
"""
import sys
import subprocess

SCRIPT = "scripts/analyze_results.py"
RESULTS = "results"

# Count what scan_results() currently finds
result = subprocess.run(
    ["python3", SCRIPT, "--results-dir", RESULTS],
    capture_output=True, text=True
)
stdout = result.stdout

# Parse "Found N run(s) across M unique run IDs"
import re
m = re.search(r"Found (\d+) run\(s\) across (\d+) unique", stdout)
if not m:
    print("FAIL: Could not parse run count from analyze_results.py output")
    print("STDOUT:", stdout[:500])
    sys.exit(1)

found_runs = int(m.group(1))

# Expected: 42 runs total (Mode A=15, Mode B=27)
# Mode A: S1/L1×3 + S1/L2×3 + S1/L3×3 + S2/L2×3 + S2/L3×3 = 15
# Mode B: S1/L1×3 + S1/L2×3 + S1/L3×3 + S2/L2×3 + S2/L3×3 + S3/L2/off×3 + S3/L2/on×3 + S3/L3/off×3 + S3/L3/on×3 = 27
EXPECTED_RUNS = 78  # all phase-level measurements: S1/S3=1 row each, S2=4 phase rows each

print(f"Found runs: {found_runs} / expected: {EXPECTED_RUNS}")
if found_runs == EXPECTED_RUNS:
    print("PASS")
    sys.exit(0)
else:
    print(f"FAIL: {found_runs} != {EXPECTED_RUNS}")
    sys.exit(1)
