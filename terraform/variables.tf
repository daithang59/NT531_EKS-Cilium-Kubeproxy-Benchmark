variable "project_name" {
  description = "Project name, used for all resource naming"
  type        = string
}

variable "region" {
  description = "AWS region for all resources"
  type        = string
}

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

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.large"
}

variable "node_count" {
  description = "Number of worker nodes (min=desired=max, no autoscaling during benchmark)"
  type        = number
  default     = 3
}

variable "endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible"
  type        = bool
  default     = true
}
