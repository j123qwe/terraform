output "api_endpoint" {
  value = local.api_url
}

output "registration_endpoint" {
  value = local.registration_url
}

output "api_nodebalancer_id" {
  value = linode_nodebalancer.api.id
}

output "masters" {
  value = { for name, node in linode_instance.masters : name => {
    id = node.id, public_ip = local.public_ips[name], private_ip = node.private_ip_address
  } }
}

output "workers" {
  value = { for name, node in linode_instance.workers : name => {
    id = node.id, public_ip = local.public_ips[name], private_ip = node.private_ip_address
  } }
}

output "rke2_install_version" {
  description = "Configured version for new installations, not a live inventory of upgraded nodes."
  value       = var.rke2_version
}

output "kubeconfig_path" {
  value      = local.kubeconfig_out
  depends_on = [terraform_data.kubeconfig]
}

output "kubectl_hint" {
  value = "export KUBECONFIG=${local.kubeconfig_out} && kubectl get nodes -o wide"
}
