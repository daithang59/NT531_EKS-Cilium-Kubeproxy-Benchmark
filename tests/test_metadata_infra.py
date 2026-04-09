#!/usr/bin/env python3
"""
RED: write_metadata() must populate infrastructure metadata from cluster.
GREEN: metadata.json contains cluster_name, region, availability_zones, kubernetes_version.
"""
import sys, json, pathlib, subprocess, tempfile

# We'll test the Python helper script that write_metadata() delegates to
HELPER = pathlib.Path("scripts/write_metadata.py")
TEMPLATE = pathlib.Path("results/metadata.template.json.txt")

if not HELPER.exists():
    print(f"FAIL: {HELPER} not found — write_metadata must be rewritten in Python")
    sys.exit(1)

if not TEMPLATE.exists():
    print(f"SKIP: {TEMPLATE} not found")
    sys.exit(0)

# Call the helper with mock values
result = subprocess.run(
    [
        sys.executable, str(HELPER),
        "--outdir", str(tempfile.mkdtemp()),
        "--run-num", "1",
        "--mode", "B",
        "--scenario", "S1",
        "--load", "L1",
        "--bench-qps", "100",
        "--bench-conns", "8",
        "--duration-sec", "180",
        "--warmup-sec", "30",
    ],
    capture_output=True, text=True
)

if result.returncode != 0:
    print(f"FAIL: write_metadata.py exited {result.returncode}")
    print("STDERR:", result.stderr[:300])
    sys.exit(1)

# Parse output JSON (helper writes to stdout if --write not given)
try:
    meta = json.loads(result.stdout)
except json.JSONDecodeError:
    print("FAIL: output is not valid JSON")
    print("STDOUT:", result.stdout[:300])
    sys.exit(1)

# Check infrastructure fields are populated
eks = meta.get("cluster", {}).get("eks", {})
cluster_name = eks.get("cluster_name", "")
region = meta.get("cluster", {}).get("region", "")
k8s_version = eks.get("kubernetes_version", "")
azs = meta.get("cluster", {}).get("availability_zones", [])

errors = []
if not cluster_name:
    errors.append("cluster.cluster_name is empty")
if not region:
    errors.append("cluster.region is empty")
if not k8s_version:
    errors.append("cluster.eks.kubernetes_version is empty")
if not azs or azs == [""]:
    errors.append("cluster.availability_zones is empty")

if errors:
    print("FAIL: infrastructure metadata not populated:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)

# Check Mode B kube_proxy.enabled = false
kp = meta.get("datapath", {}).get("kube_proxy", {})
if kp.get("enabled") is True:
    print("FAIL: Mode B but kube_proxy.enabled=true — should be false")
    sys.exit(1)

print(f"PASS: metadata.json populated — cluster={cluster_name} region={region} k8s={k8s_version} AZs={azs}")
sys.exit(0)
