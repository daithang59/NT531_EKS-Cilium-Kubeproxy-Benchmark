# CLAUDE.md

Tệp này cung cấp hướng dẫn cho Claude Code (claude.ai/code) khi làm việc với codebase này.

## Tổng quan dự án

Đây là benchmark **đo hiệu năng datapath mạng Kubernetes trên AWS EKS**, so sánh hai mode datapath của Cilium:
- **Mode A (Baseline):** Cilium CNI + kube-proxy (iptables DNAT/SNAT)
- **Mode B (eBPF KPR):** Cilium CNI với `kubeProxyReplacement: true`, thay thế hoàn toàn kube-proxy bằng eBPF socket-level redirect

Workload chính: Fortio (load generator) → HTTP echo server qua ClusterIP Service.
Scenarios: S1 (steady-state), S2 (stress + churn), S3 (policy overhead — **chỉ Mode B**).
Load levels: L1, L2, L3 (được xác định qua calibration).

---

## Các lệnh thường dùng

### Terraform (Hạ tầng)

```bash
cd terraform
terraform init
terraform plan -var-file=envs/dev/terraform.tfvars
terraform apply -var-file=envs/dev/terraform.tfvars
make fmt
```

### Cài đặt Cilium

```bash
# Mode A — kube-proxy baseline
helm upgrade --install cilium cilium/cilium -n kube-system --version 1.18.7 \
  -f helm/cilium/values-baseline.yaml

# Mode B — eBPF KPR
# ⚠️ PHẢI tắt kube-proxy trước, rồi upgrade Cilium in-place.
helm upgrade cilium cilium/cilium -n kube-system --version 1.18.7 \
  -f helm/cilium/values-ebpfkpr.yaml
```

### Triển khai Workload

```bash
kubectl apply -f workload/server/
kubectl apply -f workload/client/
kubectl -n benchmark get pods
```

### Calibration (chạy TRƯỚC benchmark chính thức)

```bash
MODE=A REPEAT=2 ./scripts/calibrate.sh
# Xem kết quả → cập nhật L1_QPS/L2_QPS/L3_QPS trong common.sh
```

### Chạy Benchmark

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

### Phân tích thống kê

```bash
python3 scripts/analyze_results.py
# Xuất: aggregated_summary.csv, comparison_AB.csv (Δ%, p-value, ✓ sig)
```

### Thu thập evidence độc lập

```bash
./scripts/collect_meta.sh results/mode=A_kube-proxy/
./scripts/collect_meta.sh results/mode=B_cilium-ebpfkpr/
./scripts/collect_hubble.sh results/mode=B_cilium-ebpfkpr/
```

---

## Kiến trúc

### Hạ tầng (Terraform)
- `terraform/main.tf` — Entry point, gọi `modules/vpc` + `modules/eks`
- `terraform/modules/vpc/` — Module VPC (10.0.0.0/16, 2 AZs, public/private subnets, NAT Gateway)
- `terraform/modules/eks/` — Module EKS (managed node group, m5.large × 3, workers ghim vào 1 AZ, non-burstable)
- Cilium KHÔNG cài qua Terraform — luôn cài qua Helm sau khi cluster đã lên

### Helm Values (Các mode datapath)
- `helm/cilium/values-baseline.yaml` — Mode A: `kubeProxyReplacement: false`
- `helm/cilium/values-ebpfkpr.yaml` — Mode B: `kubeProxyReplacement: true`, cần điền `k8sServiceHost` = EKS API endpoint hostname (không có https://)
- `helm/monitoring/values.yaml` — kube-prometheus-stack (Prometheus + Grafana + node-exporter)

### Scripts
- `scripts/common.sh` — Thư viện dùng chung, được source bởi tất cả `run_*.sh`; xử lý pre-checks, Fortio execution, thu thập evidence, tạo metadata. **Không chạy độc lập.**
- `scripts/run_s1.sh` — S1: đo tải steady-state
- `scripts/run_s2.sh` — S2: test stress 4 phase (ramp-up → sustained → burst ×3 → cool-down)
- `scripts/run_s3.sh` — S3: toggle NetworkPolicy OFF → ON, đo overhead enforcement (chỉ Mode B)
- `scripts/collect_meta.sh` / `scripts/collect_hubble.sh` — Thu thập evidence độc lập
- `scripts/calibrate.sh` — Calibration sweep: tăng dần QPS để xác định L1/L2/L3 bằng dữ liệu
- `scripts/analyze_results.py` — Phân tích thống kê: CI (t-distribution), Welch's t-test A vs B

### Workload
- `workload/server/` — hashicorp/http-echo:1.0 trên ClusterIP port 80→5678 trong namespace `benchmark`
- `workload/client/` — fortio/fortio:1.74.0 (load generator, exec vào pod để chạy test)
- `workload/policies/` — CiliumNetworkPolicy cho S3

---

## Các quy ước quan trọng

### Results Contract
Mỗi benchmark run tạo artifacts tại:
```
results/mode=<A|B>/scenario=<S1|S2|S3>/load=<L1|L2|L3>/[phase=<off|on>/]run=<R1_timestamp>/
```
File bắt buộc mỗi run: `bench.log`, `metadata.json`, `checklist.txt`, `kubectl_get_all.txt`, `kubectl_top_nodes.txt`, `events.txt`. Mode B/S3 thêm: `cilium_status.txt`, `hubble_status.txt`, `hubble_flows.jsonl`.

S2 tạo log theo từng phase (`bench_phase1_rampup.log`, v.v.) gộp vào `bench.log`.
S3 chia output thành 2 thư mục con: `phase=off/` và `phase=on/`.

### Biến môi trường cho Benchmark Scripts
| Biến | Mặc định | Mô tả |
|------|---------|--------|
| `MODE` | `A` | `A` = kube-proxy, `B` = Cilium eBPF KPR |
| `LOAD` | `L1` | `L1` (100 QPS/8 conns), `L2` (500 QPS/32 conns), `L3` (1000 QPS/64 conns) |
| `REPEAT` | `3` | Số lần lặp mỗi tổ hợp |
| `DURATION_SEC` | `180` | Thời gian đo chính thức (tối thiểu 3 phút) |
| `WARMUP_SEC` | `30` | Thời gian warm-up trước khi đo |
| `REST_BETWEEN_RUNS` | `60` | Thời gian nghỉ giữa các runs |

### Git / Branching
- Đặt tên nhánh: `feature/`, `fix/`, `docs/`, `infra/`, `script/`, `config/`
- Format commit: [Conventional Commits](https://www.conventionalcommits.org/) bằng tiếng Anh (`feat:`, `fix:`, `infra:`, `docs:`, v.v.)
- **Không bao giờ commit trực tiếp lên `main`** — luôn qua PR với ít nhất 1 review approval
- `terraform.tfstate` và `results/` được gitignore

### Tiêu chuẩn code
- Terraform: chạy `make fmt` trước khi commit
- Shell scripts: `set -euo pipefail` ở đầu file; scripts dùng `common.sh` làm thư viện dùng chung
- YAML: indent 2 spaces, không dùng tabs

---

## Các quyết định thiết kế cần biết

- **Workers ghim vào 1 AZ** — loại bỏ biến động latency cross-AZ. Cấu hình qua `benchmark_subnet_ids` trong EKS module, chỉ dùng subnets của AZ đầu tiên.
- **m5.large (non-burstable)** — CPU ổn định 100% xuyên suốt, không có credit exhaustion, loại bỏ 1 biến nhiễu khỏi benchmark.
- **S3 chỉ chạy ở Mode B** — S3 đo policy enforcement overhead, Hubble chỉ có ở Mode B. Mode A không cần S3.
- **S2 không chạy L1** — L1 × S2 burst QPS 150 vẫn quá thấp, không stress được conntrack.
- **Chuyển Mode A → B cần gỡ kube-proxy trước** — kube-proxy phải được xóa trước khi bật `kubeProxyReplacement: true`. Xem `docs/runbook.md` §3.
- **Hubble chỉ có ở Mode B** — Hubble flows cung cấp bằng chứng verdict FORWARDED/DROPPED cho phân tích policy enforcement ở S3.
- **Load levels phải calibrate** — chạy `calibrate.sh` trước benchmark chính thức; cập nhật `L1_QPS/L2_QPS/L3_QPS` trong `common.sh` với giá trị thực tế.
- **Có Hubble overhead chưa kiểm soát ở Mode B** — Mode B bật Hubble (observability) trong khi Mode A không có tương đương. Điều này có thể làm Mode B chậm hơn một chút ở S1/S2. Ghi nhận trong Threats to Validity.
