# dashboards/ — Screenshots Grafana Dashboard

Thư mục này chứa **screenshots từ Grafana dashboards** được chụp trong quá trình chạy benchmark.

## Nội dung cần lưu

| Loại dashboard | Mô tả | Ví dụ tên file |
|----------------|-------|-----------------|
| Network Latency | Biểu đồ latency theo thời gian (p50, p90, p95, p99) | `latency_modeA_S1_L2.png` |
| Throughput | Biểu đồ RPS (requests per second) | `throughput_modeB_S1_L3.png` |
| Node Resources | CPU, Memory usage của từng node | `cpu_usage_modeA_S1.png` |
| Cilium Metrics | Forward/drop counts, policy verdicts, BPF map ops | `cilium_drops_modeB_S3.png` |

> Naming convention: `<metric>_mode<A|B>_<S1|S2|S3>_<L1|L2|L3>.png` — khớp với `results/` naming.

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
