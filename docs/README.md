# docs/ — Tài liệu thiết kế thí nghiệm

Thư mục này chứa các tài liệu mô tả **thiết kế thí nghiệm** và **quy trình vận hành** (runbook) cho toàn bộ benchmark.

## Cấu trúc

| File | Mô tả |
|------|-------|
| `experiment_spec.md` | Đặc tả thí nghiệm: mục tiêu, biến kiểm soát, metrics, kịch bản, load levels, protocol thu thập dữ liệu |
| `runbook.md` | Checklist trước / trong / sau mỗi lần chạy benchmark, giúp đảm bảo kết quả đáng tin cậy |

## Vai trò trong dự án

- **experiment_spec.md** là tài liệu tham chiếu chính khi lập kế hoạch đo đạc.
  Mọi thay đổi về scenario, load level, hoặc metrics đều cập nhật ở đây trước.
- **runbook.md** là checklist vận hành; người chạy benchmark phải đọc và tick từng mục
  trước khi bắt đầu để tránh sai sót (quên deploy workload, autoscale đang bật, v.v.).

## Gợi ý mở rộng

- Thêm `architecture.md` nếu cần vẽ sơ đồ kiến trúc cluster.
- Thêm `troubleshooting.md` ghi lại các lỗi thường gặp và cách xử lý.
