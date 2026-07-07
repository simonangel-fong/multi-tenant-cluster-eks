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

variable "cluster_public_access_cidrs" {
  description = "CIDRs allowed to reach the EKS public API endpoint.(curl -4 ifconfig.me)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ##############################
# TLS / DNS (phase 7.11)
# ##############################
variable "domain_name" {
  description = "Apex domain managed in Cloudflare (e.g. arguswatcher.net)."
  type        = string
}

variable "subdomain" {
  description = "Subdomain hosting the voting app (e.g. voting -> voting.arguswatcher.net)."
  type        = string
  default     = "voting"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Zone:Read + DNS:Edit on the domain_name zone. Set via TF_VAR_cloudflare_api_token or tfvars."
  type        = string
  sensitive   = true
}
