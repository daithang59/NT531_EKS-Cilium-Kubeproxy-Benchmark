terraform {
  required_version = ">= 1.5.0"
}

# ==============================================================
# Placeholder: thay bằng module VPC/EKS thực tế
# ==============================================================
#
# module "vpc" {
#   source = "./modules/vpc"
#   ...
# }
#
# module "eks" {
#   source             = "./modules/eks"
#   cluster_name       = var.project_name
#   kubernetes_version = var.kubernetes_version   # "1.34" (hoặc "1.33")
#   ...
# }
#
# --- Cilium install (via Helm provider hoặc null_resource) ---
# helm_release "cilium" {
#   chart      = "cilium"
#   repository = "https://helm.cilium.io"
#   version    = var.cilium_version               # "1.18.7"
#   ...
# }
