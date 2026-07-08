# argocd.tf

# ##############################
# ArgoCD (Helm)
# ##############################
resource "helm_release" "argocd" {
  name       = local.argocd_release
  repository = local.argocd_repo
  chart      = local.argocd_chart
  version    = local.argocd_chart_ver
  namespace  = local.argocd_namespace

  create_namespace = true

  values = compact([
    local.argocd_values
  ])

  atomic        = true
  wait          = true
  wait_for_jobs = true
  timeout       = 600

  depends_on = [module.eks]
}
