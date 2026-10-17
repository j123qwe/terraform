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
