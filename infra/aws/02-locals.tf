locals {
  name_prefix  = "${var.project}-${var.env}"
  cluster_name = "${local.name_prefix}-eks"

  common_tags = {
    Project     = var.project
    Environment = var.env
    ManagedBy   = "terraform"
  }
}
