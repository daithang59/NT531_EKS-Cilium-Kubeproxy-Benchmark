# Cilium Helm Values

## Phiên bản khuyến nghị

| Component  | Version | Ghi chú |
|------------|---------|----------|
| Cilium chart | **1.18.7** | Pin `--version 1.18.7` khi `helm install/upgrade` |
| Kubernetes (EKS) | **1.34** | Fallback 1.33 nếu region chưa hỗ trợ |

## Value files

| File | Mode | `kubeProxyReplacement` |
|------|------|------------------------|
| `values-baseline.yaml` | A — kube-proxy ON | `false` |
| `values-ebpfkpr.yaml`  | B — eBPF KPR (kube-proxy-free) | `true` |

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
