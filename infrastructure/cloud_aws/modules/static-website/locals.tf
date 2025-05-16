locals {
  domain_name_underscore = replace(var.domain_name, ".", "_")

  s3_origin_id = "S3-${var.stage_subdomain}.${var.domain_name}"
}


locals {
  # Calculate the length needed for the fixed parts
  fixed_part_length = length("${var.stage_subdomain}.${var.domain_name}") + 1 # +1 for the hyphen
  
  # Calculate the maximum allowed length for account_name
  max_account_name_length = 63 - local.fixed_part_length
  
  # Use the shorter of actual length or max allowed length
  truncated_account_name = substr(var.account_name, 0, min(length(var.account_name), local.max_account_name_length))
  
  # Construct the final bucket name
  bucket_name = "${local.truncated_account_name}-${var.stage_subdomain}.${var.domain_name}"
}