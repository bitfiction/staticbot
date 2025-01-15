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
