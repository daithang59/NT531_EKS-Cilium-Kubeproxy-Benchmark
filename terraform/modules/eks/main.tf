# ==============================================================================
# EKS Module — nt531 benchmark cluster
# Module: terraform-aws-modules/eks/aws ~> 20.0
#
# Auth design:
#   - Cluster creator → không tạo access entry (enable_cluster_creator_admin_permissions = false)
#   - IAM user kubectl → access entry đã tồn tại trên AWS, quản lý ngoài Terraform (state rm)
#   - Node IAM role  → EKS tự tạo access entry cho managed node groups
#     khi dùng API_AND_CONFIG_MAP.
# ==============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project_name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  cluster_endpoint_public_access  = var.endpoint_public_access
  cluster_endpoint_private_access = true

  # ---------------------------------------------------------------------------
  # Authentication
  #
  # authentication_mode = "API_AND_CONFIG_MAP":
  #   Cho phép Access Entries (API) hoạt động cùng aws-auth ConfigMap.
  #   Khi dùng mode này, EKS tự tạo access entry cho IAM role của
  #   managed node groups.
  #   Set explicit vì rõ ràng.
  #
  # enable_cluster_creator_admin_permissions = false:
  #   Module KHÔNG tự tạo access entry cho principal chạy terraform.
  #   Access entry cho nt531-benchmark-thai đã tồn tại trên AWS
  #   (từ lần apply trước). Dùng terraform state rm để bỏ khỏi
  #   Terraform state, coi là resource ngoài Terraform management.
  #
  # access_entries = {}:
  #   Không khai báo thêm access_entries. Không tạo entry mới.
  # ---------------------------------------------------------------------------

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = false

  access_entries = {}

  # OIDC for IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # ---------------------------------------------------------------------------
  # Managed Node Group — benchmark workers, pinned to single AZ
  # ---------------------------------------------------------------------------
  eks_managed_node_groups = {
    benchmark = {
      name           = "${var.project_name}-nodes"
      instance_types = [var.instance_type]
      min_size       = var.node_count
      desired_size   = var.node_count
      max_size       = var.node_count
      subnet_ids     = var.benchmark_subnet_ids
      ami_type       = "AL2023_x86_64_STANDARD"
      labels = {
        role = "benchmark"
      }
      tags = {
        Project   = var.project_name
        ManagedBy = "terraform"
      }
    }
  }

  # Core addons
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
