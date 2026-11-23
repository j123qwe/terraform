output "grafana_url" {
  value = "https://${local.grafana_host}"
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}

output "traefik_lb_ip" {
  description = "Cilium-allocated Traefik LoadBalancer IP."
  value       = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip
}
