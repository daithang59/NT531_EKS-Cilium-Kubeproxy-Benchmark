

## KẾ HOẠCH ĐỒ ÁN – NHÓM 12

NT531 – Đánh giá hiệu năng hệ thống mạng máy tính


Đề tài: So sánh hiệu năng Kubernetes Service datapath giữa kube-
proxy và Cilium eBPF kube-proxy replacement trên AWS EKS


Mục lục
- Tổng quan đề tài .................................................................................................................... 3
1.1. Mục tiêu .......................................................................................................................... 3
1.2. Câu hỏi nghiên cứu và giả thuyết ................................................................................... 3
- Phạm vi và giả định ............................................................................................................... 4
2.1. Phạm vi đo lường (scope) ............................................................................................... 4
2.2. Ngoài phạm vi (out of scope) ......................................................................................... 4
2.3. Giả định và ràng buộc ..................................................................................................... 4
- Kiến trúc triển khai (01 cluster) ............................................................................................. 4
3.1. Thành phần ..................................................................................................................... 5
3.2. Hai chế độ so sánh .......................................................................................................... 5
3.3. Sơ đồ topology triển khai ................................................................................................ 5
- Thiết kế thí nghiệm (Experiment design) .............................................................................. 7
4.1. Biến độc lập, biến phụ thuộc .......................................................................................... 7
4.2. Kịch bản và mức tải ........................................................................................................ 7
4.3. Run protocol (chuẩn chạy để tái lập) .............................................................................. 8
4.4. Thu thập dữ liệu (metrics + evidence) ............................................................................ 8
4.5. Quy tắc công bằng và kiểm soát biến (fairness rules) .................................................... 8
- Threats to validity và cách giảm thiểu ................................................................................... 9
- Công cụ và cấu hình đề xuất ................................................................................................ 10
6.1. Stack .............................................................................................................................. 10
6.2. Bảng thông số cấu hình tối thiểu cần chốt .................................................................... 10
- Artifacts và cấu trúc lưu trữ kết quả .................................................................................... 10
- Phân tích và trình bày kết quả ............................................................................................. 11
- Kế hoạch tiến độ (Milestones) ............................................................................................. 11
- Tài liệu tham khảo ............................................................................................................. 12



- Tổng quan đề tài
− Trong   Kubernetes,   kube-proxy  chịu  trách  nhiệm  hiện  thực  cơ  chế  Service
(ClusterIP/NodePort/LoadBalancer)  bằng  iptables/ipvs.  Cilium  cung  cấp  lựa  chọn
thay  thế  kube-proxy  dựa  trên  eBPF  (kube-proxy  replacement),  hướng  tới  giảm
overhead, cải thiện tail latency và tăng khả năng quan sát (observability) thông qua
## Hubble.
− Đồ án này xây dựng 01 cụm AWS EKS và thực hiện benchmark có kiểm soát để so
sánh datapath Service giữa hai chế độ: Mode A (kube-proxy  baseline)  và  Mode  B
(Cilium eBPF kube-proxy replacement, tắt kube-proxy).
1.1. Mục tiêu
− Đánh giá định lượng sự khác biệt về độ trễ (p50/p95/p99), thông lượng (RPS/QPS), tỉ
lệ lỗi, và đặc tính ổn định (jitter/đuôi phân phối) của Kubernetes Service datapath khi
dùng kube-proxy so với Cilium eBPF.
1.2. Câu hỏi nghiên cứu và giả thuyết
Câu hỏi nghiên cứu (RQ):
- RQ1: Ở cùng cấu hình hạ tầng và workload, Mode B có cải thiện p95/p99 so với Mode
A không?
- RQ2: Dưới tải cao và/hoặc connection churn, Mode B có giữ ổn định (ít error, ít spike
latency) tốt hơn Mode A không?
- RQ3:  Khi  bật  NetworkPolicy  và  quan  sát  bằng  Hubble,  overhead  lên
latency/throughput thay đổi như thế nào ở mỗi mode?
Giả thuyết (H):
- H1: Mode B giảm tail latency (p95/p99) so với Mode A trong kịch bản steady load.
- H2: Mode B chịu tải connection churn tốt hơn (ít dao động và ít lỗi hơn) do giảm phụ
thuộc vào iptables ruleset lớn.
- H3: Bật NetworkPolicy + observability (Hubble) tạo overhead, nhưng Mode B vẫn giữ
lợi thế ở tail latency.

- Phạm vi và giả định
2.1. Phạm vi đo lường (scope)
Chốt phạm vi chính (primary):
- Đo datapath Service kiểu ClusterIP (east-west, nội bộ cluster), vì đây là đường đi phổ
biến cho microservices.
- Tập trung vào HTTP (Fortio) để đo latency distribution và RPS ổn định.
Phạm vi mở rộng (optional nếu còn thời gian):
- So  sánh  thêm  NodePort  (north-south vào node) để đánh giá khác biệt node-local  vs
cross-node.
- So sánh thêm 2 kiểu service routing: same-node (client và server cùng node) và cross-
node.
2.2. Ngoài phạm vi (out of scope)
- Không tối ưu chi phí/giá thành AWS; chỉ tập trung đo hiệu năng.
- Không đánh giá đa cụm (multi-cluster), mesh nâng cao, hoặc Gateway API.
- Không benchmark dữ liệu lớn/streaming; payload giữ ổn định để đo datapath.
2.3. Giả định và ràng buộc
- Chỉ dùng 01 cluster duy nhất, chạy lần lượt Mode A và Mode B. Mỗi mode chạy nhiều
lần để giảm sai số.
- Một AZ để giảm nhiễu mạng liên AZ.
- Tắt/khóa autoscaling trong lúc đo (Cluster Autoscaler / HPA), giữ số node cố định.
- Giới hạn tài nguyên (requests/limits) cho client/server để tránh CPU throttling làm sai
số.
- Kiến trúc triển khai (01 cluster)
− Triển khai 01 cụm AWS EKS trong 01 VPC, 01 Availability Zone, với worker nodes
nằm trong private subnet. Benchmark client và workload server chạy trên các worker

nodes.  Thu  thập  metrics bằng  Prometheus/Grafana  và  luồng  mạng  bằng  Hubble
(Cilium).
3.1. Thành phần
- EKS Control Plane (managed): điều phối Kubernetes API.
- Managed  Node  Group  (workers):  chạy  pod  benchmark  client,  server,  cilium-agent,
(kube-proxy ở Mode A).
- Cilium CNI: datapath eBPF; Hubble để quan sát flow.
- Prometheus + Grafana: thu thập và hiển thị metrics (CPU, mem, network).
- Fortio (benchmark): tạo tải HTTP, xuất thống kê latency distribution và RPS.
3.2. Hai chế độ so sánh
Mode Cấu hình chính Mục đích
## Mode A
kube-proxy bật (iptables hoặc
ipvs tùy default); Cilium
chạy ở chế độ bình thường
Baseline – so sánh truyền
thống
## Mode B
Cilium eBPF kube-proxy
replacement; kube-proxy tắt
So sánh datapath eBPF thay
thế kube-proxy
− Lưu  ý:  Hai  mode  dùng  cùng  loại  node,  cùng  namespace/workload,  cùng  benchmark
config. Chỉ thay đổi datapath Service.
3.3. Sơ đồ topology triển khai

Hình 1 – Topology triển khai tham chiếu (EKS + private workers + monitoring +

benchmark).
− Ghi chú: Trong thực nghiệm, chỉ thay đổi datapath Service giữa Mode A và Mode B;
các thành phần còn lại giữ nguyên.
- Thiết kế thí nghiệm (Experiment design)
4.1. Biến độc lập, biến phụ thuộc
Biến độc lập (independent variables):
- Datapath mode: Mode A vs Mode B
- Kịch bản: S1 (baseline), S2 (stress), S3 (policy + observability)
- Mức tải: L1/L2/L3 (tăng dần concurrency hoặc QPS)
- Vị trí traffic: same-node vs cross-node
Biến phụ thuộc (dependent variables):
- Latency distribution: p50, p90, p95, p99, max
- Throughput: RPS/QPS đạt được
- Error rate: % non-2xx hoặc timeout
- Resource overhead: CPU/mem của datapath components (cilium-agent, kube-proxy)
4.2. Kịch bản và mức tải
Kịch bản Mục tiêu Mô tả chạy Kết quả kỳ vọng
S1 – Baseline Đo hiệu năng cơ bản
Steady load; keep-
alive ON; payload cố
định
So sánh p95/p99 và
RPS trong điều kiện
ổn định
## S2 – Stress
Tìm ngưỡng và đánh
giá tail under
pressure
S2a: tăng tải tìm
knee point; S2b:
connection churn
## (keep-alive
OFF/Connection:
close)
Mode B kỳ vọng ổn
định hơn ở p99/error
khi churn

S3 – Policy/Obs
Đánh giá overhead
policy + quan sát
NetworkPolicy
allow-list + thêm
deny case; bật
Hubble flow export
Chứng minh
allow/deny và đo
overhead lên
latency/RPS
Mức tải (Load levels):
- L1 (nhẹ): concurrency ~ 10–20 hoặc QPS thấp
- L2 (trung bình): concurrency ~ 50–100
- L3 (nặng): concurrency ~ 200+ hoặc đến khi error bắt đầu tăng đáng kể
Giá trị cụ thể sẽ được tinh chỉnh sau bước smoke test để đảm bảo server không phải là nút cổ
chai.
4.3. Run protocol (chuẩn chạy để tái lập)
- Mỗi (Mode, Scenario, Load) chạy ít nhất 3 lần (run1–run3).
- Warm-up trước mỗi run: 30–60 giây (không lấy số liệu).
- Measurement window: 3–5 phút/run (tùy kịch bản).
- Rest giữa các run: 60–120 giây; xóa pod benchmark client (hoặc restart) để tránh state
còn lại.
- Giữ payload cố định (ví dụ 256B–1KB), timeout cố định, số kết nối/threads do Fortio
cấu hình.
4.4. Thu thập dữ liệu (metrics + evidence)
- Fortio output: latency histogram + p50/p95/p99 + RPS + error.
- Prometheus: CPU/mem của node và pods (cilium-agent, kube-proxy, server), network.
- Hubble: flow logs để chứng minh policy allow/deny/drop và quan sát path.
- Metadata: commit hash, helm values, kubectl manifests, thời gian chạy, thông số
## Fortio.
4.5. Quy tắc công bằng và kiểm soát biến (fairness rules)
- Cùng 01 cluster, cùng instance type và số node; chạy lần lượt Mode A rồi Mode B; có
thể đảo thứ tự theo ngày để giảm bias.

- Trước khi chuyển mode: giữ nguyên addon; xóa namespace benchmark và triển khai
lại sạch.
- Tắt autoscaling khi đo; pin node selection (nodeSelector/affinity) để kiểm soát same-
node vs cross-node.
- Giữ cùng phiên bản Kubernetes/EKS, cùng version Cilium, cùng image server/client.
- Ghi rõ tất cả thông số trong artifact metadata để tái lập.
- Threats to validity và cách giảm thiểu
Nguy cơ Giảm thiểu
Nhiễu do scheduling (pod placement thay đổi)
Dùng nodeSelector/affinity, cố định
client/server lên node cụ thể; chạy nhiều lần và
lấy median/mean + CI.
Nhiễu nền AWS / noisy neighbor
Dùng 1 AZ; ghi lại thời gian chạy; tăng số lần
lặp nếu cần.
Bottleneck tại server (CPU throttling) thay vì
datapath
Set requests/limits hợp lý; theo dõi CPU/mem;
scale replicas nếu cần.
Overhead monitoring làm ảnh hưởng kết quả
Giữ monitoring cố định; coi S3 là kịch bản
riêng; tránh so sánh chéo S1 với S3.
State còn lại (conntrack cache, DNS cache,
warm caches)
Warm-up chuẩn; rest giữa runs; có thể restart
namespace benchmark.
Config drift
Pin version bằng IaC/Helm; lưu
values/manifests + commit hash trong artifacts.
kube-proxy và eBPF chạy song song khi chuyển
Mode A → Mode B (NAT table conflict)
Chuyển mode: PHẢI tắt kube-proxy DaemonSet
trước khi bật kubeProxyReplacement=true.
Xem runbook §3.

- Công cụ và cấu hình đề xuất
## 6.1. Stack
- Infrastructure: Terraform (VPC, EKS, Node Group).
- CNI: Cilium + Hubble (Helm).
- Benchmark: Fortio (client) + HTTP echo server.
- Monitoring: Prometheus + Grafana (Helm), optional node-exporter.
- Automation/scripts: bash + kubectl + helm; script thu thập evidence.
6.2. Bảng thông số cấu hình tối thiểu cần chốt
Hạng mục Giá trị (đề xuất) Ghi chú
Số node 3 workers
Dễ tạo traffic cross-node; tối
thiểu 2
Instance type T3.large
Nên dùng loại không
burstable nếu có (tránh CPU
credits)
K8s version 1.34 Pin một version
Cilium version 1.18.7 Pin version + values.yaml
Service type test ClusterIP Primary scope
Payload 256B–1KB Giữ cố định giữa các runs
Duration/run 3–5 phút Tùy S1/S2/S3
- Artifacts và cấu trúc lưu trữ kết quả
Artifacts cần nộp:
- Mã nguồn + IaC (Terraform), Helm values, manifests.
- Dữ liệu benchmark thô (raw logs) cho từng run.
- Metrics export (query results) + ảnh dashboard.

- Hubble flows minh chứng allow/deny/drop (S3).
- Báo cáo cuối: setup, bảng/biểu đồ, phân tích, kết luận.
Cấu trúc thư mục kết quả đề xuất:
results/
## <timestamp>/
mode-A/
S1/L1/run1/{fortio.json, fortio.txt, hubble.log, prom.json, meta.json}
## ...
mode-B/
S1/L1/run1/{...}
## ...
- Phân tích và trình bày kết quả
- Thống kê mô tả cho mỗi (Mode, Scenario, Load): median/mean, p95/p99, min/max,
error rate.
- Biểu đồ: p95/p99 theo mức tải; RPS theo mức tải; error rate theo mức tải.
- So sánh Mode A vs Mode B theo từng kịch bản (S1/S2/S3) riêng biệt.
- Kết luận dựa trên RQ/H; nêu rõ điều kiện mà lợi thế xuất hiện (steady vs churn vs
policy).
- Kế hoạch tiến độ (Milestones)
Mốc Nội dung Đầu ra
## M0
Khởi tạo repo + chuẩn hóa
cấu trúc + CI cơ bản
Repo, README, hướng dẫn
run
## M1
Terraform dựng VPC + EKS
+ node group
Cluster chạy ổn định
## M2
Cài Cilium (Mode A) +
Hubble + smoke test
Service ClusterIP hoạt động

## M3
Cài Prometheus/Grafana,
dashboard tối thiểu
Metrics thu thập OK
## M4
Thiết lập benchmark Fortio
+ workload server
Chạy được S1 L1
## M5
Chạy S1/S2 đầy đủ ở Mode
A (>=3 repeats)
Raw results mode-A
## M6
## Chuyển Mode B (kube-
proxy replacement) + smoke
test
Mode-B ổn định
## M7
Chạy S1/S2/S3 đầy đủ ở
Mode B (>=3 repeats)
Raw results mode-B
## M8
Phân tích + vẽ biểu đồ + viết
report + hoàn thiện nộp
Báo cáo + artifacts
- Tài liệu tham khảo
- Kubernetes Documentation – Service, kube-proxy (iptables/ipvs).
- Cilium Documentation – kube-proxy replacement, Hubble.
- Fortio Documentation – load testing and latency histogram.