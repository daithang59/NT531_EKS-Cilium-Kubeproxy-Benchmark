# terraform/ — Hạ tầng AWS bằng Infrastructure-as-Code

Thư mục này chứa cấu hình **Terraform** để provision toàn bộ hạ tầng AWS cần thiết cho benchmark: VPC và EKS cluster.

## Cấu trúc

```
terraform/
├── main.tf              # Entry point — khai báo provider, gọi modules
├── variables.tf         # Input variables (project_name, region, k8s version, cilium version)
├── outputs.tf           # Output values (cluster endpoint, kubeconfig…)
├── envs/
│   └── dev/
│       └── terraform.tfvars   # Giá trị biến cho môi trường dev
└── modules/
    ├── vpc/             # Module tạo VPC (subnets, NAT Gateway, Internet Gateway)
    └── eks/             # Module tạo EKS cluster + managed node group
```

## Hai phương án triển khai

| Phương án | Mô tả | Độ phức tạp |
|-----------|-------|-------------|
| Tự viết resource | Viết trực tiếp `aws_vpc`, `aws_eks_cluster`… | Cao — cần hiểu rõ AWS networking |
| Dùng `terraform-aws-modules` (khuyến nghị) | Sử dụng module cộng đồng `terraform-aws-modules/vpc/aws` và `terraform-aws-modules/eks/aws` | Thấp — chỉ cần cấu hình biến |

## Cách sử dụng

```bash
cd terraform

# Khởi tạo
terraform init

# Xem trước thay đổi
terraform plan -var-file=envs/dev/terraform.tfvars

# Triển khai hạ tầng
terraform apply -var-file=envs/dev/terraform.tfvars

# Lấy kubeconfig
aws eks update-kubeconfig --name nt531-netperf --region ap-southeast-1
```

## Biến quan trọng

| Biến | Mặc định | Mô tả |
|------|----------|-------|
| `project_name` | `"nt531-netperf"` | Tên dự án, dùng làm prefix cho tài nguyên AWS |
| `region` | `"ap-southeast-1"` | AWS region triển khai |
| `kubernetes_version` | `"1.34"` | Phiên bản Kubernetes cho EKS cluster |
| `cilium_version` | `"1.18.7"` | Phiên bản Cilium Helm chart |

## Lưu ý

- Thư mục `modules/` hiện là **placeholder** — cần implement logic VPC và EKS bên trong.
- File `terraform.tfstate` nằm trong `.gitignore` — không commit lên git.
- Chạy `terraform fmt` (hoặc `make fmt`) để format code trước khi commit.
- Sau khi destroy cluster, nhớ kiểm tra AWS Console xem còn tài nguyên "mồ côi" không (NAT Gateway, EIP…).
