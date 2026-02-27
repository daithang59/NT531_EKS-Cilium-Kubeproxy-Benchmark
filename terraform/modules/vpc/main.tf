# ==============================================================================
# VPC Module — Creates VPC + subnets for EKS benchmark cluster
# ==============================================================================
# - VPC 10.0.0.0/16
# - 2 public subnets + 2 private subnets across 2 AZs
# - Internet Gateway, single NAT Gateway (cost-optimised)
# - EKS-required subnet tags
# ==============================================================================

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.project_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  # EKS-required tags for subnet auto-discovery
  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.project_name}"  = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"            = "1"
    "kubernetes.io/cluster/${var.project_name}"  = "shared"
  }

  tags = {
    Project     = var.project_name
    ManagedBy   = "terraform"
  }
}
