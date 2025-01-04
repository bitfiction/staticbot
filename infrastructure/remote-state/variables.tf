# infrastructure/remote-state/variables.tf

variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "business" {
  type = string
}

variable "terraform_role_arn" {
  type = string
}
