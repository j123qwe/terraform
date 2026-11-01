output "cluster_id" {
  value = linode_lke_cluster.dev.id
}

output "k8s_version" {
  value = linode_lke_cluster.dev.k8s_version
}

output "api_endpoints" {
  value = linode_lke_cluster.dev.api_endpoints
}

output "kubeconfig_path" {
  value = abspath(local_sensitive_file.kubeconfig.filename)
}

output "kubectl_hint" {
  value = "export KUBECONFIG=${abspath(local_sensitive_file.kubeconfig.filename)} && kubectl get nodes"
}

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

# LDAP outputs are null when deploy_ldap = false
output "ldap_url" {
  value = var.deploy_ldap ? "ldap://${local.ldap_host}:389" : null
}

output "ldaps_url" {
  value = var.deploy_ldap ? "ldaps://${local.ldap_host}:636" : null
}

output "ldap_base_dn" {
  value = var.deploy_ldap ? local.ldap_base_dn : null
}

output "ldap_bind_dn" {
  value = var.deploy_ldap ? local.ldap_bind_dn : null
}

output "ldap_bind_password" {
  value     = one(random_password.ldap_bind[*].result)
  sensitive = true
}

output "ldap_admin_dn" {
  value = var.deploy_ldap ? local.ldap_admin_dn : null
}

output "ldap_admin_password" {
  value     = one(random_password.ldap_admin[*].result)
  sensitive = true
}

output "ldap_admin_gui_url" {
  value = var.deploy_ldap ? "https://${local.ldap_admin_host}" : null
}

output "ldap_users_csv" {
  value = var.deploy_ldap ? abspath(local_sensitive_file.ldap_users_csv[0].filename) : null
}
