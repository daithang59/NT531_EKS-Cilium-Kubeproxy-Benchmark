# vpc/ — Module tạo VPC cho EKS

Module này tạo **Amazon VPC** với đầy đủ thành phần mạng cần thiết cho EKS cluster.

## Thành phần đã triển khai

| Tài nguyên | Mô tả |
|------------|-------|
| VPC | `10.0.0.0/16` — Virtual Private Cloud |
| Public Subnets | 2 subnet (`10.0.1.0/24`, `10.0.2.0/24`) ở 2 AZ — cho NAT Gateway |
| Private Subnets | 2 subnet (`10.0.10.0/24`, `10.0.11.0/24`) ở 2 AZ — cho EKS worker nodes |
| Internet Gateway | Public subnets truy cập internet |
| NAT Gateway | Single NAT GW — private subnets gọi ra internet (pull image, AWS API) |
| Route Tables | Tự động tạo cho public/private subnets |
| EKS Subnet Tags | `kubernetes.io/cluster/<name>`, `kubernetes.io/role/elb`, `kubernetes.io/role/internal-elb` |

## Implementation

Sử dụng community module `terraform-aws-modules/vpc/aws ~> 5.0`.

### Files

| File | Mô tả |
|------|-------|
| `main.tf` | VPC module call, AZ auto-discovery, subnet tags |
| `variables.tf` | `project_name`, `vpc_cidr`, `public_subnet_cidrs`, `private_subnet_cidrs` |
| `outputs.tf` | `vpc_id`, `private_subnet_ids`, `public_subnet_ids`, `vpc_cidr_block` |

### Input Variables

| Variable | Default | Mô tả |
|----------|---------|-------|
| `project_name` | — | Tên project, dùng cho naming |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block cho VPC |
| `public_subnet_cidrs` | `["10.0.1.0/24", "10.0.2.0/24"]` | CIDRs public subnets |
| `private_subnet_cidrs` | `["10.0.10.0/24", "10.0.11.0/24"]` | CIDRs private subnets |

## Lưu ý

- `single_nat_gateway = true` để tiết kiệm chi phí (chỉ cần 1 NAT cho benchmark).
- AZs được auto-discover từ region (lấy 2 AZ đầu tiên).
- Subnet tags cho EKS được tự động gán.
