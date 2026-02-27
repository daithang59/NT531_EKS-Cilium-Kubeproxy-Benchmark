# ==============================================================================
# EKS Module — Creates EKS cluster + Managed Node Group for benchmark
# ==============================================================================
# - EKS cluster with specified Kubernetes version
# - Managed Node Group: t3.large × 3, min=desired=max=3 (no autoscaling)
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

  # OIDC for IRSA
  enable_irsa = true

  # Managed Node Group
  eks_managed_node_groups = {
    benchmark = {
      name           = "${var.project_name}-benchmark"
      instance_types = [var.instance_type]

      min_size     = var.node_count
      desired_size = var.node_count
      max_size     = var.node_count

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

  # Cluster addons
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  tags = {
    Project   = var.project_name
    ManagedBy = "terraform"
  }
}
