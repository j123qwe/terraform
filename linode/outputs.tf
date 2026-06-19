output "node_labels" {
  description = "Labels assigned to each compute node"
  value       = linode_instance.node[*].label
}

output "node_ids" {
  description = "Linode instance IDs"
  value       = linode_instance.node[*].id
}

output "node_public_ips" {
  description = "Public IPv4 addresses of each node"
  value       = linode_instance.node[*].ip_address
}

output "node_private_ips" {
  description = "Private IPv4 addresses of each node (requires private_ip = true)"
  value       = linode_instance.node[*].private_ip_address
}

output "node_ipv6" {
  description = "IPv6 addresses of each node"
  value       = linode_instance.node[*].ipv6
}
