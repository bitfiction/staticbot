module "remote_state" {
  source = "../../../cloud_aws/modules/remote-state"

  aws_region         = var.aws_region
  account_name       = var.account_name
  terraform_role_arn = var.terraform_role_arn
  external_id        = var.external_id
}
