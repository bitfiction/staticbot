variable "aws_account" {
  description = "AWS account configuration"
  type = object({
    account_id = string
    role_arn   = string
    region     = string
  })
}

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
