output "zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "certificate_arn" {
  value = aws_acm_certificate.cert.arn
}

output "nameservers" {
  value = aws_route53_zone.main.name_servers
}
