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

---

## 3. Chọn Mode (A hoặc B)

### Mode A — kube-proxy baseline

> ⚠️ **Yêu cầu trước khi cài:** EKS Terraform phải KHÔNG có `vpc-cni` trong `cluster_addons`. Nếu không — Cilium sẽ crash với lỗi `"Cannot specify IPAM mode eni in tunnel mode"` hoặc `"required IPv4 PodCIDR not available"`.

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

1. Sửa `helm/cilium/values-ebpfkpr.yaml`: điền `k8sServiceHost` = EKS API endpoint
2. **Tắt kube-proxy DaemonSet:** ← BẮT BUỘC
   ```bash
   kubectl delete daemonset kube-proxy -n kube-system
   ```
3. Đợi ~30 giây cho kube-proxy pods terminated trên tất cả nodes
4. Upgrade Cilium in-place (không gỡ):
   ```bash
   helm upgrade cilium cilium/cilium \
     --namespace kube-system \
     --version 1.18.7 \
     -f helm/cilium/values-ebpfkpr.yaml
   ```
5. Verify:
   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium status
   # Phải thấy: KubeProxyReplacement: True
   ```
6. Restart workload pods (để nhận datapath mới):
   ```bash
   kubectl delete pods -n benchmark --all
   # Đợi: kubectl -n benchmark get pods (Running)
   ```

### NetworkPolicy (S3)
> **Lưu ý:** Script `run_s3.sh` **tự động** xóa và apply policies — không cần thao tác thủ công.
> Nếu muốn test thủ công trước:
```bash
# Apply toàn bộ policies (allow + deny)
kubectl apply -f workload/policies/
# Xóa
kubectl -n benchmark delete -f workload/policies/ --ignore-not-found=true
```

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
