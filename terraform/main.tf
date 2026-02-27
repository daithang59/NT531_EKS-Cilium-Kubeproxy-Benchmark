terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

# ======================== VPC =================================================
module "vpc" {
  source = "./modules/vpc"

  project_name = var.project_name
}

# ======================== EKS =================================================
module "eks" {
  source = "./modules/eks"

  project_name           = var.project_name
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.vpc.vpc_id
  private_subnet_ids     = module.vpc.private_subnet_ids
  instance_type          = var.instance_type
  node_count             = var.node_count
  endpoint_public_access = var.endpoint_public_access
}
