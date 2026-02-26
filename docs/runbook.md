# Runbook

## Before running
- [ ] kubectl get nodes (Ready)
- [ ] Cilium status OK (`cilium status`)
- [ ] Hubble status OK (`hubble status`)
- [ ] Workload deployed (echo + fortio)
- [ ] Service reachable from fortio pod
- [ ] Confirm MODE is set correctly

## During run
- [ ] Do not scale nodegroup
- [ ] Do not redeploy Cilium mid-run
- [ ] Avoid heavy background tasks

## After run
- [ ] Verify results folders generated
- [ ] Save Grafana screenshots (if used)
- [ ] Note any anomalies (timeouts, pod restarts)
