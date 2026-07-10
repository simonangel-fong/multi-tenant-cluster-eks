# eks.tf

module "eks" {
  source = "git::https://github.com/simonangel-fong/terraform-template.git//aws/eks-dev"

  cluster_name    = local.common_name
  cluster_version = local.eks_version
  subnet_ids      = module.vpc.private_subnet_ids

  node_security_group_tags = {
    "karpenter.sh/discovery" = local.common_name
  }

  node_labels = {
    role                      = "bootstrap"
    "workload-class"          = "platform"
    "karpenter.sh/controller" = "true"
  }

  bootstrap_node_group = {
    taints = {
      "workload-class" = {
        value  = "platform"
        effect = "NO_SCHEDULE"
      }
    }
  }

  cluster_addons = {
    coredns = {
      configuration_values = jsonencode({
        tolerations = [
          { key = "workload-class", operator = "Equal", value = "platform", effect = "NoSchedule" },
          { key = "CriticalAddonsOnly", operator = "Exists" },
        ]
      })
    }
    metrics-server = {
      configuration_values = jsonencode({
        tolerations = [
          { key = "workload-class", operator = "Equal", value = "platform", effect = "NoSchedule" },
        ]
      })
    }
    kube-proxy = {}
    vpc-cni = {
      configuration_values = jsonencode({ enableNetworkPolicy = "true" })
    }
    "eks-pod-identity-agent" = {}
  }

  cluster_tags = local.default_tags
}
