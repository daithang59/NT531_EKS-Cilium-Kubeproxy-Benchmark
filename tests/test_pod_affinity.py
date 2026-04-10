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


def check_pod_antiaffinity(name: str, spec: dict):
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

    label_key = label_req[0].get("key", "")
    print(
        f"PASS: {name} deployment has podAntiAffinity "
        f"(topologyKey=kubernetes.io/hostname, labelKey={label_key})"
    )
    return label_key


def test_echo_has_pod_antiaffinity():
    spec = get_affinity_spec("echo")
    check_pod_antiaffinity("echo", spec)


def test_fortio_has_pod_antiaffinity():
    spec = get_affinity_spec("fortio")
    check_pod_antiaffinity("fortio", spec)


def test_same_label_key_across_pods():
    """Both pods must use the SAME label key in their anti-affinity selector
    so they repel each other (A avoids B via label X, B avoids A via label X).
    """
    echo_spec = get_affinity_spec("echo")
    fortio_spec = get_affinity_spec("fortio")

    def extract_label_key(spec: dict) -> str:
        aff = spec["affinity"]["podAntiAffinity"]
        return (
            aff["requiredDuringSchedulingIgnoredDuringExecution"][0]
            .get("labelSelector", {})
            .get("matchExpressions", [{}])[0]
            .get("key", "")
        )

    echo_key = extract_label_key(echo_spec)
    fortio_key = extract_label_key(fortio_spec)

    assert echo_key, "FAIL: echo podAntiAffinity label key is empty"
    assert fortio_key, "FAIL: fortio podAntiAffinity label key is empty"
    assert echo_key == fortio_key, (
        f"FAIL: echo and fortio must use the SAME label key in anti-affinity. "
        f"echo uses '{echo_key}', fortio uses '{fortio_key}'."
    )

    # Verify the label key exists on the peer pod's template labels
    def get_template_labels(filename: str) -> dict:
        resp = kubectl_get(filename)
        items = resp.get("items", [resp])
        doc = items[0]
        return doc["spec"]["template"]["metadata"]["labels"]

    echo_labels_map = get_template_labels("server/02-echo-deploy.yaml")
    fortio_labels_map = get_template_labels("client/01-fortio-deploy.yaml")

    assert echo_key in fortio_labels_map, (
        f"FAIL: echo's anti-affinity label key '{echo_key}' "
        f"is not a label on fortio pod. fortio labels: {fortio_labels_map}"
    )
    assert fortio_key in echo_labels_map, (
        f"FAIL: fortio's anti-affinity label key '{fortio_key}' "
        f"is not a label on echo pod. echo labels: {echo_labels_map}"
    )

    print(
        f"PASS: same label key '{echo_key}' used across both pods "
        f"(echo labels={echo_labels_map}, fortio labels={fortio_labels_map})"
    )


if __name__ == "__main__":
    tests = [
        test_echo_has_pod_antiaffinity,
        test_fortio_has_pod_antiaffinity,
        test_same_label_key_across_pods,
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
