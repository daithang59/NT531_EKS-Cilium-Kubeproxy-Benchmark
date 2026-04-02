# Cilium Helm Values

## Phiên bản khuyến nghị

| Component  | Version | Ghi chú |
|------------|---------|----------|
| Cilium chart | **1.18.7** | Pin `--version 1.18.7` khi `helm install/upgrade` |
| Kubernetes (EKS) | **1.34** | Fallback 1.33 nếu region chưa hỗ trợ |

## Value files

| File | Mode | `kubeProxyReplacement` | CNI / IPAM |
|------|------|------------------------|------------|
| `values-baseline.yaml` | A — kube-proxy ON | `false` | AWS VPC CNI chaining |
| `values-ebpfkpr.yaml`  | B — eBPF KPR (kube-proxy-free) | `true` | AWS VPC CNI chaining |

## Cài đặt

```bash
helm repo add cilium https://helm.cilium.io
helm repo update

# Mode A: baseline
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.7 \
  -f values-baseline.yaml

# Mode B: eBPF KPR
helm upgrade --install cilium cilium/cilium \
  --namespace kube-system \
  --version 1.18.7 \
  -f values-ebpfkpr.yaml
```

> **Lưu ý Cilium 1.14+**: `kubeProxyReplacement` dùng **boolean** (`true`/`false`) thay vì chuỗi (`"strict"`/`"disabled"`).

> **EKS lưu ý**: Khi dùng Mode B (KPR), cần điền `k8sServiceHost` (EKS API endpoint hostname) trong `values-ebpfkpr.yaml`.

---

## Lịch sử cấu hình & các lỗi đã gặp

### Các tổ hợp IPAM/routing KHÔNG hợp lệ trên EKS

| IPAM | Routing | Lỗi | Ghi chú |
|------|---------|-------|---------|
| `eni` | `tunnel` | `Cannot specify IPAM mode eni in tunnel mode` | ENI IPAM bắt buộc native routing |
| `kubernetes` / `cluster` | `tunnel` | `required IPv4 PodCIDR not available` | EKS node không có annotation PodCIDR; Cilium deadlock ở `0/1 Ready` |
| `kubernetes` / `cluster` | `native` | `native routing cidr must be configured with --ipv4-native-routing-cidr` | Cần set `ipv4-native-routing-cidr` tường minh |
| `eni` | `native` (bare) | `eni allocator is not supported by this version of cilium-operator-generic` | Chart 1.18.7 dùng `cilium-operator-generic` không có ENI allocator |

### Giải pháp: AWS VPC CNI chaining

Trên EKS, **aws-node (VPC CNI)** đã gán IP cho pods qua ENI. Cilium không nên tranh giành IPAM.

```
aws-node (VPC CNI plugin)  →  gán IP qua ENI secondary IPs
        ↓
Cilium (chaining mode)    →  nhận network từ aws-node
                              gắn eBPF, policy, observability
                              KHÔNG gán IP
```

**Điều này áp dụng cho CẢ Mode A và Mode B** — cả hai đều dùng `cni.chainingMode: aws-cni`.

Mode A và Mode B **chỉ khác nhau** ở `kubeProxyReplacement`:
- **Mode A** `kubeProxyReplacement: false` → kube-proxy vẫn quản lý iptables NAT
- **Mode B** `kubeProxyReplacement: true` → Cilium thay thế kube-proxy bằng eBPF socket redirect

### File config chuẩn

**Mode A (`values-baseline.yaml`):**
```yaml
kubeProxyReplacement: false
cni:
  chainingMode: aws-cni
  exclusive: false
enableIPv4Masquerade: false
routingMode: native
hubble:
  enabled: true
  relay:
    enabled: true
```

**Mode B (`values-ebpfkpr.yaml`):**
```yaml
kubeProxyReplacement: true
cni:
  chainingMode: aws-cni
  exclusive: false
enableIPv4Masquerade: false
routingMode: native
k8sServiceHost: "<EKS-API-endpoint>"   # điền bằng terraform output cluster_endpoint
hubble:
  enabled: true
  relay:
    enabled: true
```

### Lệnh verify sau khi cài

```bash
# 1. Tất cả pods Ready
kubectl -n kube-system get pods | grep -E "cilium|operator|aws-node|kube-proxy"

# 2. ConfigMap đúng chaining
kubectl -n kube-system get cm cilium-config \
  -o jsonpath='{.data}' | grep -E "chaining|kube-proxy|routing-mode"

# 3. aws-node vẫn chạy (không bị Cilium thay thế)
kubectl -n kube-system get pods -l k8s-app=aws-node

# 4. kube-proxy chạy đúng mode
# Mode A: kubectl -n kube-system get ds kube-proxy  (Running)
# Mode B: kubectl -n kube-system get ds kube-proxy  (có thể Removed tùy config)

# 5. Hubble Ready (Mode B)
kubectl -n kube-system exec ds/cilium -- cilium hubble status
```

### Các lỗi thường gặp & cách debug

| Lỗi | Nguyên nhân | Cách fix |
|------|-------------|---------|
| `Cannot specify IPAM mode eni in tunnel mode` | ENI IPAM + tunnel routing | Dùng `cni.chainingMode: aws-cni` thay vì tự quản lý IPAM |
| `required IPv4 PodCIDR not available` | Cilium thiếu PodCIDR annotation trên node | Dùng `cni.chainingMode: aws-cni` — aws-node lo IPAM |
| `eni allocator is not supported by this version of cilium-operator-generic` | Chart 1.18.7 chạy generic operator, không có AWS allocator | Dùng `cni.chainingMode: aws-cni` — không cần ENI IPAM |
| `0/1 Ready` nhưng không crash | Cilium deadlock chờ thông tin node | Kiểm tra `kubectl -n kube-system get events --sort-by=.lastTimestamp` |
| Cilium pods crash sau vài phút | Config sai IPAM/routing | Xem log: `kubectl -n kube-system logs ds/cilium --previous` |
