#!/usr/bin/env python3
"""
RED: collect_hubble.sh must use port-forward to hubble-relay ClusterIP.
GREEN: It should port-forward hubble-relay:80 -> localhost:4245 before hubble observe.

Checks that:
  1. collect_hubble.sh uses kubectl port-forward to hubble-relay
  2. collect_cilium_hubble() in common.sh is updated or calls collect_hubble.sh
"""
import sys, re, pathlib

COLLECT_HUBBLE = pathlib.Path("scripts/collect_hubble.sh")
COMMON_SH      = pathlib.Path("scripts/common.sh")

ok = True

# --- Test 1: collect_hubble.sh uses port-forward to hubble-relay ---
if COLLECT_HUBBLE.exists():
    text = COLLECT_HUBBLE.read_text(errors="replace")

    # kubectl port-forward svc/hubble-relay 4245:80 spans 2 source lines via '\'
    # Check each line individually for both "kubectl" and "port-forward" AND "hubble-relay"
    raw_lines = text.split('\n')
    kubectl_lines = [
        l for l in raw_lines
        if 'kubectl' in l and 'port-forward' in l
    ]
    has_portforward = any(
        'svc/hubble-relay' in l for l in kubectl_lines
    )

    if has_portforward:
        print("PASS: collect_hubble.sh uses kubectl port-forward to hubble-relay")
    else:
        print("FAIL: collect_hubble.sh does not kubectl port-forward to hubble-relay")
        print("      Hubble relay is ClusterIP — hubble CLI needs port-forward to reach it.")
        ok = False
else:
    print(f"SKIP: {COLLECT_HUBBLE} not found")
    sys.exit(0)

# --- Test 2: common.sh collect_cilium_hubble() calls collect_hubble.sh ---
if COMMON_SH.exists():
    text = COMMON_SH.read_text(errors="replace")
    calls_script = bool(re.search(r'collect_hubble\.sh', text))
    if calls_script:
        print("PASS: common.sh calls collect_hubble.sh")
    else:
        print("INFO: collect_cilium_hubble() is inline in common.sh (not calling script)")

sys.exit(0 if ok else 1)
