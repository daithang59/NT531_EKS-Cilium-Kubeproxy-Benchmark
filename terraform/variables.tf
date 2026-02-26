variable "project_name" { type = string }
variable "region" { type = string }

variable "kubernetes_version" {
  description = "EKS Kubernetes version. Use 1.34 (recommended) or 1.33 if 1.34 is not yet available in your region/account."
  type        = string
  default     = "1.34"
}

variable "cilium_version" {
  description = "Cilium Helm chart version. Pin to latest patch of 1.18.x for stability."
  type        = string
  default     = "1.18.7"
}
