# NT531 Benchmark Execution & Documentation Plan
**Project:** Kubernetes Datapath Benchmark — kube-proxy vs Cilium eBPF KPR
**Date:** 2026-04-11
**Status:** Draft

---

## 1. Requirements Summary

Chạy benchmark chính thức và ghi nhận kết quả/bằng chứng phục vụ:
1. **Thesis report** (báo cáo khoa học)
2. **Presentation slides** (slide thuyết trình)
3. **Statistical significance** — kết quả phải đo được, có CI, có p-value

---

## 2. RALPLAN-DR Summary

### Principles
1. **Isolate the variable** — chỉ đo datapath overhead, không đo network noise
2. **Evidence completeness** — mọi claim trong thesis phải có artifact gốc
3. **Statistical rigor** — dùng CI (95%) và Welch's t-test, không chỉ trung bình
4. **Reproducibility** — mọi step phải repeatable từ artifact + script

### Decision Drivers
1. Same-node placement loại bỏ VXLAN overhead → clean comparison
2. Mode A → Mode B switch là rủi ro cao → cần rollback plan sẵn sàng
3. 42 runs thực tế (~3h15m) → cần systematic evidence collection mỗi run
4. Thesis cần 3 RQs → evidence phải map được vào từng RQ

### Viable Options

**Option A: Sequential A→B (sequential, as designed)**
- Pros: đúng design, đã test, rollback A→B có documented
- Cons: sequential → không fair comparison nhưng thesis design đã accept

**Option B: Parallel runs (A và B cùng lúc)**
- Pros: fair comparison hơn
- Cons: cần 2 cluster, tốn gấp đôi chi phí, không realistic cho thesis timeline

→ **Option A selected** — sequential A→B đúng design đã accept trong thesis

---

## 3. Pre-Benchmark Checklist (TRƯỚC KHI CHẠY BẤT KỲ BENCHMARK NÀO)

### 3.1 Verify Cluster Health
```bash
kubectl get nodes          # 3 nodes Ready
kubectl get pods -n kube-system  # Cilium, kube-proxy (Mode A), CoreDNS all Running
kubectl get pods -n benchmark    # echo + fortio Running, cùng NODE
kubectl exec -n benchmark deploy/fortio -- fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
# Kỳ vọng: Code 200, 0 errors
```

### 3.2 Verify Calibration Data
```bash
# Check xem L1/L2/L3 QPS đã được xác định chưa
grep -E "L1_QPS|L2_QPS|L3_QPS" scripts/common.sh
# Nếu chưa → chạy calibrate.sh TRƯỚC
MODE=A REPEAT=2 ./scripts/calibrate.sh
```

### 3.3 Check AWS Bill trước khi bắt đầu
```bash
# Estimate chi phí benchmark
# ~$0.48/giờ × 4 giờ = ~$2
# Terraform destroy ngay sau khi xong
```

---

## 4. Official Benchmark Execution

### 4.0 Evidence Capture Infrastructure Setup ★

**Làm TRƯỚC benchmark đầu tiên (DUY NHẤT một lần)**

#### Grafana Dashboard Setup
```bash
# Port-forward Grafana (chạy nền, đừng tắt terminal)
kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80 &
sleep 3
echo "Grafana available at http://localhost:3000"
# User: admin
# Password: lấy từ secret:
kubectl get secret -n monitoring -l app.kubernetes.io/component=admin-secret \
  -o jsonpath='{.items[0].data.admin-password}' | base64 -d
```

#### Grafana Dashboards cần có sẵn cho benchmark

**Dashboard 1: Node Overview**
- Import: Node Exporter dashboard (ID: `1860` trên grafana.com)
- Metrics cần: CPU Usage, Memory Usage, Network I/O per node
- **Screenshot:** `docs/figures/fig-grafana-node-overview.png`

**Dashboard 2: Kubernetes / Pods**
- Import: Kubernetes cluster dashboard (ID: `15758`)
- Metrics cần: CPU by Pod, Memory by Pod, Network by Pod
- Filter: namespace=benchmark
- **Screenshot:** `docs/figures/fig-grafana-pod-metrics.png`

**Dashboard 3: Cilium Metrics (Mode B only)**
- URL: `http://localhost:3000/d/cilium-metrics`
- Metrics cần: `cilium_forwarded_packets_total`, `cilium_dropped_packets_total`
- Context: chỉ có ở Mode B
- **Screenshot:** `docs/figures/fig-grafana-cilium-metrics.png`

#### Prometheus Metrics cần ghi nhận trước benchmark
```bash
# Pod CPU/Memory tại baseline
kubectl exec -n monitoring prometheus-prometheus-kube-prometheus-prometheus-0 \
  -- wget -qO- 'api/v1/query?query=kube_pod_container_resource_requests' 2>/dev/null \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['data']['result'][:5], indent=2))"
```

---

### 4.1 PHASE 6 — Calibration (chỉ chạy 1 lần)

**Script:** `MODE=A REPEAT=2 ./scripts/calibrate.sh`
**Thời gian:** 30-60 phút
**Artificts:** `results/calibration/`

**Trong lúc chạy — GHI NHẬN:**
- [ ] Screenshot terminal output khi calibration xong
- [ ] Copy giá trị L1/L2/L3 QPS từ terminal
- [ ] **Grafana screenshot:** Node CPU Usage during calibration sweep
  → Filter theo thời gian calibration → `docs/figures/fig-calibration-node-cpu.png`
- [ ] **Prometheus screenshot:** `kubectl top nodes` output trong terminal
  → Lưu: `evidence/calibration-top-nodes.txt`
- [ ] Update `scripts/common.sh` với giá trị mới

**Sau calibration:**
```bash
cat results/calibration/mode=A_kube-proxy/calibration_*.txt
# Copy phần "RECOMMENDED LOAD LEVELS" vào notes
mkdir -p docs/figures/
# Screenshot terminal calibration output
```

**Evidence artifacts cho calibration:**
| Artifact | File | Use trong Thesis |
|---|---|---|
| Calibration table | `calibration_*.txt` | Methodology — load level justification |
| Calibration CSV | `calibration_*.csv` | Appendix — raw sweep data |
| Node CPU during sweep | `fig-calibration-node-cpu.png` | Methodology — no saturation |
| Terminal output | screenshot | Chương 4 — calibration criteria |

---

### 4.2 PHASE 7 — Mode A Benchmark (15 runs, ~90 phút)

#### Grafana Evidence Capture Protocol (trước mỗi LOAD level)

> **Làm trước khi chạy LOAD level mới**

**1. Baseline screenshot (Mode A S1 L1)**
Mở Grafana → Node Overview dashboard → chọn time range `Last 5 minutes`:
- Screenshot: `docs/figures/fig-A1-grafana-node-baseline.png`

**2. During benchmark screenshot**
Fortio đang chạy → chụp nhanh Grafana dashboard → `docs/figures/fig-A2-grafana-during-s1.png`

**3. S1 L1 screenshot sau khi run xong**
Prometheus → instant query → `histogram_quantile(0.99, rate(fortio_http_request_seconds_bucket[1m]))`:
- Screenshot: `docs/figures/fig-A3-prometheus-p99-query.png`

#### Grafana Metrics to Record per LOAD Level

| LOAD | Screenshot | Metrics |
|---|---|---|
| L1 | `fig-A-grafana-L1.png` | Node CPU, Pod CPU, Pod Memory |
| L2 | `fig-A-grafana-L2.png` | Node CPU, Pod CPU, Pod Memory |
| L3 | `fig-A-grafana-L3.png` | Node CPU, Pod CPU, Pod Memory |
| S2 L2 | `fig-A-grafana-S2-L2.png` | CPU spike trong burst phase |
| S2 L3 | `fig-A-grafana-S2-L3.png` | Max CPU, error correlation |

#### 7A. S1 — Steady-State (9 runs)
```bash
MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh   # ~18 phút
# → GRAFANA: chụp ảnh node/pod CPU trong suốt run
# → PROMETHEUS: query p99 latency trend

MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s1.sh   # ~18 phút
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s1.sh   # ~18 phút
```

#### 7B. S2 — Stress + Churn (6 runs)
```bash
MODE=A LOAD=L2 REPEAT=3 ./scripts/run_s2.sh   # ~36 phút
MODE=A LOAD=L3 REPEAT=3 ./scripts/run_s2.sh   # ~36 phút
# → GRAFANA: chụp CPU burst spike pattern
```

**MỖI RUN — GHI NHẬN:**
- [ ] Run xong → `tail -30 bench.log` — Code 200?
- [ ] `checklist.txt` — all ✅?
- [ ] Grafana: node CPU spike >85%?
- [ ] Ghi chú anomaly (spike, error > 1%)
- [ ] Prometheus: lưu p99 latency value cho từng run

**Post-run quick check (trước LOAD tiếp theo):**
```bash
LATEST=$(find results/mode=A_kube-proxy -type d -name "run=R*" | sort | tail -1)
echo "Latest: ${LATEST}"
tail -20 "${LATEST}/bench.log" | grep -E "Code|error|percentile"
# Grafana screenshot nếu CPU > 80%:
# docs/figures/fig-A-S2-burst-cpu.png
```

**Evidence artifacts cho Mode A:**
| Artifact | File | Use trong Thesis |
|---|---|---|
| Raw latency | `bench.log` S1/S2 | Histogram, percentile data |
| Pod CPU (Grafana) | `fig-A-grafana-L*.png` | Methodology — no saturation claim |
| Node CPU (Grafana) | `fig-A-grafana-node-L*.png` | Methodology — stable CPU |
| S2 phase CPU burst | `fig-A-grafana-S2-burst.png` | Results — churn behavior |
| Prometheus p99 query | `fig-A-prometheus-p99.png` | Results — p99 trend |
| Phase logs | `bench_phase*.log` | S2 per-phase analysis |

#### Thu thập Evidence Mode A
```bash
./scripts/collect_meta.sh results/mode=A_kube-proxy/
```

#### Verify kết quả Mode A
```bash
find results/mode=A_kube-proxy -name "bench.log" | wc -l   # phải = 15
find results/mode=A_kube-proxy/scenario=S2 -name "bench_phase*.log" | wc -l  # phải = 24 (4 phases × 6 runs)
```

---

### 4.3 PHASE 8 — Switch Mode A → Mode B (15-20 phút)

> ⚠️ **ĐỌM DỪNG TRƯỚC KHI SWITCH** — không chạy benchmark trong lúc switch

**Bước thực hiện theo KeHoachChayDuAn.md Phase 8**

**Trước khi switch — BACKUP:**
```bash
mkdir -p ~/backup-mode-A-$(date +%Y%m%d-%H%M)
cp -r results/mode=A_kube-proxy ~/backup-mode-A-$(date +%Y%m%d-%H%M)/
```

**Trong lúc switch — GHI NHẬN:**
- [ ] Screenshot mỗi bước switch (cilium status, kube-proxy check)
- [ ] Verify `KubeProxyReplacement: True` sau khi upgrade
- [ ] Verify pod IPs là ENI range (10.0.x.x) sau restart

**Sau switch — VERIFY:**
```bash
kubectl exec -n benchmark deploy/fortio -- fortio load -c 1 -n 5 -t 10s http://echo.benchmark.svc:80/echo
# Code 200, 0 errors trước khi chạy benchmark
```

---

### 4.4 PHASE 9 — Mode B Benchmark (27 runs, ~90 phút)

#### Grafana Evidence Capture Protocol (Mode B)

**1. Cilium-specific dashboard**
- Import Cilium dashboard (ID: `17515` trên grafana.com)
- Metrics: `cilium_forward`, `cilium_drop`, `cilium_policy_verdict`
- **Screenshot:** `docs/figures/fig-B1-cilium-metrics.png`

**2. Hubble Flow Rate Dashboard**
- Metric: `rate(hubble_flows_total[1m])`
- Shows FORWARDED vs DROPPED rate
- **Screenshot:** `docs/figures/fig-B2-hubble-flow-rate.png`

**3. eBPF Map Pressure**
- Metric: `cilium_bpf_map_pressure` (nếu available)
- Check: eBPF map không bị evict entries
- **Screenshot:** `docs/figures/fig-B3-bpf-maps.png`

#### 9A. S1 — Steady-State (9 runs)
```bash
MODE=B LOAD=L1 REPEAT=3 ./scripts/run_s1.sh
# → GRAFANA: cilium_forward rate + node CPU screenshot
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s1.sh
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s1.sh
```

#### 9B. S2 — Stress + Churn (6 runs)
```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s2.sh
# → GRAFANA: burst phase CPU + cilium_drop rate
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s2.sh
```

#### 9C. S3 — Policy Overhead (12 runs)

> ⚠️ **S3 tạo 2 phase subdirectories: `phase=off/` và `phase=on/`**

```bash
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
# → GRAFANA: phase=off vs phase=on policy enforcement screenshot
MODE=B LOAD=L3 REPEAT=3 ./scripts/run_s3.sh
```

**S3 Evidence capture trọng điểm:**

```bash
# 1. Hubble flows — FORWARDED ratio (phase=off)
hubble-off=$(find results/mode=B_cilium-ebpfkpr/scenario=S3/load=L2/phase=off \
  -name "hubble_flows.jsonl" | head -1)
grep -c "verdict=\"FORWARDED\"" "$hubble-off" || echo "0"
# Screenshot Grafana: docs/figures/fig-B-S3-off-flows.png

# 2. Hubble flows — DROP ratio (phase=on)
hubble-on=$(find results/mode=B_cilium-ebpfkpr/scenario=S3/load=L2/phase=on \
  -name "hubble_flows.jsonl" | head -1)
grep -c "verdict=\"DROPPED\"" "$hubble-on" || echo "0"
# Screenshot Grafana: docs/figures/fig-B-S3-on-flows.png

# 3. Cilium policy verdict ratio
kubectl exec -n kube-system ds/cilium -c cilium-agent -- \
  cilium status --verbose 2>&1 | grep -iE "policy|verdict"
# Screenshot: docs/figures/fig-B-S3-policy-verdict.png
```

#### Deny Case Evidence (S3) ★

**Đây là bằng chứng QUAN TRỌNG NHẤT cho RQ3**

```bash
# Attacker pod bị DROP
kubectl run attacker --image=curlimages/curl --rm -it --restart=Never -n benchmark -- \
  curl --connect-timeout 5 http://echo.benchmark.svc:80/echo
# Kỳ vọng: FAIL/TIMEOUT

# Hubble log capture (tất cả verdict trong window)
kubectl exec -n kube-system ds/cilium -c cilium-agent -- \
  hubble observe --namespace benchmark --last 5000 -o jsonpb \
  > results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log

# Count verdict
grep -o 'verdict="[^"]*"' results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log \
  | sort | uniq -c | sort -rn
# Output mẫu: "DROPPED" 47   "FORWARDED" 12
```

**→ Screenshot cho thesis:**
| Screenshot | File | Nội dung |
|---|---|---|
| Hubble flows (allowed traffic) | `fig-B-S3-forwarded.png` | FORWARDED entries, dest=echo pod |
| Hubble flows (denied traffic) | `fig-B-S3-dropped.png` | DROPPED entries, verdict=DROPPED |
| Policy verdict table | `fig-B-S3-verdict-table.png` | Verdict count summary |
| Attacker timeout | `fig-B-S3-attacker-timeout.png` | curl FAIL/TIMEOUT screenshot |

#### Post-run Quick Check (Mode B)
```bash
LATEST=$(find results/mode=B_cilium-ebpfkpr -type d -name "run=R*" | sort | tail -1)
tail -10 "${LATEST}/bench.log" | grep -E "Code|percentile"
# Grafana: cilium_drop rate >0?
tail -5 "${LATEST}/hubble_flows.jsonl" 2>/dev/null || echo "No hubble flows"
kubectl top nodes
```

#### Thu thập Evidence Mode B
```bash
./scripts/collect_meta.sh results/mode=B_cilium-ebpfkpr/
./scripts/collect_hubble.sh results/mode=B_cilium-ebpfkpr/
```

#### Verify kết quả Mode B
```bash
find results/mode=B_cilium-ebpfkpr -name "bench.log" | wc -l           # phải = 27
find results/mode=B_cilium-ebpfkpr/scenario=S3 -name "hubble_flows.jsonl" | wc -l  # phải = 12
grep -c "DROPPED" results/mode=B_cilium-ebpfkpr/scenario=S3/deny_case_hubble.log  # phải > 0
```

---

## 5. Statistical Analysis

```bash
python3 scripts/analyze_results.py
```

**Output files cần giữ lại cho thesis:**
- `results_analysis/aggregated_summary.csv` — tất cả metrics, CI
- `results_analysis/comparison_AB.csv` — Δ%, p-value, significance

**MỖI comparison — GHI NHẬN:**
- [ ] Δ% cho mỗi metric (p50, p99, p999, rps, error%)
- [ ] p-value cho mỗi comparison
- [ ] "✓ sig" hay "ns" (not significant)
- [ ] Direction: Mode B tốt hơn hay kém hơn?

---

## 6. Thesis Report Evidence Mapping

### Chapter 4 — Methodology
| Evidence | Artifact |
|---|---|
| Benchmark setup | `metadata.json` từ mỗi run |
| Node specs | `kubectl_top_nodes.txt` |
| Cluster config | `kubectl_get_all.txt` |
| Cilium version | `cilium status` screenshot |
| Same-node placement | `kubectl get pods -o wide` screenshot |
| Calibrated load levels | `calibration_*.txt` |

### Chapter 5 — Results
| Claim | Evidence |
|---|---|
| S1 latency Mode A | `bench.log` từ S1 Mode A (L1/L2/L3) |
| S1 latency Mode B | `bench.log` từ S1 Mode B (L1/L2/L3) |
| S2 churn stability | `bench_phase*.log` từ S2 Mode A/B |
| S3 policy overhead | `hubble_flows.jsonl` + `comparison_AB.csv` Δ% |
| S3 deny verdict | `deny_case_hubble.log` (DROPPED entries) |
| Statistical significance | `comparison_AB.csv` p-value column |

### Chapter 6 — Analysis / Threats to Validity
| Threat | Mitigation/Note |
|---|---|
| Hubble overhead in Mode B | Ghi nhận: Mode B bật Hubble, Mode A không |
| AWS noisy neighbor | m5.large non-burstable, same-node placement |
| Sequential A→B execution | Acceptable for thesis design |

---

## 7. Presentation Slides Evidence

### Slide 1 — Title / Introduction
| Content | Evidence |
|---------|---------|
| Cluster topology diagram | ASCII art từ `kubectl get nodes -o wide` + subnet diagram |
| Research question | RQ1/RQ2/RQ3 từ experiment spec |
| Cluster specs | m5.large, Cilium 1.18.7, K8s 1.34 |

**Screenshots:**
- `kubectl get nodes -o wide` → `docs/figures/fig-01-nodes.png`
- `kubectl get pods -n benchmark -o wide` → `docs/figures/fig-02-topology.png`

---

### Slide 2 — Methodology
| Content | Evidence |
|---------|---------|
| Same-node topology proof | `kubectl get pods -o wide` — cột NODE giống nhau |
| Load levels table | L1/L2/L3 từ calibration report |
| Duration specs | 180s run + 30s warmup + 60s rest, REPEAT=3 |
| Metrics captured | p50/75/90/95/99/999/max, RPS, error% |
| Scripts overview | S1/S2/S3 + analyze_results.py |

**Screenshots:**
- `kubectl get pods -n benchmark -o wide` → proof of same-node placement
- Calibration terminal output → load level determination table
- Fortio web UI → baseline histogram screenshot

---

### Slide 3 — S1 Results: Steady-State
| Content | Evidence |
|---------|---------|
| p50 bar chart (A vs B) | `comparison_AB.csv` S1 rows |
| p99 bar chart (A vs B) | `comparison_AB.csv` S1 rows |
| Error rate comparison | `comparison_AB.csv` error_pct column |
| Δ% per metric | Computed from `comparison_AB.csv` |
| p-value | "[sig]" highlighted green, "ns" in gray |

**Chart type:** Grouped bar chart — x-axis = L1/L2/L3, y-axis = latency (ms), grouped bars = Mode A / Mode B per percentile

**Data source:** `comparison_AB.csv` S1 section. Extract rows for p50/p99/p999 at L1/L2/L3.

**Screenshots:**
- Fortio UI histogram per run (Mode A + Mode B, cùng L level)
- Grafana node/pod CPU during S1 runs

---

### Slide 4 — S2 Results: Stress + Connection Churn
| Content | Evidence |
|---------|---------|
| p99 across phases | `bench_phase*.log` từ S2 Mode A + B |
| Burst CPU spike | Grafana node CPU screenshot during Phase 3 burst |
| Mode A vs B stability | comparison_AB.csv S2 rows |
| Connection churn behavior | Phase 3 (burst) data from phase logs |

**Chart type:** Multi-line chart — x-axis = Phase (Ramp→Sustained→Burst×3→Cool), y-axis = p99 (ms), lines = Mode A / Mode B

**Data source:** Parse `bench_phase*.log` files từ both modes

**Screenshots:**
- Grafana: node CPU burst pattern Mode A vs Mode B
- Comparison spike pattern overlay

---

### Slide 5 — S3 Results: Policy Enforcement (Mode B only) ★
| Content | Evidence |
|---------|---------|
| OFF vs ON latency delta | `bench.log` phase=off vs phase=on comparison |
| FORWARDED traffic | `hubble_flows.jsonl` — count FORWARDED entries |
| DROPPED traffic | `hubble_flows.jsonl` — count DROPPED entries |
| Attacker blocked | curl timeout screenshot + kubectl logs attacker |

**This is the KEY DIFFERENTIATING slide — Mode B only**

**Table format:**
```
Phase       FORWARDED  DROPPED  Latency Δ%
phase=off   847        0        baseline
phase=on    820        43       +Xms overhead
```

**Screenshots:**
| Screenshot | File | Content |
|---|---|---|
| Hubble flows allowed | `fig-B-S3-forwarded.png` | Hubble observe output, dest=echo, verdict=FORWARDED |
| Hubble flows denied | `fig-B-S3-dropped.png` | Hubble observe output, verdict=DROPPED |
| Attacker timeout | `fig-B-S3-attacker.png` | curl FAIL/TIMEOUT + kubectl logs |
| Policy verdict pie chart | generated | FORWARDED vs DROPPED ratio |
| Cilium status (policy) | `fig-B-status-policy.png` | `cilium status --verbose` showing policy verdicts |

---

### Slide 6 — Statistical Significance Summary
| Content | Evidence |
|---------|---------|
| Δ% across all metrics | `comparison_AB.csv` full table |
| p-value column | p-value per comparison |
| Significant (p<0.05) | Highlighted rows in comparison_AB.csv |
| Not significant | "ns" marker |
| Direction | Mode B better/worse than A |

**Table format:**
```
Metric    Mode A      Mode B     Δ%      p-value   Significant
p50 L1    0.49ms    0.45ms    -8.2%   0.003     ✓ sig
p99 L1    0.71ms    0.63ms    -11.3%  0.001     ✓ sig
p50 L2    1.82ms    1.71ms    -6.0%   0.042     ✓ sig
p50 L3    4.21ms    4.05ms    -3.8%   0.124     ns
S2 p99    8.34ms    6.91ms    -17.1%  0.002     ✓ sig
```

---

### Slide 7 — Threats to Validity & Conclusion
| Content | Evidence |
|---------|---------|
| Mode A hybrid note | Threat: "Cilium hybrid + kube-proxy vs full eBPF" |
| Hubble overhead | Screenshot cilium status — Hubble enabled |
| Same-node only | Threat: cross-node behavior khác biệt |
| Conclusion | Δ% summary table + direction |

**Screenshots:**
- `cilium status` Mode B → KubeProxyReplacement=True, Hubble Enabled
- Threats table acknowledgment in methodology section

---

## 8. Grafana & Prometheus — Specific Screenshots Checklist

> Chạy **1 lần DUY NHẤT** trước benchmark. Lưu vào `docs/figures/`

### Before Mode A Benchmark
- [ ] `fig-A0-grafana-node-overview.png` — Node CPU/Memory baseline
- [ ] `fig-A0-grafana-pod-overview.png` — Pod CPU/Memory baseline
- [ ] `fig-A0-prometheus-p99-baseline.png` — Prometheus p99 query baseline

### During/After Mode A S1
- [ ] `fig-A1-grafana-s1-l1-cpu.png` — Node CPU during S1 L1
- [ ] `fig-A2-grafana-s1-l3-cpu.png` — Node CPU during S1 L3 (highest load)

### During/After Mode A S2
- [ ] `fig-A3-grafana-s2-burst-cpu.png` — Node CPU during S2 burst (critical spike)
- [ ] `fig-A4-grafana-s2-pod-cpu.png` — Pod CPU breakdown during S2

### Before Mode B Benchmark
- [ ] `fig-B0-cilium-status.png` — `cilium status` showing KPR=True, ENI IPAM
- [ ] `fig-B0-hubble-status.png` — `hubble status` — connected + flows enabled
- [ ] `fig-B0-grafana-cilium-metrics.png` — Cilium-specific Grafana dashboard

### During/After Mode B S3
- [ ] `fig-B1-grafana-s3-policy-on.png` — Cilium policy enforcement rate
- [ ] `fig-B2-grafana-hubble-flow-rate.png` — Hubble FORWARDED vs DROPPED rate
- [ ] `fig-B3-grafana-s3-attacker-blocked.png` — DROPPED verdict during attacker test

### Post-Benchmark
- [ ] `fig-R1-prometheus-comparison-p50.png` — Prometheus p50 comparison query
- [ ] `fig-R2-prometheus-comparison-p99.png` — Prometheus p99 comparison query

---

## 8. Acceptance Criteria

### Evidence Completeness
- [ ] `results/calibration/` có calibration_*.txt + calibration_*.csv
- [ ] `results/mode=A_kube-proxy/` có đủ 15 bench.log files (S1=9, S2=6)
- [ ] `results/mode=B_cilium-ebpfkpr/` có đủ 27 bench.log files (S1=9, S2=6, S3=12)
- [ ] Tất cả S3 runs có hubble_flows.jsonl (12 files)
- [ ] `results_analysis/comparison_AB.csv` có Δ% và p-value cho mọi metric
- [ ] `results_analysis/aggregated_summary.csv` có CI 95% cho mọi group

### Grafana / Monitoring Screenshots
- [ ] 7 screenshots Grafana node/pod CPU (Mode A: 4, Mode B: 3)
- [ ] 2 screenshots Prometheus p99 query (A vs B)
- [ ] 5 screenshots S3 Hubble/Policy (Mode B)
- [ ] Attacker timeout screenshot + kubectl logs

### Thesis Structure
- [ ] `docs/chapters/` tồn tại và có 5 chapter files
- [ ] Thesis figures tồn tại trong `docs/figures/` (>= 15 screenshots)
- [ ] Threats to Validity được viết đầy đủ trong chương 6
- [ ] Slides có source evidence cited từ benchmark artifacts

---

## 9. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Mode B switch thất bại | Medium | High | Helm rollback + terraform destroy backup |
| Benchmark run fail giữa chừng | Low | Medium | Check exit code + re-run failed run |
| Data corruption / missing logs | Low | High | Verify `bench.log` count sau mỗi phase |
| Mode B pod IP conflict | Medium | Medium | Restart workload pods sau switch |
| Hubble relay BackOff | Medium | Medium | Delete relay pod sau switch (Phase 8.10) |

---

## 10. ADR — Architecture Decision Record

**Decision:** Sequential Mode A → Mode B benchmark execution với same-node pod placement

**Drivers:**
1. Clean comparison — same-node eliminates VXLAN/network overhead
2. Practical — single cluster, sequential is acceptable cho thesis design
3. Evidence completeness — systematic artifact collection per phase

**Alternatives considered:**
1. Cross-node placement — rejected: adds VXLAN overhead, thesis muốn đo datapath diff
2. Parallel runs (2 clusters) — rejected: tốn gấp đôi chi phí và thời gian

**Consequences:**
- Mode B chạy Hubble (observability) ảnh hưởng slightly perf → ghi nhận trong Threats to Validity
- Sequential execution means temporal variability có thể ảnh hưởng → ghi nhận trong thesis

**Follow-ups:**
- Commit benchmark results vào repo sau khi phân tích xong
- Backup toàn bộ `results/` và `results_analysis/` trước khi terraform destroy
