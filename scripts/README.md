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
| `cluster_power.sh` | Utility tạm dừng/bật lại cụm EKS an toàn (`pause`, `resume`, `status`) với auto-discover nodegroup và xử lý CoreDNS/PDB. |

## Cách sử dụng

### Biến môi trường

| Variable | Mặc định | Mô tả |
|----------|---------|-------|
| `MODE` | `A` | `A` = kube-proxy baseline, `B` = Cilium eBPF KPR |
| `LOAD` | `L1` | `L1` (light), `L2` (medium), `L3` (high) |
| `REPEAT` | `3` | Số lần lặp mỗi (scenario × load) |
| `OUTDIR` | _(auto)_ | Override output directory (bỏ qua auto-creation) |
| `NS` | `benchmark` | Namespace chứa workload |
| `WARMUP_SEC` | `30` | Thời gian warm-up trước mỗi lần đo |
| `DURATION_SEC` | `180` | Thời gian đo chính thức (3 phút — plan §4.3) |
| `REST_BETWEEN_RUNS` | `60` | Nghỉ giữa các runs (plan: 60–120s) |
| `L1_QPS` / `L2_QPS` / `L3_QPS` | `100` / `500` / `1000` | QPS cho mỗi load level |
| `L1_CONNS` / `L2_CONNS` / `L3_CONNS` | `8` / `32` / `64` | Concurrent connections |
| `L1_THREADS` / `L2_THREADS` / `L3_THREADS` | `2` / `4` / `8` | Fortio threads |

### Chạy benchmark

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

> S2 không chạy L1 vì QPS quá thấp. S3 chỉ Mode B.

### Tạm dừng / bật lại cụm EKS

```bash
# Pause (scale nodegroup về 0)
./scripts/cluster_power.sh pause

# Resume (khôi phục từ state; fallback TARGET_NODES=3)
./scripts/cluster_power.sh resume

# Xem trạng thái cluster + nodegroup + nodes
./scripts/cluster_power.sh status
```

Script lưu state vào `results/ops/cluster_power_<cluster>.env` để restore lại min/max/desired và số replicas CoreDNS khi resume.

### Fail-fast checks

Trước khi chạy, scripts tự động kiểm tra:
1. `kubectl` context hoạt động
2. Tất cả nodes `Ready`
3. Pod `echo` và `fortio` đang `Running` trong namespace
4. `kube-dns` Service contract hợp lệ (`53/UDP`, `53/TCP`, có endpoints)
5. DNS probe từ pod `fortio` tới `echo.benchmark.svc.cluster.local` thành công
6. (Mode B) `cilium status` khả dụng

Nếu DNS check fail, reconcile CoreDNS addon trước khi chạy lại benchmark:

```bash
CLUSTER_NAME=$(kubectl config current-context | sed 's|.*/||')
aws eks update-addon --cluster-name "$CLUSTER_NAME" --region ap-southeast-1 \
  --addon-name coredns --resolve-conflicts OVERWRITE
aws eks wait addon-active --cluster-name "$CLUSTER_NAME" --region ap-southeast-1 \
  --addon-name coredns
```

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
