# All Cloudflare Workers tenants share the prod state bucket (staticbot-prod-terraform-state)
# and lock table (staticbot-prod-terraform-locks). Those are provisioned once by
# infrastructure/cloudflare/environments/prod and managed outside this template.
#
# The remote-state step exists for per-customer AWS accounts (where each tenant gets its
# own S3 bucket + DynamoDB table). For Cloudflare Workers the step is a no-op — it just
# needs to pass so the main tofu_apply can proceed.
