variable "project" {
  description = "Project name, used as a prefix for all resources."
  type        = string
  default     = "voting"
}

variable "env" {
  description = "Deployment environment (dev, prod, ...)."
  type        = string
  default     = "dev"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ca-central-1"
}

variable "azs" {
  description = "Availability zones used by the VPC."
  type        = list(string)
  default     = ["ca-central-1a", "ca-central-1b"]
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "cluster_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.33"
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "t3.large"
}

variable "node_desired_size" {
  description = "Desired number of nodes in the managed node group."
  type        = number
  default     = 3
}
