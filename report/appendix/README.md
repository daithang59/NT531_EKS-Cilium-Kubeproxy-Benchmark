# appendix/ — Phụ lục

Thư mục này chứa các **tài liệu phụ lục** bổ sung cho luận văn — bao gồm cấu hình chi tiết, raw logs, và các artifacts tham chiếu.

## Nội dung gợi ý

| Loại tài liệu | Mô tả |
|----------------|-------|
| Cấu hình Terraform | Trích dẫn `main.tf`, `variables.tf` cho referee xem cấu hình hạ tầng |
| Helm Values | Copy `values-baseline.yaml` và `values-ebpfkpr.yaml` để minh họa sự khác biệt 2 mode |
| Cilium Status | Output `cilium status` cho mỗi mode — chứng minh cấu hình đúng |
| Raw Logs | Trích dẫn `bench.log` tiêu biểu — minh họa format output Fortio |
| Kubernetes Manifests | Trích dẫn workload manifests cho referee hiểu workload |

## Workflow

1. Sau khi hoàn thành toàn bộ benchmark, chọn các artifacts tiêu biểu.
2. Copy hoặc trích dẫn vào thư mục này.
3. Đặt tên file rõ ràng, ví dụ:
   - `cilium_status_kubeproxy.txt`
   - `cilium_status_ebpfkpr.txt`
   - `sample_bench_output.log`
   - `helm_values_diff.txt`

## Lưu ý

- Phụ lục giúp **tái tạo kết quả** (reproducibility) — nên đưa đủ thông tin cấu hình.
- File `.gitkeep` sẽ bị xóa khi đã có nội dung thật.
- Không đưa toàn bộ raw data vào phụ lục — chỉ trích dẫn tiêu biểu, phần còn lại lưu trong `results/`.
