# infrastructure/remote-state/variables.tf

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "account_name" {
  type = string
}

variable "terraform_role_arn" {
  type = string
}

variable "external_id" {
  type = string
}

variable "dynamo_table_name_suffix" {
  type    = string
  default = ""
  # default = "-tf-locks"
}

variable "s3_bucket_name_suffix" {
  type    = string
  default = ""
  # default = "-tf-state"
}

