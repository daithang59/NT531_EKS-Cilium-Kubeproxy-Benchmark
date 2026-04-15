# Phân tích repeatability / stability của benchmark

## 1. Mục tiêu

Phần này đánh giá độ ổn định của benchmark qua các lần chạy lặp lại. Thay vì chỉ nhìn vào mean p99 latency, phân tích này xem mỗi nhóm đo có biến động nhiều hay ít giữa các raw run.

Các artifact được tạo:

- `results_analysis/repeatability_summary.csv`
- `docs/figures/thesis/fig-repeatability-p99-dotplot.png`
- `docs/figures/thesis/fig-repeatability-p99-dotplot.pdf`

## 2. Dữ liệu và cách tính

Dữ liệu được đọc trực tiếp từ raw final Fortio JSON:

- S1 và S3: `fortio.json`
- S2: `fortio_phase*.json`

Các nhóm đại diện được chọn:

- S1 L3
- S2 L2, phase-aware
- S2 L3, phase-aware
- S3 L3, policy OFF/ON

Các metric được tính:

```text
mean_p99_ms = mean(p99_ms)
stdev_p99_ms = sample standard deviation of p99_ms
CV_pct = stdev_p99_ms / mean_p99_ms * 100
n = number of raw runs
```

Mỗi nhóm hiện có `n = 3`, nên CV% nên được hiểu là mô tả repeatability trong dataset hiện tại, không phải ước lượng thống kê mạnh cho mọi lần chạy tương lai.

## 3. Bảng stability summary

| Scenario | Load | Phase | Group | Mean p99 | Stdev | CV% | n |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: |
| S1 | L3 | - | Mode A | 6.899 ms | 0.240 ms | 3.477% | 3 |
| S1 | L3 | - | Mode B | 5.917 ms | 0.013 ms | 0.212% | 3 |
| S2 | L2 | Ramp-up | Mode A | 3.998 ms | 0.108 ms | 2.700% | 3 |
| S2 | L2 | Ramp-up | Mode B | 3.721 ms | 0.035 ms | 0.937% | 3 |
| S2 | L2 | Sustained | Mode A | 7.061 ms | 0.171 ms | 2.418% | 3 |
| S2 | L2 | Sustained | Mode B | 6.381 ms | 0.524 ms | 8.218% | 3 |
| S2 | L2 | Burst 1 | Mode A | 6.593 ms | 0.199 ms | 3.011% | 3 |
| S2 | L2 | Burst 1 | Mode B | 7.389 ms | 0.886 ms | 11.996% | 3 |
| S2 | L2 | Burst 2 | Mode A | 6.895 ms | 0.443 ms | 6.420% | 3 |
| S2 | L2 | Burst 2 | Mode B | 6.828 ms | 0.949 ms | 13.896% | 3 |
| S2 | L2 | Burst 3 | Mode A | 6.938 ms | 0.546 ms | 7.873% | 3 |
| S2 | L2 | Burst 3 | Mode B | 6.213 ms | 0.276 ms | 4.444% | 3 |
| S2 | L2 | Cooldown | Mode A | 3.933 ms | 0.107 ms | 2.723% | 3 |
| S2 | L2 | Cooldown | Mode B | 3.789 ms | 0.015 ms | 0.392% | 3 |
| S2 | L3 | Ramp-up | Mode A | 6.431 ms | 0.401 ms | 6.238% | 3 |
| S2 | L3 | Ramp-up | Mode B | 5.934 ms | 0.170 ms | 2.864% | 3 |
| S2 | L3 | Sustained | Mode A | 13.094 ms | 1.468 ms | 11.207% | 3 |
| S2 | L3 | Sustained | Mode B | 11.839 ms | 0.244 ms | 2.064% | 3 |
| S2 | L3 | Burst 1 | Mode A | 13.750 ms | 1.662 ms | 12.089% | 3 |
| S2 | L3 | Burst 1 | Mode B | 11.237 ms | 0.438 ms | 3.895% | 3 |
| S2 | L3 | Burst 2 | Mode A | 13.572 ms | 1.995 ms | 14.702% | 3 |
| S2 | L3 | Burst 2 | Mode B | 11.453 ms | 0.443 ms | 3.864% | 3 |
| S2 | L3 | Burst 3 | Mode A | 13.129 ms | 1.187 ms | 9.038% | 3 |
| S2 | L3 | Burst 3 | Mode B | 11.352 ms | 0.366 ms | 3.226% | 3 |
| S2 | L3 | Cooldown | Mode A | 7.355 ms | 1.257 ms | 17.092% | 3 |
| S2 | L3 | Cooldown | Mode B | 6.193 ms | 0.341 ms | 5.499% | 3 |
| S3 | L3 | - | Policy OFF | 5.857 ms | 0.035 ms | 0.598% | 3 |
| S3 | L3 | - | Policy ON | 5.928 ms | 0.044 ms | 0.744% | 3 |

## 4. Diễn giải dot plot

Hình `fig-repeatability-p99-dotplot` dùng thiết kế đơn giản:

- mỗi điểm là một raw final run;
- mỗi nhóm có 3 điểm tương ứng 3 lần chạy;
- vạch ngang ngắn là mean p99 của nhóm;
- không dùng boxplot vì `n = 3` quá nhỏ để biểu diễn phân phối một cách thuyết phục.

Panel đầu so sánh các nhóm đại diện S1 L3 và S3 L3. Hai panel sau tách S2 L2 và S2 L3 theo phase để thấy biến động theo từng đặc tính workload.

## 5. Nhóm ổn định nhất

Các nhóm ổn định nhất trong tập đại diện là:

- S1 L3 Mode B: CV khoảng 0.212%.
- S3 L3 Policy OFF: CV khoảng 0.598%.
- S3 L3 Policy ON: CV khoảng 0.744%.
- S2 L2 Cooldown Mode B: CV khoảng 0.392%.
- S2 L2 Ramp-up Mode B: CV khoảng 0.937%.

Điều này cho thấy các phép đo steady-state hoặc policy OFF/ON ở L3 có độ lặp lại tốt trong dataset hiện tại. Đặc biệt, S3 L3 có p99 rất gần nhau qua 3 run ở cả policy OFF và ON, nên kết luận "policy overhead nhỏ trong dataset này" được hỗ trợ thêm về mặt repeatability.

## 6. Nhóm biến động cao hơn

Biến động cao tập trung chủ yếu ở S2:

- S2 L3 Cooldown Mode A: CV khoảng 17.092%.
- S2 L3 Burst 2 Mode A: CV khoảng 14.702%.
- S2 L3 Burst 1 Mode A: CV khoảng 12.089%.
- S2 L3 Sustained Mode A: CV khoảng 11.207%.
- S2 L2 Burst 2 Mode B: CV khoảng 13.896%.
- S2 L2 Burst 1 Mode B: CV khoảng 11.996%.

Điểm này quan trọng vì S2 là workload có phase và burst, nên tail latency không chỉ phụ thuộc vào mode datapath mà còn phụ thuộc vào thời điểm tải thay đổi. Với các phase burst/cooldown, p99 dễ dao động hơn giữa các run so với S1/S3.

## 7. Ý nghĩa cho benchmark rigor

Phân tích repeatability giúp thesis tránh chỉ dựa vào mean. Nếu hai mode có mean khác nhau nhưng một nhóm có CV cao, kết luận cần thận trọng hơn vì khác biệt có thể bị ảnh hưởng bởi run-to-run noise.

Trong dataset này:

- S1 L3 Mode B và S3 L3 có độ ổn định tốt, nên các kết quả ở các nhóm này tương đối dễ diễn giải.
- S2 L3 Mode A có variance cao ở sustained/burst/cooldown, do đó các so sánh S2 nên giữ phase-aware và đi kèm CI/delta thay vì gộp toàn bộ S2.
- S2 L2 có một số phase Mode B biến động cao, đặc biệt Burst 1 và Burst 2, nên các ngoại lệ trong S2 heatmap cần được đọc cùng dot plot repeatability.

## 8. Kết luận an toàn cho thesis

Câu kết luận an toàn có thể dùng:

> Phân tích repeatability từ raw Fortio data cho thấy các nhóm S1 L3 và S3 L3 có độ lặp lại tốt, với CV p99 thấp trong các run đại diện. Ngược lại, S2 có biến động cao hơn, đặc biệt ở các phase burst và cooldown. Điều này củng cố quyết định phân tích S2 theo từng phase thay vì gộp toàn bộ S2 thành một nhóm duy nhất. Tuy nhiên, vì mỗi nhóm chỉ có 3 run, các giá trị CV nên được xem là bằng chứng mô tả về độ ổn định trong dataset hiện tại, không phải ước lượng thống kê đầy đủ cho mọi môi trường.

Không nên viết:

- "Benchmark hoàn toàn ổn định trong mọi trường hợp."
- "CV từ n=3 chứng minh chắc chắn phương sai của hệ thống."
- "S2 Mode A luôn unstable trong mọi workload."

Nên viết:

- "Các nhóm S1/S3 đại diện có repeatability tốt trong dataset hiện tại."
- "S2 thể hiện biến động cao hơn, đặc biệt ở phase burst/cooldown."
- "Kết quả S2 cần được diễn giải theo phase và kèm lưu ý về cỡ mẫu."
