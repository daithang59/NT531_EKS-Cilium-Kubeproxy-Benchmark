# vpc/ — Module tạo VPC cho EKS

Module này chịu trách nhiệm tạo **Amazon VPC** với đầy đủ thành phần mạng cần thiết cho EKS cluster.

## Thành phần cần triển khai

| Tài nguyên | Mô tả |
|------------|-------|
| VPC | Virtual Private Cloud với CIDR block (ví dụ: `10.0.0.0/16`) |
| Public Subnets | Ít nhất 2 subnet ở 2 AZ khác nhau — dùng cho Load Balancer, NAT Gateway |
| Private Subnets | Ít nhất 2 subnet ở 2 AZ — nơi chạy EKS worker nodes |
| Internet Gateway | Cho phép public subnet truy cập internet |
| NAT Gateway | Cho phép private subnet gọi ra internet (pull image, gọi AWS API) |
| Route Tables | Định tuyến traffic cho public/private subnets |

## Gợi ý sử dụng module cộng đồng

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.10.0/24", "10.0.11.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true   # tiết kiệm chi phí cho benchmark
}
```

## Lưu ý

- EKS yêu cầu subnet phải có tag `kubernetes.io/cluster/<cluster-name>` để tự động discover.
- Dùng `single_nat_gateway = true` để giảm chi phí (chỉ cần 1 NAT cho benchmark).
- Private subnet cần tag `kubernetes.io/role/internal-elb = 1` nếu dùng internal Load Balancer.
