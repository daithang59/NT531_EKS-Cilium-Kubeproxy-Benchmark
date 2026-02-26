# Results Summary — Mode A vs Mode B (kube-proxy vs Cilium eBPF)

> Cách đọc: mỗi ô là **median** của ≥3 runs. Kèm (min–max) nếu có.  
> Tham số tải L1/L2/L3 phải cố định giữa 2 mode.

---

## 1) Versions & Config (Appendix snapshot)
| Item | Value |
|---|---|
| EKS cluster | `...` |
| Kubernetes version | `...` |
| Node instance | `t3.large x 3` |
| Node AMI / Kernel | `...` |
| Mode A kube-proxy | `iptables/ipvs`, version `...` |
| Mode B Cilium | version `...`, kube-proxy replacement `...` |
| Hubble | enabled `yes/no`, version `...` |
| Prometheus stack | `kube-prometheus-stack`, version `...` |
| Fortio/k6 | `...` |

---

## 2) Load Levels (Calibration frozen params)
| Load | Concurrency | QPS | Duration(s) | Warmup(s) | Payload(bytes) | Notes |
|---|---:|---:|---:|---:|---:|---|
| L1 | `...` | `...` | `...` | `...` | `...` | light, ~0 error |
| L2 | `...` | `...` | `...` | `...` | `...` | tail latency appears |
| L3 | `...` | `...` | `...` | `...` | `...` | near saturation |

**Calibration plot evidence:** `figures/calibration_qps_vs_p99.png`

---

## 3) Scenario S1 — Service Baseline (policy off/allow-all)
### L1
| Mode | p50 (ms) | p95 (ms) | p99 (ms) | RPS | Error % | Notes |
|---|---:|---:|---:|---:|---:|---|
| A |  |  |  |  |  |  |
| B |  |  |  |  |  |  |

### L2
| Mode | p50 (ms) | p95 (ms) | p99 (ms) | RPS | Error % | Notes |
|---|---:|---:|---:|---:|---:|---|
| A |  |  |  |  |  |  |
| B |  |  |  |  |  |  |

### L3
| Mode | p50 (ms) | p95 (ms) | p99 (ms) | RPS | Error % | Notes |
|---|---:|---:|---:|---:|---:|---|
| A |  |  |  |  |  |  |
| B |  |  |  |  |  |  |

**Evidence**
- Grafana: `results/.../grafana/*.png`
- (Mode B) Hubble: `results/.../hubble.log`

---

## 4) Scenario S2 — High-load + Connection Churn
> Mục tiêu: xem tail latency và error rate khi churn.

### L1 / L2 / L3
(điền tương tự S1)

**Evidence**
- Grafana: CPU breakdown (đặc biệt softirq), network, pod CPU
- Fortio logs: `bench.log`
- (Mode B) Hubble: flow/drops nếu có

---

## 5) Scenario S3 — NetworkPolicy Overhead (off → on)
### S3a (simple policy)
- Policy: `...` (rule count ~ `...`)
- Hubble verdict expected: allow/deny đúng theo thiết kế

| Load | Mode | Policy | p50 | p95 | p99 | RPS | Error % | Notes |
|---|---|---|---:|---:|---:|---:|---:|---|
| L1 | A | off |  |  |  |  |  |  |
| L1 | A | on  |  |  |  |  |  |  |
| L1 | B | off |  |  |  |  |  |  |
| L1 | B | on  |  |  |  |  |  |  |
| L2 | ... | ... |  |  |  |  |  |  |
| L3 | ... | ... |  |  |  |  |  |  |

### S3b (complex policy)
- Policy: `...` (rule count ~ `...`, selectors `...`)
- Kỳ vọng: overhead tăng rõ hơn S3a

(điền bảng tương tự)

**Evidence bắt buộc**
- Hubble logs chứng minh policy enforcement: `hubble.log`
- Manifest policy đã apply: `manifests/`
- Grafana: latency/RPS + node CPU/softirq

---

## 6) Aggregate Comparison (tóm tắt "ăn điểm")
### 6.1 Δ% p99 và Δ% RPS (B so với A)
| Scenario | Load | Δp99 (B vs A) | ΔRPS (B vs A) | ΔError% | Nhận xét |
|---|---|---:|---:|---:|---|
| S1 | L1 |  |  |  |  |
| S1 | L2 |  |  |  |  |
| S1 | L3 |  |  |  |  |
| S2 | L1 |  |  |  |  |
| S2 | L2 |  |  |  |  |
| S2 | L3 |  |  |  |  |
| S3a | L2 |  |  |  |  |
| S3b | L2 |  |  |  |  |

### 6.2 Key Observations (giải thích bằng evidence)
- Observation 1: `...` (cite grafana panel + hubble)
- Observation 2: `...`

---

## 7) Threats to Validity (ghi trong report)
- t3 burstable CPU credit → ảnh hưởng tail latency (cách giảm: lặp runs, nghỉ giữa runs, theo dõi CPU/softirq)
- noisy neighbor cloud → dùng median + min/max
- observability overhead → giữ tương đương giữa 2 mode, chỉ khác datapath
- 1 AZ giảm nhiễu nhưng không đại diện cross-AZ
