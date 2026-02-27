# eks/ — Module tạo EKS Cluster

Module này tạo **Amazon EKS cluster** và **managed node group** để chạy benchmark.

## Thành phần đã triển khai

| Tài nguyên | Mô tả |
|------------|-------|
| EKS Cluster | Kubernetes control plane, version configurable (default `1.34`) |
| Managed Node Group | `t3.large` × 3, autoscaling tắt (min=desired=max) |
| IAM Roles | Tự động tạo bởi module (cluster + node group) |
| Security Groups | Control plane ↔ worker nodes communication |
| OIDC Provider | Cho IAM Roles for Service Accounts (IRSA) |
| EKS Addons | CoreDNS, kube-proxy, vpc-cni (latest compatible versions) |

## Implementation

Sử dụng community module `terraform-aws-modules/eks/aws ~> 20.0`.

### Files

| File | Mô tả |
|------|-------|
| `main.tf` | EKS module call, node group config, cluster addons, OIDC |
| `variables.tf` | `project_name`, `kubernetes_version`, `vpc_id`, `private_subnet_ids`, `instance_type`, `node_count`, `endpoint_public_access` |
| `outputs.tf` | `cluster_name`, `cluster_endpoint`, `cluster_certificate_authority_data`, `cluster_oidc_issuer_url`, `cluster_version`, `node_group_name` |

### Input Variables

| Variable | Default | Mô tả |
|----------|---------|-------|
| `project_name` | — | Tên project |
| `kubernetes_version` | `1.34` | K8s version |
| `vpc_id` | — | VPC ID từ VPC module |
| `private_subnet_ids` | — | Private subnet IDs từ VPC module |
| `instance_type` | `t3.large` | EC2 instance type |
| `node_count` | `3` | Số node (min=desired=max) |
| `endpoint_public_access` | `true` | Public API endpoint |

## Cấu hình quan trọng cho benchmark

- **Autoscaling tắt:** `min_size = max_size = desired_size` → số node cố định, tránh nhiễu.
- **Instance type `t3.large`:** 2 vCPU, 8 GiB RAM — burstable, cần theo dõi CPU credit.
- **3 nodes:** Scheduler phân bố pods trên nhiều node.
- **Addons:** CoreDNS + kube-proxy + vpc-cni cài tự động, Cilium cài riêng qua Helm.

## Lưu ý

- Sau khi tạo cluster: `aws eks update-kubeconfig --name <cluster-name> --region <region>`
- Lấy EKS API endpoint cho Mode B: `terraform output cluster_endpoint` → chỉ lấy hostname, điền vào `k8sServiceHost`.
- EKS cluster mất khoảng 10-15 phút để provision.
- **Nhớ destroy sau benchmark** để tránh chi phí: `terraform destroy -var-file=envs/dev/terraform.tfvars`.
