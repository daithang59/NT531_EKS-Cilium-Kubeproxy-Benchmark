# scripts/ — Automation scripts cho benchmark

Thư mục này chứa toàn bộ shell scripts dùng để **chạy benchmark tự động** trên cluster EKS.

## Cấu trúc

| File | Mô tả |
|------|-------|
| `common.sh` | Thư viện dùng chung: biến cấu hình (namespace, mode, QPS, duration…), các hàm helper (`fortio_pod`, `run_fortio`, `write_metadata`, `collect_kubectl_state`…). Được `source` bởi các script `run_s*.sh`. |
| `run_s1.sh` | Chạy **Scenario 1** — Baseline service datapath. Lặp qua 3 load level (L1/L2/L3), mỗi level chạy N lần (REPEATS). Ghi kết quả vào `results/`. |
| `run_s2.sh` | Chạy **Scenario 2** — High load + connection churn. Hiện tại là skeleton (tái sử dụng S1), sẽ mở rộng thêm logic churn sau. |
| `run_s3.sh` | Chạy **Scenario 3** — Policy OFF → ON. Xóa CiliumNetworkPolicy, đo (phase=off), apply lại policy, đo (phase=on). So sánh impact của network policy. |
| `collect_hubble.sh` | Thu thập Hubble flow logs từ namespace benchmark. Yêu cầu Hubble CLI đã cài. |
| `collect_meta.sh` | Thu thập metadata cluster: thời gian, cilium status, kubectl state. |

## Cách sử dụng

### Biến môi trường quan trọng

```bash
export MODE="kubeproxy"       # kubeproxy | ebpfkpr — chọn mode đang test
export NS="netperf"           # namespace chứa workload
export REPEATS=3              # số lần lặp mỗi (scenario, load)
export WARMUP_SEC=10          # thời gian warm-up trước mỗi lần đo
export DURATION_SEC=30        # thời gian đo chính thức
export L1_QPS=50              # QPS cho load level L1 (light)
export L2_QPS=200             # QPS cho load level L2 (medium)
export L3_QPS=500             # QPS cho load level L3 (heavy)
```

### Chạy benchmark

```bash
# Scenario 1
./scripts/run_s1.sh

# Scenario 3 (policy toggle)
./scripts/run_s3.sh
```

### Output

Kết quả được ghi theo cấu trúc:
```
results/
  mode=kubeproxy/
    scenario=s1/
      load=L1/
        run=01/
          metadata.json      # thông số chạy
          bench.log           # output Fortio
          cluster_state.txt   # kubectl snapshot
          hubble.log          # Hubble flows (nếu có)
          grafana/            # screenshots (thủ công)
```

## Lưu ý

- Trên Linux/WSL, nhớ `chmod +x scripts/*.sh` trước khi chạy.
- `common.sh` không chạy độc lập — nó chỉ được `source` bởi các script khác.
- Tất cả scripts đều dùng `set -euo pipefail` để fail-fast khi có lỗi.
