output "node_ips" {
  description = "Primary IPv4 addresses by node."
  value       = { for name, node in local.nodes : name => split("/", node.nic1)[0] }
}

output "kubeconfig_path" {
  description = "Cluster-admin kubeconfig generated after bootstrap."
  value       = abspath("${path.module}/kubeconfig-${var.namespace}.yaml")
  depends_on  = [terraform_data.cluster_config]
}

locals {
  application_settings = {
    domain                   = var.domain
    traefik_load_balancer_ip = var.traefik_load_balancer_ip
    traefik_ip_in_default_pool = var.traefik_load_balancer_ip == null ? null : try(
      sum([for i, octet in split(".", var.traefik_load_balancer_ip) : tonumber(octet) * pow(256, 3 - i)]) >= sum([for i, octet in split(".", var.load_balancer_ip_range.start) : tonumber(octet) * pow(256, 3 - i)]) &&
      sum([for i, octet in split(".", var.traefik_load_balancer_ip) : tonumber(octet) * pow(256, 3 - i)]) <= sum([for i, octet in split(".", var.load_balancer_ip_range.stop) : tonumber(octet) * pow(256, 3 - i)]), false
    )
    grafana_host = var.grafana_host != null ? var.grafana_host : (var.domain != null && var.traefik_load_balancer_ip != null ? "grafana.${var.traefik_load_balancer_ip}.${var.domain}" : null)
  }
}

output "application_settings" {
  description = "Nonsecret application configuration."
  value       = local.application_settings
  precondition {
    condition = var.traefik_load_balancer_ip == null ? true : !contains(
      concat([var.nic1_gateway], [for node in local.nodes : split("/", node.nic1)[0]], [for node in local.nodes : split("/", node.nic2)[0]]),
      var.traefik_load_balancer_ip
    )
    error_message = "The Traefik LoadBalancer IP must not match a node or gateway address."
  }
  precondition {
    condition     = var.grafana_host != null || var.domain == null || var.traefik_load_balancer_ip == null ? true : length("grafana.${var.traefik_load_balancer_ip}.${var.domain}") <= 253
    error_message = "The generated Grafana hostname must not exceed 253 characters."
  }
}
