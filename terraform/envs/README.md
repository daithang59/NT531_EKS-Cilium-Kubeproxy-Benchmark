# envs/ — Biến môi trường Terraform

Thư mục này chứa các file **terraform.tfvars** cho từng môi trường triển khai (dev, staging, production…).

## Cấu trúc

```
envs/
└── dev/
    └── terraform.tfvars    # Biến cho môi trường phát triển/benchmark
```

## Mục đích

Tách biệt cấu hình theo môi trường giúp:
- Dùng chung code Terraform nhưng thay đổi giá trị biến tùy môi trường.
- Tránh hardcode giá trị trong `main.tf` hoặc `variables.tf`.
- Dễ dàng thêm môi trường mới (ví dụ: `staging/`, `prod/`).

## Cách sử dụng

```bash
# Chỉ định file biến khi plan/apply
terraform plan  -var-file=envs/dev/terraform.tfvars
terraform apply -var-file=envs/dev/terraform.tfvars
```

## Thêm môi trường mới

Tạo thư mục mới và copy file tfvars:

```bash
mkdir -p envs/staging
cp envs/dev/terraform.tfvars envs/staging/terraform.tfvars
# Chỉnh sửa giá trị cho phù hợp
```
