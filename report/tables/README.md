# tables/ — Bảng tổng hợp kết quả

Thư mục này chứa các **bảng dữ liệu tổng hợp** từ kết quả benchmark, phục vụ phân tích và chèn vào luận văn.

## Định dạng file

| Định dạng | Mục đích |
|-----------|----------|
| `.csv` | Dữ liệu thô — dễ xử lý bằng Python/pandas, Excel |
| `.tex` | Bảng LaTeX — chèn trực tiếp vào luận văn |
| `.md` | Bảng Markdown — hiển thị trên GitHub / README |

## Ví dụ bảng cần tạo

| Tên bảng | Nội dung |
|----------|----------|
| `latency_comparison.csv` | So sánh p50/p90/p95/p99 latency giữa Mode A vs Mode B, theo từng load level |
| `throughput_summary.csv` | Tổng hợp RPS thực tế vs RPS target cho mỗi scenario |
| `error_rate.csv` | Tỷ lệ lỗi (nếu có) cho từng lần chạy |
| `policy_overhead.csv` | So sánh latency trước/sau khi áp dụng network policy (Scenario 3) |

## Workflow tạo bảng

```bash
# Ví dụ dùng Python
python3 -c "
import json, glob, pandas as pd

data = []
for f in glob.glob('results/**/metadata.json', recursive=True):
    with open(f) as fh:
        data.append(json.load(fh))

df = pd.DataFrame(data)
df.to_csv('report/tables/latency_comparison.csv', index=False)
"
```

## Lưu ý

- Mỗi bảng nên có header rõ ràng (tên cột đầy đủ ý nghĩa).
- File `.gitkeep` sẽ bị xóa khi đã có dữ liệu thật.
- Nếu dùng LaTeX, đảm bảo format số thập phân nhất quán (ví dụ: 2 chữ số sau dấu phẩy).
