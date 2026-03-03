# workload/ — Kubernetes manifests cho benchmark

Thư mục này chứa toàn bộ **Kubernetes manifest** dùng để triển khai workload benchmark lên cluster EKS.

## Cấu trúc

```
workload/
├── server/                          # Ứng dụng echo server (backend)
│   ├── 01-namespace.yaml            #   Tạo namespace "netperf"
│   ├── 02-echo-deploy.yaml          #   Deployment: hashicorp/http-echo (resource limits + nodeSelector)
│   └── 03-echo-svc.yaml             #   Service ClusterIP: port 80 → 5678
├── client/                          # Ứng dụng Fortio (load generator)
│   └── 01-fortio-deploy.yaml        #   Deployment: fortio/fortio:1.74.0 (resource limits + nodeSelector)
└── policies/                        # Network policies
    ├── 01-cilium-policy-allow-fortio-to-echo.yaml  # Allow: fortio → echo:5678
    └── 02-cilium-policy-deny-other.yaml            # Default-deny ingress (S3)
```

## Mô tả từng thành phần

### Server — Echo
- **Image:** `hashicorp/http-echo:1.0`
- **Chức năng:** HTTP server đơn giản, trả về text `"ok"` trên port `5678`.
- **Service:** ClusterIP, map port `80` → `5678`. Client gọi tới `echo.netperf.svc.cluster.local`.
- **Resource limits:** CPU 250m/500m, memory 128Mi/256Mi (plan §2.3).
- **nodeSelector:** `role: benchmark` (plan §4.5).

### Client — Fortio
- **Image:** `fortio/fortio:1.74.0` (pinned — plan §4.5)
- **Chức năng:** Công cụ load testing của Google/Istio. Chạy ở chế độ server (giữ pod sống), sau đó `kubectl exec` vào để phát tải.
- **Load test:** `fortio load -qps <QPS> -c <connections> -t <duration> http://echo.netperf.svc.cluster.local/`
- **Resource limits:** CPU 500m/1000m, memory 256Mi/512Mi (plan §2.3).
- **nodeSelector:** `role: benchmark` (plan §4.5).

### Policies — CiliumNetworkPolicy
- **Allow policy** (`01-...`): Cho phép ingress từ pod `app=fortio` tới pod `app=echo` trên port `5678/TCP`.
- **Deny policy** (`02-...`): Default-deny ingress cho echo server — chứng minh enforcement hoạt động (plan §4.2 S3: "deny case").
- **Dùng trong Scenario 3:** Xóa policies (phase=off) rồi apply lại (phase=on) để đo impact.

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
- Cả 2 deployments dùng `nodeSelector: role: benchmark` — đảm bảo node group có label này.
- Resource limits đã được set để tránh CPU throttling ảnh hưởng kết quả benchmark.
