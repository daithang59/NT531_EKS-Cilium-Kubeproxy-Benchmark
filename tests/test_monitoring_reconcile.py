#!/usr/bin/env python3
"""
RED: Mode B installation must trigger kube-prometheus-stack reconciliation
so that Cilium metrics scrape targets are updated after Cilium (re)install.

Checks:
  1. docs/runbook.md documents the monitoring reconcile step for Mode A-&gt;B switch
  2. The reconciliation uses 'helm upgrade' (preferred) or 'kubectl rollout restart'
     — NOT a manual 'kubectl delete pod' loop
"""
import sys
import pathlib
import subprocess
import json

DOCS = pathlib.Path("docs/runbook.md")


def check_runbook_documents_reconcile():
    """docs/runbook.md must document the monitoring reconcile step."""
    assert DOCS.exists(), (
        f"FAIL: {DOCS} does not exist. "
        "The runbook must document the Mode A-&gt;B monitoring reconcile step."
    )

    content = DOCS.read_text(encoding="utf-8", errors="replace").lower()

    has_monitoring_mention = (
        "monitoring" in content or "prometheus" in content or "grafana" in content
    )
    assert has_monitoring_mention, (
        f"FAIL: {DOCS} does not mention monitoring/prometheus. "
        "Document the kube-prometheus-stack reconciliation step for Mode A-&gt;B switch."
    )

    has_reconcile_keyword = any(
        kw in content
        for kw in ["helm upgrade", "rollout restart", "reconcil", "reload"]
    )
    assert has_reconcile_keyword, (
        f"FAIL: {DOCS} mentions monitoring but does not describe reconciliation "
        "(helm upgrade / rollout restart / reconcil). "
        "After Cilium Mode B install, kube-prometheus-stack must be reconciled "
        "so that Cilium scrape targets are refreshed."
    )

    print(f"PASS: {DOCS} documents monitoring reconcile step for Mode A-&gt;B switch")


def check_reconciliation_is_automated():
    """The reconciliation should use 'helm upgrade' (preferred) or 'kubectl rollout restart',
    not a manual 'kubectl delete pod' loop."""
    content = DOCS.read_text(encoding="utf-8")

    has_helm_upgrade = "helm upgrade" in content and "prometheus" in content.lower()
    has_rollout_restart = "kubectl rollout restart" in content

    assert has_helm_upgrade or has_rollout_restart, (
        "FAIL: docs/runbook.md does not include 'helm upgrade' or 'kubectl rollout restart' "
        "for prometheus/monitoring. "
        "Using 'kubectl delete pod' in a loop is error-prone — "
        "prefer 'helm upgrade' (triggers full reconciliation) or "
        "'kubectl rollout restart statefulset'."
    )

    method = "helm upgrade" if has_helm_upgrade else "kubectl rollout restart"
    print(f"PASS: reconciliation uses '{method}' (automated, not kubectl delete pod loop)")


def check_monitoring_namespace_exists():
    """kube-prometheus-stack must be installed in 'monitoring' namespace."""
    result = subprocess.run(
        ["kubectl", "get", "ns", "monitoring", "-o", "jsonpath={.metadata.name}"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, (
        f"FAIL: namespace 'monitoring' does not exist. "
        "kube-prometheus-stack must be installed before running benchmarks. "
        "See helm/monitoring/values.yaml."
    )
    print("PASS: monitoring namespace exists")


def check_prometheus_running():
    """Prometheus pods must be Running (ready to scrape after reconciliation)."""
    result = subprocess.run(
        ["kubectl", "get", "pod", "-n", "monitoring",
         "-l", "app.kubernetes.io/name=prometheus",
         "-o", "jsonpath={.items[0].status.phase}"],
        capture_output=True, text=True,
    )
    phase = result.stdout.strip()
    assert phase == "Running", (
        f"FAIL: Prometheus pod is not Running (phase={phase!r}). "
        "Check: kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus"
    )
    print(f"PASS: Prometheus pod is Running (phase={phase})")


if __name__ == "__main__":
    tests = [
        check_runbook_documents_reconcile,
        check_reconciliation_is_automated,
        check_monitoring_namespace_exists,
        check_prometheus_running,
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
        print(f"\n{failed} test(s) FAILED — monitoring reconcile not documented/automated")
        sys.exit(1)
    print(f"\n{len(tests)} test(s) PASSED")
    sys.exit(0)
