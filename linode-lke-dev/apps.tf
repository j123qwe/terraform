locals {
  # .env token wins; var.dns_token is the fallback when LINODE_TOKEN only lives in the environment
  dns_token    = local.linode_token != null ? local.linode_token : var.dns_token
  grafana_host = coalesce(var.grafana_host, "grafana.${var.domain}")
}

# ---------------------------------------------------------------- Traefik
resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "42.0.0"

  values = [yamlencode({
    # LoadBalancer Service -> Linode NodeBalancer
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/linode-loadbalancer-throttle" = "4"
      }
    }
    ingressClass = { enabled = true, isDefaultClass = true }
    ports = {
      web = {
        http = {
          redirections = {
            entryPoint = { to = "websecure", scheme = "https", permanent = true }
          }
        }
      }
    }
  })]

  depends_on = [linode_lke_cluster.dev]
}

data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = helm_release.traefik.namespace
  }
}

locals {
  traefik_lb_ip = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip
}

# ------------------------------------------------------------------- DNS
data "linode_domain" "zone" {
  domain = var.domain
}

resource "linode_domain_record" "grafana" {
  domain_id   = data.linode_domain.zone.id
  name        = trimsuffix(local.grafana_host, ".${var.domain}")
  record_type = "A"
  target      = local.traefik_lb_ip
  ttl_sec     = 300
}

# ----------------------------------------------------------- cert-manager
resource "kubernetes_namespace_v1" "cert_manager" {
  metadata { name = "cert-manager" }
  depends_on = [linode_lke_cluster.dev]
}

# Token the DNS-01 webhook uses to edit records in var.domain (needs Domains read/write scope).
resource "kubernetes_secret_v1" "linode_credentials" {
  lifecycle {
    precondition {
      condition     = local.dns_token != null
      error_message = "No Linode token found for DNS-01: put LINODE_TOKEN in the .env file or set var.dns_token (TF_VAR_dns_token)."
    }
  }

  metadata {
    name      = "linode-credentials"
    namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  }
  data = {
    token = local.dns_token
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  namespace  = kubernetes_namespace_v1.cert_manager.metadata[0].name
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.21.2"

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

# Linode DNS-01 solver webhook (slicen/cert-manager-webhook-linode; chart is only published as a release tarball)
resource "helm_release" "linode_webhook" {
  name      = "cert-manager-webhook-linode"
  namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  chart     = "https://github.com/slicen/cert-manager-webhook-linode/releases/download/v0.2.0/cert-manager-webhook-linode-v0.2.0.tgz"

  # The chart passes --v=<logLevel>, which the image's apiserver library no longer accepts
  # (crashloop: "unknown flag: --v"). 0 omits the flag.
  set {
    name  = "deployment.logLevel"
    value = "0"
  }

  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.linode_credentials]
}

# Local chart so the CRD-backed ClusterIssuers don't need the cluster at plan time
resource "helm_release" "cluster_issuers" {
  name      = "cluster-issuers"
  namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  chart     = "${path.module}/charts/cluster-issuers"

  set {
    name  = "email"
    value = var.acme_email
  }

  depends_on = [helm_release.linode_webhook]
}

# ------------------------------------------------------------- Monitoring
resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "helm_release" "monitoring" {
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "92.10.1"
  timeout          = 900

  values = [yamlencode({
    grafana = {
      adminPassword = random_password.grafana.result
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        annotations = {
          "cert-manager.io/cluster-issuer" = var.cert_issuer
        }
        hosts = [local.grafana_host]
        tls   = [{ secretName = "grafana-tls", hosts = [local.grafana_host] }]
      }
      "grafana.ini" = { server = { root_url = "https://${local.grafana_host}" } }
    }
    # LKE's control plane is managed; these scrape targets are unreachable
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false }
  })]

  depends_on = [helm_release.cluster_issuers, linode_domain_record.grafana]
}
