#!/usr/bin/env python3
"""
write_metadata.py — Python reimplementation of write_metadata() from common.sh.

Populates metadata.json from:
  1. Template: results/metadata.template.json.txt
  2. Cluster: kubectl cluster-info, kubectl get nodes, kubectl version
  3. Args: mode, scenario, load, QPS, connections, duration, warmup

Usage:
  python write_metadata.py --outdir <dir> --run-num <N> --mode <A|B> \
      --scenario <S1|S2|S3> --load <L1|L2|L3> \
      --bench-qps <N> --bench-conns <N> \
      --duration-sec <N> --warmup-sec <N> \
      [--policy-metadata "enabled=true,type=CiliumNetworkPolicy,..."]

Outputs JSON to stdout (or --write <file> to write directly).
"""
import argparse
import datetime
import json
import subprocess
import sys
from pathlib import Path


def kubectl(args: list[str], timeout: int = 10) -> str:
    """Run kubectl and return stdout, or empty string on failure."""
    try:
        result = subprocess.run(
            ["kubectl"] + args,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return ""


def ts_iso() -> str:
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=7))).strftime("%Y-%m-%dT%H:%M:%S+07:00")


def ts_dir() -> str:
    return datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=7))).strftime("%Y-%m-%dT%H-%M-%S+07-00")


def collect_cluster_info() -> dict:
    """Populate cluster metadata from kubectl."""
    info: dict = {
        "cluster_name": "",
        "region": "",
        "availability_zones": [],
        "kubernetes_version": "",
        "endpoint_public_access": False,
    }

    # Cluster name: prefer context display name, fallback to server URL
    raw_info = kubectl(["cluster-info"])
    if raw_info:
        # Try to extract cluster name from context or server URL
        raw_info2 = kubectl(["config", "current-context"])
        if raw_info2:
            info["cluster_name"] = raw_info2.strip()

    # Region from node AZs — sample first node AZ
    nodes_raw = kubectl(["get", "nodes", "-o", "jsonpath={.items[0].metadata.labels.topology\\.kubernetes\\.io/zone}"])
    if nodes_raw:
        # AZ format: e.g. "ap-southeast-1a" → extract region "ap-southeast-1"
        zone = nodes_raw.strip()
        if zone and len(zone) >= 2:
            info["availability_zones"] = [zone]

    # AZ regex: last char is letter (a/b/c), strip it to get region
    if info["availability_zones"]:
        az = info["availability_zones"][0]
        if az and az[-1] in "abcdefghijklmnopqrstuvwxyz":
            info["region"] = az[:-1]
        else:
            info["region"] = az

    # Kubernetes version from node kubelet version (reliable in all environments)
    ver_raw = kubectl(["get", "nodes", "-o", "jsonpath={.items[0].status.nodeInfo.kubeletVersion}"])
    if ver_raw:
        info["kubernetes_version"] = ver_raw.strip('"')

    # Endpoint public access
    ep_raw = kubectl(["get", "svc", "kubernetes", "-o", "jsonpath={.spec.type}"])
    if ep_raw == "ClusterIP":
        info["endpoint_public_access"] = False
    elif ep_raw in ("LoadBalancer", "NodePort"):
        info["endpoint_public_access"] = True

    return info


def load_template(template_path: Path) -> dict:
    with open(template_path, encoding="utf-8") as f:
        return json.load(f)


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate benchmark metadata.json")
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--run-num", type=int, default=1)
    parser.add_argument("--mode", choices=["A", "B"], required=True)
    parser.add_argument("--scenario", choices=["S1", "S2", "S3"], required=True)
    parser.add_argument("--load", choices=["L1", "L2", "L3"], required=True)
    parser.add_argument("--bench-qps", type=int, required=True)
    parser.add_argument("--bench-conns", type=int, required=True)
    parser.add_argument("--duration-sec", type=int, required=True)
    parser.add_argument("--warmup-sec", type=int, required=True)
    parser.add_argument("--policy-metadata", default="")
    parser.add_argument("--write", help="Write output to file instead of stdout")
    parser.add_argument("--template", default="results/metadata.template.json.txt")
    args = parser.parse_args()

    repo_root = Path(__file__).parent.parent
    template_path = repo_root / args.template

    if not template_path.exists():
        print(f"[ERROR] Template not found: {template_path}", file=sys.stderr)
        sys.exit(1)

    meta = load_template(template_path)
    cluster_info = collect_cluster_info()

    # --- run metadata ---
    meta["run_id"] = f"R{args.run_num}_{ts_dir()}"
    meta["timestamp_start_utc"] = ts_iso()

    # --- mode ---
    is_mode_b = args.mode == "B"
    meta["mode"]["id"] = args.mode
    meta["mode"]["name"] = f"{args.mode}_kube-proxy" if args.mode == "A" else f"{args.mode}_cilium-ebpfkpr"

    # --- scenario ---
    scenario_names = {"S1": "Service Baseline", "S2": "Stress + Churn", "S3": "NetworkPolicy Overhead"}
    meta["scenario"]["id"] = args.scenario
    meta["scenario"]["name"] = scenario_names.get(args.scenario, args.scenario)

    # --- load ---
    meta["load_level"]["id"] = args.load
    lp = meta["load_level"]["params"]
    lp["qps"] = args.bench_qps
    lp["concurrency"] = args.bench_conns
    lp["duration_seconds"] = args.duration_sec
    lp["warmup_seconds"] = args.warmup_sec

    # --- cluster ---
    meta["cluster"]["region"] = cluster_info["region"]
    meta["cluster"]["availability_zones"] = cluster_info["availability_zones"]
    meta["cluster"]["eks"]["cluster_name"] = cluster_info["cluster_name"]
    meta["cluster"]["eks"]["kubernetes_version"] = cluster_info["kubernetes_version"]
    meta["cluster"]["eks"]["endpoint_public_access"] = cluster_info["endpoint_public_access"]

    # --- datapath: Mode A → kube-proxy enabled; Mode B → kube-proxy disabled ---
    if is_mode_b:
        meta["datapath"]["kube_proxy"]["enabled"] = False
        meta["datapath"]["cilium"]["kube_proxy_replacement"] = "true"
    else:
        meta["datapath"]["kube_proxy"]["enabled"] = True
        meta["datapath"]["cilium"]["enabled"] = False

    # --- policy metadata ---
    if args.policy_metadata:
        kv = dict(p.split("=", 1) for p in args.policy_metadata.split(",") if "=" in p)
        meta["workload"]["policy"]["enabled"] = kv.get("enabled", "true").lower() == "true"
        meta["workload"]["policy"]["type"] = kv.get("type", "CiliumNetworkPolicy")
        meta["workload"]["policy"]["complexity_level"] = kv.get("complexity_level", "simple")
        rl = kv.get("rule_count_estimate", "")
        meta["workload"]["policy"]["rule_count_estimate"] = int(rl) if rl.isdigit() else 0

    # --- output_dir ---
    meta["artifacts"]["output_dir"] = args.outdir

    output = json.dumps(meta, indent=2, ensure_ascii=False) + "\n"

    if args.write:
        Path(args.write).write_text(output, encoding="utf-8")
        print(f"[INFO] metadata.json written to {args.write}")
    else:
        sys.stdout.write(output)


if __name__ == "__main__":
    main()
