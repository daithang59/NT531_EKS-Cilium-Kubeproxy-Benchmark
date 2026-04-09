#!/usr/bin/env python3
import sys
sys.path.insert(0, "scripts")
from pathlib import Path
from analyze_results import parse_fortio_log

LOG = Path("results/mode=A_kube-proxy/scenario=S2/load=L2/run=R1_2026-04-07T15-44-33+07-00/bench_phase1_rampup.log")
r = parse_fortio_log(LOG)
print("S2 phase1 rampup p99_ms:", r.get("p99_ms"))
print("S2 phase1 rampup p50_ms:", r.get("p50_ms"))
print("S2 phase1 rampup rps:", r.get("rps"))
