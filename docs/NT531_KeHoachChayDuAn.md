# Kế hoạch Thiết lập & Thực hiện Dự án NT531
## Benchmark Hiệu năng Datapath Cilium trên AWS EKS
### So sánh kube-proxy vs Cilium eBPF KPR

---

## Tổng quan

| Thông tin | Chi tiết |
|-----------|----------|
| **Đề tài** | So sánh hiệu năng datapath Kubernetes giữa kube-proxy (iptables) và Cilium eBPF KPR trên AWS EKS |
| **Tài liệu gốc** | `docs/NT531_Nhom12_KeHoachDoAn.md` |
| **Namespace** | `benchmark` (thống nhất: workload server/client/policies đều dùng `namespace: benchmark`) |
| **Công nghệ** | Terraform, AWS EKS, Cilium 1.18.7, Kubernetes 1.34, Fortio, Prometheus/Grafana |
| **Instance** | `m5.large` (quyết định có chủ đích: non-burstable CPU, tránh t3 credit exhaustion, dữ liệu sạch hơn) |
| **AZs** | 2 AZs cho EKS tương thích, nhưng node group ghim vào AZ đầu tiên (loại biến động cross-AZ) |
| **Thứ tự Mode** | Mode A (kube-proxy) trước → Mode B (eBPF KPR) sau |
| **Ước tính chi phí** | ~$0.48/giờ → ~$100–150 cho 2–3 tuần chạy benchmark |
| **Thời gian ước tính** | 2–3 tuần |

---

## Số lần chạy — Giải thích rõ ràng

**Script tự loop qua REPEAT và phase bên trong. Chỉ truyền 1 LOAD duy nhất mỗi lần gọi.**

| Scenario | Loads | Repeats | Runs/thí nghiệm | Ghi chú |
|----------|-------|---------|-----------------|---------|
| S1 | L1, L2, L3 | 3 | **9 runs** | steady-state |
| S2 | L2, L3 | 3 | **6 runs** | stress + churn (4 phases), bỏ L1 vì L1 × S2 QPS quá thấp không stress được conntrack |
| S3 | L2, L3 | 3 × 2 phases | **12 runs** | policy OFF + ON |

- **S1**: 3 load × 3 repeat = **9 runs** per mode
- **S2**: 2 load × 3 repeat = **6 runs** per mode (L1 bỏ: burst QPS 150 vẫn quá thấp, không đủ để phơi bày khác biệt iptables vs eBPF)
- **S3**: 2 load × 3 repeat × 2 phases = **12 runs** per mode
- **Tổng mỗi mode**: 9 + 6 + 12 = **27 runs thực tế**
- **Tổng cả 2 modes**: **54 runs thực tế**

---

## Phụ lục A — Chi phí AWS EKS (tham khảo)

| Resource | Đơn giá | Số lượng | Chi phí/giờ | Chi phí/tháng (730h) |
|----------|---------|----------|-------------|----------------------|
| EKS Cluster | $0.10/giờ | 1 | $0.10 | ~$73 |
| EC2 m5.large × 3 | $0.096/giờ | 3 | $0.288 | ~$210 |
| NAT Gateway | $0.045/giờ | 1 | $0.045 | ~$33 |
| EBS Volumes | ~$0.08/GB/tháng | ~6 GB | nhỏ | ~$3–5 |
| **Tổng** | | | **~$0.48/giờ** | **~$350/tháng** |

> **Lưu ý**: m5.large không thuộc Free Tier. Khuyến nghị: chạy benchmark xong → `terraform destroy` ngay để tránh phí không cần thiết.

---

## Phase 1 — Tạo AWS Account & Chuẩn bị Prerequisites

### 1.1 Tạo AWS Account

1. Truy cập https://aws.amazon.com → **Create an AWS Account**
2. Đăng nhập với **Root account** (chỉ dùng để tạo IAM user đầu tiên)
3. Bật **AWS Free Tier** monitoring để tránh phí bất ngờ

### 1.2 Tạo IAM User cho Terraform/Cilium

> ⚠️ **NGUYÊN TẮC**: KHÔNG dùng Root account cho EKS/Terraform — luôn tạo IAM user riêng.

**Bước 1**: AWS Console → IAM → Users → **Create user**
- User name: `nt531-eks-admin`
- Access type: ✅ **Access key - Programmatic access**
- Permissions: Chọn **Attach policies directly**

**Bước 2**: Attach managed policies:
```
AmazonEKSClusterPolicy
AmazonEKSWorkerNodePolicy
AmazonEKSVPCResourceController
AmazonEC2FullAccess
IAMFullAccess
AWSCloudFormationFullAccess
AmazonEKSServiceRolePolicy
```

**Bước 3**: Sau khi tạo user → tab **Security credentials** → **Create access key**
- Chọn: **Command Line Interface (CLI)**
- Lưu `Access Key ID` và `Secret Access Key` ngay (chỉ hiển thị **1 lần duy nhất**)

### 1.3 Cài AWS CLI v2

```powershell
# Windows (PowerShell) — chạy với quyền Administrator:
msiexec.exe /i https://awscli.amazonaws.com/AWSCLIV2.msi

# Hoặc winget:
winget install Amazon.AWSCLI --accept-package-agreements --accept-source-agreements
```

### 1.4 Configure AWS CLI

```bash
aws configure
AWS Access Key ID [None]: <gõ Access Key ID từ bước 1.2>
AWS Secret Access Key [None]: <gõ Secret Access Key từ bước 1.2>
Default region name [None]: ap-southeast-1
Default output format [None]: json
```

```bash
# Verify:
aws sts get-caller-identity
# Phải trả về Account, Arn chứa "nt531-eks-admin"
```

### 1.5 Kiểm tra AWS Service Quotas

```bash
aws service-quotas get-service-quota --service-code eks --quota-code L-A2AFCT9C6 --region ap-southeast-1
aws ec2 describe-instance-type-offerings --region ap-southeast-1 --filters Name=instance-type,Values=m5.large
```

### 1.6 Cài các công cụ còn lại

| Tool | Phiên bản | Verify |
|------|-----------|--------|
| kubectl | >= 1.28 | `kubectl version --client` |
| helm | >= 3.12 | `helm version` |
| terraform | >= 1.5.0 | `terraform version` |
| python3 | >= 3.8 | `python3 --version` |
| boto3 | latest | `pip install boto3` |

> pandas, scipy, numpy: **bỏ qua** — `analyze_results.py` chỉ dùng thư viện chuẩn Python.

```bash
# Hubble CLI (tùy chọn, cho S3 verification trên macOS/Linux):
curl -sL https://raw.githubusercontent.com/cilium/hubble/main/install.sh | bash
# Windows: dùng kubectl exec thay thế
```

### Checklist Phase 1 ✅
```
[ ] AWS account tồn tại
[ ] IAM user nt531-eks-admin đã tạo với đầy đủ policies
[ ] aws configure đã chạy, aws sts get-caller-identity thành công
[ ] kubectl >= 1.28, helm >= 3.12, terraform >= 1.5.0, python3 >= 3.8, boto3 đã cài
[ ] Quota AWS đủ cho EKS + EC2
```

---

## Phase 2 — Triển khai Hạ tầng EKS (Terraform)

### 2.1 Review cấu hình Terraform

Kiểm tra `terraform/envs/dev/terraform.tfvars`:
```hcl
project_name       = "nt531-netperf"
region             = "ap-southeast-1"
kubernetes_version = "1.34"
cilium_version     = "1.18.7"
instance_type      = "m5.large"      # ← non-burstable: tránh t3 credit exhaustion
node_count         = 3
endpoint_public_access = true
```

> **Quyết định có chủ đích**: Dùng `m5.large` thay vì `t3.large` để đảm bảo CPU non-burstable, không có credit exhaustion gây biến động số liệu benchmark.

> Nếu VPC CIDR `10.0.0.0/16` xung đột với mạng nội bộ, thêm vào `terraform.tfvars`:
> ```hcl
> vpc_cidr = "172.16.0.0/16"
> ```

### 2.2 Init, Validate, Format

```bash
cd thesis-cilium-eks-benchmark/terraform
terraform init
terraform validate
make fmt   # format code trước commit
```

### 2.3 Plan & Apply

```bash
terraform plan -var-file=envs/dev/terraform.tfvars -out=tfplan
terraform apply tfplan
```

⏱ **Thời gian: 15–25 phút.** Không interrupt trong quá trình apply.

### 2.4 Cập nhật kubectl context

```bash
aws eks update-kubeconfig --name nt531-netperf --region ap-southeast-1
kubectl get nodes
# Output kỳ vọng: 3 node Ready
```

### Checklist Phase 2 ✅
```
[ ] terraform init/validate thành công
[ ] terraform apply hoàn tất không lỗi
[ ] kubectl get nodes → 3 node Ready
```

---

## Phase 3 — Cài đặt Monitoring (Prometheus + Grafana)

### 3.1 Thêm Helm repos & cài kube-prometheus-stack

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add cilium https://helm.cilium.io
helm repo update

kubectl create ns monitoring
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --version 60.0.0 \
  -f helm/monitoring/values.yaml
```

### 3.2 Chờ pods Ready & Truy cập Grafana

```bash
kubectl get pods -n monitoring -w
# Đợi ~3–5 phút

# Port-forward:
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80

# Password:
kubectl get secret -n monitoring prometheus-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d
# Username: admin
```

Truy cập http://localhost:3000

### Checklist Phase 3 ✅
```
[ ] Prometheus pods Running
[ ] Grafana truy cập được (http://localhost:3000)
```

---

## Phase 4 — Cài Cilium Mode A (Baseline kube-proxy)

### 4.1 Cài Cilium với kube-proxy enabled

```bash
helm upgrade --install cilium cilium/cilium \
  -n kube-system --version 1.18.7 \
  -f helm/cilium/values-baseline.yaml \
  --wait

kubectl rollout status ds/cilium -n kube-system -w
```

### 4.2 Xác minh Mode A

```bash
kubectl exec -n kube-system ds/cilium -- cilium status
# Kỳ vọng: KubeProxyReplacement = Disabled, Kube-proxy = Enabled

kubectl get ds -n kube-system kube-proxy
# Kỳ vọng: kube-proxy DaemonSet vẫn Running
```

### Checklist Phase 4 ✅
```
[ ] Cilium pods Running
[ ] cilium status → kubeProxyReplacement = Disabled
[ ] kube-proxy DaemonSet vẫn Running
```

---

## Phase 5 — Triển khai Workload (Fortio + Echo Server)

> **Namespace**: `benchmark` (thống nhất toàn bộ codebase)

### 5.1 Deploy

```bash
kubectl apply -f workload/server/
kubectl apply -f workload/client/
kubectl get pods -n benchmark -w
# Đợi: echo Running, fortio Running
```

### 5.2 Kiểm tra kết nối

```bash
kubectl exec -n benchmark deploy/fortio -- \
  fortio curl http://echo.benchmark.svc.cluster.local:80/echo
# Kỳ vọng: "ok"

kubectl get svc,endpoints -n benchmark
```

### Checklist Phase 5 ✅
```
[ ] echo + fortio pods Running trong namespace benchmark
[ ] fortio → echo connectivity OK
[ ] Service ClusterIP tồn tại, endpoint được populate
```

---

## Phase 6 — Calibration: Xác định L1/L2/L3 QPS ⭐

> **BẮT BUỘC chạy TRƯỚC benchmark chính thức.** Sweep QPS để tìm giá trị L1/L2/L3 thực tế.

### 6.1 Chạy Calibration (Mode A)

```bash
MODE=A REPEAT=2 ./scripts/calibrate.sh
```

> Script tự động sweep 50→1500 QPS theo multiplicative steps. Nhận MODE, LOAD (namespace/service), REPEAT (số lần lặp mỗi QPS point).

⏱ Thời gian: **30–60 phút**

### 6.2 Xem kết quả

```bash
cat results/calibration/mode=A_kube-proxy/calibration_*.txt
# Xem phần "RECOMMENDED LOAD LEVELS"
```

### 6.3 Đọc kết quả — Tìm L1/L2/L3

CSV: `qps,conns,run,p50_ms,...,error_rate_pct,...`

| Load Level | Criteria |
|------------|----------|
| **L1** (Light) | `error_rate_pct < 0.1` VÀ `p99_ms < 5` → stable, near-zero errors |
| **L2** (Medium) | `error_rate_pct < 1` VÀ `p99_ms < 20` → visible tail, no saturation |
| **L3** (High) | `error_rate_pct < 5` → near saturation |

### 6.4 Cập nhật `scripts/common.sh`

```bash
# Tìm phần Load-level profiles, thay:
L1_QPS=<giá trị>; L1_CONNS=<giá trị>
L2_QPS=<giá trị>; L2_CONNS=<giá trị>
L3_QPS=<giá trị>; L3_CONNS=<giá trị>
```

### 6.5 Lưu Calibration Report

```bash
mkdir -p report/appendix
cp results/calibration/mode=A_kube-proxy/calibration_*.txt report/appendix/
cp results/calibration/mode=A_kube-proxy/calibration_*.csv report/appendix/
```

### Checklist Phase 6 ✅
```
[ ] calibrate.sh chạy hoàn tất (không crash)
[ ] CSV có data points từ ~50 QPS → ~1500+ QPS
[ ] Xác định được L1/L2/L3 QPS + CONNS
[ ] common.sh đã cập nhật L1_QPS/L2_QPS/L3_QPS
[ ] Calibration report lưu vào report/appendix/
```

---

## Phase 7 — Mode A Full Benchmark Runs (27 runs thực tế)

> **Script tự loop REPEAT bên trong. Chỉ truyền 1 LOAD mỗi lần gọi.**
> Biến: `REPEAT` (số runs mỗi load), KHÔNG phải `REPEATS`.

### 7.1 S1 — Steady-state (Mode A)

```bash
MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s1.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s1.sh
```
3 load × 3 repeat = **9 runs** | ~5 phút/lệnh | **Tổng ~15 phút**

### 7.2 S2 — Stress + Connection Churn (Mode A)

```bash
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s2.sh
```
2 load × 3 repeat = **6 runs** | ~7 phút/lệnh | **Tổng ~14 phút**

### 7.3 S3 — NetworkPolicy Overhead (Mode A)

```bash
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s3.sh
```
2 load × 3 repeat × 2 phases (OFF→ON) = **12 runs** | **Tổng ~30 phút**

### 7.4 Thu thập Evidence

```bash
./scripts/collect_meta.sh results/mode=A_kube-proxy/
```

### 7.5 Verify kết quả Mode A

```bash
find results/mode=A_kube-proxy -name "bench.log" | wc -l    # phải = 27
find results/mode=A_kube-proxy/scenario=S2 -name "bench_phase1_rampup.log" | wc -l  # phải = 9
find results/mode=A_kube-proxy/scenario=S3 -name "bench.log" | wc -l             # phải = 12
```

### Checklist Phase 7 ✅
```
[ ] 27 runs hoàn tất (S1=9, S2=6, S3=12)
[ ] Mỗi run có: bench.log, metadata.json, checklist.txt
[ ] kubectl_get_all.txt, kubectl_top_nodes.txt, events.txt
[ ] S2: 4 phase logs mỗi run (phase1→phase4)
[ ] S3: phase=off/ + phase=on/ subdirectories
```

---

## Phase 8 — Chuyển sang Mode B (eBPF KPR) ⚠️ CRITICAL

> **NẾU LÀM SAI**: kube-proxy + eBPF chạy song song → NAT table conflict → results sai hoàn toàn.

### 8.1 Lấy EKS API endpoint

```bash
aws eks describe-cluster --name nt531-netperf --region ap-southeast-1 \
  --query 'cluster.endpoint' --output text
# Output: https://ABCDE...eks.amazonaws.com
```

### 8.2 Cập nhật `helm/cilium/values-ebpfkpr.yaml`

```yaml
k8sServiceHost: "ABCDE1234567890ABCD1234567890.sk1.ap-southeast-1.eks.amazonaws.com"
# Lưu ý: KHÔNG có https://
```

### 8.3 XÓA kube-proxy (BẮT BUỘC trước bước 8.4)

```bash
kubectl delete ds kube-proxy -n kube-system
sleep 30  # đợi Cilium eBPF takeover
```

### 8.4 Upgrade Cilium Mode B (in-place)

```bash
helm upgrade cilium cilium/cilium -n kube-system --version 1.18.7 \
  -f helm/cilium/values-ebpfkpr.yaml --wait

kubectl rollout status ds/cilium -n kube-system -w
```

### 8.5 Restart workload pods

```bash
kubectl delete pod -n benchmark -l app=echo -l app=fortio
kubectl get pods -n benchmark -w  # đợi Ready
```

### 8.6 Xác minh Mode B

```bash
kubectl exec -n kube-system ds/cilium -- cilium status
# Kỳ vọng: KubeProxyReplacement = Strict, Kube-proxy = Disabled

kubectl exec -n kube-system ds/cilium -- cilium hubble status
# Kỳ vọng: Relay = Enabled

kubectl exec -n benchmark deploy/fortio -- \
  fortio curl http://echo.benchmark.svc.cluster.local:80/echo
# Phải vẫn trả về "ok"
```

### Checklist Phase 8 ✅
```
[ ] values-ebpfkpr.yaml đã điền k8sServiceHost (không có https://)
[ ] kube-proxy DaemonSet đã xóa
[ ] Cilium kubeProxyReplacement = Strict
[ ] Fortio → Echo connectivity sau switch vẫn OK
[ ] Hubble Relay Enabled
```

---

## Phase 9 — Mode B Full Benchmark Runs (27 runs thực tế)

### 9.1 S1 — Steady-state (Mode B)

```bash
MODE=B LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s1.sh
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s1.sh
```

### 9.2 S2 — Stress + Connection Churn (Mode B)

```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s2.sh
```

### 9.3 S3 — NetworkPolicy Overhead (Mode B) ⭐

```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s3.sh
```

### 9.4 Deny case verification (bổ sung evidence cho S3)

> Checklist môn học yêu cầu S3 phải chứng minh được deny/drop. Cần thu Hubble flows có cả FORWARDED và DROPPED verdict.

**Sau khi S3 chạy xong, thực hiện kiểm tra deny case:**

```bash
# Bước 1: Deploy attacker pod (không có app=fortio label → bị default-deny chặn)
kubectl run attacker --image=curlimages/curl -n benchmark --rm -it -- sh
# Trong attacker pod:
curl --connect-timeout 5 http://echo.benchmark.svc.cluster.local:80/echo
# Kỳ vọng: FAIL/TIMEOUT (vì attacker không match policy allow)

# Bước 2: Thu Hubble flows để xác nhận DROPPED verdict
kubectl exec -n kube-system ds/cilium -- \
  cilium hubble observe --namespace benchmark --last 2000 -o jsonpb \
  > results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log

# Bước 3: Verify DROPPED verdict có mặt
grep -c "DROPPED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
# Kỳ vọng: > 0 → bằng chứng enforcement hoạt động

# Bước 4: Verify FORWARDED verdict cũng có (legit traffic vẫn đi)
grep -c "FORWARDED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
# Kỳ vọng: > 0 → fortio→echo vẫn được phép
```

### 9.5 Thu thập Evidence Mode B

```bash
./scripts/collect_meta.sh results/mode=B_cilium-ebpfkpr/
./scripts/collect_hubble.sh results/mode=B_cilium-ebpfkpr/
```

### 9.6 Verify kết quả Mode B

```bash
find results/mode=B_cilium-ebpfkpr -name "bench.log" | wc -l        # phải = 27
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "hubble_flows.jsonl" | wc -l  # phải = 12
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "deny_case_hubble.log" | wc -l  # phải >= 1
```

### Checklist Phase 9 ✅
```
[ ] 27 runs Mode B hoàn tất (S1=9, S2=6, S3=12)
[ ] hubble_flows.jsonl đầy đủ (12 files S3)
[ ] Deny case: attacker pod bị DROP, hubble log có DROPPED verdict
[ ] Deny case: fortio→echo vẫn FORWARDED (không false-positive)
[ ] Cilium status + Hubble status evidence đầy đủ
```

---

## Phase 10 — Phân tích Thống kê & Viết Báo cáo

### 10.1 Chạy phân tích tự động

```bash
python3 scripts/analyze_results.py
```

Output:
- `results_analysis/aggregated_summary.csv` — median, mean ± 95% CI per mode
- `results_analysis/comparison_AB.csv` — Δ%, p-value (Welch's t-test), significance ✓

### 10.2 Trả lời Research Questions

#### RQ1: Latency Improvement (S1)
- So sánh p95/p99 Mode A vs Mode B ở L1/L2/L3
- eBPF KPR giảm được bao nhiêu % tail latency?

#### RQ2: Stability Under Churn (S2)
- So sánh p95/p99 ở Phase 2 (SUSTAINED) và Phase 3 (BURST ×3)
- eBPF socket-level redirect vs iptables conntrack: cái nào ổn định hơn?

#### RQ3: Policy + Observability Overhead (S3)
- So sánh `phase=on` vs `phase=off` cho mỗi mode
- Hubble flow export overhead trong Mode B
- **Deny case evidence**: DROPPED verdict trong Hubble log

### 10.3 Threats to Validity (ghi nhận trong báo cáo)

1. **Hubble overhead chưa kiểm soát**: Mode B bật Hubble (observability), Mode A không có tương đương → có thể làm Mode B chậm hơn ở S1/S2
2. **Pod scheduling noise**: Dù ghim AZ, vẫn có variability
3. **AWS noisy neighbor**: Các VM host cùng physical host có thể gây nhiễu
4. **Server bottleneck**: hashicorp/http-echo:1.0 có thể trở thành bottleneck ở L3
5. **Sequential execution A→B**: Không có fair comparison song song

### 10.4 Cấu trúc báo cáo thesis

```
docs/
├── chapters/
│   ├── 01-introduction.md
│   ├── 02-related-work.md
│   ├── 03-architecture.md    # topology, m5.large decision
│   ├── 04-methodology.md      # benchmark methodology
│   ├── 05-results.md          # số liệu + biểu đồ
│   ├── 06-analysis.md         # RQ1/RQ2/RQ3 + Threats to Validity
│   └── 07-conclusion.md
├── appendix/
│   ├── calibration_report.md
│   ├── raw_benchmarks/
│   └── terraform_outputs.md
```

### Checklist Phase 10 ✅
```
[ ] analyze_results.py chạy thành công
[ ] comparison_AB.csv có đầy đủ p-value, Δ%, significance
[ ] RQ1/RQ2/RQ3 trả lời được bằng dữ liệu cụ thể
[ ] Threats to Validity được ghi nhận
[ ] Deny case (DROPPED verdict) trong S3 được ghi nhận
[ ] Báo cáo thesis có cấu trúc đầy đủ
```

---

## Phase 11 — Dọn dẹp Hạ tầng

### 11.1 Backup kết quả

```bash
cp -r results/ ~/backup-nt531-results-$(date +%Y%m%d)/
```

### 11.2 Destroy EKS cluster

```bash
cd terraform
terraform destroy -var-file=envs/dev/terraform.tfvars
```

⏱ Thời gian: **5–10 phút**

### 11.3 Verify

```bash
aws eks list-clusters --region ap-southeast-1
# { "clusters": [] }
```

---

## Artifacts sinh ra bởi scripts

Mỗi benchmark run tạo thư mục `results/mode=<A|B>/scenario=<S1|S2|S3>/load=<L?>/[phase=<off|on>/]run=R<#>/`:

| File | Mô tả | S1 | S2 | S3 |
|------|-------|----|----|----|
| `bench.log` | Fortio stdout (measurement) | ✅ | ✅ | ✅ |
| `metadata.json` | Run metadata (JSON) | ✅ | ✅ | ✅ |
| `checklist.txt` | Human-readable checklist | ✅ | ✅ | ✅ |
| `kubectl_get_all.txt` | `kubectl get all -A` | ✅ | ✅ | ✅ |
| `kubectl_top_nodes.txt` | `kubectl top nodes` | ✅ | ✅ | ✅ |
| `events.txt` | `kubectl get events -A` | ✅ | ✅ | ✅ |
| `cilium_status.txt` | `cilium status` | ✅ Mode B | ✅ Mode B | ✅ |
| `hubble_status.txt` | `cilium hubble status` | ✅ Mode B | ✅ Mode B | ✅ |
| `hubble_flows.jsonl` | Hubble flows jsonpb | ✅ Mode B | ✅ Mode B | ✅ |
| `bench_phase1_rampup.log` | S2 phase 1 | | ✅ | |
| `bench_phase2_sustained.log` | S2 phase 2 | | ✅ | |
| `bench_phase3_bursts.log` | S2 phase 3 | | ✅ | |
| `bench_phase4_cooldown.log` | S2 phase 4 | | ✅ | |
| `deny_case_hubble.log` | Hubble observe cho deny case | | | ✅ Mode B |

---

## Tổng hợp Checklist cuối cùng

| Phase | Checklist |
|-------|----------|
| 1 — Prerequisites | [ ] AWS account; [ ] IAM user nt531-eks-admin; [ ] aws configure OK; [ ] tools đã cài |
| 2 — Terraform EKS | [ ] terraform apply thành công; [ ] 3 node Ready |
| 3 — Monitoring | [ ] Prometheus/Grafana Running; [ ] Grafana truy cập được |
| 4 — Cilium Mode A | [ ] Cilium Running; [ ] kubeProxyReplacement = Disabled; [ ] kube-proxy Running |
| 5 — Workload | [ ] Echo + Fortio Running trong namespace `benchmark`; [ ] connectivity OK |
| 6 — Calibration ⭐ | [ ] Calibration xong; [ ] L1/L2/L3 đã xác định; [ ] common.sh đã cập nhật |
| 7 — Mode A Runs | [ ] 27 runs hoàn tất (S1=9, S2=6, S3=12); [ ] S2: 4 phase logs; [ ] S3: phase=off/ + phase=on/ |
| 8 — Switch A→B ⚠️ | [ ] values-ebpfkpr.yaml đã điền EKS endpoint; [ ] kube-proxy đã xóa; [ ] kubeProxyReplacement = Strict; [ ] connectivity sau switch OK |
| 9 — Mode B Runs | [ ] 27 runs hoàn tất (S1=9, S2=6, S3=12); [ ] hubble_flows.jsonl đầy đủ; [ ] deny case DROPPED verdict xác nhận |
| 10 — Phân tích | [ ] comparison_AB.csv có p-value + Δ%; [ ] RQ1/RQ2/RQ3 trả lời được; [ ] Threats to Validity; [ ] Deny case evidence |
| 11 — Cleanup | [ ] Kết quả backup; [ ] terraform destroy thành công |

---

## Thứ tự bước thực hiện — Tóm tắt

```
1. Phase 1  → AWS account + tools (2–4h)
2. Phase 2  → Terraform EKS (15–25 phút)
3. Phase 3  → Prometheus/Grafana (10–15 phút)
4. Phase 4  → Cilium Mode A (10 phút)
5. Phase 5  → Deploy Workload (5–10 phút)
6. Phase 6  → Calibration ★ (30–60 phút)
7. Phase 7  → Mode A: S1(9) + S2(6) + S3(12) = 27 runs (~59 phút)
8. Phase 8  → Switch A→B ⚠️ (15–20 phút)
9. Phase 9  → Mode B: S1(9) + S2(6) + S3(12) = 27 runs (~59 phút) + deny case
10. Phase 10 → Phân tích + báo cáo (1–2 ngày)
11. Phase 11 → Dọn dẹp (5–10 phút)
─────────────────────────────────────────
Tổng: 2–3 tuần (chủ yếu benchmark runs chạy nền)
```

---

## Hỗ trợ kỹ thuật nhanh

| Vấn đề | Giải quyết |
|---------|-----------|
| Terraform fail | `terraform show`; `terraform plan` để diagnose |
| Cilium CrashLoopBackOff | `kubectl describe pod -n kube-system -l k8s-app=cilium`; xem `events.txt` |
| kube-proxy không xóa được | `kubectl delete --grace-period=0 ds/kube-proxy -n kube-system` |
| Fortio → Echo timeout | `kubectl get endpoints -n benchmark`; `cilium endpoint list` |
| Hubble flows empty | `cilium hubble observe` sau khi chạy S3; enable port 4245 |
| Deny case không thấy DROPPED | Kiểm tra attacker pod không có `app=fortio` label; chạy Hubble observe với `--last` lớn hơn |
| Calibrate.sh Python lỗi | `python3 --version` >= 3.8; kiểm tra inline script syntax hoạt động |
