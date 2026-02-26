# dashboards/ — Screenshots Grafana Dashboard

Thư mục này chứa **screenshots từ Grafana dashboards** được chụp trong quá trình chạy benchmark.

## Nội dung cần lưu

| Loại dashboard | Mô tả | Ví dụ tên file |
|----------------|-------|-----------------|
| Network Latency | Biểu đồ latency theo thời gian (p50, p90, p95, p99) | `latency_kubeproxy_s1_L2.png` |
| Throughput | Biểu đồ RPS (requests per second) | `throughput_ebpfkpr_s1_L3.png` |
| Node Resources | CPU, Memory usage của từng node | `cpu_usage_kubeproxy_s1.png` |
| Cilium Metrics | Forward/drop counts, policy verdicts, BPF map ops | `cilium_drops_ebpfkpr_s3.png` |

## Cách chụp

1. Truy cập Grafana UI (thường qua `kubectl port-forward`).
2. Chọn dashboard cần chụp.
3. Chỉnh **time range** cho đúng khoảng thời gian benchmark.
4. Dùng nút **Share → Direct link rendered image** hoặc screenshot thủ công.
5. Lưu file vào thư mục này với tên chuẩn.

## Lưu ý

- Chụp cùng time range cho cả Mode A và Mode B để so sánh công bằng.
- Nếu dùng Grafana export image API, có thể tự động hóa bằng script.
- `.gitkeep` sẽ bị xóa khi đã có file thật trong thư mục.
