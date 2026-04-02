# Runbook — Benchmark Execution Guide

> Hướng dẫn từng bước chạy benchmark so sánh
> **Mode A (kube-proxy)** vs **Mode B (Cilium eBPF kube-proxy replacement)**.

---

## 1. Prerequisites

### 1.1 Infrastructure
- EKS cluster đã tạo (xem `terraform/README.md`)
- 3 nodes `t3.large`, cùng AZ, `min=desired=max=3`

### 1.2 Tools cần có trên máy Runner
- `kubectl` (>= 1.28)
- `bash` (>= 4.0, trên WSL/Linux)
- `aws` CLI (đã authenticated)
- (Mode B) `hubble` CLI (optional — script sẽ fallback qua cilium pod exec)

---

## 2. EKS Access Configuration

> **⚠️ Quan trọng:** Sau khi `terraform apply` xong, `kubectl` **không tự động chạy được**.
> `aws eks update-kubeconfig` thành công chỉ tạo kubeconfig — không có nghĩa principal đã có quyền trên cluster.
> Phải tạo **EKS Access Entry + Policy Association** cho IAM principal.
> Nếu bỏ qua, `kubectl get nodes` sẽ bị:
> `error: You must be logged in to the server (Unauthorized)`.

---

### A. Verify EKS Access After Terraform

Luôn chạy **tất cả** theo thứ tự để biết chính xác vấn đề ở đâu:

```bash
# 1. Xác nhận IAM identity đang dùng
aws sts get-caller-identity
# → Ghi lại ARN — đây là <IAM_PRINCIPAL_ARN> cần kiểm tra

# 2. Verify authentication mode
aws eks describe-cluster \
  --name nt531 \
  --region ap-southeast-1 \
  --query 'cluster.accessConfig.authenticationMode'
# → "API_AND_CONFIG_MAP"

# 3. Verify token lấy được
aws eks get-token --cluster-name nt531 --region ap-southeast-1
# → Lấy được token ≠ principal có quyền cluster

# 4. List all access entries trên cluster
aws eks list-access-entries \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --output json --no-cli-pager
# → principal ARN cần có trong danh sách

# 5. Cấu hình kubeconfig
aws eks update-kubeconfig --name nt531 --region ap-southeast-1

# 6. Test kubectl — sẽ fail nếu principal chưa có access entry
kubectl get nodes
# → "Unauthorized" nếu principal chưa được cấp quyền
```

---

### B. If kubectl Unauthorized

Nếu `kubectl` fail ở bước 6, kiểm tra chi tiết principal đó:

```bash
# Lấy ARN từ bước 1
# Thay <IAM_PRINCIPAL_ARN> bằng ARN từ aws sts get-caller-identity
# Ví dụ: arn:aws:iam::372546842352:user/my-user

# Kiểm tra principal có access entry không
aws eks describe-access-entry \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN>
# → ResourceNotFoundException → principal chưa có access entry

# Kiểm tra principal có policy gắn không
aws eks list-associated-access-policies \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN> \
  --output json --no-cli-pager
# → ResourceNotFoundException → chưa có policy gắn
```

---

### C. Grant Access for the Current IAM Principal

Nếu principal hiện tại **chưa có** access entry hoặc **chưa có** policy association:

```bash
# Thay <IAM_PRINCIPAL_ARN> bằng ARN từ aws sts get-caller-identity
# Ví dụ: arn:aws:iam::372546842352:user/my-user

# Bước 1: Tạo access entry
aws eks create-access-entry \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN>

# Bước 2: Gắn policy cluster admin
aws eks associate-access-policy \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

**Verify:**

```bash
aws eks describe-access-entry \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN>
# → principalArn + type = STANDARD

aws eks list-associated-access-policies \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <IAM_PRINCIPAL_ARN> \
  --output json --no-cli-pager
# → associatedAccessPolicies[].policyArn = AmazonEKSClusterAdminPolicy
```

**Dùng kubectl:**

```bash
aws eks update-kubeconfig --name nt531 --region ap-southeast-1
kubectl get nodes                   # 3 nodes STATUS=Ready
kubectl get pods -n kube-system   # core-dns, kube-proxy Running
```

---

### D. Grant Access for Another IAM Principal / Teammate

Khi một teammate (IAM user hoặc IAM role khác) cần truy cập cluster:

**Bước 1 — Admin hiện tại** tạo access entry cho teammate:

```bash
# Thay <OTHER_IAM_PRINCIPAL_ARN> bằng ARN của teammate
# Ví dụ: arn:aws:iam::372546842352:user/teammate-name
#          arn:aws:iam::372546842352:role/teammate-role

aws eks create-access-entry \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <OTHER_IAM_PRINCIPAL_ARN>

aws eks associate-access-policy \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <OTHER_IAM_PRINCIPAL_ARN> \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster
```

**Bước 2 — Teammate xác nhận credentials** trên máy của teammate:

```bash
# Trên máy/terminal của teammate:
aws sts get-caller-identity
# → Phải là <OTHER_IAM_PRINCIPAL_ARN> — không nhầm với user khác

aws eks update-kubeconfig --name nt531 --region ap-southeast-1
kubectl get nodes                   # phải thành công
```

**Verify:**

```bash
aws eks describe-access-entry \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <OTHER_IAM_PRINCIPAL_ARN>

aws eks list-associated-access-policies \
  --cluster-name nt531 \
  --region ap-southeast-1 \
  --principal-arn <OTHER_IAM_PRINCIPAL_ARN> \
  --output json --no-cli-pager
```

---

### E. Troubleshooting Unauthorized

| Dấu hiệu | Lệnh kiểm tra |
|-----------|----------------|
| `kubectl` Unauthorized dù `update-kubeconfig` thành công | `aws eks list-access-entries` — principal ARN có trong danh sách? |
| Principal có trong danh sách nhưng vẫn lỗi | `aws eks list-associated-access-policies --principal-arn <IAM_PRINCIPAL_ARN>` — có policy không? |
| `aws eks get-token` chạy được nhưng `kubectl` vẫn lỗi | Token ≠ quyền. Kiểm tra access entry + policy association. |
| Principal không có trong `list-access-entries` | Tạo access entry theo §C hoặc §D. |
| Teammate dùng nhầm credentials | Trên máy teammate: `aws sts get-caller-identity` — phải đúng principal được cấp quyền. |
| Mới tạo access entry nhưng vẫn lỗi | Đợi 1-2 phút cho AWS propagate. Thử lại. |

---

## 3. Deploy Workload

### 3.1 Namespace + Server + Service
```bash
kubectl apply -f workload/server/01-namespace.yaml
kubectl apply -f workload/server/02-echo-deploy.yaml
kubectl apply -f workload/server/03-echo-svc.yaml
```

### 3.2 Client (Fortio)
```bash
kubectl apply -f workload/client/01-fortio-deploy.yaml
```

### 3.3 Verify
```bash
kubectl -n netperf get pods          # echo + fortio phải Running
kubectl -n netperf get svc echo      # ClusterIP, port 80 → 5678
```

### 3.4 Test connectivity
```bash
FORTIO_POD=$(kubectl -n netperf get pod -l app=fortio -o jsonpath='{.items[0].metadata.name}')
kubectl -n netperf exec "${FORTIO_POD}" -- \
  fortio load -qps 10 -c 1 -t 5s http://echo.netperf.svc.cluster.local/
```

---

## 4. Chọn Mode (A hoặc B)

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

### NetworkPolicy (S3)
> **Lưu ý:** Script `run_s3.sh` **tự động** xóa và apply policies — không cần thao tác thủ công.
> Nếu muốn test thủ công trước:
```bash
# Apply toàn bộ policies (allow + deny)
kubectl apply -f workload/policies/
# Xóa
kubectl -n netperf delete -f workload/policies/ --ignore-not-found=true
```

---

## 5. Chạy Benchmark

### 5.1 Environment variables

| Variable | Giá trị | Mô tả |
|----------|---------|-------|
| `MODE` | `A` hoặc `B` | Mode đang test |
| `LOAD` | `L1`, `L2`, `L3` | Load level |
| `REPEAT` | `3` (khuyến nghị ≥ 3) | Số lần lặp |

### 5.2 Scenario S1 — Service Baseline
```bash
MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s1.sh
```
Lặp lại toàn bộ với `MODE=B`.

### 5.3 Scenario S2 — High-load + Connection Churn
```bash
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s2.sh
```
S2 gồm 4 phase: ramp-up → sustained high → burst ×3 → cool-down.
Keepalive tắt → mỗi request mở TCP connection mới (churn).

### 5.4 Scenario S3 — NetworkPolicy Overhead
```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
```
Script tự động: xóa policy → đo (phase=off) → apply policy → đo (phase=on).

### 5.5 Chạy toàn bộ ma trận (ví dụ)
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

## 6. Kết quả & Kiểm tra

### 6.1 Nơi lưu results
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

### 6.2 Tiêu chí 1 run hợp lệ
Mở `checklist.txt` trong mỗi run folder và xác nhận:
- [ ] Tất cả Pre-run checks pass
- [ ] MODE / SCENARIO / LOAD / REPEAT đúng
- [ ] `bench.log` không trống, có latency percentiles
- [ ] Không có pod restart / OOM / node NotReady trong `events.txt`
- [ ] `metadata.json` hợp lệ (valid JSON)
- [ ] (Mode B / S3) `hubble_flows.jsonl` có dữ liệu

### 6.3 Anomalies
Nếu phát hiện bất thường (timeout, error rate cao, pod restart), ghi vào
`metadata.json` → `results.anomalies[]` và đánh dấu trong `checklist.txt`.

---

## 7. Quy tắc khi chạy

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

## 8. Load Level Reference

| Level | QPS | Connections | Threads | Mục đích |
|-------|-----|-------------|---------|----------|
| L1 | 100 | 8 | 2 | Light — near-zero error, stable p99 |
| L2 | 500 | 32 | 4 | Medium — tail latency visible |
| L3 | 1000 | 64 | 8 | High — near saturation |

> Giá trị mặc định. Điều chỉnh qua env vars sau khi calibration.
> Xem `docs/experiment_spec.md` § 7 về quy trình Calibration.
