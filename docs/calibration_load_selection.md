# Calibration load selection

## 1. Mục tiêu

Mục tiêu của calibration là chọn các mức tải `L1`, `L2`, `L3` dựa trên dữ liệu đo thay vì chọn cảm tính. Các mức tải này được dùng làm đầu vào cho benchmark chính:

- S1: steady-state latency ở `L1`, `L2`, `L3`.
- S2: phase-aware stress/churn ở `L2`, `L3`.
- S3: NetworkPolicy OFF/ON ở `L2`, `L3`.

Dữ liệu calibration được lấy từ file non-pilot cuối cùng:

- `results/calibration/mode=A_kube-proxy/calibration_2026-04-12T05-24-25+07-00.csv`
- `results/calibration/mode=A_kube-proxy/calibration_2026-04-12T05-24-25+07-00.txt`

CSV calibration lưu latency theo **giây**, vì vậy bảng dưới đây đã đổi p50/p90/p99/p999 sang **millisecond**.

## 2. Bảng calibration load selection

| QPS | Conns | Runs | p50 | p90 | p99 | p999 | Achieved RPS | Error rate | Final load | Ghi chú |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| 50 | 4 | 2 | 0.150 ms | 0.267 ms | 0.293 ms | 0.295 ms | 50.000 | 0.000% | - | Dưới L1 final; quá nhẹ cho so sánh chính |
| 100 | 8 | 2 | 0.208 ms | 0.353 ms | 0.385 ms | 0.388 ms | 100.000 | 0.000% | L1 | Light baseline, tail latency thấp và ổn định |
| 200 | 16 | 2 | 1.833 ms | 2.639 ms | 2.742 ms | 2.753 ms | 200.000 | 0.000% | - | Điểm trung gian giúp quan sát chuyển tiếp lên L2 |
| 400 | 32 | 2 | 0.846 ms | 1.854 ms | 2.107 ms | 2.133 ms | 400.000 | 0.000% | L2 | Medium load, p99 đã thấy rõ nhưng chưa tạo lỗi |
| 800 | 64 | 2 | 1.709 ms | 4.411 ms | 33.006 ms | 33.420 ms | 799.900 | 0.000% | L3 | High stress point; p99 tăng mạnh nhưng RPS/error vẫn usable |
| 1600 | 64 | 2 | 3.085 ms | 5.746 ms | 48.135 ms | 49.152 ms | 1599.950 | 0.000% | - | Upper stress point trong calibration; không dùng làm L3 final |

## 3. Final load levels đang dùng trong benchmark

Theo `scripts/common.sh`, benchmark chính đang dùng:

| Load | QPS | Conns | Threads | Duration | Warm-up | Vai trò |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| L1 | 100 | 8 | 2 | 180 s | 30 s | Light baseline |
| L2 | 400 | 32 | 4 | 180 s | 30 s | Medium load |
| L3 | 800 | 64 | 8 | 180 s | 30 s | High stress / tail-spike load |

Cross-check với final `metadata.json` trong `results/mode=A_kube-proxy/` và `results/mode=B_cilium-ebpfkpr/` cho thấy:

- `L1`: 100 QPS, concurrency 8.
- `L2`: 400 QPS, concurrency 32.
- `L3`: 800 QPS, concurrency 64.

S2 dùng các giá trị này làm base load rồi tạo phase:

- ramp-up/cooldown: 50% base QPS;
- sustained: 100% base QPS;
- burst: 150% base QPS;
- sustained/burst dùng số connection cao hơn để tạo connection churn.

Vì vậy với `L3 = 800`, S2 burst chạy ở khoảng `1200 QPS`, không phải 800 QPS cố định trong mọi phase.

## 4. Diễn giải calibration sweep

Calibration sweep cho thấy ba vùng tải chính:

1. **Vùng rất nhẹ: 50-100 QPS**

   p99 rất thấp, dưới 0.4 ms ở 100 QPS. Đây là vùng phù hợp để chọn `L1`, vì nó đại diện cho baseline nhẹ, ít chịu ảnh hưởng bởi tail latency.

2. **Vùng medium: 200-400 QPS**

   p99 tăng lên mức vài millisecond. Ở 400 QPS, p99 mean khoảng 2.107 ms, achieved RPS vẫn đúng target và error rate bằng 0%. Đây là điểm hợp lý cho `L2`: đủ tạo tail latency quan sát được nhưng chưa đẩy hệ thống vào vùng tail spike mạnh.

3. **Vùng high stress: 800-1600 QPS**

   Tại 800 QPS, p99 tăng mạnh lên khoảng 33.006 ms, trong khi achieved RPS vẫn gần 800 và error rate vẫn 0%. Tại 1600 QPS, p99 tiếp tục tăng lên khoảng 48.135 ms nhưng error rate vẫn 0%.

Điểm quan trọng là calibration không cho thấy một saturation cliff theo nghĩa hệ thống bắt đầu lỗi HTTP hoặc không đạt RPS. Thay vào đó, dấu hiệu rõ nhất là **tail latency tăng mạnh**, đặc biệt từ 400 lên 800 QPS.

## 5. Vì sao final benchmark chọn L1/L2/L3 như hiện tại

Final benchmark chọn:

- `L1 = 100 QPS / 8 conns`
- `L2 = 400 QPS / 32 conns`
- `L3 = 800 QPS / 64 conns`

Cách chọn này có cơ sở từ calibration:

- `L1` lấy điểm nhẹ, ổn định, p99 thấp.
- `L2` lấy điểm medium có tail latency rõ hơn L1 nhưng vẫn không lỗi.
- `L3` lấy điểm đầu tiên trong sweep nơi p99 tăng mạnh, nhưng achieved RPS vẫn bám target và error rate vẫn 0%.

Điều này giúp benchmark có ba mức tải dễ diễn giải:

- light;
- medium;
- high stress.

Quan trọng: calibration report có gợi ý `L3` near-saturation ở `1600 QPS`. Final benchmark không dùng 1600 QPS làm L3, mà dùng 800 QPS. Cách viết thesis nên giải thích trung thực rằng 1600 là upper stress point trong calibration, còn 800 được chọn làm high-load final vì nó đã tạo tail spike rõ rệt nhưng vẫn giữ measurement usable cho S1/S2/S3. Nếu dùng 1600 làm base L3, S2 burst có thể lên 2400 QPS, làm kết quả dễ bị chi phối bởi stress cực cao hơn là so sánh datapath ổn định.

Ngoài ra, calibration script thực tế cap connection ở 64 trong sweep, nên dòng 1600 trong CSV có `conns = 64`. Calibration TXT có dòng `Suggested CONNS=128` cho 1600 QPS do công thức gợi ý không áp dụng cap này. Khi viết thesis, nên dựa vào CSV thực tế và `scripts/common.sh`, tức L3 final là `800 QPS / 64 conns`.

## 6. Wording an toàn cho thesis

Có thể viết:

> Các mức tải L1/L2/L3 được chọn dựa trên calibration sweep của Mode A. L1 được đặt tại 100 QPS để đại diện cho baseline nhẹ với p99 thấp. L2 được đặt tại 400 QPS vì p99 đã tăng lên mức quan sát được nhưng error rate vẫn bằng 0%. L3 được đặt tại 800 QPS vì đây là điểm đầu tiên trong sweep nơi p99 tăng mạnh, trong khi achieved RPS vẫn bám target và không xuất hiện lỗi HTTP. Do đó, L3 được xem là high-stress load dùng cho so sánh benchmark, không phải một saturation point tuyệt đối.

Không nên viết:

- "L3 là saturation point chính xác của hệ thống."
- "800 QPS là ngưỡng gãy tuyệt đối."
- "1600 QPS bị lỗi nên không dùng."

Nên viết:

- "L3 là high-load point với tail-latency spike rõ rệt."
- "Calibration cho thấy p99 tăng mạnh từ 400 lên 800 QPS, trong khi error rate vẫn 0%."
- "1600 QPS là upper stress point trong calibration, nhưng final benchmark chọn 800 QPS để cân bằng giữa stress level, tính ổn định và khả năng diễn giải."

## 7. Lưu ý về tài liệu trong repo

Nguồn authoritative cho final benchmark hiện tại là:

- `scripts/common.sh`
- final `metadata.json` trong `results/mode=A_kube-proxy/`
- final `metadata.json` trong `results/mode=B_cilium-ebpfkpr/`

Một số tài liệu cũ trong repo có thể còn nhắc tới default cũ như L2=500 hoặc L3=1000. Những giá trị đó không khớp với final raw data và không nên dùng cho thesis tables. Thesis nên dùng bảng calibration này cùng với `scripts/common.sh` và final metadata.
