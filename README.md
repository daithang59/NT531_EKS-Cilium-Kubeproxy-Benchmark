# NT531 — Benchmark Datapath mạng Kubernetes trên AWS EKS

## Tổng quan

Đây là **đồ án môn học NT531** đo và so sánh hiệu năng datapath mạng Kubernetes trên AWS EKS. Hai mode datapath được so sánh trên cùng hạ tầng:

| Mode | Tên | Mô tả |
|------|-----|-------|
| **A** | kube-proxy baseline | Cilium CNI hoạt động cùng kube-proxy (iptables). Đây là baseline. |
| **B** | Cilium eBPF KPR | Cilium thay thế hoàn toàn kube-proxy bằng eBPF (`kubeProxyReplacement: true`). |

**Workload:** Fortio (load generator) → HTTP echo server qua ClusterIP Service.

**3 kịch bản đo:**
- **S1 — Service Baseline:** Tải steady-state, không policy.
- **S2 — High-load + Connection Churn:** Multi-phase stress (ramp-up → sustained → burst × 3 → cool-down), keepalive off.
- **S3 — NetworkPolicy Overhead:** Policy OFF → policy ON, đo overhead enforcement.

**3 mức tải:** L1 (light) / L2 (medium) / L3 (high) — xác định qua calibration trước khi chạy chính thức.

> Chi tiết thiết kế thí nghiệm: `docs/experiment_spec.md`
> Hướng dẫn chạy: `docs/runbook.md`

---

## Kiến trúc hệ thống

### Topology tổng quan

```
┌─────────────────────────────────────────────────────────────────────┐
│                        AWS EKS Cluster (1 AZ)                       │
│                     Kubernetes 1.34 · 3× m5.large                     │
│                                                                      │
│  ┌──────────────┐                           ┌──────────────┐         │
│  │  Fortio Pod   │──── ClusterIP Service ───▶│  Echo Pod    │         │
│  │  (client)     │     echo.benchmark:80      │  (server)    │         │
│  │  ns: benchmark│                           │  ns: benchmark│         │
│  └──────────────┘                           └──────────────┘         │
│         │                                          │                 │
│         ▼                                          ▼                 │
│  ╔══════════════════════════════════════════════════════════════╗   │
│  ║  Mode A (Baseline)        │  Mode B (eBPF KPR)              ║     │
│  ║  ─────────────────        │  ──────────────────             ║     │
│  ║  Cilium CNI               │  Cilium CNI                     ║     │
│  ║  + kube-proxy (iptables)  │  + kubeProxyReplacement: true   ║     │
│  ║  → iptables DNAT/SNAT     │  → eBPF socket-level redirect   ║     │
│  ╚══════════════════════════════════════════════════════════════╝   │
│                                                                      │
│  ┌───────────────────────────────────────────────────────────┐       │
│  │  Observability: Prometheus + Grafana + Hubble (Mode B)    │       │
│  └───────────────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────────────┘
```

**Hạ tầng AWS:**
- **VPC** `10.0.0.0/16` với 2 Availability Zones (AZs), mỗi AZ có 1 public subnet + 1 private subnet.
- **EKS Cluster** (Kubernetes 1.34) với Managed Node Group gồm **3 worker nodes** `m5.large` (2 vCPU, 8GB RAM, non-burstable).
- Worker nodes được **pin vào 1 AZ duy nhất** để giảm nhiễu latency cross-AZ trong quá trình đo.
- Node group cố định `min = desired = max = 3`, **không autoscale** trong lúc benchmark.

**Workload benchmark (namespace `benchmark`):**
- **Echo server** (`hashicorp/http-echo:1.0`) — HTTP echo backend, expose qua **ClusterIP Service** (`echo.benchmark:80 → 5678`).
- **Fortio client** (`fortio/fortio:1.74.0`) — load generator chạy trong cluster, gửi request đến echo qua Service.
- Cả 2 pods đều có `nodeSelector: role: benchmark` và resource requests/limits để đảm bảo tính công bằng.

**CNI & Datapath:**
- **Mode A — kube-proxy baseline:** Cilium làm CNI, kube-proxy xử lý Service routing bằng iptables (DNAT/SNAT).
- **Mode B — Cilium eBPF KPR:** Cilium thay thế hoàn toàn kube-proxy (`kubeProxyReplacement: true`), Service routing được xử lý trực tiếp ở tầng eBPF (socket-level redirect), bypass iptables.

**Monitoring & Observability:**
- **Prometheus + Grafana** (kube-prometheus-stack) — thu thập metrics CPU, memory, network từ nodes và pods.
- **Hubble** (Mode B) — observability layer của Cilium, cung cấp flow-level visibility (FORWARDED/DROPPED verdicts).

**NetworkPolicy (Scenario S3):**
- `CiliumNetworkPolicy` cho phép Fortio → Echo và default-deny ingress cho echo pod.
- Dùng để đo overhead khi bật policy enforcement so với không có policy.

---

## Cấu trúc dự án

```
thesis-cilium-eks-benchmark/
├── README.md                          # File này — tổng quan đồ án
├── .gitignore                         # Ignore rules (results, tfstate, logs…)
├── Makefile                           # Lệnh tiện ích: fmt, lint
│
├── docs/                              # Tài liệu thiết kế & vận hành
│   ├── experiment_spec.md             #   Đặc tả thí nghiệm (metrics, scenarios, protocol)
│   ├── runbook.md                     #   Hướng dẫn chạy benchmark từng bước
│   └── images/                        #   Hình ảnh kiến trúc, topology, diagrams
│
├── terraform/                         # IaC — provision hạ tầng AWS
│   ├── main.tf                        #   Entry point — gọi modules VPC + EKS
│   ├── variables.tf                   #   Input variables
│   ├── outputs.tf                     #   Output values (cluster endpoint, kubeconfig command)
│   ├── envs/dev/terraform.tfvars      #   Biến cho môi trường dev
│   └── modules/
│       ├── vpc/                       #   VPC module (10.0.0.0/16, 2 AZs; workers pinned to 1st AZ)
│       │   ├── main.tf, variables.tf, outputs.tf
│       └── eks/                       #   EKS module (m5.large × 3, managed node group)
│           ├── main.tf, variables.tf, outputs.tf
│
├── helm/                              # Helm values cho CNI + monitoring
│   ├── cilium/
│   │   ├── values-baseline.yaml       #   Mode A: kubeProxyReplacement=false
│   │   └── values-ebpfkpr.yaml        #   Mode B: kubeProxyReplacement=true
│   └── monitoring/
│       ├── values.yaml                #   kube-prometheus-stack (placeholder)
│       └── dashboards/                #   Grafana dashboard JSON exports
│
├── workload/                          # Kubernetes manifests cho benchmark
│   ├── server/
│   │   ├── 01-namespace.yaml          #   Namespace "benchmark"
│   │   ├── 02-echo-deploy.yaml        #   hashicorp/http-echo:1.0 (resource limits + nodeSelector)
│   │   └── 03-echo-svc.yaml           #   ClusterIP port 80 → 5678
│   ├── client/
│   │   └── 01-fortio-deploy.yaml      #   fortio/fortio:1.74.0 (resource limits + nodeSelector)
│   └── policies/
│       ├── 01-cilium-policy-allow-fortio-to-echo.yaml
│       └── 02-cilium-policy-deny-other.yaml  # Default-deny ingress (S3)
│
├── scripts/                           # Shell scripts tự động hóa benchmark
│   ├── common.sh                      #   Thư viện dùng chung (validation, Fortio, evidence)
│   ├── run_s1.sh                      #   S1: Service Baseline (steady-state)
│   ├── run_s2.sh                      #   S2: High-load + Connection Churn (4 phases)
│   ├── run_s3.sh                      #   S3: NetworkPolicy OFF → ON
│   ├── collect_meta.sh                #   Standalone kubectl evidence collector
│   ├── collect_hubble.sh              #   Standalone Cilium/Hubble evidence collector
│   ├── calibrate.sh                   #   Tự động xác định L1/L2/L3 bằng dữ liệu
│   └── cluster_power.sh               #   Tạm dừng / bật lại cụm EKS (tiết kiệm chi phí)
│
├── results/                           # Output artifacts (theo Results Contract)
│   ├── README.md                      #   Quy ước cấu trúc output bắt buộc
│   └── metadata.template.json.txt     #   Template cho metadata.json mỗi run
│
├── report/                            # Tài liệu báo cáo
│   ├── result_summary.md              #   Template bảng tổng hợp kết quả
│   ├── figures/dashboards/            #   Screenshots Grafana
│   ├── tables/                        #   Bảng CSV/LaTeX
│   └── appendix/                      #   Phụ lục: config, logs, calibration report
│
└── python3 scripts/analyze_results.py # Phân tích thống kê (Welch's t-test, CI 95%)
```

---

## Prerequisites

- **AWS CLI** + credentials (`aws configure`)
- **kubectl** (>= 1.28)
- **helm** (>= 3.x)
- **terraform** (>= 1.5)
- **bash** (>= 4.0, trên WSL/Linux)
- **python3** (>= 3.8)
- (optional) `jq`, `hubble` CLI

---

## Quick Start

### 1) Calibration (BẮT BUỘC trước benchmark)

> Chạy calibration để xác định L1/L2/L3 phù hợp với hạ tầng thực tế, thay vì dùng giá trị mặc định.

```bash
kubectl apply -f workload/server/
kubectl apply -f workload/client/
MODE=A REPEAT=2 ./scripts/calibrate.sh
# Xem kết quả → cập nhật L1_QPS/L2_QPS/L3_QPS trong scripts/common.sh
```

### 2) Provision EKS

```bash
cd terraform
terraform init
terraform plan -var-file=envs/dev/terraform.tfvars
terraform apply -var-file=envs/dev/terraform.tfvars
```

### 3) Configure kubeconfig

```bash
# Lấy command từ terraform output
$(terraform output -raw kubeconfig_command)
kubectl get nodes   # 3 nodes Ready
```

### 4) Install Cilium (chọn Mode)

```bash
helm repo add cilium https://helm.cilium.io && helm repo update
```

**Mode A** (kube-proxy baseline):
```bash
helm upgrade --install cilium cilium/cilium \
  -n kube-system --version 1.18.7 \
  -f helm/cilium/values-baseline.yaml
```

**Mode B** (eBPF KPR — kube-proxy-free):
```bash
# ⚠️ PHẢI tắt kube-proxy trước (xem docs/runbook.md §3)
# Điền k8sServiceHost trong values-ebpfkpr.yaml trước
helm upgrade --install cilium cilium/cilium \
  -n kube-system --version 1.18.7 \
  -f helm/cilium/values-ebpfkpr.yaml
```

### 5) Deploy workload

```bash
kubectl apply -f workload/server/
kubectl apply -f workload/client/
# Verify
kubectl -n benchmark get pods   # echo + fortio Running
```

### 6) Run benchmarks

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

> Chi tiết: `docs/runbook.md`

---

## Mức tải (Load Levels)

| Level | QPS mặc định | Connections | Threads | Mục đích |
|-------|-------------|-------------|---------|----------|
| L1 | 100 | 8 | 2 | Light — gần như 0 error, p99 thấp |
| L2 | 500 | 32 | 4 | Medium — tail latency rõ nhưng chưa bão hòa |
| L3 | 1000 | 64 | 8 | High — gần ngưỡng bão hòa, error còn trong mức chấp nhận |

> **Phải chạy `calibrate.sh`** để xác nhận giá trị trên hạ tầng thực tế. Cập nhật `scripts/common.sh` sau calibration.

---

## Kết quả & Evidence

Mỗi run tự động tạo artifacts theo quy ước:

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

**S2** tạo thêm log theo từng phase (`bench_phase1_rampup.log`, v.v.).
**S3** chia output thành 2 thư mục: `phase=off/` và `phase=on/`.

> Xem chi tiết: `results/README.md`

---

## Phân tích thống kê

```bash
python3 scripts/analyze_results.py
# Output:
#   - aggregated_summary.csv   (median, mean ± 95% CI, stdev)
#   - comparison_AB.csv        (Δ%, p-value, ✓ sig theo Welch's t-test)
```

> Chi tiết methodology: `docs/experiment_spec.md` §10

---

## Biến môi trường

| Variable | Default | Mô tả |
|----------|---------|-------|
| `MODE` | `A` | `A` = kube-proxy, `B` = Cilium eBPF KPR |
| `LOAD` | `L1` | `L1` (light), `L2` (medium), `L3` (high) |
| `REPEAT` | `3` | Số lần lặp mỗi (scenario × load) |
| `DURATION_SEC` | `180` | Thời gian đo chính thức (giây) — tối thiểu 3 phút |
| `WARMUP_SEC` | `30` | Thời gian warm-up (giây) |
| `REST_BETWEEN_RUNS` | `60` | Nghỉ giữa các runs (giây) |

Xem đầy đủ: `scripts/README.md`

---

## Lưu ý quan trọng

- **Không autoscale** nodegroup trong lúc đo — `min=desired=max=3` (tránh nhiễu).
- **Workers pinned 1 AZ** — tất cả benchmark nodes nằm trên cùng 1 AZ để giảm nhiễu cross-AZ.
- **Resource limits** đã set cho cả Fortio và echo pods (tránh CPU throttling).
- **nodeSelector `role: benchmark`** trên cả 2 workload pods.
- Mỗi tổ hợp chạy **≥ 3 runs**, nghỉ **60s** giữa các runs.
- Measurement duration: **180s** (3 phút).
- Scripts fail-fast nếu kubectl context sai hoặc pods chưa Ready.
- Trên Linux/WSL: `chmod +x scripts/*.sh` trước khi chạy.
- **Tiết kiệm chi phí:** sau mỗi session, chạy `./scripts/cluster_power.sh pause` để giảm chi phí EKS.

---

## Các quyết định thiết kế

- **m5.large (non-burstable)** — CPU ổn định 100%, không có credit exhaustion, loại bỏ 1 biến nhiễu.
- **S3 chỉ chạy ở Mode B** — S3 đo policy enforcement overhead, Hubble chỉ có ở Mode B.
- **Chuyển Mode A → B cần gỡ kube-proxy trước** — xem `docs/runbook.md` §3.
- **Load levels phải calibrate** — chạy `calibrate.sh` trước benchmark chính thức.
- **Mode B bật Hubble** — Hubble là observability layer, có thể tạo overhead nhỏ cho Mode B. Ghi nhận trong Threats to Validity.