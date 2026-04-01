resource "digitalocean_kubernetes_cluster" "main" {
  name     = "${local.sanitized_name}-k8s"
  region   = var.do_region
  version  = var.k8s_version
  vpc_uuid = digitalocean_vpc.main.id

  node_pool {
    name       = "${local.sanitized_name}-pool"
    size       = var.node_size
    auto_scale = true
    min_nodes  = var.node_min_count
    max_nodes  = var.node_max_count
  }

  lifecycle {
    ignore_changes = [
      node_pool[0].labels,
      node_pool[0].name,
    ]
  }
}
