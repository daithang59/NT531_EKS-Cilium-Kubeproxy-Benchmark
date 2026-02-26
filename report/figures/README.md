# figures/ — Hình ảnh minh họa cho báo cáo

Thư mục này chứa các **hình ảnh, biểu đồ, sơ đồ** dùng để chèn vào luận văn hoặc slide trình bày.

## Cấu trúc

```
figures/
└── dashboards/     # Screenshots từ Grafana dashboards
    └── .gitkeep
```

## Thư mục con

### `dashboards/`
Chứa screenshots Grafana dashboards trong quá trình benchmark:
- Latency heatmap
- Throughput (RPS) timeline
- CPU/Memory usage per node
- Cilium metrics (drops, policy verdicts, BPF map operations…)

## Quy ước đặt tên file

Đặt tên có ý nghĩa để dễ tham chiếu trong báo cáo:

```
<mode>_<scenario>_<metric>_<load>.png

Ví dụ:
  kubeproxy_s1_latency_L2.png
  ebpfkpr_s3_throughput_L3.png
  comparison_p99_all_loads.png
```

## Workflow

1. Chạy benchmark với monitoring stack bật.
2. Mở Grafana → chọn dashboard → chỉnh time range cho đúng khoảng benchmark.
3. Screenshot hoặc dùng tính năng "Share → Direct link rendered image" của Grafana.
4. Lưu vào thư mục tương ứng với tên chuẩn.
5. Tham chiếu trong LaTeX: `\includegraphics{figures/dashboards/kubeproxy_s1_latency_L2.png}`
