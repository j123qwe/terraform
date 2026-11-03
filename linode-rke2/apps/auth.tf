locals {
  env_file        = pathexpand(coalesce(var.env_file, "${path.module}/../.env"))
  env_raw         = fileexists(local.env_file) ? file(local.env_file) : ""
  env_match       = regexall("(?m)^[ \\t]*(?:export[ \\t]+)?LINODE_TOKEN[ \\t]*=[ \\t]*[\"']?([^\"'\\s#]+)", local.env_raw)
  linode_token    = length(local.env_match) > 0 ? sensitive(local.env_match[0][0]) : var.linode_token
  dns_token       = var.dns_token != null ? var.dns_token : local.linode_token
  kubeconfig_path = pathexpand(coalesce(var.kubeconfig_path, "${path.module}/../kubeconfig-${var.cluster_label}.yaml"))
  grafana_host    = coalesce(var.grafana_host, "grafana.${var.domain}")
}
