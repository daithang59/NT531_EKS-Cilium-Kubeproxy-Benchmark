# Runbook — Benchmark Execution Guide

> Hướng dẫn từng bước chạy benchmark so sánh
> **Mode A (Cilium CNI + kube-proxy)** vs **Mode B (Cilium CNI + eBPF kube-proxy replacement)**.

---

## 1. Prerequisites

### 1.1 Infrastructure
- EKS cluster đã tạo (xem `terraform/README.md`)
- 3 nodes `m5.large`, cùng AZ, `min=desired=max=3` (non-burstable)
- `kubectl` context trỏ đúng cluster:
  ```bash
  aws eks update-kubeconfig --name nt531-bm --region ap-southeast-1
  kubectl get nodes   # tất cả phải Ready
  ```

### 1.2 Tools cần có trên máy Runner
- `kubectl` (>= 1.28)
- `bash` (>= 4.0, trên WSL/Linux)
- `aws` CLI (đã authenticated)
- `python3` (>= 3.8 — cần cho scripts phân tích)
- `bc` (cho calibrate.sh)
- (Mode B) `hubble` CLI (optional — script sẽ fallback qua cilium pod exec)

### 1.3 Benchmark Environment

Truyền biến trực tiếp bằng lệnh. Biến:

| Biến | Giá trị | Mô tả |
|------|---------|--------|
| `MODE` | `A` hoặc `B` | Mode đang test |
| `LOAD` | `L1`, `L2`, `L3` | Load level |
| `REPEAT` | `3` (khuyến nghị ≥ 3) | Số lần lặp |

---

## 1bis. Calibration (bắt buộc chạy TRƯỚC bước 2)

> **Tại sao cần calibration?** Để xác định L1/L2/L3 bằng dữ liệu thực tế trên hạ tầng của bạn, thay vì dùng giá trị mặc định. T3.large burstable nên calibration càng quan trọng.

### 1bis.1 Chạy Calibration Sweep

```bash
# Deploy workload trước (xem 2.1–2.2 bên dưới)
kubectl apply -f workload/server/
kubectl apply -f workload/client/

# Chạy calibration trên Mode A trước
MODE=A REPEAT=2 ./scripts/calibrate.sh

# (Tùy chọn) Lặp lại trên Mode B để kiểm tra consistency
MODE=B REPEAT=2 ./scripts/calibrate.sh
```

### 1bis.2 Xem kết quả Calibration

Script xuất file tại:
```
results/calibration/mode=A_kube-proxy/calibration_<ts>.txt
results/calibration/mode=A_kube-proxy/calibration_<ts>.csv
```

Mở file `.txt`, xem phần **"RECOMMENDED LOAD LEVELS"**:
```
 Recommended L1 (Light):
   QPS=80  p99=1.23ms  err=0.0000%
   Suggested CONNS=6

 Recommended L2 (Medium):
   QPS=400  p99=8.45ms  err=0.0012%
   Suggested CONNS=32

 Recommended L3 (High):
   QPS=900  p99=22.30ms  err=1.234%
   Suggested CONNS=72
```

### 1bis.3 Đóng băng tham số

Cập nhật `scripts/common.sh` với giá trị từ calibration:
```bash
# L1 — Light: stable, near-zero errors
L1_QPS=80
L1_CONNS=6
L1_THREADS=2

# L2 — Medium: visible tail, no saturation
L2_QPS=400
L2_CONNS=32
L2_THREADS=4

# L3 — High: near saturation
L3_QPS=900
L3_CONNS=72
L3_THREADS=8
```

### 1bis.4 Lưu Calibration Report
- Copy file `calibration_<ts>.txt` và `calibration_<ts>.csv` vào `report/appendix/`
- Tạo biểu đồ p99 vs QPS từ CSV (dùng Python/matplotlib hoặc Excel)
- Dán vào luận văn phần Calibration Results

---

## 2. Deploy Workload

### 2.1 Namespace + Server + Service
```bash
kubectl apply -f workload/server/01-namespace.yaml
kubectl apply -f workload/server/02-echo-deploy.yaml
kubectl apply -f workload/server/03-echo-svc.yaml
```

### 2.2 Client (Fortio)
```bash
kubectl apply -f workload/client/01-fortio-deploy.yaml
```

### 2.3 Verify
```bash
kubectl -n benchmark get pods          # echo + fortio phải Running
kubectl -n benchmark get svc echo      # ClusterIP, port 80 → 5678
```

### 2.4 Test connectivity
```bash
FORTIO_POD=$(kubectl -n benchmark get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}')
kubectl -n benchmark exec "${FORTIO_POD}" -- \
  fortio load -qps 10 -c 1 -t 5s http://echo.benchmark.svc.cluster.local/
```

### 2.5 Verify DNS contract (fail-fast trước benchmark)

```bash
kubectl get svc -n kube-system kube-dns -o wide
kubectl get endpoints -n kube-system kube-dns -o wide
kubectl -n benchmark exec "${FORTIO_POD}" -- \
  fortio curl http://echo.benchmark.svc.cluster.local:80/echo
```

Nếu pod resolve DNS bị timeout (ví dụ `lookup ... on 172.20.0.10:53: i/o timeout`), reconcile CoreDNS addon:

```bash
CLUSTER_NAME=$(kubectl config current-context | sed 's|.*/||')
aws eks update-addon --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
  --addon-name coredns --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
  --addon-name coredns
```

---

## 3. Chọn Mode (A hoặc B)

### Mode A — kube-proxy baseline

> ⚠️ **Yêu cầu trước khi cài:** Terraform module EKS đã set `manage_vpc_cni = false` nên aws-node sẽ **không được cài tự động**. Nếu dùng cluster cũ (chưa có fix này) — xóa aws-node trước: `kubectl delete ds aws-node -n kube-system`. Không xóa → Cilium sẽ crash với lỗi `"Cannot specify IPAM mode eni in tunnel mode"` hoặc `"required IPv4 PodCIDR not available"`.

```bash
# Tạo namespace cần thiết:
kubectl create namespace cilium-secrets

# Cài Cilium (Mode A):
helm install cilium cilium/cilium -n kube-system --version 1.18.7 -f helm/cilium/values-baseline.yaml

# Verify:
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl get ds -n kube-system kube-proxy
```

Xác nhận: `KubeProxyReplacement: False`, `IPAM: cluster-pool`, `kube-proxy 3/3 Running`.

### Mode B — Cilium eBPF kube-proxy replacement

> ⚠️ **QUAN TRỌNG — Chuyển Mode A → Mode B:**
> Khi bật `kubeProxyReplacement: true`, Cilium eBPF thay thế **hoàn toàn** kube-proxy cho Service routing.
> **Phải tắt kube-proxy DaemonSet TRƯỚC.**
> Chạy song song → cả hai cùng thao túng NAT tables → connection drops → benchmark kết quả sai.
>
> Lưu ý: Cilium có mặt ở cả 2 mode → chỉ cần **upgrade in-place**, không cần gỡ và cài lại.

**Các bước chuyển Mode A → Mode B:**

1. **Điền `k8sServiceHost`** trong `helm/cilium/values-ebpfkpr.yaml` (nếu chưa có)
2. **Đảm bảo `eni.enabled: true`** trong `values-ebpfkpr.yaml` ← BẮT BUỘC
   - Dòng này báo cho helm chart chọn đúng `operator-aws` (thay vì `operator-generic`)
   - Nếu thiếu → cilium-operator crash với lỗi `"cilium-operator-generic: executable file not found"`
3. **Tắt kube-proxy DaemonSet:** ← BẮT BUỘC
   ```bash
   kubectl delete daemonset kube-proxy -n kube-system || true
   ```
4. Đợi ~30 giây cho kube-proxy pods terminated
5. **Upgrade Cilium in-place:**
   ```bash
   helm upgrade cilium cilium/cilium \
     --namespace kube-system \
     --version 1.18.7 \
     -f helm/cilium/values-ebpfkpr.yaml
   ```
   > ⚠️ Không dùng `--wait` — cilium-agent restart mất 2-3 phút, helm `--wait` timeout sẽ fail.
6. **Theo dõi tiến trình:**
   ```bash
   kubectl get pods -n kube-system -l app=cilium-operator -w &
   kubectl get pods -n kube-system -l k8s-app=cilium -w &
   ```
   Chờ cho đến khi `cilium-operator` và cả 3 `cilium` pods đều `Running 1/1`.
   (Thường mất 2-5 phút sau upgrade)
7. **Verify:**
   ```bash
   kubectl exec -n kube-system ds/cilium -- cilium status
   # Phải thấy:
   #   KubeProxyReplacement: True
   #   IPAM: IPv4: X/10 allocated (ENI, không phải cluster-pool)
   #   Routing: Network: Native (không phải Tunnel [vxlan])
   #   Hubble: Ok (Enabled)
   ```
8. **Restart CoreDNS** (bắt buộc sau Mode B switch):
   ```bash
   kubectl delete pods -n kube-system -l k8s-app=kube-dns
   # Đợi ~30s
   kubectl get pods -n kube-system -l k8s-app=kube-dns  # phải Running 1/1
   ```
   Lý do: kube-proxy bị xóa → CoreDNS endpoint resolver bị broken. Phải restart để pick up eBPF datapath mới.
9. **Restart workload pods** (để nhận ENI IPs):
   ```bash
   kubectl delete pods -n benchmark --all
   # Đợi: kubectl -n benchmark get pods (Running)
   ```
   Lý do: Pods cũ dùng cluster-pool IPs (10.96.x.x), không đi qua ENI native routing. Restart để nhận ENI IPs (10.0.x.x).
10. **Xóa Hubble relay và Hubble UI pods** ← BẮT BUỘC sau Mode B upgrade:
    ```bash
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-relay
    kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-ui
    # Verify ENI IP (phải là 10.0.x.x, KHÔNG phải 10.96.x.x):
    kubectl get pod -n kube-system -l app.kubernetes.io/name=hubble-relay -o jsonpath='{.items[0].status.podIP}'
    # Verify không BackOff:
    kubectl get events -n kube-system --sort-by='.lastTimestamp' | grep hubble-relay
    ```
    Lý do: Hubble relay pod giữ **cluster-pool IP (`10.96.x.x`)** từ Mode A. ENI native routing không route được `10.96.x.x` → eBPF drop packet → startup probe fail → BackOff loop. Xóa pod buộc nó nhận ENI IP mới (`10.0.x.x`).
11. **Verify kết nối:**
    ```bash
    FORTIO=$(kubectl get pods -n benchmark -l app=fortio -o jsonpath='{.items[0].metadata.name}')
    kubectl exec -n benchmark "$FORTIO" -- fortio load -qps 10 -c 1 -t 5s http://echo.benchmark.svc.cluster.local/
    # Phải thấy: Code 200, 0 errors
    ```

### Chuyển Mode B → Mode A (rollback)

Các bước tương tự nhưng ngược lại:

1. **Restore kube-proxy** (Mode A cần kube-proxy):
   ```bash
   kubectl apply -f terraform/modules/eks/kube-proxy-daemonset.yaml
   # Hoặc restore từ EKS addon:
   aws eks create-addon --cluster-name nt531-bm --region ap-southeast-1 --addon-name kube-proxy
   ```
2. **Upgrade Cilium về Mode A:**
   ```bash
   helm upgrade cilium cilium/cilium -n kube-system \
     --version 1.18.7 -f helm/cilium/values-baseline.yaml
   ```
3. **Theo dõi** đợi cả 3 cilium pods Ready
4. **Restart workload pods** (`kubectl delete pods -n benchmark --all`)
5. **Restart CoreDNS** (`kubectl delete pods -n kube-system -l k8s-app=kube-dns`)
6. **Verify**

> ⚠️ **Mỗi lần switch mode (A→B hoặc B→A), LUÔN restart workload pods.** Lý do: IPAM mode khác nhau → pod IP ranges khác nhau. Workload pods cần restart để nhận IP pool tương ứng.

### Troubleshooting Mode B Upgrade

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `cilium-operator` CrashLoopBackOff: `"cilium-operator-generic: executable not found"` | Thiếu `eni.enabled: true` trong values → chart chọn sai operator image | Thêm `eni.enabled: true` vào `values-ebpfkpr.yaml`, upgrade lại |
| `cilium-operator` CrashLoopBackOff: `dial tcp 172.20.0.1:443: i/o timeout` | Cilium BPF service entries bị stuck `non-routable` trên 1+ nodes → không kết nối được API server | Restart Cilium DaemonSet trên nodes bị ảnh hưởng: `kubectl delete pod -n kube-system -l k8s-app=cilium`; đợi pods recreate; verify: `kubectl exec -n kube-system ds/cilium -- cilium bpf lb list \| grep "172.20.0.1:443"` phải thấy backend `active` |
| `cilium` pods CrashLoopBackOff: `"Waiting for IPs to become available in CRD-backed allocation pool"` | `cilium-operator` chưa Running → không cấp IP ENI được | Đợi operator Ready trước, hoặc check operator logs |
| Fortio DNS lookup timeout: `lookup echo.benchmark.svc.cluster.local on 172.20.0.10:53: i/o timeout` | CoreDNS chưa pick up eBPF datapath | Restart CoreDNS: `kubectl delete pods -n kube-system -l k8s-app=kube-dns` |
| Fortio dial timeout trên IP trực tiếp: `dial tcp 172.20.x.x:80: i/o timeout` | Workload pods giữ cluster-pool IPs (10.96.x.x) | Restart workload pods: `kubectl delete pods -n benchmark --all` |
| `hubble-relay` BackOff: `timeout: failed to connect service "10.96.x.x:4222"` | Hubble relay pod giữ cluster-pool IP (`10.96.x.x`) sau Mode A→B upgrade — ENI native routing không route được dải này → startup probe fail → BackOff loop | Xóa relay và UI pods để buộc nhận ENI IP: `kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-relay && kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-ui` |

### ⚠️ Confound giữa Mode A và Mode B — IPAM mode

> **Đọc kỹ trước khi chạy.** Thông tin này cần ghi nhận trong thesis/report.

Mode A và Mode B **khác nhau ở 2 biến** thay vì 1:

| | Mode A | Mode B |
|---|---|---|
| **IPAM** | `cluster-pool` (dải IP riêng Cilium) | `eni` (VPC native ENI) |
| **Datapath** | kube-proxy iptables DNAT/SNAT | eBPF socket-level redirect |

→ Δ hiệu năng = **eBPF effect** + **NAT/overlay removal effect**. Không isolate riêng được. Cả 2 đều là production-grade config — phản ánh cách deploy thực tế trên EKS. Xem `docs/experiment_spec.md` §12 (Threats to Validity) để biết cách trình bày trong thesis.

### NetworkPolicy (S3)
> **Lưu ý:** Script `run_s3.sh` **tự động** xóa và apply policies — không cần thao tác thủ công.
> Nếu muốn test thủ công trước:
```bash
# Apply toàn bộ policies (allow + deny)
kubectl apply -f workload/policies/
# Xóa
kubectl -n benchmark delete -f workload/policies/ --ignore-not-found=true
```

### ⚠️ Monitoring / Grafana không hoạt động sau switch A→B

> Sau khi switch Mode A→B, tất cả monitoring pods trong namespace `monitoring` giữ cluster-pool IPs (10.96.x.x) cũ. Chúng không thể reach Kubernetes API server vì:
> - cluster-pool IP range không còn routeable qua ENI native routing
> - Cilium ENI mode chỉ hỗ trợ ENI IPs (10.0.x.x)
>
> **Ảnh hưởng:** Grafana dashboards trống, Prometheus không scrape được metrics.

**Fix — Helm upgrade monitoring (tốt nhất):**
```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack -n monitoring \
  --version 60.0.0 -f helm/monitoring/values.yaml \
  --timeout 10m
# Helm sẽ terminate và recreate tất cả pods
```

**Fix nhanh (nếu helm upgrade không khả thi):**
```bash
# Xóa từng pod để buộc nhận ENI IP mới
kubectl delete pod -n monitoring prometheus-kube-prometheus-prometheus-0
kubectl delete pod -n monitoring -l app.kubernetes.io/name=grafana
kubectl delete pod -n monitoring -l app.kubernetes.io/name=kube-prometheus-operator
# Monitor:
kubectl get pods -n monitoring -w
```

**Verify Grafana đã hoạt động:**
```bash
# Port-forward (chú ý: service port là 80, không phải 3000)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Lấy password (service name khác với secret name):
kubectl get secret -n monitoring -l app.kubernetes.io/component=admin-secret -o jsonpath='{.items[0].data.admin-password}' | base64 -d
# Username: admin
```

Truy cập http://localhost:3000
- Dashboard "Kubernetes / Compute Resources / Node" → có data
- Dashboard "Kubernetes / Compute Resources / Pods" → có data

---

## 4. Chạy Benchmark

### 4.2 Scenario S1 — Service Baseline

```bash
MODE=A LOAD=L1 ./scripts/run_s1.sh
MODE=A LOAD=L2 ./scripts/run_s1.sh
MODE=A LOAD=L3 ./scripts/run_s1.sh
```

Lặp lại với `MODE=B`.

### 4.3 Scenario S2 — High-load + Connection Churn

```bash
MODE=A LOAD=L2 ./scripts/run_s2.sh
MODE=A LOAD=L3 ./scripts/run_s2.sh
```
S2 gồm 4 phase: ramp-up → sustained → burst ×3 → cool-down.
Keepalive tắt → mỗi request mở TCP connection mới (churn).
L1 không chạy S2 vì QPS quá thấp không stress được conntrack.

### 4.4 Scenario S3 — NetworkPolicy Overhead (Mode B)

```bash
MODE=B LOAD=L2 ./scripts/run_s3.sh
MODE=B LOAD=L3 ./scripts/run_s3.sh
```
Script tự động: xóa policy → đo (phase=off) → apply policy → đo (phase=on).
S3 chỉ chạy ở Mode B. Mode A không cần.

### 4.5 Tổng hợp

```bash
# Mode A — S1, S2
MODE=A LOAD=L1 ./scripts/run_s1.sh
MODE=A LOAD=L2 ./scripts/run_s1.sh
MODE=A LOAD=L3 ./scripts/run_s1.sh
MODE=A LOAD=L2 ./scripts/run_s2.sh
MODE=A LOAD=L3 ./scripts/run_s2.sh

# Mode B — S1, S2, S3
MODE=B LOAD=L1 ./scripts/run_s1.sh
MODE=B LOAD=L2 ./scripts/run_s1.sh
MODE=B LOAD=L3 ./scripts/run_s1.sh
MODE=B LOAD=L2 ./scripts/run_s2.sh
MODE=B LOAD=L3 ./scripts/run_s2.sh
MODE=B LOAD=L2 ./scripts/run_s3.sh
MODE=B LOAD=L3 ./scripts/run_s3.sh
```

---

## 5. Kết quả & Kiểm tra

### 5.1 Nơi lưu results
Mọi artifacts tự động tạo theo Results Contract:

**S1 (steady-state):**
```
results/
  mode=A_kube-proxy/
    scenario=S1/
      load=L1/
        run=R1_2026-02-27T14-30-00+07-00/
          bench.log             # Fortio output (latency, RPS, errors)
          metadata.json         # Run config (từ template)
          checklist.txt         # Runner/Checker validation
          kubectl_get_all.txt   # kubectl get all -A
          kubectl_top_nodes.txt # kubectl top nodes
          events.txt            # kubectl get events
          cilium_status.txt     # (Mode B / S3)
          hubble_status.txt     # (Mode B / S3)
          hubble_flows.jsonl    # (Mode B / S3)
```

**S2 (multi-phase) — thêm per-phase logs:**
```
results/mode=…/scenario=S2/load=…/run=R1_…/
  bench.log                    # Combined tất cả phases
  bench_phase1_rampup.log      # Phase 1: ramp-up 50% QPS
  bench_phase2_sustained.log   # Phase 2: sustained 100% QPS
  bench_phase3_bursts.log      # Phase 3: burst ×3 150% QPS
  bench_phase4_cooldown.log    # Phase 4: cool-down 50% QPS
  metadata.json, checklist.txt, kubectl_*.txt, events.txt, …
```

**S3 (policy toggle) — tách theo phase:**
```
results/mode=…/scenario=S3/load=…/
  phase=off/
    run=R1_…/                  # Benchmark KHI KHÔNG có policy
      bench.log, metadata.json, checklist.txt, …
  phase=on/
    run=R1_…/                  # Benchmark KHI CÓ policy
      bench.log, metadata.json, checklist.txt, …
      cilium_status.txt, hubble_flows.jsonl
```

### 5.2 Tiêu chí 1 run hợp lệ
Mở `checklist.txt` trong mỗi run folder và xác nhận:
- [ ] Tất cả Pre-run checks pass
- [ ] MODE / SCENARIO / LOAD / REPEAT đúng
- [ ] `bench.log` không trống, có latency percentiles
- [ ] Không có pod restart / OOM / node NotReady trong `events.txt`
- [ ] `metadata.json` hợp lệ (valid JSON)
- [ ] (Mode B / S3) `hubble_flows.jsonl` có dữ liệu

### 5.3 Anomalies
Nếu phát hiện bất thường (timeout, error rate cao, pod restart), ghi vào
`metadata.json` → `results.anomalies[]` và đánh dấu trong `checklist.txt`.

---

## 6. Quy tắc khi chạy

### Before running
- [ ] `kubectl get nodes` — tất cả Ready
- [ ] (Mode B) `cilium status` OK, `hubble status` OK
- [ ] Workload deployed (echo + fortio Running)
- [ ] Service reachable (`fortio load -t 5s`)
- [ ] Xác nhận `MODE` đúng mode hiện tại

### During run
- [ ] **KHÔNG** scale nodegroup
- [ ] **KHÔNG** redeploy/upgrade Cilium
- [ ] **KHÔNG** chạy heavy background tasks
- [ ] Nghỉ ≥ 60s giữa các runs (script tự động, default `REST_BETWEEN_RUNS=60`)

### After run
- [ ] Verify `results/` folders đã tạo đầy đủ
- [ ] Kiểm tra `checklist.txt` cho mỗi run
- [ ] (Optional) Chụp Grafana dashboards vào folder run
- [ ] Ghi chép anomalies nếu có

---

## 7. Load Level Reference

| Level | QPS | Connections | Threads | Mục đích |
|-------|-----|-------------|---------|----------|
| L1 | 100 | 8 | 2 | Light — near-zero error, stable p99 |
| L2 | 500 | 32 | 4 | Medium — tail latency visible |
| L3 | 1000 | 64 | 8 | High — near saturation |

> Giá trị mặc định. Điều chỉnh qua env vars sau khi calibration.
> Xem `docs/experiment_spec.md` § 7 về quy trình Calibration.
