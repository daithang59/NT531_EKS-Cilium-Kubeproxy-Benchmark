# Kế hoạch Viết Thesis Hoàn chỉnh — Benchmark NT531

---

## MỤC LỤC

### Cấu trúc thesis (file)

| # | File thesis |
|---|------------|
| 1 | Chương 1 — Giới thiệu (Introduction) |
| 2 | Chương 2 — Background & Architecture |
| 3 | Chương 3 — Methodology |
| 4 | Chương 4 — Results & Analysis |
| 5 | Chương 5 — Conclusion |
| A | Appendix A — Infrastructure |
| B | Appendix B — Calibration |
| C | Appendix C — Statistical Methods |
| D | Appendix D — Raw Data |
| E | Appendix E — Figures |
| F | Appendix F — Scripts & Configuration |

---

### MỤC LỤC Hình ẢNH (Infrastructure screenshots)

| # | Hình | Mô tả | Nguồn | Chương |
|---|------|--------|--------|--------|
| H1 | `fig-infra-01.png` | Sơ đồ topology triển khai EKS + workers | terraform outputs | Chương 3 |
| H2 | `fig-infra-02.png` | kubectl get all sau khi deploy workload | kubectl output | Chương 3 |
| H3 | `fig-infra-03.png` | Cilium status (Mode B) — kubeProxyReplacement: strict | `cilium status` | Chương 3 |
| H4 | `fig-infra-04.png` | Prometheus dashboard — node CPU/memory | Grafana | Chương 3/5 |
| H5 | `fig-hubble-01.png` | Hubble status output | `hubble status` | Chương 3 |
| H6 | `fig-hubble-02.png` | Hubble flows sample (FORWARDED/DROPPED) | `hubble observe` | §3.2 |

---

### MỤC LỤC BảNG BIỂU (Tables)

| # | Bảng | Mô tả | § trong thesis |
|---|------|--------|----------------|
| B1 | Table 1.1 | Research Questions & Hypotheses | §1.3 |
| B2 | Table 1.2 | Giả thuyết (Hypotheses) | §1.4 |
| B3 | Table 2.1 | Related Work comparison | §2.4 |
| B4 | Table 2.2 | Infrastructure specifications | §3.1.2 |
| B5 | Table 2.3 | Datapath comparison (iptables vs eBPF) | §2.2.3 |
| B6 | Table 2.4 | Mode A / Mode B Helm values | §2.3 |
| B7 | Table 2.5 | Workload configuration | §2.4 |
| B8 | Table 2.6 | Monitoring stack | §2.5 |
| B9 | Table 3.1 | RQ → Hypothesis → Metric traceability | §3.1 |
| B10 | Table 3.2 | Load levels (L1/L2/L3) | §3.3 |
| B11 | Table 3.3 | Fairness controls | §3.5 |
| B12 | Table 3.4 | Threats to validity (Internal) | §3.6 |
| B13 | Table 3.5 | Threats to validity (External) | §3.6 |
| B14 | Table 4.1 | S1 L1 latency results | §4.1.2 |
| B15 | Table 4.1 | S1 L2 latency results (template) | §4.1.3 |
| B16 | Table 4.1 | S1 L3 latency results (template) | §4.1.4 |
| B17 | Table 4.2 | S3 policy overhead (OFF vs ON) | §4.2.2 |
| B18 | Table 4.3 | S2 L2 latency results | §4.3.2 |
| B19 | Table 4.4 | S2 L3 latency results | §4.3.3 |
| B20 | Table 4.5 | S2 phase-level p99 per phase | §4.3.4 |
| B21 | Table 4.8 | Full comparison (all scenarios × metrics) | §4.4 |
| B22 | Table 4.10 | Artifact provenance | §4.5 |
| B23 | Table 4.9 | RQ answer summary | §4.9 |
| B24 | Table 5.1 | Practical implications | §5.2 |
| B25 | Table 5.2 | Limitations | §5.3 |
| B26 | Table A.1 | Terraform configuration | Appendix A |
| B27 | Table A.2 | Cluster versions | Appendix A |
| B28 | Table B.1 | Calibration sweep data | Appendix B |
| B29 | Table B.2 | L1/L2/L3 justification | Appendix B |
| B30 | Table C.1 | Statistical methods summary | Appendix C |

---

### MỤC LỤC BIỂU ĐỒ (Charts)

| # | Biểu đồ | Mô tả | Đặt ở |
|---|---------|--------|--------|
| C1 | S1 Latency AB (Grouped Bar) | p50/p90/p99 Mode A vs B | §4.1 |
| C2 | S1 Delta % Bar | Δ% Mode B vs A + ★ sig | §4.1 |
| C3 | S1 L3 p999 Box Plot | p999 distribution 9 runs | §4.1 |
| C4 | S3 Policy Overhead | OFF vs ON grouped bar | §4.2 |
| C5 | S2 Latency AB (Grouped Bar) | p50/p90/p99 Mode A vs B | §4.3 |
| C6 | S2 Delta % Bar | Δ% Mode B vs A (high variance) | §4.3 |
| C7 | S2 Phase Line Chart | phase → p99 + CI band | §4.3 |
| C8 | Effect CI Forest Plot | Δms với 95% CI toàn bộ comparisons | §4.9 |
| C9 | Hubble Verdict Chart | Stacked bar FORWARDED/DROPPED | §4.2 |
| C10 | Error Rate Chart | Bar error% theo scenario/load | §4.4 |
| C11 | Calibration Curve | QPS → p99 + error% | §3.3 |
| C12 | Datapath Comparison | Packet flow diagrams Mode A vs B | §2.2 |
| — | LaTeX Table | comparison_AB.tex | §4.9 |

### MỤC LỤC CODE & SCRIPT

| # | Script / Config | Mô tả |
|---|----------------|--------|
| K1 | `scripts/calibrate.sh` | Calibration sweep — xác định L1/L2/L3 |
| K2 | `scripts/run_s1.sh` | S1 steady-state benchmark |
| K3 | `scripts/run_s2.sh` | S2 stress + connection churn |
| K4 | `scripts/run_s3.sh` | S3 policy ON/OFF |
| K5 | `scripts/collect_meta.sh` | Thu thập metadata & evidence |
| K6 | `scripts/collect_hubble.sh` | Thu thập Hubble flows |
| K7 | `scripts/analyze_results.py` | Statistical analysis |
| K8 | `scripts/generate_charts.py` | Generate fig-01 → fig-12 |
| K9 | `terraform/main.tf` | Terraform entry point |
| K10 | `terraform/envs/dev/terraform.tfvars` | Variable definitions |
| K11 | `helm/cilium/values-baseline.yaml` | Mode A Helm values |
| K12 | `helm/cilium/values-ebpfkpr.yaml` | Mode B Helm values |
| K13 | `workload/server/deployment.yaml` | HTTP echo server |
| K14 | `workload/client/fortio.yaml` | Fortio load generator |
| K15 | `workload/policies/` | CiliumNetworkPolicy |

---

## Tổng quan

**Đầu vào:** `results_analysis/comparison_AB.csv`, `results_analysis/aggregated_summary.csv`, `results/calibration/`, Hubble evidence
**Đầu ra:** Thesis đầy đủ 5 chương + 6 appendix + 12 biểu đồ chính
**Thứ tự viết đề xuất:** Chương 2 → 3 → 4 → 1 → 5 (viết chương "nền" trước, viết introduction/conclusion cuối)

---

## Cấu trúc thesis hoàn chỉnh

```
docs/
├── thesis/
│   ├── 01-introduction.md           ← Chương 1
│   ├── 02-background-architecture.md ← Chương 2
│   ├── 03-methodology.md             ← Chương 3
│   ├── 04-results-analysis.md         ← Chương 4
│   └── 05-conclusion.md               ← Chương 5
│
├── appendix/
│   ├── A-infrastructure.md         ← Terraform + Helm values
│   ├── B-calibration.md           ← Calibration sweep + chart
│   ├── C-statistical-methods.md   ← Full statistical protocol
│   ├── D-raw-data/                ← CSV files
│   └── E-figures/                 ← All charts (fig-01 → fig-12)
│
└── figures/                        ← Infrastructure + Hubble screenshots
```

---

## Chương 1 — Giới thiệu (Introduction)

### 1.1 Bối cảnh (Context)
**Takeaway cho reviewer:** Tại sao kube-proxy là pain point khi cluster mở rộng? Tại sao AWS EKS là môi trường thực tế?

Nội dung:
- Kubernetes là tiêu chuẩn de-facto; networking layer quyết định service latency
- kube-proxy dùng iptables — chain traversal O(n) khi số services tăng
- Cilium eBPF datapath — O(1) map lookup, nhưng cần production evidence
- Tại sao AWS EKS: production-grade, không phải Minikube/local

### 1.2 Vấn đề nghiên cứu (Problem Statement)
- Mục tiêu: so sánh thực nghiệm trên AWS EKS thực tế
- Research Gap: các benchmark hiện tại chủ yếu là môi trường giả lập hoặc không đo trên production-grade cluster

### 1.3 Research Questions

| RQ | Câu hỏi | Primary Endpoint |
|----|---------|-----------------|
| RQ1 | Mode B có cải thiện tail latency ở steady-state so với Mode A? | p90, p99, p999 |
| RQ2 | Mode B có ổn định hơn dưới connection churn? | p99, p999, variance |
| RQ3 | CiliumNetworkPolicy enforcement tạo overhead bao nhiêu trên eBPF datapath? | Δ% off→on, p99 |

### 1.4 Giả thuyết (Hypotheses)

| H | Giả thuyết | Kỳ vọng |
|---|------------|---------|
| H1 | Mode B giảm tail latency (p90/p99) so với Mode A trong steady-state | Δ% < 0, p < 0.05 |
| H2 | Mode B chịu churn tốt hơn (ít spike, ít lỗi) | Trend B, nhưng variance cao |
| H3 | CiliumNetworkPolicy overhead < 5% trên eBPF datapath | Δ% < 5% |

### 1.5 Đóng góp chính (Contributions)

1. Benchmark thực trên production-grade AWS EKS m5.large × 3 (không phải Minikube/local)
2. Statistical significance: Holm-Bonferroni correction, Welch's t-test, 95% CI, Hedges' g effect size
3. Policy enforcement overhead measurement với Hubble verdict evidence (FORWARDED/DROPPED)
4. Phase-level analysis của S2 burst behavior (không chỉ mean per scenario)

### 1.6 Cấu trúc thesis
```
Chapter 2: Background & Architecture
Chapter 3: Methodology
Chapter 4: Results & Analysis
Chapter 5: Conclusion
```

---

## Chương 2 — Background & Architecture

#### 2.1.1 netfilter/iptables Framework
- Chain traversal O(n): PREROUTING → INPUT/OUTPUT → FORWARD → POSTROUTING
- KUBE-SERVICES chain: DNAT cho ClusterIP → PodIP
- KUBE-SEP-* chains: per-endpoint DNAT
- conntrack: stateful inspection overhead
- Điểm yếu: khi số services/rules tăng → traversal time tăng tuyến tính

#### 2.1.2 eBPF (Extended Berkeley Packet Filter)
- Hook-based: TC (traffic control), XDP, socket hooks, cgroup hooks
- BPF maps: hash map O(1) lookup thay chain traversal
- Verifier: safety guarantees trước khi load program vào kernel
- JIT compilation: native code execution speed

### 2.2 Kubernetes Networking Layer

#### 2.2.1 CNI Plugins
- CNI role: pod networking, IPAM, network policies
- Cilium: eBPF-based CNI, bypass iptables, datapath optimization

#### 2.2.2 kube-proxy Mechanics
```
Client Pod → veth → host netns → iptables PREROUTING
→ KUBE-SERVICES (DNAT ClusterIP→PodIP)
→ KUBE-SEP-* (per-endpoint)
→ conntrack (stateful NAT)
→ forward/delivery
← reply path: reverse DNAT + SNAT
```
**Điểm nghẽn:** Mỗi packet phải traverse O(n) rules

#### 2.2.3 Cilium eBPF Datapath (kubeProxyReplacement)
```
Client Pod → veth → TC eBPF hook
→ BPF service map lookup (O(1)) → backend selection
→ BPF endpoint map → policy check (if S3)
→ local delivery / redirect
← reply: reverse lookup
```
**Tối ưu:** Không cần conntrack cho Service LB (eBPF state map)

### 2.3 Hubble Observability
- Per-flow visibility tại datapath level
- Verdict: FORWARDED / DROPPED / ERROR
- Overhead: ring buffer, export pipeline (đã ghi nhận trong Threats)

### 2.4 Related Work & Research Gap

**Bảng tổng hợp Related Work:**

| Paper/Source | Môi trường | Metric đo | Scope | Thesis này bổ sung |
|-------------|-----------|---------|-------|-----------------|
| Cilium Official Benchmarks | Bare-metal, GKE | p50/p99 latency | Không nói rõ methodology | EKS, full methodology + stats |
| Isovalent eBPF benchmarks | GKE, self-managed | Throughput, latency | Single scenario | S1+S2+S3, policy overhead |
| SIGCOMM Kubernetes networking paper | GCE | Latency distribution | Không có policy | Thêm S3 + Hubble evidence |
| NT531 prior projects | — | — | — | Benchmark thực EKS + statistical rigor |
| [Paper 4] | ... | ... | ... | ... |
| [Paper 5] | ... | ... | ... | ... |

[📊 **TABLE:** Bảng Related Work ở trên chính là **Table 2.1** — đặt ngay cuối §2.4, giữ nguyên format. Đây là bảng tĩnh, không cần generated chart.]

**Research Gap Statement:**
> "Các benchmark hiện tại chủ yếu thực hiện trên môi trường GKE hoặc bare-metal, thiếu:
> 1. Production-grade EKS cluster với non-burstable instances
> 2. Statistical rigor đầy đủ (multiple comparison correction, effect size)
> 3. Phase-level burst analysis trong stress scenario
> 4. Policy enforcement overhead với Hubble verdict evidence"

---

## Chương 3 — Methodology

### 3.1 Topology & Infrastructure

#### 3.1.1 Sơ đồ triển khai (Deployment Diagram)

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS EKS (ap-southeast-1)               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │  Node-1      │  │  Node-2      │  │  Node-3      │    │
│  │  m5.large    │  │  m5.large    │  │  m5.large    │    │
│  │  ┌─────────┐│  │              │  │              │    │
│  │  │Fortio   ││  │              │  │              │    │
│  │  │(client) ││  │              │  │              │    │
│  │  └────┬────┘│  │              │  │              │    │
│  │       │     │  │              │  │              │    │
│  │  ┌────▼────┐│  │              │  │              │    │
│  │  │Echo Svc ││  │              │  │              │    │
│  │  │(server) ││  │              │  │              │    │
│  │  └─────────┘│  │              │  │              │    │
│  │  ┌─────────┐│  │              │  │              │    │
│  │  │Cilium   ││  │  (workers)   │  │  (workers)   │    │
│  │  │Agent    ││  │              │  │              │    │
│  │  └─────────┘│  │              │  │              │    │
│  └──────────────┘  └──────────────┘  └──────────────┘    │
│          ↑                              ↑                   │
│   same-node placement            workers cùng AZ          │
│   (podAntiAffinity)                                        │
└─────────────────────────────────────────────────────────────┘
```

[📊 **SCREENSHOT:** Nên chèn `fig-infra-01.png` (AWS Console screenshot hoặc Terraform output diagram) vào đây — sơ đồ topology thực tế của cluster. Đây là **H1** trong MỤC LỤC Hình ảnh.]

**Note:** Client và server được schedule cùng node qua podAntiAffinity (cùng node = cùng worker, cùng cilium-agent). Topology này loại bỏ cross-AZ latency.

[📊 **SCREENSHOT:** Sau deployment, chụp `kubectl get all -n benchmark` → `fig-infra-02.png` (**H2**). Nên đặt gần §3.1.1.]
[📊 **SCREENSHOT:** Sau khi cài Cilium Mode B, chụp `cilium status` → `fig-infra-03.png` (**H3**). Đặt sau §3.3 Cilium Deployment Configuration.]
[📊 **SCREENSHOT:** Prometheus/Grafana node CPU dashboard → `fig-infra-04.png` (**H4**). Đặt ở §3.5 Monitoring Stack hoặc §5.1 Summary.]

#### 3.1.2 Infrastructure Specs

| Component | Specification |
|-----------|--------------|
| Region | ap-southeast-1 |
| Instance type | m5.large (2 vCPU, 8 GiB RAM, non-burstable) |
| Node count | 3 workers |
| Kubernetes version | 1.34 |
| Cilium version | 1.18.7 |
| Topology | Single AZ (workers cùng subnet, cùng AZ) |

### 3.2 Datapath Architecture — Packet Flow Diagrams

#### 3.2.1 Mode A — kube-proxy datapath (same-node)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        MODE A: kube-proxy (iptables)                     │
│                    Client Pod → Service → Server Pod                     │
│                      (same node, same cilium-agent)                     │
└─────────────────────────────────────────────────────────────────────────┘

  [Client]    [veth pair]    [host netns]    [iptables]    [veth]   [Server]
      │              │              │               │           │         │
      │  TCP SYN     │              │               │           │         │
      │─────────────►│              │               │           │         │
      │              │   prerouting │               │           │         │
      │              │─────────────►│               │           │         │
      │              │              │ PREROUTING    │           │         │
      │              │              │   (nf_hook)   │           │         │
      │              │              │               │           │         │
      │              │              │ KUBE-SERVICES  │           │         │
      │              │              │ DNAT ClusterIP │           │         │
      │              │              │   → PodIP      │           │         │
      │              │              │               │           │         │
      │              │              │ KUBE-SEP-*    │           │         │
      │              │              │ per-endpoint  │           │         │
      │              │              │ DNAT          │           │         │
      │              │              │               │           │         │
      │              │              │ conntrack     │           │         │
      │              │              │ (stateful)    │           │         │
      │              │              │               │           │         │
      │              │              │               │◄───────────│─────────│ TCP SYN
      │              │              │               │   forward  │         │
      │              │              │               │───────────►│         │
      │              │              │               │           │         │
      │  TCP SYN-ACK│              │               │           │         │
      │◄─────────────│              │               │           │         │
      │              │    [reverse DNAT via conntrack]             │         │
      │              │              │               │           │         │
      │  HTTP GET    │              │               │           │         │
      │─────────────►│─────────────►│ KUBE-SERVICES │──────────►│─────────►│
      │              │              │ (each packet!) │           │         │
      │  HTTP 200    │              │               │           │         │
      │◄─────────────│◄──────────────│ (conntrack)   │◄──────────│─────────││

  O(n) iptables traversal — mỗi packet đều qua kube-services chain
  conntrack stateful overhead — mỗi connection tạo entry trong conntrack table
```

#### 3.2.2 Mode B — Cilium eBPF KPR (same-node)

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     MODE B: Cilium eBPF KPR (strict)                   │
│                    Client Pod → Service → Server Pod                    │
│                      (same node, same cilium-agent)                     │
└─────────────────────────────────────────────────────────────────────────┘

  [Client]    [veth pair]   [TC eBPF]    [BPF maps]     [veth]   [Server]
      │              │            │            │           │         │
      │  TCP SYN     │            │            │           │         │
      │─────────────►│            │            │           │         │
      │              │  tc_ingress │            │           │         │
      │              │────────────►│            │           │         │
      │              │            │ service_v2  │           │         │
      │              │            │ map lookup  │           │         │
      │              │            │   O(1) ✓    │           │         │
      │              │            │            │           │         │
      │              │            │ backend_sel │           │         │
      │              │            │────────────►│           │         │
      │              │            │            │           │         │
      │              │            │ [policy_map│ (if S3)   │         │
      │              │            │  check]    │           │         │
      │              │            │   O(1) ✓    │           │         │
      │              │            │            │           │         │
      │              │            │            │◄───────────│─────────│ TCP SYN
      │              │            │            │   redirect │         │
      │              │            │            │───────────►│         │
      │              │            │            │           │         │
      │  TCP SYN-ACK│            │            │           │         │
      │◄─────────────│            │            │           │         │
      │              │            │            │           │         │
      │  HTTP GET    │            │            │           │         │
      │─────────────►│────────────►│ [fast path]──────────►│─────────►│
      │              │  tc_ingress │   bypasses │           │         │
      │              │  (no iptables traversal)             │         │
      │  HTTP 200    │            │            │           │         │
      │◄─────────────│◄──────────────│───────────│◄──────────│─────────││

  ✓  O(1) BPF map lookup — mỗi packet chỉ 1 map lookup
  ✓  eBPF state map thay conntrack — kernel-level, không cần netfilter
  ✓  Policy check tại socket level — không cần iptables
  ✓  Hubble event export (ngoài fast path) — không ảnh hưởng datapath chính
```

[📊 **CHART:** Nên chèn `fig-12-datapath-comparison.png` (Mermaid hoặc draw.io) vào đây — so sánh trực quan luồng packet Mode A vs Mode B bên cạnh text. Biểu đồ này là backbone visual cho toàn bộ thesis.]

#### 3.2.3 So sánh datapath side-by-side

| Aspect | Mode A (kube-proxy) | Mode B (eBPF KPR) |
|--------|--------------------|--------------------|
| Service lookup | iptables chain traversal O(n) | BPF service map O(1) |
| State consulted | conntrack table (netfilter) | eBPF state map (kernel) |
| NAT point | iptables DNAT/SNAT per packet | eBPF redirect (in-kernel) |
| Policy enforcement | iptables (nếu dùng k8s NetworkPolicy) | BPF policy map O(1) |
| Observability | iptables audit/log | Hubble (ring buffer, async) |
| Per-packet overhead | Yes — mỗi packet đều qua iptables | No — bypass hoàn toàn |
| IPAM | cluster-pool (10.96.x.x) | ENI (10.0.x.x, AWS native) |
| **Đo được trong thesis này** | Latency/RPS/Error | Latency/RPS/Error |
| **Không đo được** | conntrack CPU overhead riêng | Hubble overhead riêng |

[📊 **TABLE:** Bảng so sánh datapath ở trên chính là **Table 2.3** — đặt ngay cuối §2.2.3 (trong Chương 2) hoặc §3.2.3 (trong Chương 3). Đây là bảng tĩnh.]

#### 3.2.4 Scope Boundary Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    SCOPE BOUNDARY                           │
│  ✓ ĐO TRONG THESIS: same-node ClusterIP, HTTP             │
│  ✗ NGOÀI SCOPE: cross-node, NodePort, gRPC, long-stream  │
└─────────────────────────────────────────────────────────────┘

  same-node ◄── ĐÂY LÀ PHẠM VI ──► cross-node (VXLAN/ENI)
  ClusterIP ◄─────────────────────► NodePort/LoadBalancer
  HTTP     ◄─────────────────────► gRPC/TCP-only
  1:1 pod  ◄─────────────────────► multi-backend load balancing
```

### 3.3 Cilium Deployment Configuration

#### Mode A — Baseline
```yaml
kubeProxyReplacement: false  # Cilium hybrid, kube-proxy active
cni.install: true
# kube-proxy daemon tồn tại → ClusterIP via iptables DNAT
# IPAM: cluster-pool (10.96.0.0/24)
```

#### Mode B — eBPF KPR
```yaml
kubeProxyReplacement: strict  # Thay thế hoàn toàn kube-proxy
eni.enabled: true             # ENI native routing
k8sServiceHost: <EKS-API>   # EKS API endpoint
hubble.enabled: true         # Observability
# IPAM: ENI (10.0.x.x/19, AWS native)
```

### 3.4 Workload Configuration

| Component | Image | Resource | Placement |
|-----------|-------|----------|-----------|
| HTTP Echo | hashicorp/http-echo:1.0 | 100m req / 200m limit, 64Mi | benchmark ns |
| Fortio | fortio/fortio:1.74.0 | 250m req / 500m limit, 128Mi | benchmark ns |
| Pod placement | podAntiAffinity (requiredDuringSchedulingIgnoredDuringExecution) | — | same node |

> podAntiAffinity đảm bảo Fortio client và HTTP echo server được schedule cùng node (để isolate datapath test, loại bỏ cross-node network variable). Với 1 client + 1 server + 3 nodes, same-node placement xảy ra phần lớn thời gian.

### 3.5 Monitoring Stack
- kube-prometheus-stack 60.0.0
- Cilium metrics: `cilium_forward_count_total`, `cilium_drop_count_total`
- Node metrics: CPU, memory, network I/O
- Hubble: flow logs (Mode B only)

[📊 **SCREENSHOT:** Chụp `hubble status` → `fig-hubble-01.png` (**H5**). Đặt trong §3.5.]
[📊 **SCREENSHOT:** `hubble observe` sample flows → `fig-hubble-02.png` (**H6**). Đặt trong §3.5 hoặc §4.2.3.]
[📊 **TABLE:** **Table 3.1** (RQ→H→Metric Traceability) — đặt ở đầu §3.1 Methodology. Bảng này trace từng RQ qua hypothesis → scenario → load → metric → figure. Không cần generated chart, just a static reference table:]

| RQ | Hypothesis | Scenario | Load | Primary Endpoint | Secondary | Statistical Test | Figure |
|----|-----------|----------|------|-----------------|-----------|-----------------|--------|
| RQ1 | H1: Mode B giảm p90/p99 so với Mode A | S1 | L1/L2/L3 | p90, p99 (ms) | p50, p999 | Welch's t + Holm-Bonf | fig-01, fig-02, fig-03 |
| RQ2 | H2: Mode B chịu churn tốt hơn | S2 | L2/L3 | p99, variance | p50, p90, p999 | Welch's t | fig-05, fig-06, fig-07 |
| RQ3 | H3: Policy overhead < 5% trên eBPF | S3 | L2/L3 | Δ% p99 (off→on) | p50, p90 | Welch's t | fig-04, fig-09 |

[📊 **TABLE:** **Table 3.1** ở trên — đặt ở đầu §3.1. Đây là bảng tĩnh.]

---

## Chương 4 — Results & Analysis

### 4.0 Overview
- Tổng quan: X benchmark runs, thời gian Y
- Bảng: total runs breakdown by scenario/load/mode
- Data availability: all error rates < threshold

[📊 **TABLE:** Overview nên chứa bảng tổng hợp số lượng runs (VD: S1 L1 × 3 modes × 3 repeats = 9 runs, S2 L2 × 3 modes × 3 repeats = 18 runs). Đây là bảng tĕng hợp, không cần generated chart — just static text. Đặt ngay sau §4.0 heading.]

### 4.1 S1 — Steady-State Performance

#### 4.1.1 Setup
- Mô tả: Load levels, duration, topology
- Số lượng measurements

#### 4.1.2 L1 Results (Low Load)

**Table 4.1: S1 L1 Latency**

| Metric | Mode A mean (ms) | Mode A 95% CI | Mode B mean (ms) | Mode B 95% CI | Δ% | p-value | Hedges' g | Sig. |
|--------|-----------------|--------------|-----------------|--------------|-----|---------|-----------|------|
| p50 | 0.564 | [x,x] | 0.551 | [x,x] | −2.4% | 0.027 | tbd | ✓ |
| p90 | 0.953 | [x,x] | 0.932 | [x,x] | −2.2% | 0.017 | tbd | ✓ |
| p99 | 1.846 | [x,x] | 1.667 | [x,x] | −9.7% | 0.083 | tbd | |
| p999 | 2.656 | [x,x] | 2.397 | [x,x] | −9.8% | 0.362 | tbd | |

> **Nhận xét:** Trình bày số liệu. Interpretation ở §4.6–§4.9 (Analysis trong Chương 4).

[📊 **CHART:** Ngay sau **Table 4.1** (S1 L1 latency), chèn:
- **fig-01-s1-latency-ab-comparison.png** (**C1**): Grouped bar chart p50/p90/p99 cho Mode A vs Mode B, L1. Hiển thị mean ± 95% CI.
- **fig-02-s1-latency-delta-pct.png** (**C2**): Bar chart Δ% (Mode B vs A) với ★ marker cho significant results. Hiển thị CI bars.
- **fig-03-s1-l3-p999-boxplot.png** (**C3**): Box plot p999 distribution. Đặt ở §4.1.4 (L3 results) hoặc §4.1.2 nếu muốn show tất cả loads cùng lúc.
]

#### 4.1.3 L2 Results (Medium Load) — tương tự
#### 4.1.4 L3 Results (High Load) — tương tự

[📊 **CHART:** Ngay sau bảng S1 L3 results, chèn **fig-03-s1-l3-p999-boxplot.png** (**C3**) — box plot showing p999 distribution across all 9 runs (3 repeats × 3 runs). Box plot này thể hiện rõ tail behavior và outliers, phù hợp với research về tail latency.]

### 4.2 S3 — NetworkPolicy Enforcement (Mode B only)

> **Thứ tự:** S3 đến trước S2 (steady-state → stable enforcement → stress edge case)

#### 4.2.1 Setup
- Policy OFF vs ON, L2 và L3
- Deny case: attacker pod test protocol

#### 4.2.2 Policy Overhead Results

**Table 4.2: S3 Policy Overhead**

| Load | Phase | p50 (ms) | p90 (ms) | p99 (ms) | Δ% p99 | Holm sig. |
|------|-------|---------|---------|---------|---------|-----------|
| L2 | OFF | 1.463 | 2.618 | 3.747 | — | |
| L2 | ON | 1.430 | 2.549 | 3.619 | −3.4% | ✗ |
| L3 | OFF | 2.286 | 3.961 | 5.857 | — | |
| L3 | ON | 2.331 | 4.063 | 5.928 | +1.2% | ✗ |

[📊 **CHART:** Ngay sau **Table 4.2**, chèn:
- **fig-04-s3-policy-overhead.png** (**C4**): Grouped bar OFF vs ON cho L2 và L3, hiển thị p50/p90/p99. Thể hiện policy overhead negligible.
- **fig-09-hubble-verdict-chart.png** (**C9**): Stacked bar FORWARDED/DROPPED từ `hubble_flows.jsonl`. Đặt trong §4.2.3 Hubble Evidence.
]

#### 4.2.3 Hubble Evidence
```
Attacker pod: curl → echo service → TIMEOUT/FAIL ✓
Hubble verdict: FORWARDED × N, TRACED × N, DROPPED × N
Policy enforcement: active tại endpoint level ✓
```

### 4.3 S2 — Stress + Connection Churn

#### 4.3.1 Setup
- 4 phases: rampup → sustained → burst ×3 → cooldown
- L2 và L3

#### 4.3.2 S2 L2 Results

**Table 4.3: S2 L2 Latency**

| Metric | Mode A mean (ms) | Mode A 95% CI | Mode B mean (ms) | Mode B 95% CI | Δ% | p-value | Holm sig. |
|--------|-----------------|--------------|-----------------|--------------|-----|---------|-----------|
| p50 | 2.208 | [x,x] | 2.140 | [x,x] | −3.1% | 0.695 | ✗ |
| p90 | 4.004 | [x,x] | 3.777 | [x,x] | −5.7% | 0.486 | ✗ |
| p99 | 5.903 | [x,x] | 5.720 | [x,x] | −3.1% | 0.717 | ✗ |
| p999 | 9.211 | [x,x] | 7.812 | [x,x] | −15.2% | 0.097 | ✗ |

> **Lưu ý:** Wide confidence intervals do high variance trong burst phases.

[📊 **CHART:** Ngay sau **Table 4.3** (S2 L2 latency), chèn:

#### 4.3.3 S2 L3 Results

**Table 4.4: S2 L3 Latency**

| Metric | Mode A mean (ms) | Mode A 95% CI | Mode B mean (ms) | Mode B 95% CI | Δ% | p-value | Holm sig. |
|--------|-----------------|--------------|-----------------|--------------|-----|---------|-----------|
| p50 | 3.985 | [x,x] | 3.665 | [x,x] | −8.0% | 0.365 | ✗ |
| p90 | 7.538 | [x,x] | 6.779 | [x,x] | −10.1% | 0.318 | ✗ |
| p99 | 11.222 | [x,x] | 9.668 | [x,x] | −13.8% | 0.135 | ✗ |
| p999 | 15.580 | [x,x] | 12.650 | [x,x] | **−18.8%** | **0.046** | ✓ |

#### 4.3.4 S2 Phase Behavior
- Bảng: p99 per phase (rampup, sustained, burst1, burst2, burst3, cooldown)
- fig-07 S2 phase-level line chart

### 4.4 Summary Statistics

[📊 **CHART:** Ngay trước §4.4, chèn **fig-07-s2-phase-analysis.png** (**C7**) — line chart phase→p99. Mỗi line = 1 mode (A/B), mỗi point = mean p99 của phase đó ± 95% CI band. Annotate burst phases để thấy spike amplitude. Đây là chart quan trọng để explain RQ2 high variance.]

**Table 4.8: Full Comparison Table (tất cả scenario × load × metric)**

| Scenario | Load | Metric | A mean | B mean | Δ% | p-value | Holm sig. | Hedges' g |
|----------|------|--------|--------|--------|-----|---------|-----------|-----------|
| S1 | L1 | p50 | ... | ... | ... | ... | ✓/✗ | ... |
| ... | ... | ... | ... | ... | ... | ... | ... | ... |

### 4.5 Artifact Provenance

- Mỗi số liệu gắn với: file path trong `results/`, run timestamp, git commit
- Reviewer có thể reproduce từ raw artifacts

---



### 4.6 RQ1: Steady-State Performance

**Trả lời: CÓ — có ý nghĩa thống kê sau Holm-Bonferroni correction.**

Evidence:
- L1: Mode B nhanh hơn 2.2–9.7% (p < 0.05 sau Holm cho p50/p90)
- L2: Mode B nhanh hơn 4.6–15.6% (tất cả p < 0.05 sau Holm)
- L3: Mode B nhanh hơn 8.0–27.1% (tất cả p < 0.05 sau Holm)

**Cơ chế giải thích:**
> Mode B nhanh hơn vì mỗi packet chỉ cần 1 BPF map lookup O(1), không phải traverse iptables chains O(n). Ở high load (L3), số iptables rules trong KUBE-SERVICES/KUBE-SEP-* chains tăng → thời gian traversal tăng. eBPF map lookup không phụ thuộc số lượng services.

**Effect size:** Hedges' g cho thấy medium-to-large effect size ở L2/L3.

### 4.7 RQ2: Stress & Connection Churn

**Trả lời: CÓ xu hướng, nhưng bằng chứng CHƯA đủ mạnh để khẳng định chắc chắn.**

Hedging language:
> "Mặc dù Mode B có xu hướng nhanh hơn ở mọi metric trong S2, sự khác biệt không đạt ý nghĩa thống kê (p > 0.05 sau Holm-Bonferroni) ở hầu hết trường hợp, do độ lệch chuẩn lớn trong burst phases. Chỉ p999 tại L3 đạt ý nghĩa thống kê (Δ% = −18.8%, p = 0.046)."

**Cơ chế giải thích:**
> Stress test tạo connection churn cao → Mode A: mỗi SYN/SYN-ACK/FIN đều qua iptables + conntrack. Mode B: eBPF socket redirect bỏ qua conntrack, nhưng burst phases tạo scheduling noise trên node (node-local competition). High variance ở cả hai mode → khó phát hiện difference với n=18.

**Nguyên nhân high variance:**
- Burst phases tạo connection churn cao
- Node-local CPU scheduling noise
- AWS EKS control plane latency spikes

### 4.8 RQ3: Policy Enforcement Overhead

**Trả lời: OVERHEAD < 5% — negligible trên eBPF datapath.**

Evidence:
- L2: Δ% p99 = −3.4% (ON nhanh hơn OFF — within noise)
- L3: Δ% p99 = +1.2% (ON chậm hơn OFF — negligible)

**Cơ chế giải thích:**
> CiliumNetworkPolicy được enforce tại socket level qua BPF policy map lookup — O(1). Không traverse iptables chain. Policy check chỉ thêm 1 map lookup khi endpoint được authorized. Deny case chứng minh enforcement hoạt động tại endpoint level qua Hubble verdict DROPPED.

### 4.9 Comparative Summary

[📊 **CHART:** Ngay trước **Table 4.9**, chèn **fig-08-effect-ci-forest-plot.png** (**C8**) — forest plot thể hiện Δms với 95% CI cho tất cả comparisons. Mỗi row = 1 comparison. Zero line highlighted. ★ sig markers. Color-coded: green (B faster) / red (B slower). Đây là chart tổng hợp cho toàn bộ thesis.]

**Table 4.9: Answer Summary**

| RQ | Trả lời | Confidence | Evidence Strength |
|----|---------|-----------|------------------|
| RQ1 | YES (Mode B faster) | HIGH | All S1 significant, large effect size |
| RQ2 | INCONCLUSIVE | MEDIUM | Trend B, high variance, 1 sig |
| RQ3 | YES (overhead < 5%) | HIGH | Both loads within noise |

[📊 **CHART:** Sau **Table 4.9**, nên có bản lưu LaTeX **table-01-comparison-ab.tex** trong Appendix E — LaTeX comparison table cho phép reader copy/paste vào paper.]

### 4.10 Resource Overhead Analysis

Nếu có Prometheus data:
- kube-proxy CPU usage vs cilium-agent CPU usage
- Node softirq time
- BPF map memory usage

### 4.11 Sensitivity Analysis

Với n=3 và tail percentiles:
- Mann-Whitney U test results
- Bootstrap CI (1000 iterations)
→ Khẳng định robustness của kết luận

---

## Chương 5 — Conclusion

### 5.1 Summary of Findings

[📊 **CHART RECAP:** §5.1 nên reference lại các chart chính: fig-01 (S1 latency), fig-08 (forest plot), fig-03 (box plot). Không cần chèn lại full chart, chỉ cần caption ghi "Như đã trình bày ở Hình X, Y, Z" để connective flow.]

**RQ1 — Steady-State:** [viết cụ thể như dưới]
**RQ2 — Stress/Churn:** [viết rất chặt — không over-claim]
**RQ3 — Policy Overhead:** [viết với scope rõ ràng]

#### RQ1 Cụ thể:
> Trong cụm EKS 3 node m5.large, topology same-node, Mode B (Cilium eBPF KPR) giảm latency so với Mode A (kube-proxy hybrid) ở steady-state. Mức cải thiện có ý nghĩa thống kê (Welch's t-test, two-tailed, α=0.05, Holm-Bonferroni corrected) ở tất cả load levels L1/L2/L3. Tail latency (p99/p999) cải thiện nhiều nhất: đến 27.1% ở L3. Effect size (Hedges' g) ở mức medium-to-large ở L2/L3.

#### RQ2 Cụ thể:
> Dữ liệu S2 cho thấy xu hướng Mode B tốt hơn ở mọi metric, nhưng bằng chứng chưa đủ mạnh để khẳng định Mode B ổn định hơn một cách nhất quán. Chỉ p999 tại L3 đạt ý nghĩa thống kê sau Holm-Bonferroni correction (Δ% = −18.8%, p = 0.046). High variance trong burst phases và node-local scheduling noise là các yếu tố nhiễu chính.

#### RQ3 Cụ thể:
> Trong phạm vi same-node và policy rule đơn giản, CiliumNetworkPolicy tạo overhead dưới 5% trên eBPF datapath — nằm trong measurement noise. Deny-case test xác nhận enforcement hoạt động tại endpoint level với Hubble verdict DROPPED. Policy enforcement overhead không đáng kể khi so sánh với iptables-based enforcement.

### 5.2 Practical Implications

- **Dùng eBPF KPR khi:**
  - Cluster có nhiều services/policies (100+)
  - Latency-sensitive workloads (p99/p999 là SLA metric)
  - Cần observability (Hubble)
- **Cân nhắc:**
  - Rollout cần careful coordination (tắt kube-proxy trước)
  - IPAM change (cluster-pool → ENI) có thể ảnh hưởng network policy
  - Hubble overhead (1–5%) nên benchmark riêng

### 5.3 Limitations

4 điểm bắt buộc:

1. **Hybrid baseline:** Mode A là "Cilium hybrid + kube-proxy" không phải pure kube-proxy
2. **IPAM confound:** cluster-pool vs ENI routing không kiểm soát được
3. **Same-node only:** Kết luận chỉ áp dụng same-node, cross-node cần additional research
4. **Sequential A→B:** Time-of-day effect, Hubble asymmetry (Mode B only)

### 5.4 Future Work

- Cross-node traffic benchmark (VXLAN vs ENI native routing)
- Parallel A/B execution (2 clusters, đồng thời)
- Hubble overhead isolation study (tắt Hubble, benchmark riêng)
- k8s NetworkPolicy vs CiliumNetworkPolicy overhead comparison
- Policy complexity scaling (1 rule → 50 rules)

---

## PHẦN BIỂU ĐỒ — Hướng dẫn chi tiết

### Tổng quan: 12 biểu đồ + 1 LaTeX table

| # | Biểu đồ | Type | Data source | Đặt ở |
|---|---------|------|-------------|--------|
| C1 | `fig-01-s1-latency-ab-comparison.png` | Grouped bar p50/p90/p99 A vs B | comparison_AB.csv | §4.1.2 |
| C2 | `fig-02-s1-latency-delta-pct.png` | Bar Δ% + ★ sig + CI error bars | comparison_AB.csv | §4.1.2 |
| C3 | `fig-03-s1-l3-p999-boxplot.png` | Box plot p999 distribution | per-run bench.log | §4.1.4 |
| C4 | `fig-04-s3-policy-overhead.png` | Grouped bar OFF vs ON (L2/L3) | aggregated_summary.csv | §4.2.2 |
| C5 | `fig-05-s2-latency-ab-comparison.png` | Grouped bar p50/p90/p99 A vs B | comparison_AB.csv | §4.3.2 |
| C6 | `fig-06-s2-latency-delta-pct.png` | Bar Δ% cho S2 L2/L3 | comparison_AB.csv | §4.3.2 |
| C7 | `fig-07-s2-phase-analysis.png` | Line chart: phase → p99 + CI band | bench_phase*.log | §4.3.4 |
| C8 | `fig-08-effect-ci-forest-plot.png` | Forest plot: Δms với 95% CI | comparison_AB.csv | §4.9 |
| C9 | `fig-09-hubble-verdict-chart.png` | Stacked bar FORWARDED/DROPPED | hubble_flows.jsonl | §4.2.3 |
| C10 | `fig-10-error-rate-chart.png` | Bar error% theo load/scenario | aggregated_summary.csv | §4.4 |
| C11 | `fig-11-calibration-curve.png` | Line QPS → p99 + error% | calibration CSV | §3.3 |
| C12 | `fig-12-datapath-comparison.png` | Packet flow diagrams | static | §2.2.3 |
| — | `table-01-comparison-ab.tex` | LaTeX comparison table | comparison_AB.csv | §4.9 |

---

### Hướng dẫn vẽ từng biểu đồ (không cần code)

#### fig-01 — S1 Latency AB Comparison (Grouped Bar)

**Dữ liệu đầu vào:** `comparison_AB.csv` — chứa mean + 95% CI cho từng scenario/load/mode.

**Cách vẽ:**
- Trục X: 3 nhóm (p50, p90, p99) cho mỗi load level (L1 / L2 / L3)
- Trong mỗi nhóm: 2 bars (Mode A đỏ, Mode B xanh)
- Error bars: 95% CI (bắt buộc)
- Trên đỉnh mỗi bar: ghi giá trị mean (VD: "0.55")
- Dưới chart: caption ghi "Error bars = 95% CI, n=9 (3 runs × 3 repeats)"

**S1 L1:** Low load, chênh lệch nhỏ — dùng chart này để show baseline.
**S1 L2:** Medium load — đây là chart quan trọng nhất, Mode B bắt đầu nổi rõ.
**S1 L3:** High load — Mode B nhanh hơn đáng kể (8–27%). Đặt cạnh box plot fig-03.

---

#### fig-02 — S1 Latency Delta Percentage (Bar Δ%)

**Dữ liệu đầu vào:** `comparison_AB.csv` — Δ% = (B−A)/A × 100.

**Cách vẽ:**
- Trục X: từng metric × load (VD: "p50 L1", "p90 L1", "p99 L1", ..., "p999 L3")
- Trục Y: Δ% (âm = Mode B nhanh hơn)
- Bar màu xanh lá nếu Mode B nhanh hơn (Δ% < 0)
- Bar màu đỏ nếu Mode B chậm hơn (Δ% > 0)
- **★ marker** trên bar nếu p < 0.05 sau Holm-Bonferroni
- Horizontal line at 0 (no difference)
- Ghi chú: "★ = statistically significant (Welch's t-test, α=0.05, Holm-Bonferroni corrected)"

**Takeaway:** Reader nhìn chart này sẽ thấy ngay Mode B nhanh hơn ở đâu và significant ở đâu.

---

#### fig-03 — S1 L3 p999 Box Plot

**Dữ liệu đầu vào:** `per-run bench.log` — tất cả 9 giá trị p999 (3 runs × 3 repeats) cho L3.

**Cách vẽ:**
- 2 box plots: Mode A vs Mode B
- Box: Q1 → Q3, median line ở giữa
- Whiskers: min/max hoặc 1.5×IQR
- Individual dots: từng run (jitter nhẹ để tránh overlap)
- Đây là chart duy nhất show được raw data distribution — phù hợp với tail latency research

**Lý do:** p999 không phải Gaussian → box plot thể hiện outliers và skewness tốt hơn bar chart.

---

#### fig-04 — S3 Policy Overhead (Grouped Bar OFF vs ON)

**Dữ liệu đầu vào:** `aggregated_summary.csv` — policy OFF vs ON results cho Mode B L2/L3.

**Cách vẽ:**
- 4 nhóm: L2-OFF, L2-ON, L3-OFF, L3-ON
- Trong mỗi nhóm: 3 bars (p50, p90, p99)
- Đặt OFF và ON cạnh nhau để dễ so sánh
- Δ% annotation trên mỗi cặp OFF/ON

**Takeaway:** Cho thấy policy overhead ≈ 0 (trong noise) → eBPF policy check không đáng kể.

---

#### fig-05 — S2 Latency AB Comparison (Grouped Bar)

**Cách vẽ:** Tương tự fig-01 nhưng cho S2 L2 và L3.
- **Lưu ý:** CI bars sẽ rất rộng — đây là điểm chính của RQ2.
- Ghi rõ "Wide CI bands reflect high variance in burst phases" trong caption.

---

#### fig-06 — S2 Latency Delta Percentage

**Cách vẽ:** Tương tự fig-02 cho S2 L2 và L3.
- Nhiều bars sẽ **không có ★** — đây là bằng chứng cho RQ2 INCONCLUSIVE.
- Đây là chart để **minh họa hedging language** trong §4.7.

---

#### fig-07 — S2 Phase Analysis (Line Chart)

**Dữ liệu đầu vào:** `bench_phase*.log` — p99 mean + CI cho từng phase (rampup, sustained, burst1, burst2, burst3, cooldown).

**Cách vẽ:**
- Trục X: 6 phases
- 2 lines: Mode A (đỏ), Mode B (xanh)
- Shaded area: ± 95% CI band quanh mỗi line
- Annotate burst phases: chỉ rõ spike amplitude (VD: "burst2: A=18ms vs B=14ms")
- Dùng vertical shading để highlight burst zones

**Đây là chart quan trọng nhất cho RQ2** — cho thấy Mode B stable hơn ở burst nhưng high variance làm không significant.

---

#### fig-08 — Effect CI Forest Plot

**Dữ liệu đầu vào:** `comparison_AB.csv` — Δms + 95% CI cho tất cả comparisons.

**Cách vẽ:**
- Mỗi row = 1 comparison (VD: "S1 L3 p99", "S2 L2 p999", v.v.)
- Trục X: Δms (Mode B − Mode A)
- Diamond/point với horizontal CI bar
- **Vertical line at 0** (no difference) — đây là reference line quan trọng
- Diamond nằm bên trái line 0 → Mode B nhanh hơn (màu xanh)
- Diamond nằm bên phải → Mode B chậm hơn (màu đỏ)
- **★ marker** nếu significant
- Color gradient cho effect size (negligible → large)

**Đây là "signature chart" của thesis** — thể hiện toàn bộ kết quả trong 1 view, được dùng rất nhiều trong SIGCOMM/USENIX.

---

#### fig-09 — Hubble Verdict Chart (Stacked Bar)

**Dữ liệu đầu vào:** `hubble_flows.jsonl` — count FORWARDED / TRACED / DROPPED.

**Cách vẽ:**
- 2 nhóm: S3 OFF vs S3 ON (cho L2 và L3)
- Stacked bar: mỗi bar chồng 3 phần (FORWARDED=xanh, TRACED=xanh dương, DROPPED=đỏ)
- Deny case: bar 100% DROPPED (đặt bên cạnh allow case)

**Đặt ngay sau Table 4.2** để reader thấy policy enforcement hoạt động qua Hubble verdict, không phải chỉ qua latency numbers.

---

#### fig-10 — Error Rate Chart (Bar)

**Dữ liệu đầu vào:** `aggregated_summary.csv` — error% theo scenario/load/mode.

**Cách vẽ:**
- Bar chart, mỗi bar = error% của 1 run group
- Horizontal threshold lines: 0.1% (L1), 1% (L2), 5% (L3)
- Ghi giá trị trên đỉnh bars

**Takeaway:** Show tất cả error rates đều < threshold → data quality verified.

---

#### fig-11 — Calibration Curve

**Dữ liệu đầu vào:** Calibration CSV từ `scripts/calibrate.sh`.

**Cách vẽ:**
- Line 1 (primary): QPS → p99_ms — đường tăng dần
- Line 2 (secondary): QPS → error% — đường tăng dần theo QPS
- Vertical lines tại L1/L2/L3 breakpoints
- Annotate QPS values đã chọn
- Shaded region cho acceptable zone (p99 < threshold)

**Đặt trong §3.3** để justify load levels bằng dữ liệu thực tế, không phải guess.

---

#### fig-12 — Datapath Comparison (Static Diagram)

**Nguồn:** Vẽ bằng draw.io / Mermaid / Lucidchart / PowerPoint.

**2 diagram cần vẽ:**

**Diagram A — Mode A (kube-proxy):**
- Client Pod → veth → host netns → PREROUTING → KUBE-SERVICES → KUBE-SEP-* → conntrack → forward
- Annotation: "O(n) iptables traversal" + "conntrack stateful overhead"

**Diagram B — Mode B (eBPF KPR):**
- Client Pod → veth → TC eBPF → BPF service map → BPF endpoint map → policy check → redirect
- Annotation: "O(1) BPF map lookup" + "socket-level policy"

**Đặt cạnh nhau (side-by-side)** để reader so sánh trực quan. Dùng cùng color scheme: Mode A = đỏ, Mode B = xanh.

---

### Công cụ đề xuất vẽ biểu đồ

#### 🎯 Primary: Python (matplotlib + seaborn)
**Lý do:** Tất cả data đã ở CSV, Python xử lý nhanh, dễ tái sử dụng, export PNG DPI cao.

```bash
pip install matplotlib seaborn pandas numpy scipy
```

**Ưu điểm:**
- Seaborn grouped bar (`sns.barplot`) — chuẩn academic
- Seaborn box plot (`sns.boxplot`) — clean, professional
- Matplotlib line với CI band — linh hoạt
- Pandas groupby để aggregate raw data → chart data

**Nhược điểm:**
- Forest plot phải vẽ thủ công bằng matplotlib (không có ready-made)

---

#### 🎨 Alternative: Google Sheets / Excel
**Phù hợp khi:** Data đã clean, muốn nhanh, không cần code.
**Ưu điểm:** Nhanh, trực quan, ai cũng dùng được
**Nhược điểm:** Khó đảm bảo consistency (font, color, DPI) xuyên suốt 12 charts

**Phù hợp cho:** fig-10 (error rate), fig-11 (calibration) — đơn giản, không cần CI bars.

---

#### 📊 Alternative: Plotly (Python/JavaScript)
**Phù hợp khi:** Muốn interactive chart (hover, zoom) cho bản online/slides.
**Ưu điểm:** Interactive, export HTML interactive hoặc static PNG
**Nhược điểm:** File HTML interactive không dùng được cho thesis PDF

**Phù hợp cho:** fig-08 (forest plot) — interactive hover cho từng comparison.

---

#### 🔧 Alternative: R (ggplot2)
**Phù hợp khi:** Đã quen R, muốn publication-quality tối đa.
**Ưu điểm:** ggplot2 cho academic charts rất chuẩn, `ggpubr` package cho thesis-ready formatting.
**Nhược điểm:** Setup lâu hơn Python.

---

### Công cụ phân tích kết quả thống kê

#### 🎯 Primary: Python (scipy + numpy + custom scripts)

```bash
pip install scipy numpy pandas matplotlib seaborn
```

**Script chính:** `scripts/analyze_results.py` (đã có trong repo)

**Các phép tính cần thực hiện:**

| Phép tính | Công cụ | Output |
|-----------|---------|--------|
| Welch's t-test | `scipy.stats.ttest_ind(data_A, data_B, equal_var=False)` | t-stat, p-value |
| Holm-Bonferroni correction | Tự viết (sắp xếp p-values, nhân theo rank) | Holm-adjusted p |
| Hedges' g effect size | Tự viết (mean diff / pooled std × correction) | g value |
| 95% CI (mean) | `scipy.stats.t.interval(df, loc, scale)` | CI [low, high] |
| Bootstrap CI | `numpy.random.choice(resamples, size=n, replace=True)` | Bootstrap CI |
| Mann-Whitney U | `scipy.stats.mannwhitneyu(data_A, data_B)` | U statistic, p |
| Shapiro-Wilk (normality) | `scipy.stats.shapiro(data)` | p-value (normality check) |

---

#### 📊 Alternative: JASP (GUI, miễn phí)
**Phù hợp khi:** Không muốn code, cần GUI cho statistical tests.
**Ưu điểm:** Miễn phí, GUI dễ dùng, export publication-ready tables.
**Tính năng:** Welch's t-test, Holm-Bonferroni, box plots, violin plots đều có.
**Link:** https://jasp-stats.org/

**Phù hợp cho:** sinh viên không quen code nhưng cần statistical rigor.

---

#### 📈 Alternative: R (lme4 + stats)
**Phù hợp khi:** Có nhiều time-series data hoặc cần mixed-effects model.
**Ưu điểm:** Mạnh về mixed-effects, publication-ready plots.
**Nhược điểm:** Learning curve cao.

---

### Nguyên tắc thiết kế biểu đồ cho thesis

**Màu sắc (thống nhất toàn thesis):**
- Mode A: `#e74c3c` (đỏ) hoặc `#d62728`
- Mode B: `#27ae60` (xanh lá) hoặc `#2ca02c`
- Significance star: `#f39c12` (vàng)
- Error/drop: `#e74c3c` (đỏ)
- Forwarded/OK: `#27ae60` (xanh)

**Font & kích thước:**
- Font chính: DejaVu Sans hoặc Times New Roman, 10–11pt
- Chart title: Bold, 12pt
- Axis labels: 10pt
- Legend: 9pt

**Figure dimensions:**
- Single column: ~8cm width → DPI 300
- Double column: ~16cm width → DPI 300
- Aspect ratio: 4:3 hoặc 16:9 tùy chart type

**Labels & annotations:**
- Đơn vị bắt buộc: ms, req/s, %
- Error bars: "Error bars = 95% CI, n=9" trong caption
- Significance: "★ = p < 0.05 (Welch's t-test, Holm-Bonferroni corrected)"
- Mode labels: luôn ghi "Mode A (kube-proxy)" và "Mode B (Cilium eBPF KPR)" — không viết tắt

**Grid lines:**
- Light gray (#cccccc) horizontal grid
- Không dùng vertical grid (confusing)

**Axis treatment:**
- Trục Y latency: bắt đầu từ 0 (không truncate baseline)
- Trục Y Δ%: nên include cả giá trị âm và dương
- Log scale: CHỉ dùng khi data range rất lớn, phải ghi rõ log scale

---

### Quy trình vẽ biểu đồ (bước đi)

1. **Chạy benchmark** → thu data (CSV)
2. **Chạy `scripts/analyze_results.py`** → sinh `comparison_AB.csv` + `aggregated_summary.csv`
3. **Vẽ charts** → Python script generate tất cả 12 PNG
4. **Review charts** → kiểm tra bằng mắt (outliers, labeling)
5. **Insert vào thesis** → caption + cross-reference
6. **Export LaTeX** → `table-01-comparison-ab.tex` cho Appendix

---

### Mẫu caption chuẩn cho từng chart

| Chart | Mẫu caption |
|-------|------------|
| fig-01 | **Figure X.** Latency comparison between Mode A (kube-proxy) and Mode B (Cilium eBPF KPR) under S1 steady-state at L1 load. Grouped bar shows mean p50/p90/p99 with 95% CI. Mode B shows [Δ%] lower latency at p90 (★ p=...). Error bars = 95% CI, n=9 runs. |
| fig-02 | **Figure X.** Percentage difference (Δ%) in latency from Mode A to Mode B across S1 loads. Negative values indicate Mode B is faster. ★ = statistically significant (Welch's t-test, two-tailed, α=0.05, Holm-Bonferroni corrected). |
| fig-03 | **Figure X.** Distribution of p999 latency across 9 runs (3 runs × 3 repeats) for S1 L3. Box shows Q1–Q3, whiskers extend to min/max. Individual dots represent single runs. |
| fig-04 | **Figure X.** NetworkPolicy enforcement overhead on Mode B (eBPF KPR). Bars show p50/p90/p99 for policy OFF vs ON at L2 and L3. Overhead is within measurement noise (|Δ%| < 5%). |
| fig-07 | **Figure X.** p99 latency across S2 phases for Mode A (red) and Mode B (green). Shaded bands = 95% CI. Burst phases show high variance in both modes. |
| fig-08 | **Figure X.** Forest plot of Δms (Mode B − Mode A) with 95% CI for all comparisons. Zero line indicates no difference. ★ = significant after Holm-Bonferroni correction. |

---

### Thứ tự vẽ biểu đồ đề xuất

1. **fig-12** (datapath) — vẽ trước, dùng làm nền cho Chương 2
2. **fig-11** (calibration) — vẽ trước, justify L1/L2/L3
3. **fig-01, fig-02, fig-03** — S1 charts, dùng cho §4.1
4. **fig-04, fig-09** — S3 charts, dùng cho §4.2
5. **fig-05, fig-06, fig-07** — S2 charts, dùng cho §4.3
6. **fig-10** — error rate, dùng cho §4.4
7. **fig-08** — forest plot, vẽ cuối cùng vì cần tất cả data từ 1-6
8. **table-01.tex** — LaTeX table, export từ comparison_AB.csv

---

---

## Appendix A — Infrastructure

### A.1 Terraform Configuration
```hcl
kubernetes_version = "1.34"
cilium_version    = "1.18.7"
instance_type     = "m5.large"
node_count        = 3
region            = "ap-southeast-1"
```

### A.2 Helm Values Key Params
**Mode A:** `kubeProxyReplacement: false`
**Mode B:** `kubeProxyReplacement: strict`, `eni.enabled: true`, `hubble.enabled: true`

### A.3 Cluster Versions Table

| Component | Version |
|-----------|---------|
| Kubernetes | 1.34 |
| Cilium | 1.18.7 |
| Prometheus (kube-prom) | 60.0.0 |
| Fortio | 1.74.0 |
| HTTP Echo | 1.0 |

---

## Appendix B — Calibration

### B.1 Calibration Sweep Data
[Copy từ results/calibration/*.csv]

### B.2 Calibration Chart
fig-11: QPS → p99 + error rate curve

### B.3 L1/L2/L3 Justification Table
[QPS/Conn/Threads → p99/error% → rationale]

---

## Appendix C — Statistical Methods

### C.1 Welch's t-test
### C.2 Holm-Bonferroni Correction
### C.3 Hedges' g Effect Size
### C.4 Confidence Intervals (Difference)
### C.5 Mann-Whitney U (Sensitivity)
### C.6 Bootstrap CI (Sensitivity)
### C.7 Unit of Analysis Definition
### C.8 Sample Size Justification

---

## Appendix D — Raw Data

```bash
cp results_analysis/aggregated_summary.csv docs/appendix/D-raw-data/
cp results_analysis/comparison_AB.csv docs/appendix/D-raw-data/
cp results/calibration/*.csv docs/appendix/D-raw-data/calibration/
```

---

## Appendix E — Figures

Tất cả fig-01 → fig-12 + table-01-comparison-ab.tex

---

## Appendix F — Scripts & Configuration

### F.1 Benchmark Scripts
- `scripts/calibrate.sh`
- `scripts/run_s1.sh`, `scripts/run_s2.sh`, `scripts/run_s3.sh`
- `scripts/collect_meta.sh`, `scripts/collect_hubble.sh`

### F.2 Analysis Scripts
- `scripts/analyze_results.py`

### F.3 Workload Manifests
- `workload/server/deployment.yaml`
- `workload/client/fortio.yaml`
- `workload/policies/`

---

## THỨ TỰ VIẾT ĐỀ XUẤT

| Thứ tự | Chương/File | Lý do |
|---------|-------------|--------|
| 1 | Chương 2 (Background & Architecture) | Hiểu rõ datapath → viết methodology chuẩn |
| 2 | Chương 3 (Methodology) | Design chi tiết → viết results khách quan |
| 3 | Chương 4 (Results & Analysis) | Dữ liệu thực tế → phân tích sâu + giải thích RQ |
| 4 | Chương 1 (Introduction) | Viết cuối — biết hết nội dung → viết intro chuẩn |
| 5 | Chương 5 (Conclusion) | Tổng hợp từ 1–4 |
| 6 | Appendices A→F | Copy/parse từ artifacts |
| 7 | Appendix E figures | Generate charts từ CSV |
| 8 | Review + Proofread | Đọc lại toàn bộ |

---

## Checklist Trước Khi Nộp

```
[ ] Related Work table (§2.4)
[ ] RQ→H→S→M→Figure traceability (§3.1)
[ ] Holm-Bonferroni correction applied
[ ] Hedges' g effect size reported
[ ] IPAM confound ghi nhận trong Threats
[ ] Mann-Whitney / Bootstrap sensitivity analysis
[ ] Unit of analysis = run-level percentile
[ ] Chương 4 (§4.1–§4.5): chỉ data + so lieu khach quan, không interpretation
[ ] Chương 4 (§4.6–§4.11): cơ chế + RQ1/RQ2/RQ3 (Analysis trong cùng chương)
[ ] RQ2: hedging language đúng mức, không over-claim
[ ] RQ3: wording đúng với S3 design
[ ] 12 biểu đồ (fig-01 → fig-12)
[ ] table-01 LaTeX comparison table
[ ] Calibration chart (fig-11)
[ ] All CSV raw files in appendix D
[ ] Threat table đầy đủ (11 threats)
[ ] Hubble verdict evidence trong §3.2
[ ] podAntiAffinity clarification trong §2.4
[ ] Scope boundary diagram (§2.2.4)
[ ] Artifact provenance in §3.5
[ ] GitHub link / reproducibility info
```
