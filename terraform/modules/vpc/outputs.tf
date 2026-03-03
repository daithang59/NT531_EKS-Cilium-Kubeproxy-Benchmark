output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnets
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value       = module.vpc.vpc_cidr_block
}

# First-AZ-only subnet for pinning benchmark workers (plan §2.3)
output "first_az_private_subnet_ids" {
  description = "Private subnet ID(s) in the first AZ only — use for node group to reduce inter-AZ noise"
  value       = [module.vpc.private_subnets[0]]
}
