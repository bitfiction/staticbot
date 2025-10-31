locals {
  domain_name_underscore = replace(var.domain_name, ".", "_")

  # In subdomain deployments, stage_subdomain can be empty.
  # We construct the full domain part of the bucket name carefully, avoiding leading/trailing dots.
  domain_part = join(".", compact([var.stage_subdomain, var.domain_name]))

  s3_origin_id = "S3-${local.domain_part}"

  # Calculate the length needed for the fixed parts
  fixed_part_length = length(local.domain_part) + 1 # +1 for the hyphen

  # Calculate the maximum allowed length for account_name
  max_account_name_length = 63 - local.fixed_part_length

  # Use the shorter of actual length or max allowed length
  truncated_account_name = substr(var.account_name, 0, min(length(var.account_name), local.max_account_name_length))

  # Construct the final bucket name.
  bucket_name = "${local.truncated_account_name}-${local.domain_part}"

  # Sanitize domain parts for resource naming. CloudFront Function names must match [a-zA-Z0-9-_]{1,64}.
  # We create a sanitized string by converting to lowercase, replacing any invalid characters with a hyphen,
  # and truncating to a safe length.
  sanitized_domain_part_for_naming = substr(lower(replace(local.domain_part, /[^a-zA-Z0-9_-]/, "-")), 0, 40)
}
