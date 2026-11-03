resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "42.0.0"
  timeout          = 900

  values = [yamlencode({
    service = {
      type = "LoadBalancer"
      annotations = merge(
        { "service.beta.kubernetes.io/linode-loadbalancer-throttle" = "4" },
        length(var.ingress_allowed_cidrs) == 0 ? {} : {
          "service.beta.kubernetes.io/linode-loadbalancer-firewall-acl" = jsonencode({ allowList = { ipv4 = var.ingress_allowed_cidrs } })
        }
      )
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

data "linode_domain" "zone" {
  domain = var.domain
}

resource "linode_domain_record" "grafana" {
  domain_id   = data.linode_domain.zone.id
  name        = trimsuffix(local.grafana_host, ".${var.domain}")
  record_type = "A"
  target      = local.traefik_lb_ip
  ttl_sec     = 300
  lifecycle {
    precondition {
      condition     = endswith(local.grafana_host, ".${var.domain}")
      error_message = "grafana_host must be a hostname within domain."
    }
  }
}

resource "kubernetes_namespace_v1" "cert_manager" {
  metadata { name = "cert-manager" }
}

resource "kubernetes_secret_v1" "linode_credentials" {
  metadata {
    name      = "linode-credentials"
    namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  }
  data = {
    token = local.dns_token
  }
  lifecycle {
    precondition {
      condition     = local.dns_token != null
      error_message = "Set LINODE_TOKEN in ../.env, TF_VAR_linode_token, or TF_VAR_dns_token for DNS-01."
    }
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

resource "helm_release" "linode_webhook" {
  name      = "cert-manager-webhook-linode"
  namespace = kubernetes_namespace_v1.cert_manager.metadata[0].name
  chart     = "https://github.com/slicen/cert-manager-webhook-linode/releases/download/v0.2.0/cert-manager-webhook-linode-v0.2.0.tgz"

  # This image no longer accepts --v; zero makes the chart omit that flag.
  set {
    name  = "deployment.logLevel"
    value = "0"
  }
  depends_on = [helm_release.cert_manager, kubernetes_secret_v1.linode_credentials]
}

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
      adminPassword      = random_password.grafana.result
      deploymentStrategy = { type = "Recreate" }
      persistence = {
        enabled          = true
        storageClassName = "linode-block-storage"
        size             = "10Gi"
      }
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        annotations      = { "cert-manager.io/cluster-issuer" = var.cert_issuer }
        hosts            = [local.grafana_host]
        tls              = [{ secretName = "grafana-tls", hosts = [local.grafana_host] }]
      }
      "grafana.ini" = { server = { root_url = "https://${local.grafana_host}" } }
    }
    prometheus = {
      prometheusSpec = {
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = "linode-block-storage"
              accessModes      = ["ReadWriteOnce"]
              resources        = { requests = { storage = "20Gi" } }
            }
          }
        }
      }
    }
    kubeEtcd = {
      enabled        = true
      service        = { port = 2381, targetPort = 2381 }
      serviceMonitor = { scheme = "http" }
    }
    kubeControllerManager = { enabled = true }
    kubeScheduler         = { enabled = true }
    kubeProxy             = { enabled = true }
  })]

  depends_on = [helm_release.cluster_issuers, linode_domain_record.grafana]
}
