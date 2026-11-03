output "grafana_url" {
  value = "https://${local.grafana_host}"
}

output "grafana_admin_password" {
  value     = random_password.grafana.result
  sensitive = true
}

output "traefik_lb_ip" {
  value = local.traefik_lb_ip
}
