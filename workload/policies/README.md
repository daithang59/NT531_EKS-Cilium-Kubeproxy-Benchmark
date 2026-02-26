# policies/ — CiliumNetworkPolicy

Thư mục này chứa các **CiliumNetworkPolicy** dùng để kiểm soát traffic giữa các pod trong benchmark.

## Danh sách file

| File | Mô tả |
|------|-------|
| `01-cilium-policy-allow-fortio-to-echo.yaml` | Cho phép ingress traffic từ pod `app=fortio` tới pod `app=echo` trên port `5678/TCP` |

## Chi tiết policy

```yaml
# Tóm tắt logic:
- endpointSelector: app=echo        # Áp dụng lên echo server
- ingress:
    from: app=fortio                 # Chỉ cho phép từ Fortio client
    toPorts: 5678/TCP                # Trên port HTTP của echo
```

**Ý nghĩa:** Khi policy được apply, chỉ có Fortio mới gọi được tới echo server. Mọi traffic khác (nếu có) sẽ bị chặn theo nguyên tắc **default deny** của CiliumNetworkPolicy.

## Vai trò trong benchmark

Policy này được dùng chủ yếu trong **Scenario 3 (Policy Toggle)**:

1. **Phase OFF:** Xóa policy → đo performance khi không có network policy enforcement.
2. **Phase ON:** Apply lại policy → đo performance khi Cilium phải kiểm tra policy rules cho mỗi packet.
3. So sánh kết quả giữa 2 phase để đánh giá **overhead của network policy** lên latency/throughput.

## Cách sử dụng

```bash
# Áp dụng policy
kubectl apply -f workload/policies/

# Xóa policy (cho phase OFF)
kubectl delete -f workload/policies/

# Kiểm tra policy đã apply
kubectl get cnp -n netperf
```

## Lưu ý

- **CiliumNetworkPolicy** (CNP) là CRD của Cilium — yêu cầu Cilium CNI đã cài đặt trên cluster.
- Khác với Kubernetes NetworkPolicy chuẩn, CNP hỗ trợ L7 filtering, DNS-aware policies, và nhiều tính năng nâng cao.
- Scripts `run_s3.sh` tự động xóa/apply policy — không cần thao tác thủ công khi chạy benchmark.
