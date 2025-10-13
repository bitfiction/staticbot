output "zone_id" {
  value = var.use_existing_hosted_zone ? data.aws_route53_zone.existing[0].zone_id : aws_route53_zone.main[0].zone_id
}

output "certificate_arn" {
  value = var.use_existing_certificate ? data.aws_acm_certificate.existing[0].arn : aws_acm_certificate.cert[0].arn
}

output "nameservers" {
  value = var.use_existing_hosted_zone ? data.aws_route53_zone.existing[0].name_servers : aws_route53_zone.main[0].name_servers
}
