# report/ — Báo cáo và tài liệu trình bày

Thư mục này chứa các **tài liệu báo cáo** phục vụ viết luận văn / trình bày kết quả.

## Cấu trúc

```
report/
  figures/
    dashboards/       # Screenshots Grafana dashboards
      .gitkeep
  tables/             # Bảng tổng hợp kết quả (CSV, LaTeX, Markdown)
    .gitkeep
  appendix/           # Phụ lục: cấu hình chi tiết, raw logs trích dẫn
    .gitkeep
```

## Giải thích thư mục con

| Thư mục | Mô tả |
|---------|-------|
| `figures/dashboards/` | Chứa screenshot từ Grafana dashboards — latency heatmap, throughput timeline, CPU/memory usage. Dùng để chèn vào báo cáo/slide. |
| `tables/` | Bảng kết quả tổng hợp. Có thể ở dạng CSV (cho phân tích), LaTeX (cho luận văn), hoặc Markdown (cho README). Ví dụ: bảng so sánh p99 latency giữa Mode A vs Mode B. |
| `appendix/` | Phụ lục bổ sung: trích dẫn cấu hình Terraform, Helm values, cilium status output, hoặc logs đặc biệt cần tham chiếu. |

## Workflow gợi ý

1. Sau khi chạy benchmark → copy screenshots Grafana vào `figures/dashboards/`.
2. Dùng script Python / pandas để parse `results/` → tạo bảng tổng hợp trong `tables/`.
3. Export bảng sang LaTeX → chèn vào luận văn.
4. Lưu các config / output đặc biệt vào `appendix/` để referee có thể xác minh.

## Lưu ý

- Đặt tên file có ý nghĩa, ví dụ: `latency_comparison_s1_L2.png`, `throughput_summary.csv`.
- `.gitkeep` files chỉ để git track thư mục trống — xóa khi đã có file thật.
