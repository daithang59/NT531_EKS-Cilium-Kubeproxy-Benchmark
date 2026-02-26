# helm/ — Helm values cho Cilium và Monitoring

Thư mục này chứa các **Helm values files** để cài đặt Cilium CNI và monitoring stack lên cluster EKS.

## Cấu trúc

```
helm/
  cilium/
    values-baseline.yaml     # Values cho Mode A: kube-proxy ON (baseline)
    values-ebpfkpr.yaml      # Values cho Mode B: eBPF kube-proxy replacement
    README.md
  monitoring/
    values.yaml              # Values cho kube-prometheus-stack (placeholder)
    dashboards/              # Grafana dashboard JSON exports
      .gitkeep
    README.md
```

## Thư mục con

### `cilium/`

Chứa 2 bộ Helm values tương ứng 2 mode datapath cần so sánh:

| File | Mode | `kubeProxyReplacement` | Mô tả |
|------|------|----------------------|-------|
| `values-baseline.yaml` | A — kube-proxy | `false` | Cilium chạy song song với kube-proxy (iptables). Đây là baseline để so sánh. |
| `values-ebpfkpr.yaml` | B — eBPF KPR | `true` | Cilium thay thế hoàn toàn kube-proxy bằng eBPF. Không cần kube-proxy DaemonSet. |

> **Lưu ý Cilium 1.14+**: `kubeProxyReplacement` dùng **boolean** (`true`/`false`) thay vì chuỗi (`"strict"`/`"disabled"`).

Cả 2 đều bật **Hubble** (observability) với relay + UI.

**Cách dùng:**

```bash
# Cài mode baseline
helm upgrade --install cilium cilium/cilium -n kube-system \
  -f helm/cilium/values-baseline.yaml

# Hoặc mode eBPF KPR
helm upgrade --install cilium cilium/cilium -n kube-system \
  -f helm/cilium/values-ebpfkpr.yaml
```

### `monitoring/`

Placeholder để cài monitoring stack (ví dụ: kube-prometheus-stack).

- `values.yaml` — Helm values cho Prometheus + Grafana (điền sau khi chọn stack).
- `dashboards/` — Nơi lưu JSON export của Grafana dashboards (network perf, Cilium metrics…).

## Lưu ý

- Cần chỉnh `kubeProxyReplacement`, `routingMode`, `socketLB`… cho khớp version Cilium + EKS cụ thể.
- Khi chuyển từ Mode A sang Mode B: phải **uninstall Cilium → disable/remove kube-proxy → reinstall Cilium** với values mới.
- Hubble UI chỉ cần cho debug; production có thể tắt để giảm overhead.
