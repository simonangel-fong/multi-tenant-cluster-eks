# ################################################################################
# Phase 7.11 — public HTTPS on {subdomain}.{domain_name}
#
# Path: client -> Cloudflare DNS -> API Gateway custom domain (TLS terminated
#       here with ACM cert) -> VPC Link -> internal ALB -> pod.
#
# TLS terminates at API Gateway. The ALB stays HTTP-only inside the VPC.
# ################################################################################

locals {
  fqdn = "${var.subdomain}.${var.domain_name}"
}

# ####################
# Cloudflare zone lookup
# ####################
data "cloudflare_zone" "this" {
  name = var.domain_name
}

# ####################
# ACM certificate (DNS-validated via Cloudflare)
# ####################
resource "aws_acm_certificate" "voting" {
  domain_name       = local.fqdn
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.voting.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      value = dvo.resource_record_value
      type  = dvo.resource_record_type
    }
  }

  zone_id = data.cloudflare_zone.this.id
  name    = trimsuffix(each.value.name, ".")
  content = trimsuffix(each.value.value, ".")
  type    = each.value.type
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "voting" {
  certificate_arn         = aws_acm_certificate.voting.arn
  validation_record_fqdns = [for r in cloudflare_record.acm_validation : r.hostname]
}

# ####################
# API Gateway custom domain
# ####################
resource "aws_apigatewayv2_domain_name" "voting" {
  domain_name = local.fqdn

  domain_name_configuration {
    certificate_arn = aws_acm_certificate_validation.voting.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "voting" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.voting.id
  stage       = aws_apigatewayv2_stage.default.id
}

# ####################
# Cloudflare DNS record -> API Gateway regional domain
# gray cloud (proxied=false) so clients see the ACM cert directly
# ####################
resource "cloudflare_record" "voting" {
  zone_id = data.cloudflare_zone.this.id
  name    = var.subdomain
  content = aws_apigatewayv2_domain_name.voting.domain_name_configuration[0].target_domain_name
  type    = "CNAME"
  ttl     = 300
  proxied = false
}

output "voting_url" {
  description = "Public HTTPS URL for the voting app."
  value       = "https://${local.fqdn}"
}
