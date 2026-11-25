locals {
  traefik_ip   = local.application_settings.traefik_load_balancer_ip
  assigned_ip  = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip
  grafana_host = coalesce(local.application_settings.grafana_host, "grafana.${local.assigned_ip}.${var.domain}")

  traefik_values = {
    service = {
      annotations = local.traefik_ip == null ? {} : { "lbipam.cilium.io/ips" = local.traefik_ip }
      spec        = { type = "LoadBalancer", externalTrafficPolicy = "Cluster" }
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
  }

  monitoring_values = {
    grafana = {
      admin       = { existingSecret = kubernetes_secret_v1.grafana.metadata[0].name, userKey = "admin-user", passwordKey = "admin-password" }
      persistence = { enabled = false }
      ingress = {
        enabled          = true
        ingressClassName = "traefik"
        annotations      = { "cert-manager.io/cluster-issuer" = "selfsigned" }
        hosts            = [local.grafana_host]
        tls              = [{ secretName = "grafana-tls", hosts = [local.grafana_host] }]
      }
      "grafana.ini" = { server = { root_url = "https://${local.grafana_host}" } }
    }
    kubeEtcd              = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeScheduler         = { enabled = false }
    kubeProxy             = { enabled = false }
  }
}

resource "helm_release" "longhorn" {
  name             = "longhorn"
  namespace        = "longhorn-system"
  create_namespace = true
  repository       = "https://charts.longhorn.io"
  chart            = "longhorn"
  version          = "1.13.0"
  timeout          = 900
  values = [yamlencode({
    persistence = {
      defaultClass             = true
      defaultClassReplicaCount = 1
    }
  })]

  depends_on = [terraform_data.kubeconfig_ready]
}

resource "helm_release" "traefik_ip_pool" {
  count            = local.traefik_ip == null ? 0 : (local.application_settings.traefik_ip_in_default_pool ? 0 : 1)
  name             = "traefik-ip-pool"
  namespace        = "traefik"
  create_namespace = true
  chart            = "${path.module}/apps/charts/traefik-ip-pool"
  values           = [yamlencode({ ip = local.traefik_ip })]
  depends_on       = [terraform_data.kubeconfig_ready]
}

resource "terraform_data" "traefik_pool_ready" {
  count            = length(helm_release.traefik_ip_pool)
  triggers_replace = [local.traefik_ip, helm_release.traefik_ip_pool[0].id]

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      for attempt in $(seq 1 60); do
        generation=$(kubectl get ciliumloadbalancerippool traefik-static -o jsonpath='{.metadata.generation}')
        observed=$(kubectl get ciliumloadbalancerippool traefik-static -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].observedGeneration}')
        status=$(kubectl get ciliumloadbalancerippool traefik-static -o jsonpath='{.status.conditions[?(@.type=="cilium.io/PoolConflict")].status}')
        if [ "$generation" = "$observed" ]; then
          if [ "$status" = "False" ]; then exit 0; fi
          if [ "$status" = "True" ]; then
            echo "Traefik IP pool conflicts with another Cilium pool." >&2
            exit 1
          fi
        fi
        sleep 2
      done
      echo "Timed out waiting for Cilium to validate the Traefik IP pool." >&2
      exit 1
    EOT
    environment = {
      KUBECONFIG = terraform_data.cluster_config.output
    }
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  namespace        = "traefik"
  create_namespace = true
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "42.0.0"
  timeout          = 900
  values           = [yamlencode(local.traefik_values)]

  depends_on = [terraform_data.kubeconfig_ready, terraform_data.traefik_pool_ready]
}

resource "terraform_data" "traefik_ip_ready" {
  count            = local.traefik_ip == null ? 0 : 1
  triggers_replace = [local.traefik_ip, helm_release.traefik.id]

  provisioner "local-exec" {
    command = "kubectl -n traefik wait --for=\"jsonpath={.status.loadBalancer.ingress[0].ip}=$TRAEFIK_IP\" service/traefik --timeout=300s"
    environment = {
      KUBECONFIG = terraform_data.cluster_config.output
      TRAEFIK_IP = local.traefik_ip
    }
  }
}

data "kubernetes_service_v1" "traefik" {
  provider = kubernetes.cluster
  metadata {
    name      = "traefik"
    namespace = helm_release.traefik.namespace
  }
  depends_on = [helm_release.traefik, terraform_data.traefik_ip_ready]

  lifecycle {
    postcondition {
      condition     = try(self.status[0].load_balancer[0].ingress[0].ip != "" && (local.traefik_ip == null || self.status[0].load_balancer[0].ingress[0].ip == local.traefik_ip), false)
      error_message = "Traefik has no LoadBalancer IP or did not receive the requested IP. Check Cilium pool conflicts and Service events."
    }
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.21.2"
  timeout          = 900
  set {
    name  = "crds.enabled"
    value = "true"
  }
  depends_on = [terraform_data.kubeconfig_ready]
}

resource "helm_release" "cluster_issuer" {
  name       = "cluster-issuer"
  namespace  = helm_release.cert_manager.namespace
  chart      = "${path.module}/apps/charts/cluster-issuer"
  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_namespace_v1" "monitoring" {
  provider = kubernetes.cluster
  metadata {
    name = "monitoring"
  }
  depends_on = [terraform_data.kubeconfig_ready]
}

resource "random_password" "grafana" {
  length  = 24
  special = false
}

resource "kubernetes_secret_v1" "grafana" {
  provider = kubernetes.cluster
  metadata {
    name      = "grafana-admin"
    namespace = kubernetes_namespace_v1.monitoring.metadata[0].name
  }
  data = {
    admin-user     = "admin"
    admin-password = random_password.grafana.result
  }
}

resource "helm_release" "monitoring" {
  name       = "monitoring"
  namespace  = kubernetes_namespace_v1.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "92.10.1"
  timeout    = 900
  values     = [yamlencode(local.monitoring_values)]

  depends_on = [terraform_data.traefik_ip_ready, helm_release.cluster_issuer, kubernetes_secret_v1.grafana]

  lifecycle {
    precondition {
      condition     = length(local.grafana_host) <= 253
      error_message = "The generated Grafana hostname must not exceed 253 characters."
    }
  }
}
