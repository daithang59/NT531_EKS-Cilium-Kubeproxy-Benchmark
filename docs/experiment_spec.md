# Experiment Spec — Đánh giá hiệu năng datapath mạng Kubernetes
**So sánh Mode A (kube-proxy baseline) vs Mode B (Cilium eBPF kube-proxy replacement)**
> Mục tiêu của spec này là làm cho thí nghiệm **reproducible**, **fair**, có **bằng chứng** và có thể **giải thích cơ chế** (không chỉ "ra số").

---

## 1) Mục tiêu (Objectives)
1. Đo và so sánh hiệu năng đường đi mạng (datapath) cho traffic nội bộ Kubernetes:
   - Service-to-Service qua **ClusterIP**
   - Hành vi khi **tải cao** và **connection churn**
   - Overhead khi bật **NetworkPolicy** (off → on)
2. Trả lời được 3 câu hỏi chính:
   - Mode B có cải thiện **tail latency (p95/p99)** so với Mode A không?
   - Ở tải cao và churn, mode nào **ổn định** hơn (error rate/timeout)?
   - Khi bật policy, overhead tăng thế nào và có **evidence** về enforcement?

---

## 2) Phạm vi và giả thuyết (Scope & Hypotheses)
### Phạm vi
- In-cluster traffic (client pod → Service → server pods)
- Không đo Internet ingress/egress hay cross-region.
- Focus vào datapath Service + Policy.

### Giả thuyết
- **Mode B** (eBPF datapath) có thể giảm overhead/giảm tail latency khi tải cao.
- **Mode B** có thể nhạy với cấu hình (kube-proxy replacement, policy), và overhead observability (Hubble) cần được kiểm soát.

---

## 3) Môi trường thực nghiệm (Environment)
### 3.1 Hạ tầng (AWS/EKS)
- Platform: **AWS EKS**
- AZ: **1 AZ** (giảm nhiễu cross-AZ; ghi rõ vì sao trong Threats to validity)
- Node group: **Managed Node Group**, cố định **min=desired=max=3**, không autoscale khi đo
- Instance type: **m5.large (2 vCPU, 8GB RAM)** đồng nhất giữa các node — non-burstable, CPU ổn định
- Không chạy workload ngoài scope benchmark trong lúc đo

> Lưu ý: dùng m5.large (non-burstable) để loại bỏ CPU credit exhaustion như một biến nhiễu.

### 3.2 Thành phần trong cluster
- **Mode A (Baseline)**: kube-proxy mặc định EKS (iptables/ipvs tùy cấu hình)
- **Mode B (eBPF)**: Cilium kube-proxy replacement (kube-proxy-free) + Hubble
- Observability: Prometheus + Grafana (kube-prometheus-stack hoặc tương đương)
- Benchmark tool: Fortio (in-cluster) *(có thể thay bằng k6 nếu bạn chọn k6)*

### 3.3 Workload benchmark (tối giản nhưng đúng bài)
- `server`: HTTP echo/httpbin
  - replicas cố định
  - có requests/limits (để tránh noisy scheduling)
- `client`: pod chạy Fortio
- Service type: **ClusterIP**
- Namespace: `workload-bench`

---

## 4) Biến thực nghiệm & tiêu chí đánh giá (Variables & Metrics)
### 4.1 Biến độc lập (Independent variables)
- **Mode**: A vs B
- **Scenario**: S1, S2, S3 (mục 6)
- **Load level**: L1, L2, L3 (được calibrate trước)

### 4.2 Metric bắt buộc (Primary metrics)
- Latency: **p50 / p95 / p99** (ms)
- Throughput/RPS
- Error rate (HTTP errors, timeouts, connection errors)

### 4.3 Metric để giải thích cơ chế (Explainability metrics)
Tối thiểu chọn 1–2 nhóm sau (đủ để "giải thích", không cần tham):
- Node CPU breakdown: user/system/**softirq**
- Pod CPU/memory (server/client/cilium)
- Network drops/retransmits (nếu có)
- **Hubble flows** (Mode B): verdict FORWARDED/DROPPED, drops, policy decisions

---

## 5) Kiểm soát nhiễu (Controls) + Fairness Checklist
### 5.1 Controls (nguyên tắc)
- Cố định: số node, instance type, replicas, resource requests/limits
- Benchmark **in-cluster** (giảm nhiễu Internet)
- Có warm-up, duration cố định, và lặp **≥ 3 runs/case**
- Không nâng cấp/đổi cấu hình giữa các runs trong cùng mode
- Không chạy 2 mode đồng thời trên cùng hạ tầng (tránh nhiễu tài nguyên)

### 5.2 Fairness checklist (đưa vào report/slide để chống bắt bẻ)
Giữ **giống nhau** giữa Mode A và Mode B:
- EKS/K8s version, node AMI/kernel
- Instance type, số node, AZ, scaling policy (fixed 3 nodes)
- Workload YAML: replicas, requests/limits, image, env
- Fortio params: duration, warm-up, concurrency/QPS, payload size
- Monitoring stack (Prometheus/Grafana) cấu hình tương đương
- Cách thu thập artifacts và cách tổng hợp số liệu

Chỉ khác nhau:
- Datapath: kube-proxy (A) vs Cilium eBPF kube-proxy replacement (B)
- (Nếu có) policy engine khác biệt do Cilium (nhưng phải đảm bảo semantics tương đương khi so sánh S3)

---

## 6) Kịch bản đo (Scenarios)
### S1 — Service Baseline
Mục đích: baseline latency/throughput khi chỉ đi qua Service.
- Policy: off hoặc allow-all
- Kỳ vọng: error rất thấp, tail latency ổn định

### S2 — High-load + Connection Churn
Mục đích: stress ở tải cao, nhiều connection mở/đóng liên tục.
- Tăng concurrency + QPS
- Có churn (ví dụ request ngắn, nhiều kết nối mới; keepalive có thể off tùy kịch bản)
- Kỳ vọng: tail latency (p95/p99) tách biệt rõ, error rate có thể tăng

### S3 — NetworkPolicy Overhead (off → on)
Mục đích: đo overhead khi bật policy enforcement và chứng minh enforcement có thật.
- Bước 1: policy off/allow-all → chạy như S1
- Bước 2: apply policy → chạy lại cùng tải

**Nâng độ khó vừa đủ (khuyến nghị để ăn điểm)**
- **S3a (simple)**: 1 policy rule đơn giản
- **S3b (complex)**: policy nhiều rule hơn (vd 10–20 rule hoặc nhiều selectors)
→ giúp bạn thấy "overhead tăng theo complexity" và viết phân tích tốt hơn.

---

## 7) Load levels (L1/L2/L3) + Calibration plan
### 7.1 Định nghĩa load levels
- **L1 (Light)**: ổn định, gần như 0 error, p99 thấp
- **L2 (Medium)**: xuất hiện tail latency rõ nhưng chưa gãy
- **L3 (High)**: gần ngưỡng gãy (tail tăng mạnh), error vẫn trong mức chấp nhận

### 7.2 Calibration (bắt buộc làm trước khi chạy chính thức)
Mục tiêu: chọn L1/L2/L3 bằng dữ liệu (tránh "chọn cảm tính").

**Cách thực hiện (dùng script tự động):**
```bash
# Chạy calibration sweep trên Mode A (baseline) trước
MODE=A REPEAT=2 ./scripts/calibrate.sh

# Sau khi xem bảng khuyến nghị, cập nhật common.sh:
#   L1_QPS=<gợi ý>   L1_CONNS=<gợi ý>
#   L2_QPS=<gợi ý>   L2_CONNS=<gợi ý>
#   L3_QPS=<gợi ý>   L3_CONNS=<gợi ý>
```

Script `calibrate.sh` tự động:
- Sweep QPS từ thấp → cao (50→1500 theo mặc định, tùy chỉnh được)
- Đo p50/p90/p99/p999/error rate tại mỗi điểm
- Đưa ra khuyến nghị L1/L2/L3 dựa trên tiêu chí:
  - **L1:** error < 0.1% AND p99 < 5ms → ổn định, tail thấp
  - **L2:** error < 1% AND p99 < 20ms → tail visible nhưng chưa bão hòa
  - **L3:** error < 5% → gần ngưỡng bão hòa
- Xuất file `results/calibration/mode=A_kube-proxy/calibration_<ts>.csv` và `.txt`

Output calibration cần đưa vào **report/appendix/**: bảng số và biểu đồ p99 vs QPS.

**Deliverable calibration**
- 1 hình: load (QPS) → p99 latency
- 1 hình: load (QPS) → error rate
- Bảng tham số L1/L2/L3 (QPS, conns, threads, duration)

---

## 8) Methodology — Quy trình chạy chuẩn cho mỗi case
Mỗi tổ hợp: **(Mode × Scenario × Load level)** chạy theo pipeline:

1. **Pre-check**
   - `kubectl get nodes/pods` đảm bảo healthy
   - Mode B: `cilium status`, `hubble status` OK
   - Prometheus targets UP
2. **Warm-up**
   - chạy 30–60s warm-up (không ghi số liệu chính thức)
3. **Measurement**
   - duration cố định (ví dụ 120s)
   - ghi output Fortio/k6 (latency quantiles, RPS, errors)
4. **Repeat**
   - lặp **≥ 3 runs**
   - nghỉ ngắn 30–60s giữa runs (tránh nhiệt/credit/noise)
5. **Collect artifacts**
   - thu logs/metrics snapshot theo mục 9

---

## 9) Artifacts & Evidence (bằng chứng bắt buộc)
### 9.1 Cấu trúc thư mục
`results/<mode>/<scenario>/<load>/<run_timestamp>/`

### 9.2 Tối thiểu phải có (per run)
- `bench.log` : stdout Fortio/k6
- `metadata.json` : thông tin cấu hình run (mode/scenario/load/params/versions/timestamps)
- `hubble.log` : flows/verdict (Mode B; S3 đặc biệt quan trọng)
- `grafana/` : ảnh dashboard (latency/RPS + node CPU/softirq + network)
- `manifests/` : YAML thực tế đã apply (deploy/service/policy) hoặc `kubectl get ... -o yaml`

> Thầy thường tin kết quả khi bạn có "bench output + dashboard + flow evidence".

---

## 10) Tổng hợp số liệu & so sánh (Aggregation & Comparison)
### 10.1 Tổng hợp
- Với mỗi (Mode, Scenario, Load):
  - lấy **median** của p50/p95/p99, RPS, error rate từ ≥3 runs
  - ghi thêm **min–max** (hoặc std) để thể hiện biến động
- **Confidence interval (CI):** dùng Student's t-distribution cho mỗi metric, báo cáo **95% CI** (mean ± CI)
- **Không chỉ dùng mean/median đơn lẻ** — CI cho biết độ tin cậy của kết quả

### 10.2 Kiểm định thống kê (Statistical Testing)
**Bắt buộc** trước khi kết luận A tốt hơn B hoặc ngược lại:

**Welch's t-test** (two-tailed, α = 0.05):
- So sánh từng metric (p50/p90/p99/error rate) giữa Mode A và Mode B
- p-value < 0.05 → chênh lệch có **ý nghĩa thống kê**
- p-value ≥ 0.05 → chênh lệch **không có ý nghĩa**, không nên kết luận

**Công thức tính:**
- t = (μ_A − μ_B) / √(σ²_A/n_A + σ²_B/n_B)
- df = Welch-Satterthwaite approximation
- p-value từ t-distribution (two-tailed)

**Dùng script phân tích tự động:**
```bash
python3 scripts/analyze_results.py
# Output:
#   - Bảng tổng hợp: median, mean ± 95% CI, stdev cho mỗi (mode × scenario × load)
#   - Bảng so sánh A vs B: Δ%, p-value, significance (✓/✗)
#   - CSV: aggregated_summary.csv, comparison_AB.csv
```

### 10.3 Cách đọc kết quả so sánh
| Δ% p99 | p-value | Kết luận |
|--------|---------|----------|
| B nhanh hơn A 5%, thu hẹp CI | < 0.05 | **Chắc chắn** — Mode B cải thiện p99 |
| B nhanh hơn A 2%, CI rộng | < 0.05 | **Có xu hướng** — cần thêm runs |
| B nhanh hơn A 1%, CI chồng lấn | > 0.05 | **Không rõ ràng** — nhiễu cao |
| B chậm hơn A | < 0.05 | Mode B có overhead cao hơn đáng kể |


### 10.2 So sánh A vs B
- Tính chênh lệch:
  - Δ% p99 (quan trọng nhất), Δ% p95, Δ% p50
  - Δ% RPS / throughput
  - Δ error rate
- Kèm giải thích bằng evidence:
  - node CPU/softirq, saturation signals
  - drops/retransmits (nếu có)
  - Hubble verdict (đặc biệt ở S3)

---

## 11) Appendix — Versions & Config (bắt buộc ghi rõ)
Tạo 1 bảng (1 trang) trong report/appendix:
- EKS/K8s version: `...`
- Node AMI / kernel: `...`
- Cilium version: `...`
- kube-proxy replacement mode: `...` (strict/partial/…)
- Hubble enabled: `yes/no` + sampling (nếu có)
- Prometheus/Grafana stack version: `...`
- Fortio/k6 version: `...`
- Workload image version: `...`

---

## 12) Threats to Validity (nguy cơ sai lệch) + cách giảm thiểu
- ~~**Burstable instances (t3.large):**~~ — **Đã thay bằng m5.large (non-burstable)** → loại bỏ CPU credit exhaustion hoàn toàn
- **Noisy neighbor trên AWS:** nền cloud có biến động
  - Giảm: lặp ≥3, dùng CI thay vì chỉ mean, chạy xen kẽ A/B theo phiên
  - **Statistical testing (Welch's t-test) là cách chống bắt bẻ hiệu quả nhất** — chỉ kết luận khi p < 0.05
- **Observability overhead:** Hubble chỉ có ở Mode B → Mode B chịu thêm overhead observability
  - Ghi nhận rõ: Hubble tạo thêm work cho cilium-agent
  - Nên test thêm Mode B **tắt Hubble** để có so sánh công bằng ở S1/S2 (hoặc ghi rõ trong kết luận là Hubble = on cho cả 2 mode trong deployment thực tế)
- **1 AZ vs 2 AZ:** chọn 1 AZ giảm nhiễu nhưng không đại diện cross-AZ
  - Ghi rõ giới hạn phạm vi và lý do lựa chọn
- **Calibration chưa làm:** dùng QPS mặc định không đúng với hạ tầng thực tế → L2 có thể đã bão hòa, L3 gãy hoàn toàn → kết quả S2/S3 không đáng tin
  - **Giải pháp: chạy `calibrate.sh` trước mọi benchmark chính thức**

---

## 13) Definition of Done (đủ điều kiện chốt report)
Bạn coi như "done" khi có:
- ✅ **Calibration** L1/L2/L3 đã làm + bảng số + hình p99 vs QPS → lưu ở report/appendix/
- ✅ **Bảng tổng hợp** cho S1/S2/S3: median, mean ± 95% CI, stdev (dùng `analyze_results.py`)
- ✅ **Bảng so sánh A vs B**: Δ%, p-value, ✓/✗ significance (Welch's t-test)
- ✅ **Kết luận chỉ rút ra khi p < 0.05** — nếu p ≥ 0.05, ghi "không có ý nghĩa thống kê"
- ✅ Evidence: dashboard + (Mode B) hubble flows cho S3
- ✅ Appendix: versions/config + Threats to validity rõ ràng (bao gồm Hubble overhead note)
