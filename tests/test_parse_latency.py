#!/usr/bin/env python3
"""Verify parse_fortio_log reads REQUEST latency, not CONNECTION latency.
S2 rampup log shows: p99=0.000545s vs combined bench.log header: p99=0.001512s.
We want request-level histogram values, not connection-level ones.
"""
import sys
from pathlib import Path
sys.path.insert(0, "scripts")
from analyze_results import parse_fortio_log

# Use the actual S2 rampup phase log which has both connection-level stats
# and request-level stats clearly separated
log = Path("results/mode=A_kube-proxy/scenario=S2/load=L2/run=R1_2026-04-07T15-44-33+07-00/bench_phase1_rampup.log")
if not log.exists():
    print(f"SKIP: {log} not found")
    sys.exit(0)  # skip if runs not available locally

text = log.read_text(errors="replace")
# Fortio prints two histograms per phase: connection then request
# "# target 99% VALUE" lines appear in order: connection first, request second
import re
targets = re.findall(r"# target 99%\s+([0-9.e+-]+)", text)
if len(targets) < 2:
    print("SKIP: not enough percentile lines to distinguish")
    sys.exit(0)

# parse_fortio_log should return the REQUEST histogram (second appearance, higher value)
result = parse_fortio_log(log)
p99 = result.get("p99_ms")
req_p99 = float(targets[1]) * 1000  # request p99 in ms
conn_p99 = float(targets[0]) * 1000    # connection p99 in ms

print(f"Connection p99: {conn_p99:.3f} ms")
print(f"Request p99:     {req_p99:.3f} ms")
print(f"Parsed p99:       {p99} ms")
ratio = req_p99 / conn_p99
print(f"Ratio req/conn:  {ratio:.2f}x")

# The request value should be HIGHER than connection (more latency variance)
if p99 is None:
    print("FAIL: p99 is None")
    sys.exit(1)
# Allow 20% tolerance for rounding
if abs(p99 - req_p99) / req_p99 < 0.20:
    print("PASS: p99 matches request-level value")
    sys.exit(0)
else:
    # Likely got connection-level value instead
    print(f"FAIL: parsed p99={p99:.3f} does not match request p99={req_p99:.3f}")
    sys.exit(1)
