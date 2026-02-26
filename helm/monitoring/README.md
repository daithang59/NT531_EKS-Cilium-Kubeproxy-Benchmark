# monitoring/ — Giám sát hiệu năng cluster

Thư mục này chứa cấu hình để triển khai **monitoring stack** lên cluster EKS, phục vụ thu thập metrics trong quá trình benchmark.

## Cấu trúc

| File / Thư mục | Mô tả |
|----------------|-------|
| `values.yaml` | Helm values cho monitoring stack (ví dụ: kube-prometheus-stack). Hiện là placeholder — điền sau khi chọn stack cụ thể. |
| `dashboards/` | Nơi lưu file JSON export của Grafana dashboards (network performance, Cilium metrics, node resources…). |

## Lựa chọn stack giám sát

Có thể dùng một trong các phương án:

1. **kube-prometheus-stack** (khuyến nghị) — bao gồm Prometheus, Grafana, Alertmanager, node-exporter.
2. **metrics-server + custom dashboards** — nhẹ hơn, phù hợp nếu chỉ cần CPU/memory cơ bản.

## Cài đặt (ví dụ kube-prometheus-stack)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f helm/monitoring/values.yaml
```

## Lưu ý

- Export dashboard JSON từ Grafana UI → lưu vào `dashboards/` để có thể tái tạo (reproducible).
- Nếu Cilium bật Prometheus metrics (`prometheus.enabled: true`), Grafana sẽ tự động scrape Cilium metrics.
- Monitoring stack có thể gây thêm overhead trên node — cân nhắc tắt khi chạy benchmark nếu cần kết quả chính xác tuyệt đối.
