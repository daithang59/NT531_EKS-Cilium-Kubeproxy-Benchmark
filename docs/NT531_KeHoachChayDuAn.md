# Kế hoạch Thiết lập & Thực hiện Dự án NT531

## Benchmark Hiệu năng Datapath Cilium trên AWS EKS

**So sánh:** kube-proxy (iptables) vs Cilium eBPF KPR (kube-proxy replacement)

---

## Mục lục

1. [Tổng quan](#1-tổng-quan) — đề tài, chi phí, thời gian
2. [Số lượng runs](#2-số-lượng-runs) — tổng hợp 42 runs
3. [Hạ tầng](#3-hạ-tầng) — Terraform, EKS, cấu hình
4. [Setup từng bước](#4-setup-từng-bước) — Phase 1→11 chi tiết
5. [Artifacts sinh ra](#5-artifacts-sinh-ra)
6. [Tổng hợp checklist](#6-tổng-hợp-checklist)
7. [Hỗ trợ nhanh](#7-hỗ-trợ-nhanh)

---

## 1. Tổng quan

### Đề tài & thiết kế

| Hạng mục | Giá trị |
|---|---|
| **Đề tài** | So sánh hiệu năng datapath Kubernetes: kube-proxy (iptables) vs Cilium eBPF KPR trên AWS EKS |
| **Namespace** | `benchmark` (thống nhất toàn bộ codebase) |
| **Công nghệ** | Terraform, AWS EKS, Cilium 1.18.7, Kubernetes 1.34, Fortio, Prometheus/Grafana |
| **Instance** | `m5.large` (non-burstable CPU, tránh t3 credit exhaustion) |
| **AZs** | 2 AZs (EKS yêu cầu), nhưng node group ghim vào AZ đầu tiên (loại biến cross-AZ) |
| **Thứ tự Mode** | Mode A (kube-proxy) → Mode B (eBPF KPR) |

### Chi phí ước tính

| Resource | $/giờ | $/tháng (730h) |
|---|---|---|
| EKS Cluster | $0.10 | ~$73 |
| EC2 m5.large × 3 | $0.288 | ~$210 |
| NAT Gateway | $0.045 | ~$33 |
| EBS Volumes | nhỏ | ~$3–5 |
| **Tổng** | **~$0.48** | **~$350** |

> **Quan trọng:** m5.large không thuộc Free Tier. Sau khi benchmark xong → `terraform destroy` ngay.

---

## 2. Số lượng Runs

Script tự loop `REPEAT` và phase bên trong. **Chỉ truyền 1 LOAD duy nhất mỗi lần gọi.**

| Scenario | Loads | Repeats | Runs/thí nghiệm | Ghi chú |
|---|---|---|---|---|
| S1 — Steady-state | L1, L2, L3 | 3 | **9 runs** | steady-state |
| S2 — Stress + Churn | L2, L3 | 3 | **6 runs** | 4 phases; bỏ L1 vì QPS quá thấp |
| S3 — Policy Overhead | L2, L3 | 3 × 2 phases | **12 runs** | **chỉ Mode B** (OFF + ON) |

- **Mode A**: 9 (S1) + 6 (S2) = **15 runs thực tế**
- **Mode B**: 9 (S1) + 6 (S2) + 12 (S3) = **27 runs thực tế**
- **Tổng cả hai modes**: **42 runs thực tế**

---

## 3. Hạ tầng

### 3.1 Terraform vars (`terraform/envs/dev/terraform.tfvars`)

```hcl
project_name       = "nt531-bm"
region             = "ap-southeast-1"
kubernetes_version = "1.34"
cilium_version     = "1.18.7"
instance_type      = "m5.large"
node_count         = 3
endpoint_public_access = true
```

> Nếu VPC CIDR `10.0.0.0/16` xung đột với mạng nội bộ, thêm:
> ```hcl
> vpc_cidr = "172.16.0.0/16"
> ```

### 3.2 Topology EKS (không đổi giữa hai modes)

```
Fortio (client) ──HTTP──> ClusterIP Service ──HTTP──> HTTP Echo Server
                    Mode A: iptables DNAT/SNAT (kube-proxy)
                    Mode B: eBPF socket-level redirect (Cilium KPR)
```

---

## 4. Setup từng bước

---

### Phase 1 — Prerequisites (2–4h)

#### 1.1 Tạo AWS Account

1. https://aws.amazon.com → **Create an AWS Account**
2. Bật **AWS Free Tier** monitoring để tránh phí bất ngờ

#### 1.2 Tạo IAM User

> ⚠️ **NGUYÊN TẮC:** KHÔNG dùng Root account cho EKS/Terraform — luôn tạo IAM user riêng.

**Bước 1:** Console → IAM → Users → **Create user**
- User name: `nt531-eks-admin`
- Access type: ✅ **Access key - Programmatic access**

**Bước 2:** Attach managed policies:

```
AmazonEKSClusterPolicy
AmazonEKSWorkerNodePolicy
AmazonEKSVPCResourceController
AmazonEC2FullAccess
IAMFullAccess
AWSCloudFormationFullAccess
AmazonEKSServiceRolePolicy
```

**Bước 3:** Attach inline policy cho EKS full lifecycle + PassRole
→ Xem chi tiết tại **`docs/appendix/iam-policy-eks.md`**

**Bước 4:** Tab **Security credentials** → **Create access key** → lưu ngay (chỉ hiển thị **1 lần duy nhất**)

#### 1.3 Cài AWS CLI v2

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip
sudo ./awsinstall
```

#### 1.4 Configure AWS CLI

```bash
aws configure
# AWS Access Key ID:     <từ bước 1.2>
# Secret Access Key:     <từ bước 1.2>
# Default region name:   ap-southeast-1
# Default output format: json

# Verify:
aws sts get-caller-identity
# Phải trả về Arn chứa "nt531-eks-admin"
```

#### 1.5 Kiểm tra Service Quotas

```bash
aws service-quotas get-service-quota --service-code eks --quota-code L-A2AFCT9C6 --region ap-southeast-1
aws ec2 describe-instance-type-offerings --region ap-southeast-1 --filters Name=instance-type,Values=m5.large
```

#### 1.6 Cài tools còn lại

| Tool | Phiên bản | Verify |
|---|---|---|
| kubectl | >= 1.28 | `kubectl version --client` |
| helm | >= 3.12 | `helm version` |
| terraform | >= 1.5.0 | `terraform version` |
| python3 | >= 3.8 | `python3 --version` |
| boto3 | latest | `pip install boto3` |

> pandas, scipy, numpy: **bỏ qua** — `analyze_results.py` chỉ dùng thư viện chuẩn Python.

#### ✅ Checklist Phase 1

```
[ ] AWS account tồn tại
[ ] IAM user nt531-eks-admin đã tạo với managed policies
[ ] Inline policy EKS full lifecycle + PassRole đã attach
[ ] aws configure OK; aws sts get-caller-identity thành công
[ ] kubectl >= 1.28, helm >= 3.12, terraform >= 1.5.0, python3 >= 3.8, boto3
[ ] Quota AWS đủ cho EKS + EC2
```

---

### Phase 2 — Triển khai Hạ tầng EKS (15–25 phút)

#### 2.1 Review cấu hình

Kiểm tra `terraform/envs/dev/terraform.tfvars` khớp mục 3.1.

#### 2.2 Init, Validate, Format

```bash
cd terraform && terraform init && terraform validate && make fmt
```

#### 2.3 Plan & Apply

```bash
cd terraform && terraform plan -var-file="envs/dev/terraform.tfvars" -out=tfplan && terraform apply tfplan
```

⏱ Thời gian: **15–25 phút.** Không interrupt trong quá trình apply.

#### 2.4 Cập nhật kubectl context

```bash
aws eks update-kubeconfig --name nt531-bm --region ap-southeast-1 && kubectl get nodes
# Kỳ vọng: 3 node Ready
```

#### ✅ Checklist Phase 2

```
[ ] terraform init/validate thành công
[ ] terraform apply hoàn tất không lỗi
[ ] kubectl get nodes → 3 node Ready
```

---

### Phase 3 — Monitoring: Prometheus + Grafana (10–15 phút)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts && \
helm repo add cilium https://helm.cilium.io && \
helm repo update && \
kubectl create ns monitoring && \
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n monitoring --version 60.0.0 -f helm/monitoring/values.yaml
```

```bash
kubectl get pods -n monitoring -w
# Chờ ~3–5 phút cho pods Running
```

```bash
# Port-forward Grafana (chạy nền):
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Lấy password:
kubectl get secret -n monitoring prometheus-grafana -o jsonpath='{.data.admin-password}' | base64 -d
# Username: admin
```

Truy cập http://localhost:3000

#### ✅ Checklist Phase 3

```
[ ] Prometheus pods Running
[ ] Grafana truy cập được (http://localhost:3000)
```

---

### Phase 4 — Cilium Mode A: kube-proxy Baseline (10 phút)

> ⚠️ **Lưu ý trước khi cài:** EKS dùng VPC CNI làm CNI mặc định. Phải tắt `vpc-cni` addon trong Terraform trước (xem `terraform/modules/eks/main.tf`). Nếu không — Cilium sẽ crash với lỗi `"Cannot specify IPAM mode eni in tunnel mode"` hoặc `"required IPv4 PodCIDR not available"`.

```bash
kubectl create namespace cilium-secrets && \
helm install cilium cilium/cilium -n kube-system --version 1.18.7 -f helm/cilium/values-baseline.yaml && \
kubectl get pods -n kube-system -l k8s-app=cilium --watch
# Đợi tất cả cilium pods READY 1/1
# Bấm Ctrl+C khi done
```

```bash
kubectl exec -n kube-system ds/cilium -- cilium status && kubectl get ds -n kube-system kube-proxy
```

> Kỳ vọng: `KubeProxyReplacement = False`, `IPAM: cluster-pool 10.96.0.0/24`, `kube-proxy DaemonSet 3/3 Running`.

#### ✅ Checklist Phase 4

```
[ ] Cilium pods Running
[ ] cilium status → kubeProxyReplacement = Disabled
[ ] kube-proxy DaemonSet vẫn Running
```

---

### Phase 5 — Deploy Workload (5–10 phút)

```bash
kubectl apply -f workload/server/ && kubectl apply -f workload/client/ && \
kubectl get pods -n benchmark -w
# Đợi: echo Running, fortio Running
```

```bash
kubectl exec -n benchmark deploy/fortio -- fortio curl http://echo.benchmark.svc.cluster.local:80/echo
# Kỳ vọng: "ok"
kubectl get svc,endpoints -n benchmark
```

```bash
# DNS contract check (nên pass trước benchmark)
kubectl get svc -n kube-system kube-dns -o wide
kubectl get endpoints -n kube-system kube-dns -o wide
# Kỳ vọng: kube-dns có 53/UDP + 53/TCP và có endpoints
```

Nếu có lỗi kiểu `lookup ... on 172.20.0.10:53: i/o timeout`, reconcile CoreDNS addon:

```bash
CLUSTER_NAME=$(kubectl config current-context | sed 's|.*/||')
aws eks update-addon --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
    --addon-name coredns --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
    --addon-name coredns
```

#### ✅ Checklist Phase 5

```
[ ] echo + fortio pods Running trong namespace benchmark
[ ] fortio → echo connectivity OK
[ ] Service ClusterIP tồn tại, endpoint được populate
[ ] kube-dns service có 53/UDP + 53/TCP và có endpoints
```

---

### Phase 6 — Calibration ★ (30–60 phút)

> **BẮT BUỘC chạy TRƯỚC benchmark chính thức.**

```bash
MODE=A REPEAT=2 ./scripts/calibrate.sh
```

Script tự động sweep 50→1500 QPS theo multiplicative steps.

⏱ Thời gian: **30–60 phút**

#### Đọc kết quả

```bash
cat results/calibration/mode=A_kube-proxy/calibration_*.txt
# Tìm phần "RECOMMENDED LOAD LEVELS"
```

| Load Level | Criteria |
|---|---|
| **L1** (Light) | `error_rate_pct < 0.1` VÀ `p99_ms < 5` → stable, near-zero errors |
| **L2** (Medium) | `error_rate_pct < 1` VÀ `p99_ms < 20` → visible tail, no saturation |
| **L3** (High) | `error_rate_pct < 5` → near saturation |

#### Cập nhật `scripts/common.sh`

```bash
# Tìm phần Load-level profiles, thay:
L1_QPS=<giá trị>; L1_CONNS=<giá trị>
L2_QPS=<giá trị>; L2_CONNS=<giá trị>
L3_QPS=<giá trị>; L3_CONNS=<giá trị>
```

#### Lưu Calibration Report

```bash
mkdir -p report/appendix && \
cp results/calibration/mode=A_kube-proxy/calibration_*.txt report/appendix/ && \
cp results/calibration/mode=A_kube-proxy/calibration_*.csv report/appendix/
```

#### ✅ Checklist Phase 6

```
[ ] calibrate.sh chạy hoàn tất
[ ] CSV có data points từ ~50 QPS → ~1500+ QPS
[ ] Xác định được L1/L2/L3 QPS + CONNS
[ ] common.sh đã cập nhật L1_QPS/L2_QPS/L3_QPS
[ ] Calibration report lưu vào report/appendix/
```

---

### Phase 7 — Mode A Benchmark Runs: 15 runs thực tế

> Script tự loop `REPEAT` bên trong. Chỉ truyền 1 LOAD mỗi lần gọi.
> **S3 chỉ chạy ở Mode B — Mode A không cần S3.**

#### 7.1 S1 — Steady-state

```bash
MODE=A LOAD=L1 ./scripts/run_s1.sh && \
MODE=A LOAD=L2 ./scripts/run_s1.sh && \
MODE=A LOAD=L3 ./scripts/run_s1.sh
```

#### 7.2 S2 — Stress + Connection Churn

```bash
MODE=A LOAD=L2 ./scripts/run_s2.sh && \
MODE=A LOAD=L3 ./scripts/run_s2.sh
```

#### 7.3 Thu thập Evidence

```bash
./scripts/collect_meta.sh results/mode=A_kube-proxy/
```

#### 7.4 Verify kết quả

```bash
find results/mode=A_kube-proxy -name "bench.log" | wc -l    # phải = 15
find results/mode=A_kube-proxy/scenario=S2 -name "bench_phase1_rampup.log" | wc -l  # phải = 6
```

#### ✅ Checklist Phase 7

```
[ ] 15 runs hoàn tất (S1=9, S2=6)
[ ] Mỗi run có: bench.log, metadata.json, checklist.txt
[ ] kubectl_get_all.txt, kubectl_top_nodes.txt, events.txt
[ ] S2: 4 phase logs mỗi run (phase1→phase4)
```

---

### Phase 8 — Chuyển Mode A → Mode B ⚠️ CRITICAL

> **NẾU LÀM SAI:** kube-proxy + eBPF chạy song song → NAT table conflict → results sai hoàn toàn.

#### 8.1 Lấy EKS API endpoint

```bash
aws eks describe-cluster --name nt531-bm --region ap-southeast-1 --query cluster.endpoint --output text
# Output: https://ABCDE...eks.amazonaws.com → ghi lại phần hostname
```

#### 8.2 Cập nhật `helm/cilium/values-ebpfkpr.yaml`

```yaml
k8sServiceHost: "ABCD1234EFGHIJKL.gr7.ap-southeast-1.eks.amazonaws.com"
# Lưu ý: KHÔNG có https:// và KHÔNG có path
```

#### 8.3 XÓA kube-proxy (BẮT BUỘC trước bước 8.4)

```bash
kubectl delete ds kube-proxy -n kube-system && sleep 30
```

#### 8.4 Upgrade Cilium Mode B

```bash
helm upgrade cilium cilium/cilium -n kube-system --version 1.18.7 -f helm/cilium/values-ebpfkpr.yaml --wait && \
kubectl rollout status ds/cilium -n kube-system -w
```

#### 8.5 Restart workload pods

```bash
kubectl delete pod -n benchmark -l app=echo && kubectl delete pod -n benchmark -l app=fortio && \
kubectl get pods -n benchmark -w
```

#### 8.6 Xác minh Mode B

```bash
kubectl exec -n kube-system ds/cilium -- cilium status && \
kubectl exec -n kube-system ds/cilium -- cilium hubble status && \
kubectl exec -n benchmark deploy/fortio -- fortio curl http://echo.benchmark.svc.cluster.local:80/echo
```

> Kỳ vọng: `KubeProxyReplacement = Strict`, `Kube-proxy = Disabled`, Hubble Relay Enabled, connectivity trả về "ok".

#### ✅ Checklist Phase 8

```
[ ] values-ebpfkpr.yaml đã điền k8sServiceHost (không có https://)
[ ] kube-proxy DaemonSet đã xóa
[ ] Cilium kubeProxyReplacement = Strict
[ ] Fortio → Echo connectivity sau switch vẫn OK
[ ] Hubble Relay Enabled
```

---

### Phase 9 — Mode B Benchmark Runs: 27 runs thực tế

#### 9.1 S1 — Steady-state

```bash
MODE=B LOAD=L1 ./scripts/run_s1.sh && \
MODE=B LOAD=L2 ./scripts/run_s1.sh && \
MODE=B LOAD=L3 ./scripts/run_s1.sh
```

#### 9.2 S2 — Stress + Connection Churn

```bash
MODE=B LOAD=L2 ./scripts/run_s2.sh && \
MODE=B LOAD=L3 ./scripts/run_s2.sh
```

#### 9.3 S3 — NetworkPolicy Overhead ⭐

```bash
MODE=B LOAD=L2 ./scripts/run_s3.sh && \
MODE=B LOAD=L3 ./scripts/run_s3.sh
```

#### 9.4 Deny case verification (evidence cho S3)

```bash
kubectl run attacker --image=curlimages/curl -n benchmark --rm -it -- sh
# Trong attacker pod:
curl --connect-timeout 5 http://echo.benchmark.svc.cluster.local:80/echo
# Kỳ vọng: FAIL/TIMEOUT (attacker không match policy allow)
# Thoát attacker pod: exit
```

```bash
kubectl exec -n kube-system ds/cilium -- cilium hubble observe --namespace benchmark --last 2000 -o jsonpb > results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
grep -c "DROPPED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
grep -c "FORWARDED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
```

> Kỳ vọng: DROPPED > 0 (enforcement hoạt động), FORWARDED > 0 (legit traffic vẫn đi).

#### 9.5 Thu thập Evidence Mode B

```bash
./scripts/collect_meta.sh results/mode=B_cilium-ebpfkpr/ && \
./scripts/collect_hubble.sh results/mode=B_cilium-ebpfkpr/
```

#### 9.6 Verify kết quả

```bash
find results/mode=B_cilium-ebpfkpr -name "bench.log" | wc -l           # phải = 27
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "hubble_flows.jsonl" | wc -l  # phải = 12
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "deny_case_hubble.log" | wc -l  # phải >= 1
```

#### ✅ Checklist Phase 9

```
[ ] 27 runs Mode B hoàn tất (S1=9, S2=6, S3=12)
[ ] hubble_flows.jsonl đầy đủ (12 files S3)
[ ] Deny case: attacker pod bị DROP, hubble log có DROPPED verdict
[ ] Deny case: fortio→echo vẫn FORWARDED (không false-positive)
[ ] Cilium status + Hubble status evidence đầy đủ
```

---

### Phase 10 — Phân tích Thống kê & Viết Báo cáo (1–2 ngày)

#### 10.1 Chạy phân tích tự động

```bash
python3 scripts/analyze_results.py
```

Output:
- `results_analysis/aggregated_summary.csv` — median, mean ± 95% CI per mode
- `results_analysis/comparison_AB.csv` — Δ%, p-value (Welch's t-test), significance ✓

#### 10.2 Trả lời Research Questions

| RQ | Câu hỏi | So sánh |
|---|---|---|
| RQ1 | Mode B có cải thiện p95/p99 ở steady-state? | S1: Mode A vs Mode B, L1/L2/L3 |
| RQ2 | Mode B ổn định hơn dưới churn? | S2 Phase 2/3: p95/p99/error% |
| RQ3 | Overhead khi bật Policy + Hubble? | S3: phase=off vs phase=on |

#### 10.3 Threats to Validity (ghi nhận trong báo cáo)

1. **Hubble overhead chưa kiểm soát**: Mode B bật Hubble (observability), Mode A không có tương đương → có thể làm Mode B chậm hơn ở S1/S2
2. **Pod scheduling noise**: Dù ghim AZ, vẫn có variability
3. **AWS noisy neighbor**: Các VM host cùng physical host có thể gây nhiễu
4. **Server bottleneck**: hashicorp/http-echo:1.0 có thể trở thành bottleneck ở L3
5. **Sequential execution A→B**: Không có fair comparison song song

#### 10.4 Cấu trúc báo cáo thesis

```
docs/chapters/
├── 01-introduction.md
├── 02-related-work.md
├── 03-architecture.md     # topology, m5.large decision
├── 04-methodology.md      # benchmark methodology
├── 05-results.md          # số liệu + biểu đồ
├── 06-analysis.md         # RQ1/RQ2/RQ3 + Threats to Validity
└── 07-conclusion.md

docs/appendix/
├── calibration_report.md
├── raw_benchmarks/
└── terraform_outputs.md
```

#### ✅ Checklist Phase 10

```
[ ] analyze_results.py chạy thành công
[ ] comparison_AB.csv có đầy đủ p-value, Δ%, significance
[ ] RQ1/RQ2/RQ3 trả lời được bằng dữ liệu cụ thể
[ ] Threats to Validity được ghi nhận
[ ] Deny case (DROPPED verdict) trong S3 được ghi nhận
[ ] Báo cáo thesis có cấu trúc đầy đủ
```

---

### Phase 11 — Dọn dẹp Hạ tầng (5–10 phút)

#### 11.1 Backup kết quả

```bash
cp -r results/ ~/backup-nt531-results-$(date +%Y%m%d)/
```

#### 11.2 Destroy EKS cluster

```bash
cd terraform && terraform destroy -var-file="envs/dev/terraform.tfvars"
```

#### 11.3 Verify

```bash
aws eks list-clusters --region ap-southeast-1
# { "clusters": [] }
```

#### ✅ Checklist Phase 11

```
[ ] Kết quả đã backup
[ ] terraform destroy thành công
[ ] EKS cluster đã xóa hết
```

---

## 5. Artifacts sinh ra

Mỗi benchmark run tạo thư mục:

```
results/mode=<A|B>/scenario=<S1|S2|S3>/load=<L?>/[phase=<off|on>/]run=R<#>
```

| File | Mô tả | S1 | S2 | S3 |
|---|---|---|---|---|
| `bench.log` | Fortio stdout (measurement) | ✅ | ✅ | ✅ |
| `metadata.json` | Run metadata (JSON) | ✅ | ✅ | ✅ |
| `checklist.txt` | Human-readable checklist | ✅ | ✅ | ✅ |
| `kubectl_get_all.txt` | `kubectl get all -A` | ✅ | ✅ | ✅ |
| `kubectl_top_nodes.txt` | `kubectl top nodes` | ✅ | ✅ | ✅ |
| `events.txt` | `kubectl get events -A` | ✅ | ✅ | ✅ |
| `cilium_status.txt` | `cilium status` | ✅ Mode B | ✅ Mode B | ✅ |
| `hubble_status.txt` | `cilium hubble status` | ✅ Mode B | ✅ Mode B | ✅ |
| `hubble_flows.jsonl` | Hubble flows jsonpb | ✅ Mode B | ✅ Mode B | ✅ |
| `bench_phase{1-4}*.log` | S2 phase logs | | ✅ | |
| `deny_case_hubble.log` | Hubble observe cho deny case | | | ✅ Mode B |

---

## 6. Tổng hợp checklist

| Phase | Checklist |
|---|---|
| **1 — Prerequisites** | [ ] AWS account; [ ] IAM user; [ ] inline policy EKS; [ ] aws configure OK; [ ] tools đã cài |
| **2 — Terraform EKS** | [ ] terraform apply OK; [ ] 3 node Ready |
| **3 — Monitoring** | [ ] Prometheus/Grafana Running; [ ] Grafana truy cập được |
| **4 — Cilium Mode A** | [ ] Cilium Running; [ ] kubeProxyReplacement = Disabled; [ ] kube-proxy Running |
| **5 — Workload** | [ ] Echo + Fortio Running; [ ] connectivity OK |
| **6 — Calibration ⭐** | [ ] Calibration xong; [ ] L1/L2/L3 xác định; [ ] common.sh đã cập nhật |
| **7 — Mode A Runs** | [ ] 15 runs (S1=9, S2=6); [ ] S2: 4 phase logs |
| **8 — Switch A→B ⚠️** | [ ] values-ebpfkpr.yaml đã điền EKS endpoint; [ ] kube-proxy đã xóa; [ ] kubeProxyReplacement = Strict; [ ] connectivity OK |
| **9 — Mode B Runs** | [ ] 27 runs (S1=9, S2=6, S3=12); [ ] hubble_flows.jsonl đầy đủ; [ ] deny case DROPPED verdict |
| **10 — Phân tích** | [ ] comparison_AB.csv có p-value + Δ%; [ ] RQ1/RQ2/RQ3 trả lời được; [ ] Threats to Validity; [ ] Deny case |
| **11 — Cleanup** | [ ] Kết quả backup; [ ] terraform destroy OK |

### Tóm tắt thứ tự thực hiện

```
Phase  1 → AWS account + tools         (2–4h)
Phase  2 → Terraform EKS               (15–25 phút)
Phase  3 → Prometheus/Grafana          (10–15 phút)
Phase  4 → Cilium Mode A                (10 phút)
Phase  5 → Deploy Workload              (5–10 phút)
Phase  6 → Calibration ★                 (30–60 phút)
Phase  7 → Mode A: S1(9) + S2(6)        (~36 phút)
Phase  8 → Switch A→B ⚠️                 (15–20 phút)
Phase  9 → Mode B: S1(9)+S2(6)+S3(12)   (~59 phút) + deny case
Phase 10 → Phân tích + báo cáo          (1–2 ngày)
Phase 11 → Dọn dẹp                      (5–10 phút)
─────────────────────────────────────────
Tổng:   2–3 tuần (chủ yếu benchmark chạy nền)
```

---

## 7. Hỗ trợ nhanh

| Vấn đề | Giải quyết |
|---|---|
| Terraform fail | `terraform show`; `terraform plan` để diagnose |
| Terraform báo `AccessDenied` `eks:CreateCluster` | Attach inline policy EKS full lifecycle theo `docs/appendix/iam-policy-eks.md` |
| Terraform báo `AccessDenied` `eks:CreateNodegroup` / `eks:DescribeAddonVersions` | Bổ sung quyền Nodegroup + Addon theo `docs/appendix/iam-policy-eks.md` |
| Terraform báo `AccessDenied` `eks:CreateAccessEntry` | Bổ sung quyền Access Entry / Access Policy Association theo `docs/appendix/iam-policy-eks.md` |
| Cilium CrashLoopBackOff | `kubectl describe pod -n kube-system -l k8s-app=cilium`; xem `events.txt` |
| kube-proxy không xóa được | `kubectl delete --grace-period=0 ds/kube-proxy -n kube-system` |
| Fortio → Echo timeout | `kubectl get endpoints -n benchmark`; `kubectl get svc,endpoints -n kube-system kube-dns`; reconcile CoreDNS addon (`aws eks update-addon ... --resolve-conflicts OVERWRITE`) |
| Hubble flows empty | `cilium hubble observe` sau khi chạy S3; enable port 4245 |
| Deny case không thấy DROPPED | Attacker pod không có `app=fortio` label; tăng `--last` |
| Calibrate.sh Python lỗi | `python3 --version` >= 3.8; kiểm tra inline script syntax |
