# vpc.tf
module "vpc" {
  source = "git::https://github.com/simonangel-fong/terraform-template.git//aws/vpc-dev"

  name       = local.common_name
  cidr_block = "10.0.0.0/16"
  az_count   = 3

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = local.common_name
  }
}

# # Subnet discovery tags for AWS Load Balancer Controller.
# resource "aws_ec2_tag" "albc_public_subnets" {
#   for_each    = { for idx, id in module.vpc.public_subnet_ids : idx => id }
#   resource_id = each.value
#   key         = "kubernetes.io/role/elb"
#   value       = "1"
# }

# resource "aws_ec2_tag" "albc_private_subnets" {
#   for_each    = { for idx, id in module.vpc.private_subnet_ids : idx => id }
#   resource_id = each.value
#   key         = "kubernetes.io/role/internal-elb"
#   value       = "1"
# }


# # Subnet discovery tags for Karpenter.
# resource "aws_ec2_tag" "karpenter_discovery_subnets" {
#   for_each    = { for idx, id in module.vpc.private_subnet_ids : idx => id }
#   resource_id = each.value
#   key         = "karpenter.sh/discovery"
#   value       = local.common_name
# }
