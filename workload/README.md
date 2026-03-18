# workload/ — Kubernetes manifests cho benchmark

Thư mục này chứa toàn bộ **Kubernetes manifest** dùng để triển khai workload benchmark lên cluster EKS.

## Cấu trúc

```
workload/
├── server/                          # Ứng dụng echo server (backend)
│   ├── 01-namespace.yaml            #   Tạo namespace "netperf"
│   ├── 02-echo-deploy.yaml          #   Deployment: hashicorp/http-echo
│   └── 03-echo-svc.yaml             #   Service ClusterIP: port 80 → 5678
├── client/                          # Ứng dụng Fortio (load generator)
│   └── 01-fortio-deploy.yaml        #   Deployment: fortio/fortio
└── policies/                        # Network policies
    └── 01-cilium-policy-allow-fortio-to-echo.yaml  # CiliumNetworkPolicy
```

## Mô tả từng thành phần

### Server — Echo
- **Image:** `hashicorp/http-echo:1.0`
- **Chức năng:** HTTP server đơn giản, trả về text `"ok"` trên port `5678`.
- **Service:** ClusterIP, map port `80` → `5678`. Client gọi tới `echo-svc.netperf.svc.cluster.local`.

### Client — Fortio
- **Image:** `fortio/fortio:latest`
- **Chức năng:** Công cụ load testing của Google/Istio. Chạy ở chế độ server (giữ pod sống), sau đó `kubectl exec` vào để phát tải.
- **Load test:** `fortio load -qps <QPS> -c <connections> -t <duration> http://echo-svc/`

### Policies — CiliumNetworkPolicy
- **Chức năng:** Cho phép ingress traffic từ pod có label `app=fortio` tới pod có label `app=echo` trên port `5678/TCP`.
- **Dùng trong Scenario 3:** Xóa policy (phase=off) rồi apply lại (phase=on) để đo impact.

## Cách triển khai

```bash
# Triển khai server
kubectl apply -f workload/server/

# Triển khai client
kubectl apply -f workload/client/

# Áp dụng network policy (cho Scenario 3)
kubectl apply -f workload/policies/

# Kiểm tra pods
kubectl get pods -n netperf
```

## Lưu ý

- Triển khai theo thứ tự: **server → client → policies**.
- Đảm bảo Cilium CNI đã cài đặt trước khi apply CiliumNetworkPolicy.
- Fortio pod cần chạy ổn định trước khi bắt đầu benchmark (`kubectl exec` sẽ thất bại nếu pod chưa Ready).
