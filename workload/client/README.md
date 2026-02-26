# client/ — Fortio Load Generator

Thư mục này chứa manifest triển khai **Fortio** — công cụ phát tải (load generator) dùng để benchmark network performance.

## Danh sách file

| File | Mô tả |
|------|-------|
| `01-fortio-deploy.yaml` | Deployment cho Fortio client: image `fortio/fortio:latest`, chạy ở chế độ server (giữ pod sống) |

## Fortio là gì?

**Fortio** là công cụ load testing mã nguồn mở của Google (được dùng bởi dự án Istio). Nó hỗ trợ:
- Đặt QPS (queries per second) cố định
- Nhiều kết nối đồng thời (concurrent connections)
- Đo latency percentiles: p50, p90, p95, p99
- Xuất kết quả dạng text hoặc JSON

## Cách hoạt động

1. Fortio được deploy như một pod chạy ở **server mode** (lắng nghe sẵn).
2. Khi cần benchmark, dùng `kubectl exec` vào pod Fortio để chạy lệnh load test:

```bash
# Lấy tên pod Fortio
FORTIO_POD=$(kubectl get pod -n netperf -l app=fortio -o jsonpath='{.items[0].metadata.name}')

# Chạy load test
kubectl exec -n netperf $FORTIO_POD -- \
  fortio load -qps 200 -c 16 -t 30s http://echo-svc/
```

## Tham số quan trọng

| Tham số | Ý nghĩa | Giá trị mặc định (trong scripts) |
|---------|---------|----------------------------------|
| `-qps` | Số request/giây mục tiêu | L1=50, L2=200, L3=500 |
| `-c` | Số kết nối đồng thời | 16 |
| `-t` | Thời gian chạy test | 30s |
| `-n` | Số request (thay vì thời gian) | Không dùng |

## Lưu ý

- Pod Fortio phải ở trạng thái `Running` trước khi chạy `kubectl exec`.
- Không cần expose Fortio ra ngoài — chỉ dùng nội bộ trong cluster.
- Kết quả benchmark được ghi vào `results/` bởi scripts trong `scripts/`.
