# KẾ HOẠCH VIẾT THESIS — NT531

---

## MỤC LỤC

1. [Phạm vi thực nghiệm](#0-phạm-vi-thực-nghiệm)  
2. [Cấu trúc thesis](#1-cấu-trúc-thesis)  
   1. [Chương 1 — Introduction](#chương-1--introduction)  
   2. [Chương 2 — Background & Related Work](#chương-2--background--related-work)  
   3. [Chương 3 — System Design, Implementation & Methodology](#chương-3--system-design-implementation--methodology)  
   4. [Chương 4 — Results & Analysis](#chương-4--results--analysis)  
   5. [Chương 5 — Conclusion](#chương-5--conclusion)  
3. [Appendices](#2-appendices)  
4. [Must-have và Nice-to-have](#3-must-have-và-nice-to-have)  
5. [Workloads table phân công thành viên](#4-workloads-table-phân-công-thành-viên)  
6. [Bộ biểu đồ](#5-bộ-biểu-đồ)  
7. [Thứ tự viết khuyến nghị](#6-thứ-tự-viết-khuyến-nghị)  
8. [Checklist trước khi bắt đầu viết](#7-checklist-trước-khi-bắt-đầu-viết)  

---

## DANH MỤC BẢNG

- **Table 2.1** — Related Work Comparison  
- **Table 3.1** — Infrastructure Specifications  
- **Table 3.2** — Workload Configuration  
- **Table 3.3** — RQ to Metric Traceability  
- **Table 3.4** — Load Levels  
- **Table 3.5** — Fairness Controls  
- **Table 3.6** — Internal Threats  
- **Table 3.7** — External Threats  
- **Table 4.1** — S1 L1 Results  
- **Table 4.2** — S1 L2 Results  
- **Table 4.3** — S1 L3 Results  
- **Table 4.4** — S3 Policy Overhead  
- **Table 4.5** — S2 L2 Results  
- **Table 4.6** — S2 L3 Results  
- **Table 4.7** — Phase-level p99 Summary  
- **Table 4.8** — Full Summary across S1 / S2 / S3  
- **Table 4.9** — Artifact Provenance  
- **Table 4.10** — RQ Answer Summary  
- **Table W1** — Workload Distribution  

---

## DANH MỤC HÌNH

- **Figure 2.1** — Datapath Comparison Diagram  
- **Figure 3.1** — EKS Deployment Topology  
- **Figure 3.2** — Calibration Curve  
- **Figure 4.1** — S1 Latency Comparison  
- **Figure 4.2** — S3 Policy Overhead  
- **Figure 4.3** — Hubble Verdict / Deny Evidence  
- **Figure 4.4** — S2 Phase-level p99  
- **Figure 4.5** — Consolidated Comparison Summary  
- **Figure 4.6** — Error Rate Comparison *(nice-to-have)*  
- **Figure 4.7** — p99 Box Plot *(nice-to-have)*  
- **Figure 4.8** — Grafana Node Metrics Snapshot *(nice-to-have)*  
- **Figure 4.9** — Delta % Bar Chart *(nice-to-have)*  

---

# 0. Phạm vi thực nghiệm

**Tên đề tài đề xuất**  
**Đánh giá hiệu năng Kubernetes Service datapath giữa kube-proxy và Cilium eBPF kube-proxy replacement trên AWS EKS**

## Thiết kế thực nghiệm
- 01 cluster AWS EKS
- 03 worker nodes `m5.large`
- Chạy **tuần tự** hai mode trong cùng cluster:
  - **Mode A:** kube-proxy baseline
  - **Mode B:** Cilium eBPF kube-proxy replacement
- **Scenario S3 chỉ thực hiện trên Mode B**, dùng **CiliumNetworkPolicy**
- Metric chính:
  - `p50`
  - `p95`
  - `p99`
  - `RPS`
  - `error rate`
- Phạm vi chính:
  - `ClusterIP`
  - `HTTP`
  - `same-node ưu tiên`
- Hubble được dùng như:
  - evidence về correctness
  - observability support
  - policy verification

## Nguyên tắc học thuật
- Đây là benchmark có kiểm soát trên **AWS EKS thực**
- Có dùng thống kê để hỗ trợ kết luận, nhưng **không over-sell rigor**
- Kết luận chỉ áp dụng **trong đúng phạm vi thực nghiệm đã đo**

---

# 1. Cấu trúc thesis

## Chương 1 — Introduction
Mục tiêu của chương này là trả lời:
- Vì sao đề tài đáng làm
- Khoảng trống thực tế là gì
- Thesis này đóng góp gì

### 1.1 Context
- Kubernetes là nền tảng triển khai microservices phổ biến
- Service datapath ảnh hưởng trực tiếp đến latency và tail latency
- kube-proxy là baseline phổ biến
- Cilium eBPF kube-proxy replacement là hướng thay thế đáng chú ý trên production Kubernetes

### 1.2 Problem statement
- Cần đánh giá thực nghiệm trên **AWS EKS thật**
- Cần benchmark có kiểm soát, có artifacts, có observability evidence

### 1.3 Research questions

| RQ | Câu hỏi | Endpoint chính |
|---|---|---|
| RQ1 | Trong steady-state, Mode B có cải thiện p50/p95/p99 so với Mode A không? | p95, p99 |
| RQ2 | Dưới stress và connection churn, Mode B có xu hướng ổn định hơn không? | p99, error rate |
| RQ3 | Trên Mode B, CiliumNetworkPolicy tạo overhead bao nhiêu? | Δ p95/p99, Δ RPS |

### 1.4 Hypotheses

| H | Giả thuyết |
|---|---|
| H1 | Mode B giảm p95/p99 so với Mode A trong steady-state |
| H2 | Mode B có xu hướng ít spike hơn dưới connection churn |
| H3 | CiliumNetworkPolicy trên Mode B tạo overhead nhỏ, không làm thay đổi đáng kể p95/p99 |

### 1.5 Contributions
1. Benchmark thực trên **AWS EKS 1 cluster, 3 node m5.large**
2. So sánh **Mode A vs Mode B** ở S1 và S2
3. Đo **policy overhead riêng trên Mode B** ở S3
4. Kết hợp **Fortio + Prometheus/Grafana + Hubble** để có cả số đo và bằng chứng
5. Trình bày kết quả theo hướng **cẩn trọng, có kiểm soát biến, có threats to validity**

### 1.6 Thesis structure
- Chapter 2: Background & Related Work
- Chapter 3: System Design, Implementation & Methodology
- Chapter 4: Results & Analysis
- Chapter 5: Conclusion
- Appendix A–F

---

## Chương 2 — Background & Related Work
Chương này chỉ nói về **kiến thức nền và công trình liên quan**, không lẫn vào hạ tầng thực tế.

### 2.1 Linux packet processing basics
- netfilter framework
- iptables chains
- DNAT / SNAT
- conntrack
- tail latency trong networking benchmark

### 2.2 Kubernetes networking background
- Service, Endpoint, ClusterIP
- kube-proxy ở mức khái niệm
- CNI role
- Cilium là gì
- eBPF là gì
- kube-proxy replacement thay phần nào của service handling

### 2.3 Datapath comparison at concept level
Nên có 2 sơ đồ cạnh nhau:

#### Mode A
- client → veth → host netns → iptables / kube-proxy path → endpoint

#### Mode B
- client → veth → TC eBPF → service map → endpoint / policy map

**Lưu ý cách viết**
- Chỉ dùng như background mechanism
- Không biến thành claim “thesis chứng minh O(1) vs O(n)”

### 2.4 Hubble and policy observability
- Hubble relay / observe / verdict
- FORWARDED / DROPPED / ALLOWED / DENIED là gì
- Vai trò của Hubble trong thesis này:
  - supporting evidence
  - correctness evidence
  - đặc biệt cho S3

### 2.5 Related work

**Table 2.1 — Related Work Comparison**

| Nguồn | Môi trường | Nội dung chính | Điểm còn thiếu | Thesis này bổ sung |
|---|---|---|---|---|
| Cilium docs / benchmark notes | self-managed / cloud | benchmark Cilium | thiếu full methodology | benchmark có protocol rõ ràng, artifacts rõ ràng |
| Kubernetes / kube-proxy docs | docs | mô tả cơ chế | không có benchmark so sánh đầy đủ | benchmark A/B trên EKS |
| Tài liệu Hubble | docs | flow observability | không đo policy overhead thực nghiệm | thêm S3 policy overhead + evidence |
| Nguồn khác 1 | ... | ... | ... | ... |
| Nguồn khác 2 | ... | ... | ... | ... |

### 2.6 Scope boundary
**Trong scope**
- ClusterIP
- HTTP
- same-node ưu tiên
- S1 / S2 / S3 như đã định nghĩa

**Ngoài scope**
- cross-node full study
- NodePort
- gRPC
- policy complexity scaling
- multi-cluster

---

## Chương 3 — System Design, Implementation & Methodology
Chương này gom:
- hệ thống thực tế
- cách triển khai
- protocol benchmark
- fairness
- threats
- code / tracing analysis

### 3.1 System overview
- AWS region
- 1 EKS cluster
- 3 worker nodes `m5.large`
- 1 managed node group
- fixed node count
- autoscaling off during measurement

**Namespaces**
- `system-observability`
- `workload-bench`

**Table 3.1 — Infrastructure Specifications**

| Thành phần | Cấu hình |
|---|---|
| Region | ap-southeast-1 |
| Cluster count | 1 |
| Worker nodes | 3 |
| Instance type | m5.large |
| Kubernetes version | chốt theo artifact thật |
| Cilium version | chốt theo artifact thật |
| Topology | single AZ |
| Benchmark tool | Fortio |
| Monitoring | Prometheus + Grafana |
| Flow observability | Hubble |

### 3.2 Deployment topology
Nên có:
- 1 sơ đồ triển khai cluster
- 1 screenshot sau khi deploy workload

**Lưu ý kỹ thuật**
- Không viết “podAntiAffinity đảm bảo same-node”
- Nếu thực tế dùng `podAffinity` / `nodeAffinity` / node pinning thì mô tả đúng
- Nếu chỉ “ưu tiên same-node nhưng không đảm bảo tuyệt đối” thì ghi rõ

### 3.3 Mode definitions

#### Mode A
- kube-proxy active
- Cilium chạy ở chế độ không thay kube-proxy
- workload và monitoring giữ nguyên

#### Mode B
- Cilium kube-proxy replacement active
- kube-proxy disabled
- Hubble enabled

### 3.4 Fairness giữa hai mode
- Cùng cluster
- Cùng node type
- Cùng workload image
- Cùng duration
- Cùng load levels
- Chạy **tuần tự Mode A rồi Mode B**
- Reset namespace benchmark và workload giữa hai mode

### 3.5 Workload and toolchain
- Server: HTTP echo service
- Client: Fortio
- Service type: ClusterIP
- Requests/limits phải ghi rõ
- Payload giữ cố định giữa các run

**Table 3.2 — Workload Configuration**

| Thành phần | Image | Requests/Limits | Ghi chú |
|---|---|---|---|
| Server | hashicorp/http-echo | ghi theo artifact thật | endpoint đơn giản |
| Client | fortio/fortio | ghi theo artifact thật | benchmark trong cluster |
| Service | ClusterIP | — | target chính |
| Policy object | CiliumNetworkPolicy | — | chỉ dùng ở S3 |

### 3.6 Code analysis / tracing / logging

#### 3.6.1 Conceptual code-path analysis
- kube-proxy xử lý Service ở mức khái niệm ra sao
- Cilium service handling ở mức khái niệm ra sao
- Hubble event pipeline quan sát ở đâu

#### 3.6.2 Practical tracing / verification
Các lệnh verify thực tế:
- `kubectl get svc,endpoints`
- `cilium status`
- `hubble status`
- `hubble observe`
- `kubectl logs`
- các lệnh xác nhận mode, service mapping, policy enforcement

#### 3.6.3 Logging artifacts
Mỗi run lưu:
- `bench.log`
- `hubble.log`
- `metrics screenshot`
- `metadata.json`

### 3.7 Experimental design

#### 3.7.1 Independent variables
- datapath mode: A / B
- scenario: S1 / S2 / S3
- load level: L1 / L2 / L3
- policy state: OFF / ON, chỉ áp dụng ở S3 trên Mode B

#### 3.7.2 Dependent variables
- p50 / p95 / p99
- achieved RPS
- error rate
- Hubble verdict evidence cho S3

#### 3.7.3 Controlled variables
- cluster
- node type
- node count
- workload image
- request size
- run duration
- warm-up duration
- monitoring stack
- service type
- namespace reset procedure

**Table 3.3 — RQ to Metric Traceability**

| RQ | Scenario | Load | Primary metric | Supporting evidence |
|---|---|---|---|---|
| RQ1 | S1 | L1/L2/L3 | p95, p99 | RPS, node metrics |
| RQ2 | S2 | L2/L3 | p99, error rate | phase trend, node metrics |
| RQ3 | S3 | L2/L3 | Δ p95/p99, Δ RPS | Hubble verdicts |

### 3.8 Load calibration
Nguyên tắc chọn:
- L1: ổn định, ít lỗi
- L2: bắt đầu thấy tail latency
- L3: gần knee point nhưng chưa collapse

**Table 3.4 — Load Levels**

| Load | QPS | Concurrency | Mục đích |
|---|---|---|---|
| L1 | theo artifact thật | theo artifact thật | baseline ổn định |
| L2 | theo artifact thật | theo artifact thật | bắt đầu thấy khác biệt |
| L3 | theo artifact thật | theo artifact thật | gần ngưỡng |

### 3.9 Run protocol
- Warm-up: 30–60s
- Measurement window: 180s hoặc theo artifact thật
- Repeats: 3 runs per cell
- Rest giữa runs
- Reset / cleanup nếu cần

### 3.10 Scenarios

#### S1 — Steady-state service baseline
- Mode A vs Mode B
- ClusterIP
- load L1 / L2 / L3

#### S2 — Stress + connection churn
- Mode A vs Mode B
- load L2 / L3 là đủ, có L1 thì càng tốt
- giảm keep-alive / tăng churn theo cấu hình thực tế

#### S3 — Policy overhead
- **Mode B only**
- policy OFF → policy ON
- deny case riêng để lấy Hubble evidence

### 3.11 Statistics plan — rigorous but not over-sold

#### Primary reporting
- Mỗi cell có 3 runs
- Báo cáo chính dùng:
  - median p50 / p95 / p99
  - median RPS
  - error rate
  - % difference

#### Secondary inferential reporting
- Welch’s t-test dùng cho run-level comparison như chỉ báo hỗ trợ
- Holm-Bonferroni chỉ áp dụng cho **nhóm so sánh chính đã định trước**
- Hedges’ g báo effect size ở mức tham khảo

#### Sensitivity analysis
- Mann-Whitney U
- bootstrap CI
- để ở Appendix C

#### Cách diễn đạt
- S1: có thể kết luận mạnh hơn nếu kết quả nhất quán
- S2: dùng ngôn ngữ thận trọng hơn vì variance cao
- S3: kết luận theo mức overhead đo được, không suy rộng

### 3.12 Fairness controls

**Table 3.5 — Fairness Controls**

| Mối lo | Kiểm soát |
|---|---|
| Config drift | pin version, lưu Helm values, manifests, commit hash |
| Resource noise | fixed node count, same instance type |
| Autoscaling noise | autoscaling off |
| State carry-over | reset benchmark namespace, redeploy workload |
| Request mismatch | same payload, same Fortio parameters |
| Monitoring overhead | giữ monitoring cố định |

### 3.13 Threats to validity

**Table 3.6 — Internal Threats**

| Threat | Ảnh hưởng | Giảm thiểu |
|---|---|---|
| Sequential A → B | time-of-day bias | ghi rõ limitation, giữ khoảng cách thời gian ngắn |
| Single cluster | carry-over state | reset namespace, re-verify mode |
| CPU / scheduling noise | ảnh hưởng p99 | fixed resources, repeats |
| Monitoring overhead | ảnh hưởng latency | giữ stack cố định |
| Warm cache / connection state | làm lệch run | warm-up + rest |

**Table 3.7 — External Threats**

| Threat | Hạn chế suy rộng |
|---|---|
| Same-node priority | không đại diện đầy đủ cross-node |
| ClusterIP only | chưa đại diện NodePort / LoadBalancer |
| HTTP only | chưa đại diện gRPC / TCP long-lived |
| Simple policy | chưa đại diện policy complexity scaling |
| 1 cluster / 1 region | chưa đại diện đa vùng / đa cluster |

---

## Chương 4 — Results & Analysis
Chương này nên chia rõ:
- Results trước
- Analysis sau

### 4.0 Overview
- Tổng số run
- Tổng số artifacts
- Data completeness
- Error rates có nằm trong ngưỡng chấp nhận không

### 4.1 S1 — Steady-State Results

#### 4.1.1 Setup
- L1 / L2 / L3
- duration
- repeats
- topology

#### 4.1.2 Results tables
- **Table 4.1 — S1 L1**
- **Table 4.2 — S1 L2**
- **Table 4.3 — S1 L3**

Mỗi bảng gồm:
- p50
- p95
- p99
- RPS
- Δ%
- p-value nếu có
- effect size nếu có

### 4.2 S3 — Policy Overhead Results

#### 4.2.1 Setup
- Mode B only
- OFF vs ON
- deny case

#### 4.2.2 Results table
- **Table 4.4 — S3 policy overhead**

#### 4.2.3 Hubble evidence
- flow snippets
- verdict counts
- deny case correctness

### 4.3 S2 — Stress + Connection Churn Results

#### 4.3.1 Setup
- phase definition
- churn configuration
- L2 / L3

#### 4.3.2 Results tables
- **Table 4.5 — S2 L2**
- **Table 4.6 — S2 L3**
- **Table 4.7 — Phase-level p99 summary**

### 4.4 Consolidated comparison
- **Table 4.8 — Full summary across S1 / S2 / S3**

### 4.5 Artifact provenance
- **Table 4.9 — Artifact provenance**
- Gắn số liệu với:
  - file path
  - timestamp
  - commit hash

### 4.6 Analysis for RQ1
Cách viết:
- nêu xu hướng
- nêu mức cải thiện
- giải thích bằng cơ chế ở mức hợp lý
- không nói như thể mechanism đã được đo trực tiếp

### 4.7 Analysis for RQ2
Cách viết:
- nhấn mạnh xu hướng
- nếu variance cao, nói rõ variance cao
- tránh khẳng định tuyệt đối nếu đa số test không significant

**Mẫu ngôn ngữ nên dùng**
> Dữ liệu S2 cho thấy xu hướng Mode B có p99 thấp hơn, nhưng độ biến thiên giữa các run còn lớn; vì vậy kết luận về độ ổn định dưới churn nên được hiểu là bằng chứng gợi ý, chưa phải khẳng định mạnh.

### 4.8 Analysis for RQ3
Cách viết:
- S3 là Mode B only
- tập trung vào overhead policy
- Hubble dùng để chứng minh policy hoạt động đúng

### 4.9 Answer summary
- **Table 4.10 — RQ answer summary**

| RQ | Trả lời | Mức tin cậy | Ghi chú |
|---|---|---|---|
| RQ1 | Yes / likely yes | high / medium | dựa trên S1 |
| RQ2 | inconclusive trend / moderate support | medium / low | variance cao |
| RQ3 | overhead nhỏ / negligible in tested setup | medium / high | chỉ trong setup này |

### 4.10 Optional resource overhead
Nếu có dữ liệu Prometheus tốt:
- kube-proxy CPU vs cilium-agent CPU
- node CPU / softirq
- drops / retransmits

### 4.11 Sensitivity analysis
Main text chỉ tóm tắt:
- Mann-Whitney và bootstrap không đảo chiều kết luận chính
- chi tiết ở Appendix C

---

## Chương 5 — Conclusion

### 5.1 Summary of findings
Viết theo 3 RQ:
- RQ1
- RQ2
- RQ3

### 5.2 Practical implications
- Khi nào nên cân nhắc Mode B
- Khi nào baseline vẫn chấp nhận được
- Policy overhead trong setup đơn giản là nhỏ

### 5.3 Limitations
4 limitation bắt buộc:
1. **Sequential 1-cluster design**
2. **Same-node priority / limited topology scope**
3. **S3 chỉ đo trên Mode B với CiliumNetworkPolicy**
4. **HTTP ClusterIP scope only**

### 5.4 Future work
- cross-node study
- NodePort / external traffic
- policy complexity scaling
- 2-cluster parallel A/B
- Hubble overhead isolation

---

# 2. Appendices

## Appendix A — Infrastructure
- Terraform variables
- cluster specs
- version table
- Helm values summary

## Appendix B — Calibration
- calibration sweep table
- chọn L1 / L2 / L3
- calibration chart

## Appendix C — Statistical Methods
- unit of analysis
- Welch’s t-test
- Holm-Bonferroni
- Hedges’ g
- Mann-Whitney
- bootstrap CI
- sample size caveat

## Appendix D — Raw Data
- CSV summaries
- raw result file mapping

## Appendix E — Figures
- all figures
- LaTeX export table nếu có

## Appendix F — Scripts & Configuration
- benchmark scripts
- analysis scripts
- workload manifests
- policy manifest

---

# 3. Must-have và Nice-to-have

## 3.1 Must-have tables
1. Table 2.1 — Related work comparison
2. Table 3.1 — Infrastructure specifications
3. Table 3.3 — RQ to metric traceability
4. Table 3.4 — Load levels
5. Table 3.5 — Fairness controls
6. Table 3.6 / 3.7 — Threats to validity
7. Table 4.1 / 4.2 / 4.3 — S1 results
8. Table 4.4 — S3 policy overhead
9. Table 4.5 / 4.6 / 4.7 — S2 results
10. Table 4.8 — Full comparison
11. Table 4.10 — RQ answer summary
12. Table W1 — Workload distribution

## 3.2 Nice-to-have tables
- artifact provenance chi tiết
- cluster versions mở rộng
- sensitivity summary
- appendix-only raw run inventory

## 3.3 Must-have figures
1. Datapath comparison diagram
2. Deployment topology figure
3. Calibration curve
4. S1 A/B latency chart
5. S2 phase analysis chart
6. S3 policy overhead chart
7. Hubble evidence figure
8. Consolidated comparison chart

## 3.4 Nice-to-have figures
- p99 box plot
- error rate chart
- Grafana dashboard recap figure
- detailed delta % bar chart

---

# 4. Workloads table phân công thành viên

**Table W1 — Workload Distribution**

| Thành viên | Vai trò chính | Nhiệm vụ cụ thể | Artifact đầu ra |
|---|---|---|---|
| Thành viên 1 | Infra & EKS | Terraform, VPC, EKS, node group, kubeconfig, version freeze | Terraform repo, cluster spec table |
| Thành viên 2 | Cilium & Hubble | Cài Cilium, verify Mode A/Mode B, Hubble observe, policy setup | Helm values, cilium/hubble logs, Hubble evidence |
| Thành viên 3 | Benchmark & Analysis | Fortio workloads, calibration, benchmark scripts, tổng hợp số liệu, chart, viết Chương 4 | scripts, CSV summary, figures, results chapter |

**Nếu nhóm có 2 người**
- Người 1: infra + cilium
- Người 2: benchmark + analysis + report integration

Có thể thêm cột:
- `% đóng góp`

---

# 5. Bộ biểu đồ

## 5.1 Must-have
- **Figure 2.1** — Datapath comparison (Mode A vs Mode B)
- **Figure 3.1** — EKS deployment topology
- **Figure 3.2** — Calibration curve
- **Figure 4.1** — S1 latency comparison
- **Figure 4.2** — S3 policy overhead
- **Figure 4.3** — Hubble verdict / deny evidence
- **Figure 4.4** — S2 phase-level p99
- **Figure 4.5** — Consolidated comparison summary

## 5.2 Nice-to-have
- **Figure 4.6** — Error rate comparison
- **Figure 4.7** — p99 box plot
- **Figure 4.8** — Grafana node metrics snapshot
- **Figure 4.9** — Delta % bar chart

---

# 6. Thứ tự viết khuyến nghị

1. **Chương 2 — Background & Related Work**
2. **Chương 3 — System Design, Implementation & Methodology**
3. **Chương 4 — Results & Analysis**
4. **Chương 1 — Introduction**
5. **Chương 5 — Conclusion**
6. **Appendix A–F**
7. **Cross-references, list of figures, list of tables, proofreading**

---

# 7. Checklist trước khi bắt đầu viết

- [ ] Toàn thesis dùng thống nhất: **1 cluster, 3 × m5.large**
- [ ] Toàn thesis dùng thống nhất: **Mode A vs Mode B cho S1/S2; S3 là Mode B only**
- [ ] Toàn thesis dùng thống nhất metric chính: **p50 / p95 / p99**
- [ ] Không còn câu nào nói sai về **podAntiAffinity = same-node**
- [ ] Chương 2 chỉ là **background + related work**
- [ ] Chương 3 chứa **system design + implementation + methodology**
- [ ] Có mục **code analysis / tracing / logging**
- [ ] Có **fairness controls** và **threats to validity**
- [ ] Có **Workloads table phân công thành viên**
- [ ] Có bộ **must-have figures**
- [ ] Statistical section viết **có rigor nhưng không over-claim**
- [ ] Kết luận chỉ áp dụng **trong phạm vi setup đã đo**