#!/usr/bin/env python3
"""
RED: fortio and echo pods must have same-node podAntiAffinity
so that the benchmark measures single-hop latency (same node).

Checks:
  1. Both Deployments have podAntiAffinity (not just nodeSelector)
  2. Topology key = kubernetes.io/hostname (same physical node)
  3. Both use the same label key in the anti-affinity selector
     so they repel each other onto the same node

Uses 'kubectl get -f -o yaml' to validate YAML syntax AND resource spec
directly — no yaml module dependency needed.
"""
import sys
import subprocess
import json

WORKLOAD_DIR = "workload"


def kubectl_get(filename: str) -> dict:
    """Apply dry-run and return the full resource spec as parsed JSON."""
    path = f"{WORKLOAD_DIR}/{filename}"
    result = subprocess.run(
        ["kubectl", "get", "-f", path, "-o", "json"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        raise AssertionError(f"FAIL: kubectl get -f {path} failed:\n{result.stderr}")
    return json.loads(result.stdout)


def get_affinity_spec(deployment_name: str) -> dict:
    path_map = {
        "echo": "server/02-echo-deploy.yaml",
        "fortio": "client/01-fortio-deploy.yaml",
    }
    resp = kubectl_get(path_map[deployment_name])
    items = resp.get("items", [resp])
    doc = items[0]
    # kubectl get -f for a single YAML returns a dict directly,
    # not {"items": [...]}, so handle both shapes
    if "kind" in doc:
        pass  # single-doc YAML, already unwrapped
    else:
        doc = items[0] if items else doc
    return doc["spec"]["template"]["spec"]


def check_pod_antiaffinity(name: str, spec: dict) -> tuple[str, str]:
    """Returns (label_key, label_value) for the anti-affinity selector."""
    assert "affinity" in spec, (
        f"FAIL: {name} deployment — spec.template.spec.affinity is missing. "
        "Pod may land on different node from peer. "
        "Add affinity.podAntiAffinity to guarantee same-node placement."
    )

    aff = spec["affinity"]
    assert "podAntiAffinity" in aff, (
        f"FAIL: {name} deployment — affinity.podAntiAffinity is missing. "
        "PodAntiAffinity is required to co-locate fortio + echo on same node."
    )

    pa = aff["podAntiAffinity"]
    assert "requiredDuringSchedulingIgnoredDuringExecution" in pa, (
        f"FAIL: {name} deployment — "
        "podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution is missing. "
        "Use required (not preferred) to guarantee same-node placement."
    )

    terms = pa["requiredDuringSchedulingIgnoredDuringExecution"]
    assert len(terms) > 0, (
        f"FAIL: {name} deployment — "
        "requiredDuringSchedulingIgnoredDuringExecution is empty."
    )

    term = terms[0]
    topology_key = term.get("topologyKey", "")
    assert topology_key == "kubernetes.io/hostname", (
        f"FAIL: {name} deployment — topologyKey must be 'kubernetes.io/hostname' "
        f"to pin pods to same node. Got: '{topology_key}'"
    )

    label_req = term.get("labelSelector", {}).get("matchExpressions", [])
    assert len(label_req) > 0, (
        f"FAIL: {name} deployment — labelSelector.matchExpressions is empty. "
        "Need a label selector to identify the peer pod so they repel each other."
    )

    expr = label_req[0]
    label_key = expr.get("key", "")
    label_values = expr.get("values", [])
    assert label_values, (
        f"FAIL: {name} deployment — labelSelector matchExpression has no values. "
        "Use a shared label VALUE (e.g. 'workload') so both pods repel each other."
    )
    label_value = label_values[0]

    print(
        f"PASS: {name} deployment has podAntiAffinity "
        f"(topologyKey=kubernetes.io/hostname, labelKey={label_key}, "
        f"labelValue={label_value})"
    )
    return label_key, label_value


def test_echo_has_pod_antiaffinity():
    spec = get_affinity_spec("echo")
    key, value = check_pod_antiaffinity("echo", spec)
    assert key and value, f"FAIL: echo returned empty key={key!r} or value={value!r}"


def test_fortio_has_pod_antiaffinity():
    spec = get_affinity_spec("fortio")
    key, value = check_pod_antiaffinity("fortio", spec)
    assert key and value, f"FAIL: fortio returned empty key={key!r} or value={value!r}"


def test_mutual_repulsion_same_label_value():
    """Both pods must use the SAME label VALUE so each repels the other.
    key: app + Exists  = echo avoids echo, fortio avoids fortio  ← WRONG (no mutual repulsion)
    key: pair + In [workload] = echo avoids workload, fortio avoids workload ← CORRECT (mutual repulsion)
    """
    echo_spec = get_affinity_spec("echo")
    fortio_spec = get_affinity_spec("fortio")

    _, echo_value = check_pod_antiaffinity("echo", echo_spec)
    _, fortio_value = check_pod_antiaffinity("fortio", fortio_spec)

    assert echo_value == fortio_value, (
        f"FAIL: echo and fortio must use the SAME label VALUE for mutual repulsion. "
        f"echo anti-affinity selects '{echo_value}', fortio selects '{fortio_value}'. "
        "Different values mean each pod only avoids ITSELF, not each other — "
        "they may land on different nodes."
    )

    # Verify the shared label key+value exists on BOTH pod templates
    def get_template_labels(filename: str) -> dict:
        resp = kubectl_get(filename)
        items = resp.get("items", [resp])
        doc = items[0]
        return doc["spec"]["template"]["metadata"]["labels"]

    echo_labels_map = get_template_labels("server/02-echo-deploy.yaml")
    fortio_labels_map = get_template_labels("client/01-fortio-deploy.yaml")

    key_used = "app.benchmark/pair"  # the shared label key

    assert echo_labels_map.get(key_used) == echo_value, (
        f"FAIL: echo pod template does not have label '{key_used}={echo_value}'. "
        f"echo labels: {echo_labels_map}"
    )
    assert fortio_labels_map.get(key_used) == echo_value, (
        f"FAIL: fortio pod template does not have label '{key_used}={echo_value}'. "
        f"fortio labels: {fortio_labels_map}"
    )

    print(
        f"PASS: mutual repulsion achieved — both pods use label '{key_used}={echo_value}' "
        f"(echo labels={echo_labels_map}, fortio labels={fortio_labels_map})"
    )


if __name__ == "__main__":
    tests = [
        test_echo_has_pod_antiaffinity,
        test_fortio_has_pod_antiaffinity,
        test_mutual_repulsion_same_label_value,
    ]

    failed = 0
    for t in tests:
        try:
            t()
        except AssertionError as e:
            print(e)
            failed += 1
        except Exception as e:
            print(f"ERROR in {t.__name__}: {e}")
            failed += 1

    if failed:
        print(f"\n{failed} test(s) FAILED — podAntiAffinity not configured")
        sys.exit(1)
    print(f"\n{len(tests)} test(s) PASSED")
    sys.exit(0)
