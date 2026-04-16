# --- nginx-ingress controller ---
# Auto-provisions a DigitalOcean Load Balancer (~$12/mo).
# All external traffic flows: Internet → DO LB → nginx-ingress → K8s Services

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.9.1"
  namespace        = "ingress-nginx"
  create_namespace = true

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-enable-proxy-protocol"
    value = "true"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/do-loadbalancer-name"
    value = "${local.sanitized_name}-lb"
  }

  set {
    name  = "controller.config.use-proxy-protocol"
    value = "true"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }
}

# Query the Load Balancer IP after nginx-ingress creates it
data "kubernetes_service" "ingress_nginx_controller" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}

# --- cert-manager (automatic TLS via Let's Encrypt) ---

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "1.14.5"
  namespace        = "cert-manager"
  create_namespace = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  depends_on = [helm_release.ingress_nginx]
}

# ClusterIssuer for Let's Encrypt production
resource "kubernetes_manifest" "letsencrypt_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.letsencrypt_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-private-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              class = "nginx"
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# --- Ingress rules ---
# Routes external traffic to Kong (API gateway) which handles all Supabase routing.

resource "kubernetes_ingress_v1" "supabase" {
  metadata {
    name      = "supabase-ingress"
    namespace = kubernetes_namespace.supabase.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer"                 = "letsencrypt-prod"
      "nginx.ingress.kubernetes.io/proxy-body-size"    = "50m"
      "nginx.ingress.kubernetes.io/proxy-read-timeout" = "150"
      "nginx.ingress.kubernetes.io/proxy-send-timeout" = "150"
      # WebSocket support for Realtime
      "nginx.ingress.kubernetes.io/proxy-http-version" = "1.1"
      "nginx.ingress.kubernetes.io/upstream-hash-by"   = "$remote_addr"
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = [var.domain_name]
      secret_name = "supabase-tls"
    }

    rule {
      host = var.domain_name

      http {
        # All traffic goes to Kong — Kong handles internal routing
        # to auth, rest, realtime, storage, functions, studio, meta
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.kong.metadata[0].name
              port {
                number = 8000
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.ingress_nginx,
    kubernetes_manifest.letsencrypt_issuer,
  ]
}
