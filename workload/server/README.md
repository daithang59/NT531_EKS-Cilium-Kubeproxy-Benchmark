# server/ — Echo Server (Backend)

Thư mục này chứa các Kubernetes manifest để triển khai **echo server** — ứng dụng backend nhận request từ Fortio client trong quá trình benchmark.

## Danh sách file

| File | Mô tả |
|------|-------|
| `01-namespace.yaml` | Tạo namespace `netperf` — không gian riêng cho toàn bộ workload benchmark |
| `02-echo-deploy.yaml` | Deployment: `hashicorp/http-echo:1.0`, 1 replica, port `5678`, resource limits (CPU 250m/500m, mem 128Mi/256Mi), nodeSelector `role: benchmark` |
| `03-echo-svc.yaml` | Service ClusterIP: expose echo server qua port `80`, forward tới targetPort `5678` |

## Cách triển khai

```bash
# Apply theo thứ tự (namespace → deployment → service)
kubectl apply -f workload/server/

# Kiểm tra
kubectl get all -n netperf
```

## Chi tiết kỹ thuật

- **Image:** `hashicorp/http-echo:1.0` — HTTP server tĩnh, siêu nhẹ, không logic xử lý nặng → phù hợp đo network overhead thuần túy.
- **Replicas:** 1 (cố định) — giữ đơn giản để so sánh giữa 2 mode công bằng.
- **Service:** ClusterIP (không expose ra ngoài) — Fortio client gọi qua địa chỉ `echo.netperf.svc.cluster.local`.
- **Resource limits:** CPU 250m/500m, memory 128Mi/256Mi (plan §2.3 — tránh CPU throttling).
- **nodeSelector:** `role: benchmark` (plan §4.5 — pin pod lên benchmark nodes).

## Lưu ý

- File được đánh số thứ tự (`01-`, `02-`, `03-`) để `kubectl apply -f` xử lý đúng thứ tự.
- Namespace `netperf` phải tồn tại trước khi deploy echo server.
