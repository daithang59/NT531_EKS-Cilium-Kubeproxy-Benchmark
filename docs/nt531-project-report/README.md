# Tổ chức file cơ bản

Dựa trên cấu trúc của file `main.tex` và template từ `report_template.md`, dự án được tổ chức như sau để dễ dàng quản lý và biên dịch LaTeX:

## Cấu trúc thư mục đề xuất

```text
docs/nt531-project-report/
├── preamble.tex        # Cấu hình gói LaTeX (packages, định dạng, margins)
├── chapters/
│   ├── front/          # Phần mở đầu (front matter)
│   │   ├── glossaries.tex    # Danh mục từ viết tắt
│   │   └── thanks.tex        # Lời cảm ơn
│   └── main/           # Nội dung chính
│       ├── intro.tex          # Chương 0: Phạm vi thực nghiệm + Chương 1: Introduction
│       ├── chapter-1.tex      # Chương 2: Background & Related Work
│       ├── chapter-2.tex      # Chương 3: System Design & Methodology
│       ├── chapter-3.tex      # Chương 4: Results & Analysis
│       ├── conclusion.tex     # Chương 5: Conclusion
│       └── summary.tex        # Tóm tắt chung (nếu cần)
├── appendices/         # Phụ lục
│   ├── infrastructure.tex     # Chi tiết hạ tầng
│   ├── calibration.tex        # Dữ liệu calibration
│   ├── statistics.tex         # Phương pháp thống kê
│   ├── raw-data.tex           # Ánh xạ dữ liệu thô
│   ├── figures.tex            # Hình bổ sung
│   └── scripts.tex            # Scripts & cấu hình
├── graphics/           # Thư mục chứa hình ảnh và biểu đồ
│   ├── chapter-1/      # Hình cho Background
│   ├── chapter-2/      # Hình cho System Design
│   ├── chapter-3/      # Hình cho Results
│   └── appendices/     # Hình cho phụ lục
├── main.tex            # File LaTeX chính (tổng hợp tất cả)
├── project.cls         # Class tùy chỉnh cho định dạng (nếu có)
└── ref.bib             # Tài liệu tham khảo (bibliography)
```

## Giải thích cách tổ chức

- **preamble.tex**: Chứa tất cả cấu hình gói LaTeX (`\usepackage`, `\lstset`, margins, fonts, v.v.). Được import trong `main.tex` bằng `\input{preamble}`. Tách riêng để dễ quản lý cấu hình chung.
- **chapters/front/**: Chứa các phần mở đầu như danh mục từ viết tắt và lời cảm ơn, không phải là chương chính.
- **chapters/main/**: Chia nội dung chính thành các file riêng biệt theo chương để dễ chỉnh sửa và quản lý phiên bản.
  - `intro.tex`: Kết hợp Chương 0 (phạm vi thực nghiệm) và Chương 1 (Introduction) vì chúng liên quan đến giới thiệu tổng quan.
  - `chapter-1.tex` đến `chapter-3.tex`: Tương ứng với các chương 2-4 của thesis.
  - `conclusion.tex`: Chương 5.
  - `summary.tex`: Có thể dùng cho tóm tắt hoặc phần kết luận bổ sung nếu cần.
- **appendices/**: Chia phụ lục thành các file riêng để tránh file chính quá dài.
- **graphics/**: Tổ chức hình ảnh theo chương để dễ tìm và tham chiếu.
- **main.tex**: File chính import preamble và tất cả các file con, định nghĩa cấu trúc tổng thể.
- **ref.bib**: Chứa các citation để quản lý tài liệu tham khảo.

## Lưu ý

- Cấu trúc này linh hoạt và có thể điều chỉnh dựa trên độ dài của từng chương.
- `preamble.tex` được import trong `main.tex` bằng `\input{preamble}` — điều này thay thế tất cả cấu hình gói thành 1 dòng dễ đọc.
- Sử dụng `\input{chapters/main/intro.tex}` trong `main.tex` để include các file con chương.
- Đảm bảo đường dẫn tương đối chính xác khi biên dịch LaTeX.
