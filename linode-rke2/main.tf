locals {
  masters = { for i in range(var.master_count) : "${var.cluster_label}-master-${i + 1}" => i }
  workers = { for i in range(var.worker_count) : "${var.cluster_label}-worker-${i + 1}" => i }
  seed    = "${var.cluster_label}-master-1"

  nodes            = merge(linode_instance.masters, linode_instance.workers)
  public_ips       = { for name, node in local.nodes : name => one([for ip in node.ipv4 : ip if !startswith(ip, "192.168.")]) }
  node_private_ips = [for node in local.nodes : "${node.private_ip_address}/32"]
  node_public_ips  = [for ip in local.public_ips : "${ip}/32"]
  kubeconfig_out   = abspath(pathexpand(coalesce(var.kubeconfig_path, "${path.module}/kubeconfig-${var.cluster_label}.yaml")))
  bootstrap_dir    = abspath("${path.module}/.bootstrap/${var.cluster_label}")
  ssh_private_key  = pathexpand(var.ssh_private_key_path)
  api_url          = "https://${linode_nodebalancer.api.ipv4}:6443"
  registration_url = "https://${linode_nodebalancer.api.ipv4}:9345"
}

resource "random_password" "join_token" {
  length  = 64
  special = false
}

resource "linode_instance" "masters" {
  for_each        = local.masters
  label           = each.key
  image           = "linode/ubuntu24.04"
  region          = var.region
  type            = var.master_type
  private_ip      = true
  authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
  tags            = var.tags

  lifecycle {
    precondition {
      condition     = local.linode_token != null && local.cloud_token != null
      error_message = "Set LINODE_TOKEN in .env or TF_VAR_linode_token. Bootstrap needs a token explicitly, not only the provider's LINODE_TOKEN environment fallback."
    }
  }
}

resource "linode_instance" "workers" {
  for_each        = local.workers
  label           = each.key
  image           = "linode/ubuntu24.04"
  region          = var.region
  type            = var.worker_type
  private_ip      = true
  authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
  tags            = var.tags
}

resource "linode_nodebalancer" "api" {
  label                = "${var.cluster_label}-api"
  region               = var.region
  client_conn_throttle = 0
  tags                 = var.tags
}

resource "linode_nodebalancer_config" "api" {
  for_each        = toset(["6443", "9345"])
  nodebalancer_id = linode_nodebalancer.api.id
  port            = tonumber(each.key)
  protocol        = "tcp"
  algorithm       = "roundrobin"
  stickiness      = "none"
  check           = "connection"
  check_interval  = 5
  check_timeout   = 3
  check_attempts  = 3
  check_passive   = false
}

resource "linode_nodebalancer_node" "api" {
  for_each = {
    for pair in setproduct(keys(local.masters), ["6443", "9345"]) :
    "${pair[0]}-${pair[1]}" => { name = pair[0], port = pair[1] }
  }
  nodebalancer_id = linode_nodebalancer.api.id
  config_id       = linode_nodebalancer_config.api[each.value.port].id
  label           = each.value.name
  address         = "${linode_instance.masters[each.value.name].private_ip_address}:${each.value.port}"
  mode            = "accept"
  weight          = 100
}

resource "linode_firewall" "nodes" {
  label           = "${var.cluster_label}-nodes"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
  linodes         = [for node in local.nodes : node.id]
  tags            = var.tags

  inbound {
    label    = "admin-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.admin_allowed_cidrs
  }
  inbound {
    label    = "cluster-tcp"
    action   = "ACCEPT"
    protocol = "TCP"
    ipv4     = local.node_private_ips
  }
  inbound {
    label    = "cluster-udp"
    action   = "ACCEPT"
    protocol = "UDP"
    ipv4     = local.node_private_ips
  }
  inbound {
    label    = "cluster-icmp"
    action   = "ACCEPT"
    protocol = "ICMP"
    ipv4     = local.node_private_ips
  }
  inbound {
    label    = "nodebalancers"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443,9345,30000-32767"
    ipv4     = ["192.168.255.0/24"]
  }
}

resource "linode_firewall" "api" {
  label           = "${var.cluster_label}-api"
  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"
  nodebalancers   = [linode_nodebalancer.api.id]
  tags            = var.tags

  inbound {
    label    = "kubernetes-api"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "6443"
    ipv4     = concat(var.admin_allowed_cidrs, local.node_public_ips)
  }
  inbound {
    label    = "rke2-registration"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "9345"
    ipv4     = local.node_public_ips
  }
}
