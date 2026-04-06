# ==============================================================================
# EKS Module — Creates EKS cluster + Managed Node Group for benchmark
# ==============================================================================
# - EKS cluster with specified Kubernetes version
# - Managed Node Group: m5.large × 3, min=desired=max=3 (no autoscaling)
# - OIDC provider for IAM Roles for Service Accounts (IRSA)
# - Cluster endpoint: private + public access (configurable)
# ==============================================================================

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.project_name
  cluster_version = var.kubernetes_version

  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids

  # Endpoint access
  cluster_endpoint_public_access  = var.endpoint_public_access
  cluster_endpoint_private_access = true

  # Run with restricted IAM accounts: disable defaults that require extra KMS/Logs permissions.
  cluster_encryption_config   = {}
  cluster_enabled_log_types   = []
  create_cloudwatch_log_group = false

  # OIDC for IRSA
  enable_irsa = true

  # Allow the IAM principal that creates the cluster to administer it via kubectl.
  enable_cluster_creator_admin_permissions = true

  # Disable automatic VPC CNI management — Cilium manages CNI via its own DaemonSet.
  # Without this, the module installs aws-node DaemonSet regardless of cluster_addons.
  manage_vpc_cni = false

  # Managed Node Group
  eks_managed_node_groups = {
    benchmark = {
      name           = "${var.project_name}-bm"
      instance_types = [var.instance_type]

      min_size     = var.node_count
      desired_size = var.node_count
      max_size     = var.node_count

      # Pin workers to first AZ only to reduce inter-AZ noise (plan §2.3)
      subnet_ids = var.benchmark_subnet_ids

      # Use latest Amazon Linux 2023 EKS AMI
      ami_type = "AL2023_x86_64_STANDARD"

      labels = {
        role = "benchmark"
      }

      tags = {
        Project   = var.project_name
        ManagedBy = "terraform"
      }
    }
  }

  # Cluster addons — vpc-cni is NOT installed (manage_vpc_cni = false above).
  # Cilium manages CNI via its own DaemonSet.
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
