# thesis-cilium-eks-benchmark

Benchmark so sánh datapath Kubernetes:
- Mode A: kube-proxy (baseline)
- Mode B: Cilium eBPF kube-proxy replacement (kube-proxy-free) + Hubble
Workload: Fortio (client) → echo (server)

## Project Structure

```
thesis-cilium-eks-benchmark/
├── README.md                          # File này — tổng quan dự án
├── .gitignore                         # Ignore rules (results, tfstate, logs…)
├── Makefile                           # Lệnh tiện ích: fmt, lint
│
├── docs/                              # Tài liệu thiết kế thí nghiệm
│   ├── README.md                      #   Giải thích thư mục docs
│   ├── experiment_spec.md             #   Đặc tả thí nghiệm (metrics, scenarios, protocol)
│   └── runbook.md                     #   Checklist vận hành trước/trong/sau benchmark
│
├── terraform/                         # IaC — provision hạ tầng AWS (VPC + EKS)
│   ├── README.md                      #   Giải thích cách dùng Terraform
│   ├── main.tf                        #   Entry point (placeholder cho modules)
│   ├── variables.tf                   #   Input variables (project_name, region)
│   ├── outputs.tf                     #   Output values (placeholder)
│   ├── envs/
│   │   └── dev/
│   │       └── terraform.tfvars       #   Biến cho môi trường dev
│   └── modules/
│       ├── vpc/
│       │   └── README.md              #   Placeholder — implement VPC module
│       └── eks/
│           └── README.md              #   Placeholder — implement EKS module
│
├── helm/                              # Helm values cho CNI + monitoring
│   ├── README.md                      #   Tổng quan helm values
│   ├── cilium/
│   │   ├── README.md                  #   Giải thích 2 bộ values
│   │   ├── values-baseline.yaml       #   Mode A: kube-proxy ON (kubeProxyReplacement=disabled)
│   │   └── values-ebpfkpr.yaml        #   Mode B: eBPF KPR (kubeProxyReplacement=strict)
│   └── monitoring/
│       ├── README.md                  #   Giải thích monitoring stack
│       ├── values.yaml                #   Placeholder cho kube-prometheus-stack
│       └── dashboards/
│           └── .gitkeep               #   Nơi lưu Grafana dashboard JSON exports
│
├── workload/                          # Kubernetes manifests cho workload benchmark
│   ├── README.md                      #   Giải thích workload
│   ├── server/
│   │   ├── 01-namespace.yaml          #   Namespace "netperf"
│   │   ├── 02-echo-deploy.yaml        #   Deployment echo server (hashicorp/http-echo)
│   │   └── 03-echo-svc.yaml           #   Service ClusterIP cho echo (port 80 → 5678)
│   ├── client/
│   │   └── 01-fortio-deploy.yaml      #   Deployment Fortio client (fortio/fortio)
│   └── policies/
│       └── 01-cilium-policy-allow-fortio-to-echo.yaml  # CiliumNetworkPolicy
│
├── scripts/                           # Shell scripts tự động hóa benchmark
│   ├── README.md                      #   Giải thích scripts + biến môi trường
│   ├── common.sh                      #   Thư viện dùng chung (config, helpers)
│   ├── run_s1.sh                      #   Scenario 1: Baseline steady load
│   ├── run_s2.sh                      #   Scenario 2: High load + churn (skeleton)
│   ├── run_s3.sh                      #   Scenario 3: Policy OFF → ON toggle
│   ├── collect_hubble.sh              #   Thu thập Hubble flow logs
│   └── collect_meta.sh                #   Thu thập metadata cluster (cilium status…)
│
├── results/                           # Output artifacts từ benchmark runs
│   ├── README.md                      #   Giải thích cấu trúc results
│   └── .gitkeep                       #   (thư mục trong .gitignore, chỉ giữ .gitkeep)
│
└── report/                            # Tài liệu báo cáo / luận văn
    ├── README.md                      #   Giải thích thư mục report
    ├── figures/
    │   └── dashboards/
    │       └── .gitkeep               #   Screenshots Grafana dashboards
    ├── tables/
    │   └── .gitkeep                   #   Bảng tổng hợp kết quả (CSV, LaTeX)
    └── appendix/
        └── .gitkeep                   #   Phụ lục: config, raw logs trích dẫn
```

## Prerequisites
- AWS CLI + credentials
- kubectl, helm
- terraform
- (optional) jq, hubble CLI

## Quick start (high level)

### 1) Provision EKS

```bash
cd terraform
terraform init
terraform apply -var-file=envs/dev/terraform.tfvars
```

### 2) Configure kubeconfig

```bash
aws eks update-kubeconfig --name <YOUR_EKS_NAME> --region <YOUR_REGION>
kubectl get nodes
```

### 3) Install Cilium (choose mode)

> **Pin version**: luôn dùng `--version 1.18.7` để đảm bảo reproducible.

Baseline (kube-proxy ON):

```bash
helm repo add cilium https://helm.cilium.io
helm repo update
helm upgrade --install cilium cilium/cilium \
  -n kube-system \
  --version 1.18.7 \
  -f helm/cilium/values-baseline.yaml
```

eBPF KPR (kube-proxy replacement):

```bash
# Trước khi cài, điền k8sServiceHost trong values-ebpfkpr.yaml
helm upgrade --install cilium cilium/cilium \
  -n kube-system \
  --version 1.18.7 \
  -f helm/cilium/values-ebpfkpr.yaml
```

### 4) Deploy workload

```bash
kubectl apply -f workload/server/
kubectl apply -f workload/client/
kubectl apply -f workload/policies/
```

### 5) Run benchmarks

```bash
export MODE="kubeproxy"  # or ebpfkpr
export SCENARIO="s1"     # s1/s2/s3
./scripts/run_s1.sh
```

## Results layout

Artifacts được ghi vào:

```
results/mode=<kubeproxy|ebpfkpr>/scenario=<s1|s2|s3>/load=<L1|L2|L3>/run=01/
  metadata.json        # thông số chạy
  bench.log            # Fortio output
  cluster_state.txt    # kubectl snapshot
  hubble.log           # Hubble flows (nếu có)
  grafana/             # screenshots (thủ công)
```

## Notes

* Không autoscale trong lúc đo để tránh nhiễu.
* Mỗi case chạy REPEATS lần; nhớ warm-up.
* Trên Linux/WSL, nhớ `chmod +x scripts/*.sh`.
