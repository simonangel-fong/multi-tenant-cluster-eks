# vpc.tf
module "vpc" {
  source = "git::https://github.com/simonangel-fong/terraform-template.git//aws/vpc-dev"

  name       = local.common_name
  cidr_block = local.vpc_cidr
  az_count   = local.vpc_az_count

  # tag: elb
  public_subnet_tags = {
    "kubernetes.io/role/elb"                     = "1"
    "kubernetes.io/cluster/${local.common_name}" = "shared"
  }

  # tab: kapenter;
  private_subnet_tags = {
    "karpenter.sh/discovery" = local.common_name
  }
}
