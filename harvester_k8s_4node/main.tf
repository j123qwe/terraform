locals {
  mac_seed = trimspace(var.mac_seed) != "" ? trimspace(var.mac_seed) : var.namespace
  nodes = merge(
    { (var.master_hostname) = {
      server = true, nic1 = var.master_nic1_cidr, nic2 = var.master_nic2_cidr
    } },
    { for i in range(3) : "${var.worker_hostname_prefix}-${i + 1}" => {
      server = false, nic1 = var.worker_nic1_cidrs[i], nic2 = var.worker_nic2_cidrs[i]
    } }
  )
  node_macs = {
    for name, node in local.nodes : name => [
      for nic in ["nic1", "nic2"] : join(":", concat(
        ["02"],
        [for i in range(5) : substr(md5("${local.mac_seed}-${name}-${nic}"), i * 2, 2)]
      ))
    ]
  }
  server_ip     = split("/", var.master_nic1_cidr)[0]
  bootstrap_dir = "${path.module}/.bootstrap/${var.namespace}"
}

resource "kubernetes_namespace" "vm_namespace" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    precondition {
      condition     = length(local.nodes) == 4 && length(distinct([for node in local.nodes : split("/", node.nic1)[0]])) == 4 && length(distinct([for node in local.nodes : split("/", node.nic2)[0]])) == 4
      error_message = "Node names and addresses must be distinct; choose separate server and worker hostnames and IPs."
    }
  }
}

resource "harvester_virtualmachine" "nodes" {
  for_each = local.nodes

  name      = each.key
  hostname  = each.key
  namespace = kubernetes_namespace.vm_namespace.metadata[0].name
  cpu       = each.value.server ? var.master_cpu : var.worker_cpu
  memory    = each.value.server ? var.master_memory : var.worker_memory

  network_interface {
    name         = "nic-1"
    network_name = var.nic1_network_name
    mac_address  = local.node_macs[each.key][0]
  }
  network_interface {
    name         = "nic-2"
    network_name = var.nic2_network_name
    mac_address  = local.node_macs[each.key][1]
  }
  disk {
    name        = "disk0"
    type        = "disk"
    size        = each.value.server ? var.master_root_disk_size : var.worker_root_disk_size
    bus         = "virtio"
    boot_order  = 1
    image       = var.image_id
    auto_delete = true
  }
  cloudinit {
    network_data = yamlencode({
      version = 2
      ethernets = {
        nic1 = {
          match       = { macaddress = local.node_macs[each.key][0] }
          dhcp4       = false
          addresses   = [each.value.nic1]
          routes      = [{ to = "default", via = var.nic1_gateway }]
          nameservers = { addresses = var.nic1_dns_servers }
        }
        nic2 = {
          match     = { macaddress = local.node_macs[each.key][1] }
          dhcp4     = false
          addresses = [each.value.nic2]
        }
      }
    })
    user_data = join("\n", ["#cloud-config", yamlencode({
      ssh_pwauth = false
      users = [{
        name                = var.vm_username
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        lock_passwd         = true
        ssh_authorized_keys = [var.vm_ssh_public_key]
      }]
      package_update = true
      packages       = ["qemu-guest-agent"]
      runcmd         = ["systemctl enable --now qemu-guest-agent"]
    })])
  }
}
