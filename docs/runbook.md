# Runbook — Benchmark Execution Guide

> Hướng dẫn từng bước chạy benchmark so sánh
> **Mode A (kube-proxy)** vs **Mode B (Cilium eBPF kube-proxy replacement)**.

---

## 1. Prerequisites

### 1.1 Infrastructure
- EKS cluster đã tạo (xem `terraform/README.md`)
- 3 nodes `t3.large`, cùng AZ, `min=desired=max=3`
- `kubectl` context trỏ đúng cluster:
  ```bash
  aws eks update-kubeconfig --name <cluster-name> --region ap-southeast-1
  kubectl get nodes   # tất cả phải Ready
  ```

### 1.2 Tools cần có trên máy Runner
- `kubectl` (>= 1.28)
- `bash` (>= 4.0, trên WSL/Linux)
- `aws` CLI (đã authenticated)
- (Mode B) `hubble` CLI (optional — script sẽ fallback qua cilium pod exec)

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
kubectl -n netperf get pods          # echo + fortio phải Running
kubectl -n netperf get svc echo      # ClusterIP, port 80 → 5678
```

### 2.4 Test connectivity
```bash
FORTIO_POD=$(kubectl -n netperf get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}')
kubectl -n netperf exec "${FORTIO_POD}" -- \
  fortio load -qps 10 -c 1 -t 5s http://echo.netperf.svc.cluster.local/
```

---

## 3. Chọn Mode (A hoặc B)

### Mode A — kube-proxy baseline
```bash
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.7 \
  -f helm/cilium/values-baseline.yaml
```
kube-proxy vẫn chạy bình thường, Cilium chỉ là CNI.

### Mode B — Cilium eBPF kube-proxy replacement
1. Sửa `helm/cilium/values-ebpfkpr.yaml`: điền `k8sServiceHost` = EKS API endpoint
2. Deploy:
   ```bash
   helm upgrade --install cilium cilium/cilium \
     --namespace kube-system \
     --version 1.18.7 \
     -f helm/cilium/values-ebpfkpr.yaml
   ```
3. Verify:
   ```bash
   kubectl -n kube-system exec ds/cilium -- cilium status
   # Phải thấy: KubeProxyReplacement: True
   ```

### (Optional) NetworkPolicy cho S3
```bash
kubectl apply -f workload/policies/01-cilium-policy-allow-fortio-to-echo.yaml
```

---

## 4. Chạy Benchmark

### 4.1 Environment variables

| Variable | Giá trị | Mô tả |
|----------|---------|-------|
| `MODE` | `A` hoặc `B` | Mode đang test |
| `LOAD` | `L1`, `L2`, `L3` | Load level |
| `REPEAT` | `3` (khuyến nghị ≥ 3) | Số lần lặp |

### 4.2 Scenario S1 — Service Baseline
```bash
MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s1.sh
```
Lặp lại toàn bộ với `MODE=B`.

### 4.3 Scenario S2 — High-load + Connection Churn
```bash
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s2.sh
```
S2 gồm 4 phase: ramp-up → sustained high → burst ×3 → cool-down.
Keepalive tắt → mỗi request mở TCP connection mới (churn).

### 4.4 Scenario S3 — NetworkPolicy Overhead
```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
```
Script tự động: xóa policy → đo (phase=off) → apply policy → đo (phase=on).

### 4.5 Chạy toàn bộ ma trận (ví dụ)
```bash
for mode in A B; do
  for load in L1 L2 L3; do
    MODE=${mode} LOAD=${load} REPEAT=3 ./scripts/run_s1.sh
    MODE=${mode} LOAD=${load} REPEAT=3 ./scripts/run_s2.sh
  done
  MODE=${mode} LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
done
```

---

## 5. Kết quả & Kiểm tra

### 5.1 Nơi lưu results
Mọi artifacts tự động tạo theo Results Contract:
```
results/
  mode=A_kube-proxy/
    scenario=S1/
      load=L1/
        run=R1_2026-02-27T14-30-00+07-00/
          bench.log, metadata.json, checklist.txt,
          kubectl_get_all.txt, kubectl_top_nodes.txt, events.txt
          (Mode B) cilium_status.txt, hubble_status.txt, hubble_flows.jsonl
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
- [ ] Nghỉ ≥ 30s giữa các runs (script tự động)

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
