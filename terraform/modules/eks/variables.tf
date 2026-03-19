variable "project_name" {
  description = "Project name, used for cluster naming and tags"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC ID where the EKS cluster will be created"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for the EKS cluster (all AZs)"
  type        = list(string)
}

variable "benchmark_subnet_ids" {
  description = "Subnet IDs for benchmark node group — typically first-AZ-only to reduce inter-AZ noise (plan §2.3)"
  type        = list(string)
}

variable "instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "m5.large"
}

variable "node_count" {
  description = "Number of worker nodes (min=desired=max, no autoscaling)"
  type        = number
  default     = 3
}

variable "endpoint_public_access" {
  description = "Whether the EKS API endpoint is publicly accessible"
  type        = bool
  default     = true
}
