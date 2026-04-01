resource "digitalocean_vpc" "main" {
  name     = "${local.sanitized_name}-vpc"
  region   = var.do_region
  ip_range = var.vpc_cidr
}
