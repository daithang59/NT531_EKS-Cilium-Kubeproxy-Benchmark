# dev/ — Môi trường phát triển

Thư mục này chứa file biến Terraform cho **môi trường dev** — được sử dụng để chạy benchmark luận văn.

## File

| File | Mô tả |
|------|-------|
| `terraform.tfvars` | Giá trị biến đầu vào cho Terraform |

## Giá trị hiện tại

| Biến | Giá trị | Ghi chú |
|------|---------|---------|
| `project_name` | `"nt531-netperf"` | Prefix cho tên tài nguyên AWS |
| `region` | `"ap-southeast-1"` | AWS Singapore — gần Việt Nam, latency thấp |
| `kubernetes_version` | `"1.34"` | Phiên bản EKS Kubernetes |
| `cilium_version` | `"1.18.7"` | Phiên bản Cilium Helm chart |
| `instance_type` | `"t3.large"` | EC2 instance type cho worker nodes (2 vCPU, 8 GiB RAM) |
| `node_count` | `3` | Số node cố định: min=desired=max=3 (no autoscaling) |
| `endpoint_public_access` | `true` | Cho phép truy cập EKS API endpoint từ Internet |

## Lưu ý

- File `terraform.tfvars` **không chứa credentials** — AWS credentials được quản lý qua AWS CLI (`aws configure`) hoặc environment variables.
- Nếu region `ap-southeast-1` chưa hỗ trợ EKS 1.34, dùng fallback `1.33`.
- Sau khi apply, lấy EKS API endpoint cho Mode B: `terraform output cluster_endpoint`.
