#!/usr/bin/env python3
"""
RED: run_fortio() must fail when Fortio exits non-zero (crash).
GREEN: run_fortio() propagates Fortio exit code; caller sees non-zero.

We simulate this by checking the common.sh run_fortio function
does NOT have "|| true" on the measurement command.
"""
import sys, re, pathlib

SCRIPT = pathlib.Path("scripts/common.sh")
if not SCRIPT.exists():
    print(f"SKIP: {SCRIPT} not found")
    sys.exit(0)

text = SCRIPT.read_text(errors="replace")

# Find the measurement command line (contains bench.log tee + || true)
measurement_line = re.search(
    r'2>&1\s+\|\s*tee\s+"\${outdir}/bench\.log"\s+\|\|\s*true',
    text
)
if measurement_line:
    print("FAIL: measurement command has '|| true' — crash exit code is swallowed")
    sys.exit(1)

print("PASS: run_fortio measurement propagates exit code correctly")
sys.exit(0)
