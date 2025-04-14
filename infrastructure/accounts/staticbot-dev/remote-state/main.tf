module "remote_state" {
  source = "../../../cloud_aws/modules/remote-state"

  account_name             = var.account_name
  terraform_role_arn       = var.terraform_role_arn
  external_id              = null
  dynamo_table_name_suffix = "terraform-locks"
  s3_bucket_name_suffix    = "terraform-state"
}
