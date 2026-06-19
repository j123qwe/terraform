output "node_labels" {
  description = "Labels assigned to each compute node"
  value       = vultr_instance.node[*].label
}

output "node_ids" {
  description = "Vultr instance IDs"
  value       = vultr_instance.node[*].id
}

output "node_public_ips" {
  description = "Public IPv4 addresses of each node"
  value       = vultr_instance.node[*].main_ip
}

output "node_private_ips" {
  description = "Private IPv4 addresses of each node"
  value       = vultr_instance.node[*].internal_ip
}

output "node_ipv6" {
  description = "IPv6 addresses of each node"
  value       = vultr_instance.node[*].v6_main_ip
}

output "node_status" {
  description = "Power status of each node"
  value       = vultr_instance.node[*].power_status
}
