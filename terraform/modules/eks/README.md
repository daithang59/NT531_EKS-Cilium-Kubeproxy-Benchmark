# eks/ — Module tạo EKS Cluster

Module này chịu trách nhiệm tạo **Amazon EKS cluster** và **managed node group** để chạy benchmark.

## Thành phần cần triển khai

| Tài nguyên | Mô tả |
|------------|-------|
| EKS Cluster | Kubernetes control plane, version `1.34` (fallback `1.33`) |
| Managed Node Group | Nhóm EC2 worker nodes (`t3.large`, 3 nodes, autoscaling tắt) |
| IAM Roles | Role cho cluster và node group (AmazonEKSClusterPolicy, AmazonEKSWorkerNodePolicy…) |
| Security Groups | Cho phép giao tiếp giữa control plane và worker nodes |
| OIDC Provider | Cần cho IAM Roles for Service Accounts (IRSA) |

## Gợi ý sử dụng module cộng đồng

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${var.project_name}-cluster"
  cluster_version = var.kubernetes_version   # "1.34" (fallback "1.33")

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    benchmark = {
      instance_types = ["t3.large"]
      min_size       = 3
      max_size       = 3       # tắt autoscaling cho benchmark
      desired_size   = 3
    }
  }
}
```

## Cấu hình quan trọng cho benchmark

- **Autoscaling tắt:** `min_size = max_size = desired_size` để đảm bảo số node cố định, tránh ảnh hưởng kết quả đo.
- **Instance type `t3.large`:** 2 vCPU, 8 GiB RAM — đủ cho workload benchmark nhẹ.
- **3 nodes:** Đảm bảo scheduler có thể phân bố pods trên nhiều node.

## Lưu ý

- Sau khi tạo cluster, chạy `aws eks update-kubeconfig` để cập nhật kubeconfig local.
- Khi dùng Mode B (eBPF KPR), cần lấy **EKS API endpoint** để điền vào `k8sServiceHost` trong Helm values.
- EKS cluster mất khoảng 10-15 phút để provision hoàn tất.
- Nhớ destroy cluster sau khi benchmark xong để tránh phát sinh chi phí.
