# Cilium Helm Values

## Phiên bản khuyến nghị

| Component  | Version | Ghi chú |
|------------|---------|---------|
| Cilium chart | **1.18.7** | Pin `--version 1.18.7` khi `helm install/upgrade` |
| Kubernetes (EKS) | **1.34** | Fallback 1.33 nếu region chỉ hỗ trợ |

## Value files

| File | Mode | `kubeProxyReplacement` |
|------|------|------------------------|
| `values-baseline.yaml` | A — kube-proxy ON | `false` |
| `values-ebpfkpr.yaml` | B — eBPF KPR (kube-proxy-free) | `true` |

## Cài đặt

> **Lưu ý quan trọng — Thứ tự cài đặt trên EKS:**
>
> EKS dùng VPC CNI (`aws-node`) làm CNI mặc định. **KHÔNG THỂ** cài Cilium chồng lên — sẽ conflict và crash.
>
> Đúng thứ tự:
> 1. Tắt VPC CNI trong Terraform (xóa khỏi `cluster_addons`) → `terraform apply`
> 2. Cài Cilium (thay thế VPC CNI làm CNI duy nhất)
> 3. Sau khi Cilium Ready → xóa `aws-node` DaemonSet nếu còn

### Mode A: baseline

```bash
# Tạo namespace cần thiết (cilium cần):
kubectl create namespace cilium-secrets

# Nếu Helm báo "no deployed releases" dù đã cài:
helm uninstall cilium -n kube-system

# Cài mới:
helm install cilium cilium/cilium -n kube-system --version 1.18.7 -f helm/cilium/values-baseline.yaml

# Verify:
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl get ds -n kube-system kube-proxy
```

### Mode B: eBPF KPR

```bash
# Lấy EKS API endpoint:
aws eks describe-cluster --name nt531-bm --region ap-southeast-1 --query cluster.endpoint --output text
# → Lấy hostname (KHÔNG có https://), điền vào values-ebpfkpr.yaml

# XÓA kube-proxy (BẮT BUỘC trước khi cài Mode B):
kubectl delete ds kube-proxy -n kube-system

# Cài Cilium:
helm install cilium cilium/cilium -n kube-system --version 1.18.7 -f helm/cilium/values-ebpfkpr.yaml

# Verify:
kubectl exec -n kube-system ds/cilium -- cilium status
kubectl exec -n kube-system ds/cilium -- cilium hubble status
```

## IPAM Modes

| File | IPAM Mode | Phù hợp khi |
|------|-----------|--------------|
| `values-baseline.yaml` | `cluster-pool` (10.96.0.0/16) | Cilium quản lý IP pods riêng |
| `values-ebpfkpr.yaml` | `eni` + `routingMode: native` | Dùng ENI của AWS (cần VPC CNI chaining) |

> ⚠️ **KHÔNG dùng `ipam.mode: eni` với tunnel VXLAN** — Cilium sẽ crash với lỗi `"Cannot specify IPAM mode eni in tunnel mode."`. Trên EKS dùng `routingMode: native` kèm `eni` IPAM.

## Verify sau khi cài

### Mode A — Baseline
```
KubeProxyReplacement: False
IPAM: IPv4: X/254 allocated from 10.96.0.0/24
kube-proxy DaemonSet: 3/3 Running
```

### Mode B — eBPF KPR
```
KubeProxyReplacement: Strict
IPAM: ENI mode
kube-proxy DaemonSet: ĐÃ XÓA
cilium hubble status: Relay Enabled
```
