# dashboards/ — Grafana Dashboard JSON Exports

Thư mục này chứa các file **JSON export** của Grafana dashboards, giúp tái tạo (import) dashboards trên bất kỳ Grafana instance nào.

## Mục đích

- **Reproducibility:** Bất kỳ ai cũng có thể import dashboard giống hệt mà không cần cấu hình thủ công.
- **Version control:** Theo dõi thay đổi dashboard qua git.
- **Collaboration:** Chia sẻ dashboard giữa các thành viên nhóm.

## Cách export dashboard từ Grafana

1. Mở Grafana UI → vào dashboard cần export.
2. Click biểu tượng **Share** (hoặc Settings → JSON Model).
3. Chọn **Export** → **Save to file**.
4. Lưu file JSON vào thư mục này.

## Cách import dashboard vào Grafana

1. Mở Grafana UI → **Dashboards** → **Import**.
2. Upload file JSON hoặc paste nội dung.
3. Chọn datasource Prometheus phù hợp.
4. Click **Import**.

## Dashboards gợi ý

| Dashboard | Mô tả |
|-----------|-------|
| Cilium Metrics | Theo dõi forward/drop, policy verdicts, BPF operations |
| Node Exporter | CPU, Memory, Disk, Network I/O per node |
| Kubernetes Overview | Pod status, deployment health, service endpoints |
| Custom Benchmark | Dashboard tùy chỉnh cho Fortio latency/throughput |

## Lưu ý

- Dashboard JSON cần loại bỏ `id` field (set `null`) để import không bị conflict.
- `.gitkeep` sẽ bị xóa khi đã có file JSON thật.
