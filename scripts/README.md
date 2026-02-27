# scripts/ — Automation scripts cho benchmark

Thư mục này chứa toàn bộ shell scripts dùng để **chạy benchmark tự động** trên cluster EKS.
Mọi script tuân theo **Results Contract** (xem `results/README.md`).

## Cấu trúc

| File | Mô tả |
|------|-------|
| `common.sh` | Thư viện dùng chung: validation, fail-fast pre-checks, Fortio execution, evidence collection (`collect_meta`, `collect_cilium_hubble`), metadata.json + checklist.txt generation. Được `source` bởi `run_s*.sh`. |
| `run_s1.sh` | **Scenario 1 — Service Baseline.** Steady-state load qua ClusterIP. |
| `run_s2.sh` | **Scenario 2 — High-load + Connection Churn.** Multi-phase: ramp-up → sustained → burst × 3 → cool-down. |
| `run_s3.sh` | **Scenario 3 — NetworkPolicy Overhead (off → on).** Phase OFF (policy deleted) → Phase ON (policy applied). |
| `collect_meta.sh` | Standalone kubectl evidence collector (`kubectl_get_all.txt`, `kubectl_top_nodes.txt`, `events.txt`). |
| `collect_hubble.sh` | Standalone Cilium/Hubble evidence collector (`cilium_status.txt`, `hubble_status.txt`, `hubble_flows.jsonl`). |

## Cách sử dụng

### Biến môi trường

| Variable | Mặc định | Mô tả |
|----------|---------|-------|
| `MODE` | `A` | `A` = kube-proxy baseline, `B` = Cilium eBPF KPR |
| `LOAD` | `L1` | `L1` (light), `L2` (medium), `L3` (high) |
| `REPEAT` | `3` | Số lần lặp mỗi (scenario × load) |
| `OUTDIR` | _(auto)_ | Override output directory (bỏ qua auto-creation) |
| `NS` | `netperf` | Namespace chứa workload |
| `WARMUP_SEC` | `30` | Thời gian warm-up trước mỗi lần đo |
| `DURATION_SEC` | `120` | Thời gian đo chính thức |
| `REST_BETWEEN_RUNS` | `30` | Nghỉ giữa các runs |
| `L1_QPS` / `L2_QPS` / `L3_QPS` | `100` / `500` / `1000` | QPS cho mỗi load level |
| `L1_CONNS` / `L2_CONNS` / `L3_CONNS` | `8` / `32` / `64` | Concurrent connections |
| `L1_THREADS` / `L2_THREADS` / `L3_THREADS` | `2` / `4` / `8` | Fortio threads |

### Chạy benchmark

```bash
# S1 — Mode A, Load L1, 3 repeats
MODE=A LOAD=L1 REPEAT=3 ./scripts/run_s1.sh

# S2 — Mode B, Load L3, 5 repeats
MODE=B LOAD=L3 REPEAT=5 ./scripts/run_s2.sh

# S3 — Mode B, Load L2, policy toggle
MODE=B LOAD=L2 REPEAT=3 ./scripts/run_s3.sh
```

### Fail-fast checks

Trước khi chạy, scripts tự động kiểm tra:
1. `kubectl` context hoạt động
2. Tất cả nodes `Ready`
3. Pod `echo` và `fortio` đang `Running` trong namespace
4. (Mode B) `cilium status` khả dụng

### Output (theo Results Contract)

```
results/
  mode=A_kube-proxy/
    scenario=S1/
      load=L1/
        run=R1_2026-02-27T14-30-00+07-00/
          bench.log            # Fortio output
          metadata.json        # Run configuration
          checklist.txt        # Runner/Checker verification
          kubectl_get_all.txt  # kubectl get all -A
          kubectl_top_nodes.txt
          events.txt
          cilium_status.txt    # (Mode B / S3 only)
          hubble_status.txt    # (Mode B / S3 only)
          hubble_flows.jsonl   # (Mode B / S3 only)
```

## Lưu ý

- Trên Linux/WSL, nhớ `chmod +x scripts/*.sh` trước khi chạy.
- `common.sh` không chạy độc lập — nó chỉ được `source` bởi các script khác.
- Tất cả scripts đều dùng `set -euo pipefail` để fail-fast khi có lỗi.
- `collect_meta.sh` và `collect_hubble.sh` có thể chạy độc lập với `<outdir>` argument.
