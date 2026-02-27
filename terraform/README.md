# terraform/ — Hạ tầng AWS bằng Infrastructure-as-Code

Thư mục này chứa cấu hình **Terraform** để provision toàn bộ hạ tầng AWS cần thiết cho benchmark: VPC và EKS cluster.

## Cấu trúc

```
terraform/
├── main.tf              # Entry point — provider, gọi modules VPC + EKS
├── variables.tf         # Input variables
├── outputs.tf           # Output values (cluster endpoint, kubeconfig command…)
├── envs/
│   └── dev/
│       └── terraform.tfvars   # Giá trị biến cho môi trường dev
└── modules/
    ├── vpc/             # Module VPC (terraform-aws-modules/vpc/aws ~> 5.0)
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── eks/             # Module EKS (terraform-aws-modules/eks/aws ~> 20.0)
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Architecture

- **VPC**: `10.0.0.0/16`, 2 public + 2 private subnets across 2 AZs, single NAT Gateway
- **EKS**: Managed Node Group with `t3.large` × 3, `min=desired=max=3` (no autoscaling)
- **Addons**: CoreDNS, kube-proxy, VPC CNI (installed via EKS addons)
- **Cilium**: NOT installed by Terraform — installed manually via Helm (see `docs/runbook.md`)

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
$(terraform output -raw kubeconfig_command)

# Verify
kubectl get nodes   # 3 nodes Ready
```

## Biến quan trọng

| Biến | Mặc định | Mô tả |
|------|----------|-------|
| `project_name` | — | Tên dự án, dùng làm prefix cho tài nguyên AWS |
| `region` | — | AWS region triển khai |
| `kubernetes_version` | `"1.34"` | Phiên bản Kubernetes cho EKS cluster |
| `cilium_version` | `"1.18.7"` | Phiên bản Cilium Helm chart (cho reference) |
| `instance_type` | `"t3.large"` | EC2 instance type cho worker nodes |
| `node_count` | `3` | Số node (min=desired=max) |
| `endpoint_public_access` | `true` | Cho phép truy cập EKS API endpoint public |

## Mode B — Lấy EKS API endpoint

Sau khi deploy, lấy endpoint cho `helm/cilium/values-ebpfkpr.yaml`:
```bash
terraform output cluster_endpoint
# → https://XXXXX.gr7.ap-southeast-1.eks.amazonaws.com
# Chỉ lấy hostname (bỏ https://), điền vào k8sServiceHost
```

## Lưu ý

- File `terraform.tfstate` nằm trong `.gitignore` — không commit lên git.
- Chạy `terraform fmt` (hoặc `make fmt`) để format code trước khi commit.
- Sau khi destroy cluster, kiểm tra AWS Console xem còn tài nguyên "mồ côi" (NAT Gateway, EIP…).
- Modules dùng `terraform-aws-modules` community modules cho VPC và EKS.
