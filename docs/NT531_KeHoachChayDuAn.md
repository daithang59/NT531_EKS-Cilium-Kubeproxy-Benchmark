# Kế hoạch Thiết lập & Thực hiện Dự án NT531

## Benchmark Hiệu năng Datapath Cilium trên AWS EKS

**So sánh:** Cilium hybrid datapath (kube-proxy present, iptables) vs Cilium eBPF KPR (kube-proxy replacement)

---

## Mục lục

1. [Tổng quan](#1-tổng-quan) — đề tài, chi phí, thời gian
2. [Số lượng runs](#2-số-lượng-runs) — tổng hợp 42 runs
3. [Hạ tầng](#3-hạ-tầng) — Terraform, EKS, cấu hình
4. [Setup từng bước](#4-setup-từng-bước) — Phase 1→11 chi tiết (có Phase 5b: resume sau tạm dừng)
5. [Artifacts sinh ra](#5-artifacts-sinh-ra)
6. [Tổng hợp checklist](#6-tổng-hợp-checklist)
7. [Hỗ trợ nhanh](#7-hỗ-trợ-nhanh)
8. [Run Notes Template ★](#8-run-notes-template-) — template cho mỗi ngày chạy
9. [Tổng hợp Screenshot — Toàn bộ Benchmark](#9-tổng-hợp-screenshot---toàn-bộ-benchmark) — fig-01→fig-18, infra, Grafana, Hubble

---

## 1. Tổng quan

### Đề tài & thiết kế

| Hạng mục | Giá trị |
|---|---|
| **Đề tài** | So sánh hiệu năng datapath Kubernetes: Cilium hybrid (kube-proxy present) vs Cilium eBPF KPR (kube-proxy replacement) trên AWS EKS |
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
                    Mode A: Cilium hybrid (kube-proxy present) — iptables + Cilium CNI
                    Mode B: eBPF socket-level redirect (Cilium KPR, kube-proxy replaced)
```

> ⚠️ **Important:** Mode A is NOT a pure kube-proxy baseline. When `kubeProxyReplacement=false`,
> Cilium still participates in ClusterIP Service load-balancing at the per-packet level.
> The actual comparison is: "Cilium hybrid + kube-proxy" vs "Cilium full eBPF".
> This is documented in Threats to Validity (Phase 10).

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
📸 Screenshot: `docs/figures/infra/fig-A6-terraform-apply-output.png` (sau khi apply xong)

⏱ Thời gian: **15–25 phút.** Không interrupt trong quá trình apply.

#### 2.4 Cập nhật kubectl context

```bash
aws eks update-kubeconfig --name nt531-bm --region ap-southeast-1 && kubectl get nodes
# Kỳ vọng: 3 node Ready
```
📸 Screenshot: `docs/figures/infra/fig-A6-terraform-apply-output.png` (terraform apply output — `fig-A6-terraform-apply-output.png`)
📸 Screenshot: `docs/figures/infra/fig-A1-aws-eks-console-cluster.png` (AWS Console → EKS → nt531-bm, status Active — `fig-A1-aws-eks-console-cluster.png`)
📸 Screenshot: `docs/figures/infra/fig-A2-aws-eks-nodegroup.png` (AWS Console → EKS → nt531-bm → Compute → Node Group — `fig-A2-aws-eks-nodegroup.png`)
📸 Screenshot: `docs/figures/infra/fig-A3-aws-ec2-instances.png` (AWS Console → EC2 → Instances, 3 m5.large Running — `fig-A3-aws-ec2-instances.png`)
📸 Screenshot: `docs/figures/infra/fig-A4-aws-vpc-subnets.png` (AWS Console → VPC → Subnets, 2 AZs + NAT GW — `fig-A4-aws-vpc-subnets.png`)
📸 Screenshot: `docs/figures/infra/fig-A5-aws-security-group-rules.png` (AWS Console → EC2 → Security Groups → nt531-bm-node, VXLAN rules — `fig-A5-aws-security-group-rules.png`)
📸 Screenshot: `docs/figures/infra/fig-A7-terraform-output-values.png` (terraform output — `fig-A7-terraform-output-values.png`)
📸 Screenshot: `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` (chụp `kubectl get nodes -o wide` sau khi chạy — `fig-01-modeA-cluster-nodes.png`)

#### ✅ Checklist Phase 2

```
[ ] terraform init/validate thành công
[ ] terraform apply hoàn tất không lỗi
[ ] kubectl get nodes → 3 node Ready
[ ] aws-node DaemonSet KHÔNG tồn tại (không có trong cluster_addons)
[ ] Cilium VXLAN SG rules đã apply: kiểm tra AWS Console → EC2 → Security Groups → nt531-bm-node
   → Inbound rules: protocol 4 (IP-in-IP), UDP 8472 (VXLAN) self-referenced phải tồn tại
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
# ⚠️ Service port là 80, không phải 3000 — dùng cú pháp port:port
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &

# Lấy password (secret name khác với service name):
kubectl get secret -n monitoring -l app.kubernetes.io/component=admin-secret -o jsonpath='{.items[0].data.admin-password}' | base64 -d
# Username: admin
```

Truy cập http://localhost:3000

📸 Screenshot: `docs/figures/prometheus/fig-P1-prometheus-targets.png` (Prometheus UI → `Status > Targets` — **chụp ngay sau Phase 3**, tất cả jobs UP bao gồm cilium-agent — `fig-P1-prometheus-targets.png`)
📸 Screenshot: `docs/figures/prometheus/fig-P2-prometheus-cilium-metrics.png` (Prometheus UI → Graph → `cilium_forward_count_total`, **chọn Table view** — `fig-P2-prometheus-cilium-metrics.png`)
📸 Screenshot: `fig-G1-grafana-cpu-node-pod.png` (Grafana → Node/Pod CPU Usage, cilium overhead < 0.2% — `fig-G1-grafana-cpu-node-pod.png`)
📸 Screenshot: `fig-G2-grafana-cpu-quota-table.png` (Grafana → CPU Quota table, tất cả Cilium pods << 1% — `fig-G2-grafana-cpu-quota-table.png`)
📸 Screenshot: `fig-G3-grafana-memory-node-pod.png` (Grafana → Memory Usage (in cache), Cilium < 300 MiB — `fig-G3-grafana-memory-node-pod.png`)
📸 Screenshot: `fig-G4-grafana-cluster-overview.png` (Grafana → Cluster CPU/Memory overview, < 30% — `fig-G4-grafana-cluster-overview.png`)

#### ✅ Checklist Phase 3

```
[ ] Prometheus StatefulSet tồn tại và Prometheus pod Running
[ ] Grafana pod 3/3 Running
[ ] Grafana truy cập được (http://localhost:3000) — dashboard có data
```

> **Troubleshooting:** Nếu Grafana dashboard trống ("No data"), xem `docs/runbook.md` §"Monitoring / Grafana không hoạt động".

---

### Phase 4 — Cilium Mode A: kube-proxy Baseline (10 phút)

> ⚠️ **Lưu ý trước khi cài:** Cluster mới (tạo sau khi Terraform fix) không có aws-node vì nó không nằm trong `cluster_addons`. Cluster cũ có thể còn aws-node → xóa trước: `kubectl delete ds aws-node -n kube-system`.

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
>
> ⚠️ **Lưu ý:** Ở Mode A, Cilium vẫn tham gia xử lý ClusterIP Services ở per-packet level.
> Mode A KHÔNG phải pure kube-proxy baseline — nó là "Cilium hybrid + kube-proxy".
> Điều này được ghi nhận trong Threats to Validity (Phase 10).

📸 Screenshot: `docs/figures/thesis/fig-03-modeA-cilium-status.png` (cilium status → `KubeProxyReplacement = Disabled`, `IPAM: cluster-pool` — `fig-03-modeA-cilium-status.png`)
📸 Screenshot: `docs/figures/thesis/fig-04-modeA-kube-proxy-ds.png` (`kubectl get ds kube-proxy -n kube-system` — kube-proxy Running 3/3 — `fig-04-modeA-kube-proxy-ds.png`)
📸 Screenshot: `docs/figures/infra/fig-A8-values-baseline-yaml.png` (VS Code / terminal `cat helm/cilium/values-baseline.yaml` — `kubeProxyReplacement: false`, `cni.conf: cilium-cni`, `debug: false` — `fig-A8-values-baseline-yaml.png`)

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
kubectl exec -n benchmark deploy/fortio -- fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
# Kỳ vọng: Code 200, 0 errors
kubectl get pods -n benchmark -o wide
# Kỳ vọng: echo và fortio cùng NODE (podAffinity hút vào cùng 1 node)
kubectl get svc,endpoints -n benchmark
```

```bash
# DNS contract check (nên pass trước benchmark)
kubectl get svc -n kube-system kube-dns -o wide
kubectl get endpoints -n kube-system kube-dns -o wide
# Kỳ vọng: kube-dns có 53/UDP + 53/TCP và có endpoints
```

> ⚠️ **Same-node placement:** Workload deployments dùng `podAffinity` nên echo và fortio **tự động cùng 1 node**. Verify bằng `kubectl get pods -n benchmark -o wide` — cột NODE phải giống nhau. Nếu khác node → kiểm tra lại YAML affinity config.

Nếu có lỗi kiểu `lookup ... on 172.20.0.10:53: i/o timeout`, reconcile CoreDNS addon:

```bash
CLUSTER_NAME=$(kubectl config current-context | sed 's|.*/||')
aws eks update-addon --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
    --addon-name coredns --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name "${CLUSTER_NAME}" --region ap-southeast-1 \
    --addon-name coredns
```

📸 Screenshot: `docs/figures/thesis/fig-02-modeA-pod-placement.png` (`kubectl get pods -n benchmark -o wide` — echo + fortio cùng NODE — `fig-02-modeA-pod-placement.png`)
📸 Screenshot: `docs/figures/thesis/fig-04-modeA-fortio-smoke.png` (Fortio smoke test summary — `Code 200`, `p50/p90/p99`, `0 errors` — `fig-04-modeA-fortio-smoke.png`)

#### ✅ Checklist Phase 5

```
[ ] echo + fortio pods Running trong namespace benchmark
[ ] echo và fortio cùng 1 node (NODE column giống nhau)
[ ] fortio → echo connectivity OK (Code 200)
[ ] Service ClusterIP tồn tại, endpoint được populate
[ ] kube-dns service có 53/UDP + 53/TCP và có endpoints
```

---

### Phase 5b — Resume sau Tạm dừng (sau khi scale node về 0)

> Chạy sau khi scale node group lên lại 3 nodes.
> Scale về 0 → tất cả pods (workload + Cilium) bị terminated.
> Cần verify toàn bộ hệ thống trước khi tiếp tục benchmark.

#### 5b.0 Resume node group (trước khi verify anything khác)

```bash
# Lấy nodegroup name thực tế
NODEGROUP=$(aws eks list-nodegroups --cluster-name nt531-bm --region ap-southeast-1 --query 'nodegroups[0]' --output text)
echo "Nodegroup: ${NODEGROUP}"

# Scale lên 3 nodes cố định
aws eks update-nodegroup-config \
    --cluster-name nt531-bm \
    --nodegroup-name "${NODEGROUP}" \
    --scaling-config minSize=3,maxSize=3,desiredSize=3 \
    --region ap-southeast-1

# Đợi nodes ready
aws eks wait nodegroup-active \
    --cluster-name nt531-bm \
    --nodegroup-name "${NODEGROUP}" \
    --region ap-southeast-1

echo "Node group scaled up to 3. Tiếp tục 5b.1..."
```

📸 Screenshot: `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` hoặc `docs/figures/thesis/fig-07-modeB-cluster-nodes.png` (tùy mode hiện tại — `kubectl get nodes -o wide`)

#### 5b.1 Verify nodes up

```bash
kubectl get nodes -o wide
# Kỳ vọng: 3 node Ready, AGE ~5-10 phút (vừa scale lên)
```
📸 Screenshot: `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` hoặc `docs/figures/thesis/fig-07-modeB-cluster-nodes.png` (tùy mode hiện tại)

#### 5b.2 Verify Cilium pods

```bash
kubectl -n kube-system get pods -l k8s-app=cilium -o wide
# Kỳ vọng: 3 cilium-node pods Running (DaemonSet)
kubectl -n kube-system get ds
# Kỳ vọng: cilium DaemonSet tồn tại; aws-node KHÔNG tồn tại
```

#### 5b.3 Verify kube-proxy (tùy mode hiện tại)

```bash
kubectl -n kube-system get ds kube-proxy -o name
# Mode A: phải thấy daemonset.apps/kube-proxy
# Mode B: NotFound — đã bị xóa ở Phase 8
```

#### 5b.4 Verify Cilium status + datapath mode

```bash
kubectl exec -n kube-system ds/cilium -- cilium status
# Mode A: KubeProxyReplacement = Disabled, IPAM: cluster-pool
# Mode B: KubeProxyReplacement = Strict, IPAM: eni, Hubble Relay Enabled
```

#### 5b.5 Redeploy workload (sau khi scale node)

```bash
kubectl apply -f workload/server/ && kubectl apply -f workload/client/
kubectl -n benchmark get pods -w
# Đợi: echo Running, fortio Running (cột AGE sẽ ~1-2 phút)
```

#### 5b.6 Verify connectivity

```bash
kubectl exec -n benchmark deploy/fortio -- fortio curl http://echo.benchmark.svc.cluster.local:80/echo
# Kỳ vọng: HTTP 200, response chứa "ok"
```

📸 Screenshot: Fortio connectivity test output (HTTP 200 OK)

#### 5b.7 Verify DNS

```bash
kubectl get svc,endpoints -n kube-system kube-dns -o wide
# Kỳ vọng: 53/UDP + 53/TCP endpoint tồn tại
```

#### 5b.8 Verify Service + Endpoints

```bash
kubectl get svc,endpoints -n benchmark
# Kỳ vọng: echo ClusterIP, port 80→5678, ENDPOINTS có IP
```

#### 5b.9 Quick Fortio smoke test

```bash
kubectl exec -n benchmark deploy/fortio -- \
  fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
# Kỳ vọng: Code 200, 0 errors
kubectl get pods -n benchmark -o wide
# Kỳ vọng: echo và fortio cùng NODE
```

#### ✅ Checklist Phase 5b

```
[ ] NODEGROUP lấy đúng tên
[ ] aws eks update-nodegroup-config → desiredSize=3
[ ] aws eks wait nodegroup-active → thành công
[ ] 3 nodes Ready
[ ] Cilium DaemonSet Running, aws-node NOT present
[ ] kube-proxy đúng trạng thái (Mode A: Running, Mode B: absent)
[ ] cilium status: đúng mode (A: cluster-pool+Disabled / B: eni+Strict)
[ ] echo + fortio pods Running sau khi redeploy
[ ] echo và fortio cùng 1 node (NODE column giống nhau)
[ ] fortio → echo connectivity OK
[ ] kube-dns endpoints tồn tại
[ ] echo Service ClusterIP + endpoints populate
[ ] Fortio smoke test: 100% success
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

#### 7.0 — Pre-run Evidence Capture ★ (LÀM MỘT LẦN TRƯỚC KHI CHẠY BENCHMARK)

> Thu thập bằng chứng cho thesis. Chạy **MỘT LẦN DUY NHẤT** trước Phase 7.1.

##### Bước A — Chạy commands và lưu output text

```bash
# Tạo thư mục evidence
mkdir -p evidence/
mkdir -p docs/figures/

# Lưu cluster context
date +"%Y-%m-%d %H:%M" > evidence/modeA-run-timestamp.txt
kubectl config current-context >> evidence/modeA-run-timestamp.txt

# 1. Cluster nodes — lưu text output
kubectl get nodes -o wide > evidence/modeA-nodes.txt
# → Dùng output này làm bảng specs trong thesis

# 2. Pod placement — lưu text output
kubectl get pods -n benchmark -o wide > evidence/modeA-pods.txt
# → Dùng output này làm same-node proof

# 3. Same-node check (automated)
echo-node=$(kubectl get pods -n benchmark -l app=echo -o jsonpath='{.items[0].spec.nodeName}')
fortio-node=$(kubectl get pods -n benchmark -l app=fortio -o jsonpath='{.items[0].spec.nodeName}')
echo "echo-node=$echo-node fortio-node=$fortio-node"
if [[ "$echo-node" != "$fortio-node" ]]; then
  echo "[FATAL] Pods on different nodes! This invalidates same-node benchmark."
  exit 1
fi

# 4. kube-proxy status
kubectl get ds kube-proxy -n kube-system -o wide > evidence/modeA-kube-proxy-ds.txt

# 5. Cilium status
kubectl exec -n kube-system ds/cilium -- cilium status > evidence/modeA-cilium-status.txt

# 6. Fortio smoke test
kubectl exec -n benchmark deploy/fortio -- fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
```

##### Bước B — Screenshot ảnh (CHỤP 6 ẢNH cho Mode A)

> **Cách chụp:** Mở terminal → chạy lệnh → chụp ảnh toàn bộ cửa sổ terminal bằng Snipping Tool / Windows+Shift+S.

| # | Màn hình cần chụp | Lệnh đang hiển thị | Lưu thành file | Dùng trong thesis | **Ý nghĩa** |
|---|---|---|---|---|---|
| **S1** | Terminal sau khi chạy `kubectl get nodes -o wide` | Command output hiển thị 3 nodes Ready | `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` | Chương 3 — Experimental Setup | **Chứng minh cluster thật sự gồm 3 node m5.large, ghim cùng 1 AZ.** Reviewer cần thấy cluster tồn tại và đúng cấu hình thiết kế trước khi xem bất kỳ số liệu nào. |
| **S2** | Terminal sau khi chạy `kubectl get pods -n benchmark -o wide` | echo + fortio cùng cột NODE | `docs/figures/thesis/fig-02-modeA-pod-placement.png` | Chương 3 — Methodology (same-node proof) | **Chứng minh traffic chạy cùng node (same-node).** Đây là nền tảng của toàn bộ benchmark — same-node topology loại bỏ cross-AZ latency variability. Nếu khác node, benchmark design bị sai. |
| **S3** | Terminal sau khi chạy `kubectl exec -n kube-system ds/cilium -- cilium status` | `KubeProxyReplacement = Disabled` hiển thị rõ | `docs/figures/thesis/fig-03-modeA-cilium-status.png` | Chương 3 — Cilium Mode A config | **Chứng minh Mode A chạy đúng hybrid datapath với `kubeProxyReplacement=false`.** Không có ảnh này, không prove được mode thực tế đang chạy. |
| **S3b** | Terminal `kubectl get ds kube-proxy -n kube-system` | kube-proxy DaemonSet Running 3/3 | `docs/figures/thesis/fig-04-modeA-kube-proxy-ds.png` | Chương 3 — Mode A config | **Chứng minh kube-proxy vẫn active ở Mode A.** Reviewer cần thấy cả hai (cilium + kube-proxy) cùng tồn tại song song. |
| **S4** | Terminal Fortio smoke test — summary output | `Code 200`, p50/p90/p99, 0 errors | `docs/figures/thesis/fig-04-modeA-fortio-smoke.png` | Chương 3 — Workload readiness | **Chứng minh workload sẵn sàng trước benchmark.** Error rate = 0, Code 200 → benchmark data sẽ đáng tin, không phải do setup lỗi. |
| **S5** | Fortio web UI — histogram baseline — **port-forward: `kubectl port-forward -n benchmark deploy/fortio 8080:8080 &` → mở http://localhost:8080** | Histogram p50/p90/p99 baseline | `docs/figures/thesis/fig-05-modeA-fortio-histogram.png` | Appendix — Baseline performance | **Cung cấp raw baseline latency distribution cho Mode A.** Appendix reviewer cần thấy baseline p50/p90/p99 thực tế để đối chiếu với Mode B. |
| **S6** | Grafana dashboard (nếu có metrics-server) | Node CPU usage, Prometheus dashboard | `docs/figures/grafana/fig-06-modeA-grafana-nodes.png` | Chương 3 — Environment stability | **Chứng minh không có CPU saturation làm nhiễu kết quả.** Nếu node >85% CPU → results bị bias. Ảnh này tăng credibility của toàn bộ benchmark. |

> **Lệnh port-forward Fortio web UI (chạy nền terminal riêng):**
> ```bash
> kubectl port-forward -n benchmark deploy/fortio 8080:8080 &
> # Mở trình duyệt → http://localhost:8080
> ```

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

#### 7.2 Thu thập Evidence

```bash
./scripts/collect_meta.sh results/mode=A_kube-proxy/
```

#### 7.3 Verify kết quả

```bash
find results/mode=A_kube-proxy -name "bench.log" | wc -l    # phải = 15
find results/mode=A_kube-proxy/scenario=S2 -name "bench_phase1_rampup.log" | wc -l  # phải = 6
```

> **Quick sanity check sau tất cả runs:**
```bash
# Kiểm tra error rate cho mỗi run
for d in results/mode=A_kube-proxy/scenario=*/load=*/run=*/; do
  echo -n "$(basename $d): "
  grep -m1 "Non-2xx" "$d/bench.log" || echo "0 errors"
done
```

#### ✅ Checklist Phase 7

```
[ ] Phase 7.0 Pre-run evidence capture hoàn tất (nodes, pods, cilium status, Fortio smoke test)
[ ] Same-node placement verified (echo + fortio cùng node)
[ ] kubectl top nodes — no anomaly (>85% CPU)
[ ] 15 runs hoàn tất (S1=9, S2=6)
[ ] Mỗi run có: bench.log, metadata.json, checklist.txt
[ ] kubectl_get_all.txt, kubectl_top_nodes.txt, events.txt
[ ] S2: 4 phase logs mỗi run (phase1→phase4)
[ ] Error rate OK (<1%) cho tất cả runs
```

---

### Phase 8 — Chuyển Mode A → Mode B ⚠️ CRITICAL

> **⚠️ RỦI RO:** Trong thời gian chuyển đổi (~30-60 giây), cluster ở trạng thái trung gian — không có gì quản lý Services nếu kube-proxy đã xóa mà Cilium chưa ready. Benchmark runs nên **dừng trước khi switch**.
>
> **⚠️ NẾU LÀM SAI:** kube-proxy + eBPF chạy song song → NAT table conflict → results sai hoàn toàn.
>
> **Lưu ý quan trọng:** Mỗi lần switch mode (A→B hoặc B→A), LUÔN restart workload pods sau khi switch.
> Lý do: IPAM mode khác nhau (cluster-pool vs ENI) → pod IP ranges khác nhau.

#### 8.1 Cập nhật `k8sServiceHost` trong values-ebpfkpr.yaml ← BẮT BUỘC

> ⚠️ **Mỗi lần chạy `terraform apply`, endpoint THAY ĐỔI.**
> Phải cập nhật TRƯỚC bước 8.3. Sai endpoint → Cilium upgrade nhắm sai cluster → benchmark thất bại SILENT.

```bash
# Tự động lấy endpoint và update values file:
ENDPOINT=$(aws eks describe-cluster --name nt531-bm --region ap-southeast-1 \
  --query cluster.endpoint --output text | sed 's|https://||')
sed -i "s|k8sServiceHost: \".*\"|k8sServiceHost: \"${ENDPOINT}\"|" helm/cilium/values-ebpfkpr.yaml
grep k8sServiceHost helm/cilium/values-ebpfkpr.yaml
# Verify: phải khớp với endpoint AWS trả về (không có https://)
```

#### 8.2 Đảm bảo `eni.enabled: true` trong values-ebpfkpr.yaml ← BẮT BUỘC

Kiểm tra trong file có dòng:
```yaml
eni:
  enabled: true
```
Nếu thiếu → thêm vào trước bước 8.3. Thiếu dòng này → cilium-operator crash: `"cilium-operator-generic: executable not found"`.

#### 8.3 XÓA kube-proxy (BẮT BUỘC trước bước 8.4)

```bash
kubectl delete ds kube-proxy -n kube-system || true
sleep 30
```

#### 8.4 Upgrade Cilium Mode B

```bash
helm upgrade cilium cilium/cilium -n kube-system \
  --version 1.18.7 -f helm/cilium/values-ebpfkpr.yaml
```

> ⚠️ Không dùng `--wait` — cilium-agent restart mất 2-3 phút, helm `--wait` timeout sẽ fail.

#### 8.5 Theo dõi tiến trình

```bash
kubectl get pods -n kube-system -l app=cilium-operator -w &
kubectl get pods -n kube-system -l k8s-app=cilium -w &
# Chờ ~2-5 phút cho đến khi:
#   - cilium-operator Running 1/1
#   - cả 3 cilium pods Running 1/1
```

#### 8.6 Xác minh Mode B

```bash
kubectl exec -n kube-system ds/cilium -- cilium status
```

> Kỳ vọng:
> ```
> KubeProxyReplacement: True  (ens5 ...)
> IPAM: IPv4: X/10 allocated     ← ENI, không phải cluster-pool
> Routing: Network: Native       ← không phải Tunnel [vxlan]
> Hubble: Ok
> ```

#### 8.7 Restart CoreDNS (BẮT BUỘC)

```bash
kubectl delete pods -n kube-system -l k8s-app=kube-dns
# Đợi ~30s
kubectl get pods -n kube-system -l k8s-app=kube-dns
# Kỳ vọng: Running 1/1
```

> Lý do: kube-proxy bị xóa → CoreDNS endpoint resolver broken. Phải restart để pick up eBPF datapath mới.

#### 8.8 Restart workload pods (BẮT BUỘC)

```bash
kubectl delete pods -n benchmark --all
# Đợi ~30s
kubectl get pods -n benchmark -o wide
# Kỳ vọng: echo + fortio Running với ENI IPs (10.0.x.x)
```

> Lý do: Pods cũ giữ cluster-pool IPs (10.96.x.x), không đi qua ENI native routing. Restart để nhận ENI IPs (10.0.x.x).

#### 8.9 Verify connectivity

```bash
FORTIO=$(kubectl get pods -n benchmark -l app=fortio -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n benchmark "$FORTIO" -- \
  fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
# Kỳ vọng: Code 200, 0 errors
```

#### 8.10 Xóa Hubble relay và Hubble UI pods ← BẮT BUỘC

```bash
kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-relay
kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-ui
# Đợi ~10s
# Verify ENI IP (phải là 10.0.x.x, KHÔNG phải 10.96.x.x):
kubectl get pod -n kube-system -l app.kubernetes.io/name=hubble-relay -o jsonpath='{.items[0].status.podIP}'
# Verify không BackOff:
kubectl get events -n kube-system --sort-by='.lastTimestamp' | grep hubble-relay
# Kỳ vọng: Normal  Started  (không có BackOff)
```

> Lý do: Hubble relay pod giữ **cluster-pool IP (`10.96.x.x`)** từ Mode A. ENI native routing chỉ route được `10.0.x.x` → eBPF drop packet → startup probe fail → BackOff loop. Xóa pod buộc nó nhận ENI IP mới.

#### ✅ Checklist Phase 8

```
[ ] values-ebpfkpr.yaml đã điền k8sServiceHost (không có https://)
[ ] values-ebpfkpr.yaml có eni.enabled: true
[ ] kube-proxy DaemonSet đã xóa (hoặc NotFound)
[ ] cilium-operator Running 1/1 (rev mới)
[ ] cả 3 cilium pods Running 1/1
[ ] cilium status: KubeProxyReplacement=True, IPAM=ENI, Routing=Native
[ ] CoreDNS pods restarted và Running 1/1
[ ] Workload pods restarted với ENI IPs
[ ] Hubble relay + UI pods đã xóa và recreated với ENI IPs (10.0.x.x)
[ ] Hubble relay: không BackOff event, pod Running
[ ] Fortio → Echo: Code 200, 0 errors
```

#### Troubleshooting Phase 8

| Triệu chứng | Nguyên nhân | Fix |
|---|---|---|
| `cilium-operator` CrashLoopBackOff: `"cilium-operator-generic: executable not found"` | Thiếu `eni.enabled: true` | Thêm `eni.enabled: true` vào values-ebpfkpr.yaml, upgrade lại |
| `cilium` pods CrashLoopBackOff: `"Waiting for IPs to become available"` | `cilium-operator` chưa Running | Đợi operator, hoặc check operator logs |
| Fortio DNS timeout: `lookup ... on 172.20.0.10:53: i/o timeout` | CoreDNS chưa pick up eBPF datapath | Restart CoreDNS: `kubectl delete pods -n kube-system -l k8s-app=kube-dns` |
| Fortio dial timeout trên IP trực tiếp | Workload pods giữ cluster-pool IPs | Restart workload: `kubectl delete pods -n benchmark --all` |

#### Rollback Plan (nếu switch thất bại nghiêm trọng)

> **Lưu ý:** Helm values đã commit, Terraform state đã update. Nếu gặp lỗi không fix được sau 30 phút troubleshooting, dùng rollback:

**Option A — Helm rollback (nhanh, ~2 phút):**
```bash
helm rollback cilium -n kube-system
kubectl delete pods -n benchmark --all
kubectl delete pods -n kube-system -l k8s-app=kube-dns
# Verify
kubectl exec -n kube-system ds/cilium -- cilium status | grep KubeProxy
```

**Option B — Terraform destroy + apply (chậm nhưng sạch nhất, ~15-25 phút):**
```bash
cd terraform && terraform destroy -var-file=envs/dev/terraform.tfvars -auto-approve
terraform apply -var-file=envs/dev/terraform.tfvars -auto-approve
# Sau đó restart từ Phase 3
```

---

### Phase 9 — Mode B Benchmark Runs: 27 runs thực tế

#### 9.0 — Pre-run Evidence Capture ★ (LÀM MỘT LẦN TRƯỚC KHI CHẠY BENCHMARK)

> Thu thập bằng chứng cho thesis. Chạy **MỘT LẦN DUY NHẤT** trước Phase 9.1.

##### Bước A — Chạy commands và lưu output text

```bash
# Tạo thư mục
mkdir -p evidence/
mkdir -p docs/figures/

# Lưu cluster context
date +"%Y-%m-%d %H:%M" > evidence/modeB-run-timestamp.txt
kubectl config current-context >> evidence/modeB-run-timestamp.txt

# 1. Cluster nodes
kubectl get nodes -o wide > evidence/modeB-nodes.txt

# 2. Pod placement
kubectl get pods -n benchmark -o wide > evidence/modeB-pods.txt

# 3. Same-node check
echo-node=$(kubectl get pods -n benchmark -l app=echo -o jsonpath='{.items[0].spec.nodeName}')
fortio-node=$(kubectl get pods -n benchmark -l app=fortio -o jsonpath='{.items[0].spec.nodeName}')
echo "echo-node=$echo-node fortio-node=$fortio-node"
if [[ "$echo-node" != "$fortio-node" ]]; then
  echo "[FATAL] Pods on different nodes!"
  exit 1
fi

# 4. Cilium status (Mode B — phải KubeProxyReplacement=True/Strict)
kubectl exec -n kube-system ds/cilium -- cilium status > evidence/modeB-cilium-status.txt

# 5. Hubble status
kubectl exec -n kube-system ds/cilium -- hubble status > evidence/modeB-hubble-status.txt

# 6. Fortio smoke test
kubectl exec -n benchmark deploy/fortio -- fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
```

##### Bước B — Screenshot ảnh (CHỤP 6 ẢNH cho Mode B)

| # | Màn hình cần chụp | Lệnh đang hiển thị | Lưu thành file | Dùng trong thesis | **Ý nghĩa** |
|---|---|---|---|---|---|
| **S1** | Terminal sau khi chạy `kubectl get nodes -o wide` | 3 nodes Ready, cùng 1 AZ | `docs/figures/thesis/fig-07-modeB-cluster-nodes.png` | Chương 3 | **Chứng minh Mode B vẫn giữ đúng topology.** Cùng 3 node m5.large, same AZ — đảm bảo A và B so sánh công bằng (chỉ datapath khác, infrastructure không đổi). |
| **S2** | Terminal sau khi chạy `kubectl get pods -n benchmark -o wide` | echo + fortio cùng cột NODE | `docs/figures/thesis/fig-08-modeB-pod-placement.png` | Chương 3 (same-node proof) | **Chứng minh same-node topology không bị phá vỡ sau switch A→B.** Prove benchmark design nhất quán: topology đầu cuối giữa A và B chỉ khác datapath, không phải pod placement. |
| **S3** | Terminal sau khi `cilium status` — PHẦN ĐẦU output | `KubeProxyReplacement = True` (màu xanh) | `docs/figures/thesis/fig-09-modeB-kubeproxy-replacement.png` | Chương 3 — Mode B datapath proof | **Ảnh quan trọng nhất của Mode B.** Chứng minh KPR thật sự enabled — không phải "hybrid" hay "partial". Đây là claim chính của mode B. |
| **S4** | Terminal `cilium status` — PHẦN ROUTING/IPAM | `IPAM: IPv4: X/10 allocated`, `Routing: Native` | `docs/figures/thesis/fig-10-modeB-routing-native.png` | Chương 3 — ENI routing proof | **Chứng minh Mode B dùng ENI native routing, không VXLAN tunnel.** Giải thích cơ chế: Mode B bypass iptables → O(1) BPF map lookup thay vì O(n) DNAT traversal. Không có ảnh này → không có bằng chứng cơ chế. |
| **S5** | Fortio web UI histogram — **port-forward: `kubectl port-forward -n benchmark deploy/fortio 8080:8080 &` → mở http://localhost:8080** | Histogram p50/p90/p99 baseline Mode B | `docs/figures/thesis/fig-12-modeB-fortio-histogram.png` | Appendix | **Baseline histogram của Mode B để so sánh với Mode A.** Reviewer Appendix cần thấy cả hai modes ở cùng appendix để đối chiếu raw data. |
| **S6** | Hubble UI dashboard — **port-forward: `kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &` → mở http://localhost:12000** | Hubble UI connected, relay status | `docs/figures/hubble/fig-12-modeB-hubble-status.png` | Chương 3 | **Chứng minh Hubble enabled và Relay connected.** Đây vừa là requirement của S3 (policy verdict) vừa là Threat to Validity (#1) cần thừa nhận. Nếu Hubble không connected → S3 không đo được. |
| **S7** | Terminal: `kubectl exec -n kube-system ds/cilium -- hubble status` — **CLI fallback khi Hubble UI 502 Bad Gateway** | `Hubble: Ok`, `Relay: Connected` | `docs/figures/hubble/fig-11-modeB-hubble-ok.png` | Chương 3 — Hubble status | **Proof Hubble Relay kết nối thành công.** Fallback khi UI không hoạt động. |

##### Bước C — Mở Fortio + Hubble UI (2 terminal nền, chạy TRƯỚC Phase 9.1)

> **Terminal 1 — Fortio web UI:**
> ```bash
> kubectl port-forward -n benchmark deploy/fortio 8080:8080 &
> # Chờ 2 giây → mở trình duyệt http://localhost:8080
> # → Chụp ảnh histogram (fig-11)
> ```

> **Terminal 2 — Hubble UI:**
> ```bash
> kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &
> # Chờ 3 giây → mở trình duyệt http://localhost:12000
> # → Chụp ảnh Hubble dashboard thấy "Hubble Relay: Connected" (fig-12)
> ```

> ⚠️ **Nếu Hubble UI không hoạt động** (502 Bad Gateway), bỏ qua UI — dùng CLI thay thế:
> ```bash
> kubectl exec -n kube-system ds/cilium -- hubble status
> # → chụp terminal → fig-12
> ```

##### Bước D — Hubble observe CLI (thu flows mẫu, chạy SAU Phase 9.3)

> Sau khi S3 chạy xong, thu flows mẫu để proof FORWARDED verdict:
> ```bash
> kubectl exec -n kube-system ds/cilium -- hubble observe \
>   --namespace benchmark --last 100 -o table \
>   > evidence/hubble-observe-sample.txt
> # Chụp terminal → docs/figures/hubble/fig-12b-hubble-observe-sample.png
> ```

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
kubectl run attacker --image=curlimages/curl --rm -it --restart=Never -n benchmark -- \
  curl --connect-timeout 5 http://echo.benchmark.svc:80/echo
# Kỳ vọng: FAIL/TIMEOUT (attacker không match policy allow)
```

```bash
kubectl exec -n kube-system ds/cilium -c cilium-agent -- hubble observe --namespace benchmark --last 2000 -o jsonpb > results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
grep -c "DROPPED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
grep -c "FORWARDED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log
```

> Kỳ vọng: DROPPED > 0 (enforcement hoạt động), FORWARDED > 0 (legit traffic vẫn đi).

> **Hubble UI screenshot cho fig-13 (DROPPED verdict proof):**
>
> Sau khi attacker bị DROP, mở Hubble UI trên trình duyệt:
> ```bash
> kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &
> # Chờ 3 giây
> # Mở trình duyệt → http://localhost:12000
> ```
>
> Trên Hubble UI:
> 1. Filter: `namespace=benchmark`, `verdict=DROPPED`
> 2. Chụp ảnh màn hình → `docs/figures/hubble/fig-13-hubble-deny-case.png`
> 3. Filter: `namespace=benchmark`, `verdict=FORWARDED`
> 4. Chụp ảnh → `docs/figures/hubble/fig-13b-hubble-forwarded-case.png` (tùy chọn)
>
> **Nếu Hubble UI không hoạt động**, dùng CLI thay thế:
> ```bash
> kubectl exec -n kube-system ds/cilium -- hubble observe \
>   --namespace benchmark --verdict DROPPED --last 50 -o table \
>   > evidence/hubble-deny-case.txt
> # Chụp terminal output → docs/figures/hubble/fig-13-hubble-deny-cli.png
> ```

#### 9.5 Thu thập Evidence Mode B

```bash
./scripts/collect_meta.sh results/mode=B_cilium-ebpfkpr/ && \
./scripts/collect_hubble.sh results/mode=B_cilium-ebpfkpr/
```

> **Quick sanity check sau tất cả runs:**
```bash
for d in results/mode=B_cilium-ebpfkpr/scenario=*/load=*/run=*/; do
  echo -n "$(basename $d): "
  grep -m1 "Non-2xx" "$d/bench.log" || echo "0 errors"
done
```

#### 9.6 Verify kết quả

```bash
find results/mode=B_cilium-ebpfkpr -name "bench.log" | wc -l           # phải = 27
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "hubble_flows.jsonl" | wc -l  # phải = 12
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "deny_case_hubble.log" | wc -l  # phải >= 1
```

#### ✅ Checklist Phase 9

```
[ ] Phase 9.0 Pre-run evidence capture hoàn tất (nodes, pods, cilium status, Hubble status, Fortio smoke test)
[ ] Same-node placement verified (echo + fortio cùng node)
[ ] kubectl top nodes — no anomaly (>85% CPU)
[ ] 27 runs Mode B hoàn tất (S1=9, S2=6, S3=12)
[ ] hubble_flows.jsonl đầy đủ (12 files S3)
[ ] Deny case: attacker pod bị DROP, hubble log có DROPPED verdict
[ ] Deny case: fortio→echo vẫn FORWARDED (không false-positive)
[ ] Cilium status + Hubble status evidence đầy đủ
[ ] Error rate OK (<1%) cho tất cả runs
```

---

### Phase 11 — Phân tích Thống kê & Viết Báo cáo (1–2 ngày)

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

1. **Hubble overhead chưa kiểm soát**: Mode B bật Hubble (observability), Mode A không có tương đương → có thể làm Mode B chậm hơn ở S1/S2. Cilium docs ghi nhận Hubble overhead 1-15% tùy traffic pattern.
2. **Pod scheduling noise**: Dù ghim AZ, vẫn có variability
3. **AWS noisy neighbor**: Các VM host cùng physical host có thể gây nhiễu
4. **Server bottleneck**: hashicorp/http-echo:1.0 có thể trở thành bottleneck ở L3
5. **Sequential execution A→B**: Không có fair comparison song song
6. **Mode A hybrid baseline (IMPORTANT):** Mode A không phải pure kube-proxy baseline — Cilium hybrid vẫn tham gia ClusterIP load-balancing ở per-packet level khi `kubeProxyReplacement=false`. So sánh thực chất là: "Cilium hybrid + kube-proxy" vs "Cilium full eBPF". Phần này **mở rộng** Mode B advantage (vì Mode A đã có một phần Cilium optimization).
7. **Same-node topology limitation**: Benchmark chỉ test same-node traffic. Cross-node traffic behavior có thể khác biệt đáng kể (VXLAN encapsulation overhead ở Mode A vs ENI routing ở Mode B).
8. **Warm-up effect**: Lần chạy đầu tiên sau mode switch luôn chậm hơn do BPF map population, connection pool establishment, policy/identity propagation. Script có warmup 30s nhưng có thể chưa đủ cho Mode B.

#### 10.3.1 Evidence capture cho Threats to Validity

Khi viết thesis, cần ghi nhận:

| Threat | Evidence cần đưa vào thesis |
|---|---|
| #1 Hubble overhead | Screenshot `cilium status` showing Hubble enabled ở Mode B; thừa nhận trong Methodology |
| #6 Mode A hybrid | Trích dẫn Cilium docs: `kubeProxyReplacement=false` vẫn enable in-cluster load-balancing |
| #7 Same-node only | Nêu rõ trong Methodology: "Chỉ test same-node traffic, cross-node không thuộc phạm vi" |
| #8 Warm-up | Ghi nhận warmup duration (30s) và lý do discard warmup data |

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

#### 10.5 Biểu đồ cần cho Thesis

Tạo biểu đồ từ `aggregated_summary.csv` và `comparison_AB.csv` (output của `analyze_results.py`):

| Biểu đồ | Chart type | Chapter |
|---|---|---|
| Latency comparison A vs B (p50/p90/p99) | Grouped Bar Chart | Chương 5 |
| Throughput (RPS) comparison A vs B | Grouped Bar Chart | Chương 5 |
| S3 Policy overhead (off vs on) | Grouped Bar Chart | Chương 5 |
| Δ% overhead table | Percent Difference Table | Chương 5 |
| Hubble verdict (DROPPED/FORWARDED sample) | Screenshot `hubble_flows.jsonl` | Chương 5 |

> **Quy tắc đặt tên:** `fig-XX-<mô-tả>.png` / `table-XX-<mô-tả>.png`
> **Lưu raw CSV source** vào `docs/appendix/` để reviewer có thể reproduce.

#### ✅ Checklist Phase 11

```
[ ] analyze_results.py chạy thành công
[ ] comparison_AB.csv có đầy đủ p-value, Δ%, significance
[ ] RQ1/RQ2/RQ3 trả lời được bằng dữ liệu cụ thể
[ ] Threats to Validity được ghi nhận
[ ] Deny case (DROPPED verdict) trong S3 được ghi nhận
[ ] Báo cáo thesis có cấu trúc đầy đủ
```

---

### Phase 12 — Dọn dẹp Hạ tầng (5–10 phút)

#### 11.0 Tạm dừng project (không destroy)

Nếu muốn nghỉ tạm và giảm chi phí EC2, scale node group về 0 trước khi quay lại.
Không hardcode `--nodegroup-name benchmark` vì EKS managed node group thường có suffix tự sinh.

Có thể dùng script tiện ích (khuyến nghị):

```bash
./scripts/cluster_power.sh pause
# quay lại thì:
./scripts/cluster_power.sh resume
```

Hoặc chạy thủ công như bên dưới:

```bash
# Lấy nodegroup name thực tế
NODEGROUP=$(aws eks list-nodegroups --cluster-name nt531-bm --region ap-southeast-1 --query 'nodegroups[0]' --output text)

# Pause: scale xuống 0
aws eks update-nodegroup-config \
    --cluster-name nt531-bm \
    --nodegroup-name "${NODEGROUP}" \
    --scaling-config minSize=0,maxSize=3,desiredSize=0 \
    --region ap-southeast-1

aws eks wait nodegroup-active \
    --cluster-name nt531-bm \
    --nodegroup-name "${NODEGROUP}" \
    --region ap-southeast-1

# Resume: scale lên lại 3 nodes cố định cho benchmark
aws eks update-nodegroup-config \
    --cluster-name nt531-bm \
    --nodegroup-name "${NODEGROUP}" \
    --scaling-config minSize=3,maxSize=3,desiredSize=3 \
    --region ap-southeast-1
```

> Lưu ý: scale node group về 0 chỉ giảm phần EC2; EKS control plane và NAT Gateway vẫn tính phí.

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
| `hubble_status.txt` | `cilium hubble status` (exec vào cilium-agent container) | ✅ Mode B | ✅ Mode B | ✅ |
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
| **5b — Resume** | [ ] NODEGROUP name đúng (`aws eks list-nodegroups`); [ ] desiredSize=3; [ ] 3 nodes Ready; [ ] Cilium Running (DS đúng mode); [ ] kube-proxy đúng trạng thái (A: Running, B: absent); [ ] cilium status đúng mode (A: cluster-pool/False, B: ENI/Strict); [ ] Echo + Fortio Running sau redeploy; [ ] Fortio smoke test: Code 200, 0 errors |
| **6 — Calibration ⭐** | [ ] Calibration xong; [ ] L1/L2/L3 xác định; [ ] common.sh đã cập nhật |
| **7 — Mode A Runs** | [ ] 15 runs (S1=9, S2=6); [ ] Pre-run evidence (Phase 7.0) captured; [ ] Error rate <1% |
| **8 — Switch A→B ⚠️** | [ ] values-ebpfkpr.yaml k8sServiceHost = endpoint hiện tại (chạy lệnh sed ở runbook §3); [ ] eni.enabled: true có trong values; [ ] kube-proxy DS đã xóa (kubectl get ds kube-proxy → NotFound); [ ] cilium-operator Running; [ ] KubeProxyReplacement=True; [ ] CoreDNS restarted; [ ] Workload pods restarted với ENI IPs; [ ] Hubble relay/UI restarted; [ ] Fortio → Echo 200 OK |
| **9 — Mode B Runs** | [ ] 27 runs (S1=9, S2=6, S3=12); [ ] Pre-run evidence (Phase 9.0) captured; [ ] hubble_flows.jsonl đầy đủ; [ ] deny case DROPPED verdict; [ ] Error rate <1% |
| **11 — Phân tích** | [ ] comparison_AB.csv có p-value + Δ%; [ ] RQ1/RQ2/RQ3 trả lời được; [ ] Threats to Validity; [ ] Deny case |
| **12 — Cleanup** | [ ] Kết quả backup; [ ] terraform destroy OK |

### Tóm tắt thứ tự thực hiện

```
Phase  1 → AWS account + tools         (2–4h)
Phase  2 → Terraform EKS               (15–25 phút)
Phase  3 → Prometheus/Grafana          (10–15 phút)
Phase  4 → Cilium Mode A                (10 phút)
Phase  5 → Deploy Workload              (5–10 phút)
Phase  5b → Resume sau tạm dừng         (5–10 phút) ← sau khi scale node về 0
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
| Cilium CrashLoopBackOff | `kubectl describe pod -n kube-system -l k8s-app=cilium`; xem `events.txt`; nếu operator crash `"cilium-operator-generic: executable not found"` → thêm `eni.enabled: true` vào values-ebpfkpr.yaml |
| `cilium-operator` crash: `"cilium-operator-generic: executable not found"` | Thiếu `eni.enabled: true` trong values-ebpfkpr.yaml | Thêm `eni.enabled: true` rồi `helm upgrade cilium ... -f helm/cilium/values-ebpfkpr.yaml` |
| `cilium-operator` crash: `dial tcp 172.20.0.1:443: i/o timeout` | Cilium BPF service entries bị stuck `non-routable` trên 1+ nodes | Restart Cilium DaemonSet: `kubectl delete pod -n kube-system -l k8s-app=cilium`; verify: `kubectl exec -n kube-system ds/cilium -- cilium bpf lb list \| grep "172.20.0.1:443"` phải thấy backend `active` |
| Fortio DNS lookup timeout sau switch A→B | CoreDNS chưa pick up eBPF datapath | `kubectl delete pods -n kube-system -l k8s-app=kube-dns` |
| Fortio dial timeout trên ClusterIP sau switch A→B | Workload pods giữ cluster-pool IPs (10.96.x.x) | `kubectl delete pods -n benchmark --all` để restart với ENI IPs |
| kube-proxy không xóa được | `kubectl delete --grace-period=0 ds/kube-proxy -n kube-system` |
| Fortio → Echo timeout | `kubectl get endpoints -n benchmark`; `kubectl get svc,endpoints -n kube-system kube-dns`; reconcile CoreDNS addon (`aws eks update-addon ... --resolve-conflicts OVERWRITE`) |
| `ResourceNotFoundException: nodeGroup ... not found` khi scale | Sai nodegroup name. Chạy `aws eks list-nodegroups --cluster-name nt531-bm --region ap-southeast-1` rồi dùng đúng tên trả về (thường có suffix tự sinh) |
| `hubble-relay` BackOff sau switch A→B | Hubble relay pod giữ cluster-pool IP (`10.96.x.x`) cũ — ENI native routing không route được | Xóa relay + UI pods: `kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-relay && kubectl delete pod -n kube-system -l app.kubernetes.io/name=hubble-ui` |
| Hubble flows empty | `kubectl exec -n kube-system ds/cilium -c cilium-agent -- hubble observe ...` sau khi chạy S3; enable port 4245 |
| Deny case không thấy DROPPED | Attacker pod không có `app=fortio` label; tăng `--last` |
| Calibrate.sh Python lỗi | `python3 --version` >= 3.8; kiểm tra inline script syntax |
| Pod placement drift (echo ≠ fortio) | echo bị reschedule → `kubectl delete pods -n benchmark --all`; redeploy |

---

## 8. Run Notes Template ★

> **Mỗi ngày chạy benchmark — ghi đầy đủ.** Copy template này vào file riêng, ví dụ: `docs/run-notes/2026-04-XX.md`

```markdown
# Run Notes — YYYY-MM-DD

## Environment
- Cluster: _______________
- Mode: A / B
- kubectl context: _______________
- Date: _______________

## Pre-run (Phase 7.0 / 9.0)
- [ ] kube context verified: _______________
- [ ] kubectl get nodes → all Ready
- [ ] kubectl get pods -n benchmark -o wide → same node confirmed
  - echo node: _______________
  - fortio node: _______________
- [ ] kubectl top nodes → no anomaly
  - Node1 CPU: ___%
  - Node2 CPU: ___%
  - Node3 CPU: ___%
- [ ] cilium status (Mode B): KubeProxyReplacement = _______________
- [ ] kube-proxy status (Mode A): _______________
- [ ] Hubble status (Mode B): _______________
- [ ] Fortio smoke test: Code 200 OK / FAILED

## Screenshot Evidence Captured

**Mode A (fig-01 → fig-06):**
- [ ] `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` — kubectl get nodes -o wide
- [ ] `docs/figures/thesis/fig-02-modeA-pod-placement.png` — kubectl get pods -n benchmark -o wide (same-node proof)
- [ ] `docs/figures/thesis/fig-03-modeA-cilium-status.png` — cilium status (KubeProxyReplacement=Disabled)
- [ ] `docs/figures/thesis/fig-04-modeA-kube-proxy-ds.png` — kube-proxy DS Running 3/3
- [ ] `docs/figures/thesis/fig-04-modeA-fortio-smoke.png` — Fortio smoke test summary
- [ ] `docs/figures/thesis/fig-05-modeA-fortio-histogram.png` — Fortio web UI histogram
- [ ] `docs/figures/grafana/fig-06-modeA-grafana-nodes.png` — Grafana node metrics (nếu có)

**Mode B (fig-07 → fig-12):**
- [ ] `docs/figures/thesis/fig-07-modeB-cluster-nodes.png`
- [ ] `docs/figures/thesis/fig-08-modeB-pod-placement.png` — same-node proof
- [ ] `docs/figures/thesis/fig-09-modeB-kubeproxy-replacement.png` — KubeProxyReplacement=True
- [ ] `docs/figures/thesis/fig-10-modeB-routing-native.png` — ENI IPAM + Native routing
- [ ] `docs/figures/thesis/fig-12-modeB-fortio-histogram.png` — Fortio histogram
- [ ] `docs/figures/hubble/fig-12-modeB-hubble-status.png` — Hubble UI dashboard (hoặc `hubble status` CLI)
- [ ] `docs/figures/hubble/fig-11-modeB-hubble-ok.png` — `hubble status` CLI fallback
- [ ] `docs/figures/hubble/fig-12b-hubble-observe-sample.png` — Hubble observe FORWARDED verdict (sau Phase 9.3)

## Anomalies & Observations
- _______________

## Post-run
- [ ] bench.log count verified: 15 (Mode A) / 27 (Mode B)
- [ ] collect_meta.sh đã chạy
- [ ] collect_hubble.sh đã chạy (Mode B)
- [ ] Hubble DROPPED verdict count: ____ (S3 deny case)

## Overall Assessment
- Mode A vs Mode B latency direction: _______
- Statistical significance: _______ (p-value)
- Threats to Validity notes: _______

```

---

## 9. Tổng hợp Screenshot — Toàn bộ Benchmark

> Bảng này liệt kê **TẤT CẢ** ảnh chụp cần thu thập cho thesis và slide. Đánh dấu ✅ khi đã chụp xong.

### ẢNH CHỤP CHO THESIS (BÁO CÁO)

> **Ý nghĩa cột "Tại sao cần":** Mỗi ảnh minh chứng cho một claim cụ thể trong thesis. Không chụp thừa, không thiếu.

| File | Chụp gì | Nội dung | Thời điểm | Dùng trong | **Tại sao cần** |
|---|---|---|---|---|---|
| `fig-01-modeA-cluster-nodes.png` | Terminal `kubectl get nodes -o wide` | 3 node m5.large, all Ready, cùng 1 AZ | Phase 7.0 | Chương 3 — Infrastructure | **Claim:** "Cluster gồm 3 node m5.large, ghim 1 AZ". Reviewer cần thấy cluster thật sự như mô tả. → `docs/figures/thesis/fig-01-modeA-cluster-nodes.png` |
| `fig-02-modeA-pod-placement.png` | Terminal `kubectl get pods -n benchmark -o wide` | echo + fortio cùng cột NODE | Phase 7.0 | Chương 3 — Methodology | **Claim:** "Traffic cùng node (same-node)". Đây là nền tảng của toàn bộ benchmark design. → `docs/figures/thesis/fig-02-modeA-pod-placement.png` |
| `fig-03-modeA-cilium-status.png` | Terminal `cilium status` | `KubeProxyReplacement = Disabled`, `IPAM: cluster-pool` | Phase 7.0 | Chương 3 — Mode A datapath | **Claim:** "Mode A chạy Cilium hybrid với `kubeProxyReplacement=false`". Không có ảnh này → không prove được mode thực tế. → `docs/figures/thesis/fig-03-modeA-cilium-status.png` |
| `fig-04-modeA-kube-proxy-ds.png` | Terminal `kubectl get ds kube-proxy -n kube-system` | kube-proxy DaemonSet Running 3/3 | Phase 7.0 | Chương 3 — Mode A config | **Claim:** "kube-proxy vẫn active ở Mode A". Reviewer cần thấy cả hai (cilium + kube-proxy) cùng tồn tại. → `docs/figures/thesis/fig-04-modeA-kube-proxy-ds.png` |
| `fig-05-modeA-fortio-histogram.png` | Fortio web UI `http://localhost:8080` | Histogram Mode A baseline, p50/p90/p99 | Phase 7.0 / 5b.6 | Appendix — Baseline perf | **Claim:** "Baseline latency trước khi đo Mode B". Appendix cần có raw performance data. → `docs/figures/thesis/fig-05-modeA-fortio-histogram.png` |
| `fig-06-modeA-grafana-nodes.png` | Grafana dashboard (port 3000) | Node CPU %, metrics | Phase 7.0 | Chương 3 — Environment stability | **Claim:** "Không có CPU saturation làm nhiễu kết quả". → `docs/figures/grafana/fig-06-modeA-grafana-nodes.png` |
| `fig-07-modeB-cluster-nodes.png` | Terminal `kubectl get nodes -o wide` | 3 node ENI IPs (10.0.x.x) | Phase 9.0 | Chương 3 | **Claim:** "Mode B dùng ENI IPAM thay vì cluster-pool". IP khác nhau → IPAM mode thực tế khác nhau. → `docs/figures/thesis/fig-07-modeB-cluster-nodes.png` |
| `fig-08-modeB-pod-placement.png` | Terminal `kubectl get pods -n benchmark -o wide` | echo + fortio cùng NODE, ENI IPs 10.0.x.x | Phase 9.0 | Chương 3 — same-node proof | **Claim:** "Same-node topology vẫn giữ nguyên sau khi switch mode". Prove benchmark setup không thay đổi giữa A và B. → `docs/figures/thesis/fig-08-modeB-pod-placement.png` |
| `fig-09-modeB-kpr-enabled.png` | Terminal `cilium status` phần HEADER | `KubeProxyReplacement = True` ✅ | Phase 9.0 | Chương 3 — Mode B datapath | **Claim:** "Mode B thực sự bật KPR". Đây là ảnh quan trọng nhất — prove mode hoạt động đúng. → `docs/figures/thesis/fig-09-modeB-kpr-enabled.png` |
| `fig-10-modeB-routing-native.png` | Terminal `cilium status` phần IPAM/Routing | `IPAM: IPv4 X/10`, `Routing: Native` | Phase 9.0 | Chương 3 — ENI routing | **Claim:** "Mode B dùng native routing (ENI) chứ không phải VXLAN tunnel". VXLAN overhead sẽ làm Mode A chậm hơn giả — đây là bằng chứng. → `docs/figures/thesis/fig-10-modeB-routing-native.png` |
| `fig-11-modeB-hubble-ok.png` | Terminal `hubble status` CLI | `Hubble: Ok`, relay connected | Phase 9.0 | Chương 3 — Hubble enabled | **Claim:** "Hubble được bật ở Mode B". Threat to Validity: Hubble overhead cần được acknowledge. → `docs/figures/hubble/fig-11-modeB-hubble-ok.png` |
| `fig-12-modeB-fortio-histogram.png` | Fortio web UI `http://localhost:8080` | Histogram Mode B baseline | Phase 9.0 | Appendix | **Claim:** "Baseline Mode B". Để reviewer so sánh với Mode A ở Appendix đối chiếu. → `docs/figures/thesis/fig-12-modeB-fortio-histogram.png` |
| `fig-12b-hubble-observe-sample.png` | `hubble observe --last 100` CLI | FORWARDED verdict flows | Sau Phase 9.3 | Chương 5 — S3 Enforcement | **Claim:** "Policy đang áp dụng, traffic hợp lệ vẫn đi qua". Proof rằng policy không false-drop legitimate traffic. → `docs/figures/hubble/fig-12b-hubble-observe-sample.png` |
| `fig-13-hubble-deny-case.png` | Hubble UI / `hubble observe` CLI | DROPPED verdict | Phase 9.4 | Chương 5 — S3 Enforcement | **Claim:** "Policy enforcement thực sự hoạt động". DROPPED verdict = Cilium đang block traffic. Không có ảnh này → không prove S3. → `docs/figures/hubble/fig-13-hubble-deny-case.png` |
| `fig-14-s3-off-vs-on.png` | Terminal S3 off vs on output | p99 overhead Δ% | Phase 9.3 | Chương 5 — S3 Results | **Claim:** "Policy overhead cụ thể là bao nhiêu %". Đây là số cần báo cáo cho S3 RQ. → `docs/figures/thesis/fig-14-s3-off-vs-on.png` |
| `fig-15-aggregated-latency.png` | Python matplotlib (từ `comparison_AB.csv`) | Bar chart p50/p90/p99 A vs B | Phase 10 | Chương 5 — Results | **Claim:** "Mode B cải thiện latency". Đây là chart chính để present RQ1. → `docs/figures/thesis/fig-15-aggregated-latency.png` |
| `fig-16-aggregated-throughput.png` | Python matplotlib | RPS comparison A vs B | Phase 10 | Chương 5 | **Claim:** "Mode B không làm throughput giảm". Throughput comparison. → `docs/figures/thesis/fig-16-aggregated-throughput.png` |
| `fig-17-comparison-table.png` | `comparison_AB.csv` formatted | Δ%, p-value, ✓ sig | Phase 10 | Chương 5 | **Claim:** "Statistical significance đạt p<0.05". Không có bảng này → thesis thiếu phân tích thống kê. → `docs/figures/thesis/fig-17-comparison-table.png` |
| `fig-18-calibration-chart.png` | `calibrate.sh` output | QPS vs latency, L1/L2/L3 marked | Phase 6 | Chương 4 — Load Levels | **Claim:** "L1/L2/L3 được xác định qua calibration, không phải guesswork". Proof reproducibility của load levels. |

### ẢNH CHỤP CHO SLIDE THUYẾT TRÌNH (bên cạnh thesis)

| File | Nội dung | Slide | **Tại sao cần** |
|---|---|---|---|
| `slide-arch-diagram.png` | Architecture topology (draw.io/Excalidraw) | Slide 1–2 | **Claim:** "Cluster gồm Fortio → ClusterIP → Echo, same-node, Cilium datapath". Người đọc cần hình dung kiến trúc trước khi xem số. |
| `slide-modeA-vs-B-datapath.png` | Mode A (iptables path) vs Mode B (BPF path) — ASCII/diagram | Slide 3 | **Claim:** "Cơ chế khác nhau: iptables DNAT chain vs eBPF O(1) map lookup". Không có diagram → slide trình bày thiếu cơ sở kỹ thuật. |
| `slide-latency-results.png` | Bar chart p99 comparison A vs B (lấy từ fig-15) | Slide 4 | **Claim:** "Mode B cải thiện P99 latency". Đây là kết quả chính của RQ1. |
| `slide-throughput-results.png` | Bar chart RPS comparison A vs B (lấy từ fig-16) | Slide 5 | **Claim:** "Mode B không làm throughput giảm". |
| `slide-s3-policy-overhead.png` | S3 off vs on overhead chart | Slide 5 hoặc riêng | **Claim:** "Policy enforcement overhead có thể đo lường được". |
| `slide-analysis.png` | BPF O(1) vs iptables O(n) + Threats to Validity | Slide 6 | **Claim:** "Tại sao Mode B nhanh hơn". Phần phân tích kỹ thuật sâu nhất — cần giải thích cơ chế nội bộ. |
| `slide-threats.png` | Threats to Validity table/list | Slide 7 | **Claim:** "Thừa nhận hạn chế của benchmark". Tăng credibility thesis. |
| `slide-conclusion.png` | Kết luận + recommendation (khi nào dùng Cilium eBPF) | Slide 8 | **Claim:** "Thesis có kết luận rõ ràng dựa trên dữ liệu". |

### ẢNH HẠ TẦNG (AWS / Terraform) — Ngữ cảnh cho Report

> Các ảnh benchmark chứng minh **kết quả**, nhưng thesis cần thêm **ngữ cảnh hạ tầng** để reviewer tin rằng infrastructure được tạo thật trên AWS, không phải chỉ mô tả trong code.

#### BẮT BUỘC — Proof hạ tầng tồn tại thật trên AWS

| File | Chụp gì | Nội dung cần thấy | Thời điểm | Dùng ở đâu | **Ý nghĩa** |
|---|---|---|---|---|---|
| `fig-A1-aws-eks-console-cluster.png` | AWS Console → EKS → Clusters → nt531-bm | Tên cluster, Kubernetes version 1.34, API server endpoint, ARN, status Active — **chụp ngay sau khi terraform apply xong** | Phase 2 (sau `terraform apply`) | Chương 3 — Infrastructure | **Proof cluster tồn tại trên AWS thật.** Terraform code + EKS console = verify resource thật được tạo. Không có ảnh này → chỉ là claim, không có bằng chứng. → `docs/figures/infra/fig-A1-aws-eks-console-cluster.png` |
| `fig-A2-aws-eks-nodegroup.png` | AWS Console → EKS → nt531-bm → Compute → Node Group | m5.large × 3, scaling config (min/max/desired = 3/3/3), AMI version, subnet assignment — **chụp sau khi node group ready** | Phase 2 (sau node group ready) | Chương 3 — Instance Decision | **Proof instance type đúng thiết kế.** m5.large là non-burstable → benchmark không bị t3 credit exhaustion. Đây là lý do chọn instance, cần proof bằng ảnh. → `docs/figures/infra/fig-A2-aws-eks-nodegroup.png` |
| `fig-A3-aws-ec2-instances.png` | AWS Console → EC2 → Instances | 3 nodes Running, instance type m5.large, private IP (10.0.x.x ENI), AZ — **chụp lại mỗi Phase 7.0 & 9.0 để verify nodes đang chạy khi benchmark** | Phase 2 + Phase 7.0/9.0 | Chương 3 (Appendix) | **Proof nodes đang chạy khi benchmark.** Khớp với `kubectl get nodes` trong thesis. → `docs/figures/infra/fig-A3-aws-ec2-instances.png` |
| `fig-A4-aws-vpc-subnets.png` | AWS Console → VPC → Subnets | 2 AZs, public + private subnets per AZ, NAT Gateway attached, route tables visible — **chụp 1 lần sau terraform apply** | Phase 2 (sau terraform apply) | Chương 3 — Topology | **Proof network topology như mô tả trong thesis.** Đặc biệt quan trọng nếu thesis có topology diagram — diagram phải khớp với thực tế AWS. → `docs/figures/infra/fig-A4-aws-vpc-subnets.png` |
| `fig-A5-aws-security-group-rules.png` | AWS Console → EC2 → Security Groups → nt531-bm-node | Inbound rules: Protocol 4 (IP-in-IP), UDP 8472 (VXLAN) self-referenced — **chụp ngay sau terraform apply, trước khi cài Cilium** | Phase 2 (sau terraform apply) | Chương 3 (Appendix) | **Proof Cilium datapath có thể hoạt động.** VXLAN mode cần these rules. Nếu thiếu → Mode A cross-node traffic bị ảnh hưởng. Đây là security group do Terraform tạo — proof infrastructure-as-code hoạt động. → `docs/figures/infra/fig-A5-aws-security-group-rules.png` |

#### NÊN CÓ — Proof config và tooling thật được dùng

| File | Chụp gì | Nội dung cần thấy | Thời điểm | Dùng ở đâu | **Ý nghĩa** |
|---|---|---|---|---|---|
| `fig-A6-terraform-apply-output.png` | Terminal `terraform apply` cuối cùng | Resource count summary (3x instance, 1x EKS cluster, NAT GW, etc.), `Apply complete!` — **chụp ngay sau khi apply, dùng cho Phase 2** | Phase 2 | Chương 3 (Appendix) | **Proof infrastructure được provision đúng.** Thể hiện Terraform chạy thành công — best practice documentation. → `docs/figures/infra/fig-A6-terraform-apply-output.png` |
| `fig-A7-terraform-output-values.png` | Terminal `terraform output` | EKS cluster endpoint, node role ARN, cluster_name — **dùng để verify k8sServiceHost khớp** | Phase 2 | Chương 3 (Appendix) | **Proof outputs khớp với config.** Endpoint phải khớp với `k8sServiceHost` trong values-ebpfkpr.yaml. → `docs/figures/infra/fig-A7-terraform-output-values.png` |
| `fig-A8-values-baseline-yaml.png` | VS Code / terminal `cat helm/cilium/values-baseline.yaml` | `kubeProxyReplacement: false`, `cni.conf: cilium-cni`, `debug: false` — **chụp ngay sau Phase 4** | Phase 4 | Chương 3 — Methodology | **Proof Mode A config thật sự được dùng.** Reviewer nhìn thấy config chứ không phải giả. Đặc biệt thấy rõ `kubeProxyReplacement: false`. → `docs/figures/infra/fig-A8-values-baseline-yaml.png` |
| `fig-A9-values-ebpfkpr-yaml.png` | VS Code / terminal `cat helm/cilium/values-ebpfkpr.yaml` | `kubeProxyReplacement: strict`, `eni.enabled: true`, `k8sServiceHost: nt531-bm.xxxx.ap-southeast-1.eks.amazonaws.com` — **chụp SAU khi update endpoint (Phase 8.1)** | Phase 8 (sau khi update endpoint) | Chương 3 — Methodology | **Proof Mode B config thật sự được dùng.** Thấy rõ `k8sServiceHost` đã được điền giá trị thực (không phải placeholder). → `docs/figures/infra/fig-A9-values-ebpfkpr-yaml.png` |
| `fig-A10-project-structure.png` | Terminal `tree` hoặc VS Code sidebar | Cấu trúc thư mục terraform/, workload/, scripts/, helm/, docs/ — **chụp 1 lần khi bắt đầu** | Phase 1 (trước terraform apply) | Chương 3 (Appendix) hoặc GitHub README | **Proof toàn bộ project được tổ chức rõ ràng.** Reviewer muốn reproduce cần thấy cấu trúc thực tế. → `docs/figures/infra/fig-A10-project-structure.png` |

### ẢNH GRAFANA — Proof Resource Usage (Mode A & B)

> **Grafana port-forward:** `kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &`
> **Mở trình duyệt:** http://localhost:3000 (user: `admin`, pass: `benchmarkAdmin`)
> **Cách chụp panel:** Click panel title → "More" → "View" (mở panel riêng) → chụp panel đó. **Không chụp toàn màn hình dashboard** vì nhiều panels không vừa ảnh.
> **Chọn node đúng:** Grafana dashboard có variable dropdown ở góc trên — chọn **node chạy workload** (node có fortio pod, ví dụ: `ip-10-0-10-247.ap-southeast-1.compute.internal`). Dashboard `Compute Resources / Node / Pod` cần chọn node cụ thể mới hiển thị data.

#### BẮT BUỘC

| File | Chụp gì | Nội dung cần thấy | Thời điểm | Dùng ở đâu | **Ý nghĩa** |
|---|---|---|---|---|---|
| `fig-G1-grafana-cpu-node-pod.png` | Grafana: `Home > Dashboards > Kubernetes / Compute Resources / Node / Pod` → panel **CPU Usage** (time-series) | Series: `cilium-bpf` (≈ 0.00007 cores ≈ 0.07%), `cilium-envoy` (≈ 0.00011 cores ≈ 0.11%), `kube-proxy` (≈ 0.097%), `max capacity` line ≈ 2.0 cores — **chụp panel riêng: click title → "More" → "View"** | Phase 7.0 (Mode A) + Phase 9.0 (Mode B) — chụp mỗi mode 1 lần | Chương 3 — Environment stability | **Proof:** Cilium eBPF + Envoy tiêu thụ CPU ≈ 0.18% tổng cộng — overhead rất nhỏ, không làm nhiễu benchmark. Chart flat line → proof không CPU saturation. → `docs/figures/grafana/fig-G1-grafana-cpu-node-pod.png` |
| `fig-G2-grafana-cpu-quota-table.png` | Grafana: same dashboard → panel **CPU Quota** (table) | Bảng: Pod / CPU Requests / CPU Requests % / CPU Limits % — hàng `cilium-bpf` (~0.00595), `cilium-envoy` (~0.00194), `kube-proxy` (~0.0972%), `cilium-operator` — **cuộn xuống dưới bảng để thấy tất cả rows** | Phase 7.0 & 9.0 | Chương 3 — Resource usage | **Proof:** CPU request % của tất cả Cilium components << 1% → không phải bottleneck. kube-proxy chiếm 0.097% (Mode A). → `docs/figures/grafana/fig-G2-grafana-cpu-quota-table.png` |
| `fig-G3-grafana-memory-node-pod.png` | Grafana: same dashboard → panel **Memory Usage (in cache)** (time-series) | `cilium-bpf` ≈ 143 MiB, `cilium-envoy` ≈ 128 MiB, `max capacity` ≈ 7.64 GiB, flat lines — **chụp panel riêng** | Phase 7.0 & 9.0 | Chương 3 — Memory overhead | **Proof:** Cilium + Envoy memory < 300 MiB trên m5.large (7.64 GiB) → overhead không đáng kể. → `docs/figures/grafana/fig-G3-grafana-memory-node-pod.png` |
| `fig-G4-grafana-cluster-overview.png` | Grafana: `Home > Dashboards > Kubernetes / Compute Resources / Cluster` → **Cluster CPU Usage** + **Cluster Memory Usage** | CPU % < 30% cho cả 3 nodes, Memory % ổn định — **chụp mỗi panel riêng** | Phase 7.0 & 9.0 | Chương 3 — Cluster health | **Proof:** Không node nào bị saturation toàn cluster. → `docs/figures/grafana/fig-G4-grafana-cluster-overview.png` |
| `fig-G5-grafana-node-network.png` | Grafana: `Home > Dashboards > Node Exporter / Dashboard` → **Network IO** panel | Network bytes/sec, 0 saturation — **chụp panel riêng** | Phase 7.0 & 9.0 | Chương 3 — Network stability | **Proof:** Không network saturation → throughput results không bị bias. → `docs/figures/grafana/fig-G5-grafana-node-network.png` |

### ẢNH PROMETHEUS — Proof Observability Pipeline

> **Prometheus port-forward:** `kubectl port-forward -n monitoring svc/prometheus-prometheus 9090:9090 &`
> **Mở trình duyệt:** http://localhost:9090

#### BẮT BUỘC

| File | Chụp gì | Nội dung cần thấy | Thời điểm | Dùng ở đâu | **Ý nghĩa** |
|---|---|---|---|---|---|
| `fig-P1-prometheus-targets.png` | Prometheus UI → `Status > Targets` | Tất cả jobs `UP`: `kubernetes-nodes`, `kubernetes-pods`, `kubelet`, `coredns`, **`cilium-agent`** (1/1 active) — **chụp ngay sau Phase 3** | Phase 3 (sau cài monitoring) | Chương 3 — Observability setup | **Proof:** Prometheus scrape Cilium metrics thành công. Không có ảnh này → reviewer không biết Cilium metrics có vào Prometheus không. → `docs/figures/prometheus/fig-P1-prometheus-targets.png` |
| `fig-P2-prometheus-cilium-metrics.png` | Prometheus UI → Graph tab → query **`cilium_forward_count_total`** → **Table view** (không phải Graph) | Table: metric name, labels, value (ví dụ: `cilium_forward_count_total{...}` = non-zero value) — **chụp ở Table view, không phải Graph** | Phase 9.0 (Mode B) | Chương 3 (Appendix) | **Proof:** Cilium datapath metrics đổ vào Prometheus. Table view dễ đọc hơn graph — thấy số forward count cụ thể. → `docs/figures/prometheus/fig-P2-prometheus-cilium-metrics.png` |

### ẢNH HUBBLE UI — Proof S3 Enforcement (Mode B only)

> **Hubble UI port-forward:** `kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &`
> **Mở trình duyệt:** http://localhost:12000
> **Cách filter:** Nhấn nút **"Filter"** góc trái → nhập filter key (ví dụ: `namespace=benchmark`) → nhấn **Apply**. Filter bar hiện màu xanh khi đang active.
> **Nếu Hubble UI 502 Bad Gateway:** Dùng CLI fallback (fig-H4, fig-H5). Không cần chụp UI.
> **Lưu ý:** Hubble chỉ có ở Mode B. Mode A không có Hubble → không chụp phần này cho Mode A.

#### BẮT BUỘC

| File | Chụp gì | Nội dung cần thấy | Thời điểm | Dùng ở đâu | **Ý nghĩa** |
|---|---|---|---|---|---|
| `fig-H1-hubble-ui-all-flows.png` | Hubble UI → default flows list (không filter) — **port-forward: `kubectl port-forward -n kube-system svc/hubble-ui 12000:80 &`** | Table: `Verdict`, `Source`, `Destination`, `Protocol` — có FORWARDED rows, namespace=benchmark — **filter: click "Filter" → nhập `namespace=benchmark` → Apply** | Phase 9.0 (Mode B) | Chương 3 — Hubble enabled | **Proof:** Hubble UI connected + đang nhận flows thật từ benchmark workload. Không empty → Hubble hoạt động. → `docs/figures/hubble/fig-H1-hubble-ui-all-flows.png` |
| `fig-H2-hubble-ui-forwarded-flows.png` | Hubble UI → Filter **`verdict=FORWARDED`** → Apply — **dùng khi S1/S2 đã chạy** | Chỉ thấy FORWARDED rows; source = fortio pod IP → destination = echo pod IP — **filter bar màu xanh khi active** | Sau S1 hoặc S2 | Chương 5 — S3 Enforcement | **Proof:** Legit traffic (fortio→echo) được FORWARD thành công — policy không false-drop legitimate traffic. → `docs/figures/hubble/fig-H2-hubble-ui-forwarded-flows.png` |
| `fig-H3-hubble-ui-dropped-flows.png` | Hubble UI → Filter **`verdict=DROPPED`** → Apply — **chụp SAU khi attacker pod chạy ở Phase 9.4** | DROPPED rows từ attacker pod IP → echo pod — **dùng khi NetworkPolicy đang enable** | Phase 9.4 (S3 deny case, sau khi chạy attacker pod) | Chương 5 — S3 Enforcement | **Proof:** Cilium thật sự DROP traffic không hợp lệ. Đây là claim chính của S3. → `docs/figures/hubble/fig-H3-hubble-ui-dropped-flows.png` |
| `fig-H4-hubble-cli-status.png` | Terminal: `kubectl exec -n kube-system ds/cilium -c cilium-agent -- hubble status` — **fallback khi Hubble UI 502** | `Hubble: Ok`, `Relay: Connected` (Connected, không phải Disconnected) — **chụp output** | Phase 9.0 — fallback khi Hubble UI 502 | Chương 3 — Hubble status | **Proof:** Hubble Relay kết nối thành công. Fallback CLI khi UI không hoạt động. → `docs/figures/hubble/fig-H4-hubble-cli-status.png` |
| `fig-H5-hubble-cli-observe.png` | Terminal: `kubectl exec -n kube-system ds/cilium -c cilium-agent -- hubble observe --namespace benchmark --last 50 -o table` — **fallback** | Table: `Verdict`, `Source`, `Destination`, `Protocol` — thấy FORWARDED rows — **chụp output** | Phase 9.0/9.4 — fallback | Chương 5 (Appendix) | **Proof:** Raw CLI evidence backup cho H1/H2/H3. Đặc biệt dùng khi Hubble UI không hoạt động. → `docs/figures/hubble/fig-H5-hubble-cli-observe.png` |

#### TÙY CHỌN — Không cần cho thesis, chỉ cho slide/GitHub

| File | Chụp gì | Dùng ở đâu |
|---|---|---|
| `fig-A11-aws-cost-explorer.png` | AWS Console → Cost Explorer → Chi phí EKS + EC2 | Slide cuối (cost analysis), thesis bỏ qua → `docs/figures/infra/fig-A11-aws-cost-explorer.png` |
| `fig-A12-helm-list.png` | Terminal `helm list -n kube-system` | Appendix — proof Cilium + Prometheus được cài đúng namespace → `docs/figures/infra/fig-A12-helm-list.png` |
| `fig-A13-kubectl-config-context.png` | Terminal `kubectl config current-context` | Phase 7.0/9.0 proof — kubectl trỏ đúng cluster → `docs/figures/infra/fig-A13-kubectl-config-context.png` |

#### CHECKLIST ẢNH HOÀN TẤT

```
Thesis figures (fig-01 → fig-18, fig-12b = 19 total):          [ ] /19
Infrastructure figures (fig-A1 → fig-A10 = 10 total):           [ ] /10
Optional infra (fig-A11 → fig-A13 = 3 total):                   [ ] /3
Grafana figures (fig-G1 → fig-G5 = 5 total):                    [ ] /5
Prometheus figures (fig-P1 → fig-P2 = 2 total):                 [ ] /2
Hubble figures (fig-H1 → fig-H5 = 5 total):                     [ ] /5
──────────────────────────────────────────────────────────────────────
Tổng thesis figures: 44  ảnh (19 + 10 + 3 + 5 + 2 + 5)

Slide figures (slide-*.png = 8):                                 [ ] /8
Evidence text files (evidence/):                               [ ] all
Raw CSV (docs/appendix/):                                       [ ] aggregated_summary.csv, comparison_AB.csv
```

**Tổng cộng cần chụp: 52 ảnh (44 thesis + 8 slides, chưa kể optional)** — tất cả có ý nghĩa rõ ràng cho thesis.

> **Cấu trúc lưu ảnh:**
> ```
> docs/figures/
> ├── thesis/      # fig-01 → fig-18, fig-12b              (19 ảnh)
> ├── infra/      # fig-A1 → fig-A10 + fig-A11→A13 opt.  (10+3 ảnh)
> ├── grafana/    # fig-G1 → fig-G5                        (5 ảnh)
> ├── prometheus/ # fig-P1 → fig-P2                       (2 ảnh)
> └── hubble/     # fig-H1 → fig-H5                       (5 ảnh)
> docs/figures/slides/  # slide-*.png                       (8 ảnh)
> ```
>
> ⚠️ **Cập nhật đường dẫn trong thesis** sau khi sắp xếp xong.
