# Phân tích S2 p99 delta heatmap

## 1. Biểu đồ đang thể hiện gì

Hình `fig-s2-p99-delta-heatmap` thể hiện chênh lệch p99 latency của Mode B so với Mode A trong kịch bản S2. S2 là kịch bản phase-aware, trong đó workload được chia thành các phase ramp-up, sustained, burst và cooldown.

Trong heatmap:

- Hàng là các S2 phase.
- Cột là mức tải `L2` và `L3`.
- Giá trị trong mỗi ô là delta phần trăm của p99 latency.
- Màu xanh / số âm nghĩa là Mode B có p99 thấp hơn Mode A.
- Màu đỏ / số dương nghĩa là Mode B có p99 cao hơn Mode A.

Công thức sử dụng:

```text
delta_pct = (p99_mean_Mode_B - p99_mean_Mode_A) / p99_mean_Mode_A * 100
```

Giá trị p99 mean được tính trực tiếp từ raw final Fortio JSON:

- `results/mode=A_kube-proxy/scenario=S2/**/fortio_phase*.json`
- `results/mode=B_cilium-ebpfkpr/scenario=S2/**/fortio_phase*.json`

Fortio JSON lưu latency percentile theo giây, nên giá trị p99 được đổi sang millisecond trước khi tính mean và delta.

## 2. Bảng số liệu dùng để vẽ heatmap

| Phase | L2 A p99 mean | L2 B p99 mean | L2 delta | L3 A p99 mean | L3 B p99 mean | L3 delta |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ramp-up | 3.998 ms | 3.721 ms | -6.9% | 6.431 ms | 5.934 ms | -7.7% |
| Sustained | 7.061 ms | 6.381 ms | -9.6% | 13.094 ms | 11.839 ms | -9.6% |
| Burst 1 | 6.593 ms | 7.389 ms | +12.1% | 13.750 ms | 11.237 ms | -18.3% |
| Burst 2 | 6.895 ms | 6.828 ms | -1.0% | 13.572 ms | 11.453 ms | -15.6% |
| Burst 3 | 6.938 ms | 6.213 ms | -10.4% | 13.129 ms | 11.352 ms | -13.5% |
| Cooldown | 3.933 ms | 3.789 ms | -3.7% | 7.355 ms | 6.193 ms | -15.8% |

## 3. Phase nào Mode B tốt hơn

Mode B có p99 thấp hơn Mode A ở hầu hết các phase:

- `L2`: ramp-up, sustained, burst 2, burst 3 và cooldown đều âm.
- `L3`: cả 6 phase đều âm.

Kết quả mạnh nhất về mặt trực quan nằm ở `L3`, đặc biệt:

- Burst 1: Mode B thấp hơn khoảng 18.3%.
- Burst 2: Mode B thấp hơn khoảng 15.6%.
- Cooldown: Mode B thấp hơn khoảng 15.8%.
- Burst 3: Mode B thấp hơn khoảng 13.5%.

Theo góc nhìn đánh giá hiệu năng mạng, điều này gợi ý Mode B có lợi thế rõ hơn khi tải cao và khi workload có burst. Đây là điểm hợp lý về mặt kỹ thuật vì S2 L3 tạo áp lực lớn hơn lên datapath, nên khác biệt tail latency giữa hai chế độ có thể rõ hơn so với L2.

## 4. Phase nào khác biệt nhỏ

Một số ô có delta nhỏ, cần diễn giải như xu hướng nhẹ hơn là kết luận mạnh:

- `L2 Burst 2`: -1.0%, gần như không đáng kể về mặt thực tế.
- `L2 Cooldown`: -3.7%, nhỏ hơn các phase sustained/burst khác.
- `L2 Ramp-up`: -6.9%, có hướng tốt cho Mode B nhưng không quá lớn.

Những giá trị này hữu ích để cho thấy Mode B không phải lúc nào cũng tạo chênh lệch lớn. Trong thesis, nên nói rằng lợi thế của Mode B ở L2 không đồng đều qua mọi burst phase.

## 5. Phase nào cần diễn giải thận trọng

`L2 Burst 1` là ô duy nhất có delta dương:

- Mode A p99 mean: 6.593 ms.
- Mode B p99 mean: 7.389 ms.
- Delta: +12.1%.

Điều này nghĩa là trong `L2 Burst 1`, Mode B có p99 cao hơn Mode A trong raw final data. Không nên bỏ qua điểm này, vì nó cho thấy kết quả S2 không phải là "Mode B luôn tốt hơn Mode A".

Tuy nhiên, cần diễn giải thận trọng vì:

- mỗi group chỉ có 3 run;
- burst phase ngắn hơn sustained phase;
- S2 burst có run-to-run variance cao hơn S1;
- heatmap chỉ thể hiện delta mean, không tự nó chứng minh ý nghĩa thống kê.

Do đó, `L2 Burst 1` nên được viết là một ngoại lệ quan sát được trong dataset, không nên diễn giải thành bằng chứng rằng Mode B kém hơn trong mọi burst workload.

## 6. Ý nghĩa theo góc nhìn đánh giá hiệu năng mạng

Heatmap này giúp tách riêng từng phase của S2, tránh lỗi diễn giải gộp tất cả S2 vào một bucket. Đây là điều quan trọng vì ramp-up, sustained, burst và cooldown có đặc tính tải khác nhau.

Về mặt network performance evaluation:

- Các ô âm ở L3 cho thấy Mode B có tail latency tốt hơn Mode A khi tải cao.
- Các burst phase ở L3 cho thấy Mode B có vẻ xử lý burst/churn tốt hơn trong điều kiện benchmark này.
- `L2 Burst 1` cho thấy lợi thế không hoàn toàn đồng nhất và có thể bị ảnh hưởng bởi biến động run-to-run.
- Heatmap nên được xem là hình định hướng nhanh, còn kết luận thống kê cần dựa trên CI/p-value hoặc bảng repeatability bổ sung.

Nói cách khác, hình này cung cấp bằng chứng trực quan rằng datapath Mode B có xu hướng giảm p99 trong phần lớn phase S2, đặc biệt ở L3. Tuy nhiên, nó không đủ để tuyên bố nhân quả tuyệt đối nếu không kèm theo kiểm định và giới hạn mẫu đo.

## 7. Kết luận an toàn cho thesis

Kết luận an toàn có thể dùng:

> Trong kịch bản S2, heatmap delta p99 cho thấy Mode B có p99 latency thấp hơn Mode A ở hầu hết các phase, đặc biệt tại mức tải L3. Lợi thế của Mode B rõ hơn trong các phase burst và cooldown ở L3, với mức giảm p99 mean khoảng 13-18%. Tuy nhiên, tại L2 có một ngoại lệ ở Burst 1, nơi Mode B cao hơn Mode A khoảng 12.1%. Vì mỗi group chỉ có 3 run và heatmap chỉ thể hiện delta mean, kết quả nên được diễn giải như xu hướng hiệu năng theo phase, không phải bằng chứng thống kê tuyệt đối.

Không nên viết:

- "Mode B luôn tốt hơn Mode A trong S2."
- "Mode B chắc chắn giảm p99 trong mọi burst workload."
- "Màu xanh/đỏ trên heatmap tự nó chứng minh significance."

Nên viết:

- "Mode B có xu hướng p99 thấp hơn trong phần lớn S2 phase."
- "Lợi thế rõ hơn tại L3, đặc biệt trong các burst phase."
- "Một số phase cần được diễn giải thận trọng do cỡ mẫu nhỏ và variance giữa run."
