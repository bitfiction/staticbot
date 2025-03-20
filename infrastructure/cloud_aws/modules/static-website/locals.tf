locals {
  domain_name_underscore = replace(var.domain_name, ".", "_")

  s3_origin_id = "S3-${var.stage_subdomain}.${var.domain_name}"
}
