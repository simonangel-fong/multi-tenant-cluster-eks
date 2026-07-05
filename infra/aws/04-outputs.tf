output "region" {
  description = "AWS region."
  value       = var.region
}

output "name_prefix" {
  description = "Resource name prefix."
  value       = local.name_prefix
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (workloads + private ALB)."
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Public subnet IDs (NAT gateway only)."
  value       = module.vpc.public_subnets
}
