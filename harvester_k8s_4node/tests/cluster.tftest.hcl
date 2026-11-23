mock_provider "harvester" {}
mock_provider "kubernetes" {}
mock_provider "kubernetes" {
  alias = "cluster"
}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "random" {
  override_during = plan
  mock_resource "random_password" {
    defaults = { result = "test-token-only" }
  }
}

variables {
  namespace                 = "test-cluster"
  image_id                  = "default/ubuntu"
  vm_ssh_public_key         = "ssh-ed25519 test-only"
  nic1_gateway              = "192.0.2.1"
  nic1_dns_servers          = ["192.0.2.1"]
  master_nic1_cidr          = "192.0.2.10/24"
  master_nic2_cidr          = "198.51.100.10/24"
  worker_nic1_cidrs         = ["192.0.2.11/24", "192.0.2.12/24", "192.0.2.13/24"]
  worker_nic2_cidrs         = ["198.51.100.11/24", "198.51.100.12/24", "198.51.100.13/24"]
  load_balancer_ip_range    = { start = "192.0.2.200", stop = "192.0.2.220" }
  l2_announcement_interface = null
  domain                    = "nip.io"
  traefik_load_balancer_ip  = "192.0.2.205"
  grafana_host              = null
}

run "default_cluster" {
  command = plan

  assert {
    condition     = length(harvester_virtualmachine.nodes) == 4 && length(terraform_data.workers) == 3 && local.server_ip == "192.0.2.10"
    error_message = "There must be one RKE2 server and three agents."
  }
  assert {
    condition     = yamldecode(yamldecode(local.cilium_config).spec.valuesContent).kubeProxyReplacement && yamldecode(yamldecode(local.cilium_config).spec.valuesContent).l2announcements.enabled && yamldecode(yamldecode(local.cilium_config).spec.valuesContent).bgpControlPlane.enabled && yamldecode(yamldecode(local.cilium_config).spec.valuesContent).k8sServiceHost == "192.0.2.10"
    error_message = "Cilium must enable L2, BGP and kube-proxy replacement using the server API."
  }
  assert {
    condition     = yamldecode(split("\n---\n", local.cilium_resources)[0]).spec.blocks[0] == var.load_balancer_ip_range && yamldecode(split("\n---\n", local.cilium_resources)[1]).spec.interfaces == ["__DETECT_PRIMARY_INTERFACE__"]
    error_message = "The IP pool must use the requested range and the default policy must detect the primary NIC."
  }
  assert {
    condition     = yamldecode(split("\n---\n", local.cilium_resources)[1]).spec.nodeSelector.matchExpressions[0] == { key = "node-role.kubernetes.io/control-plane", operator = "DoesNotExist" } && yamldecode(split("\n---\n", local.cilium_resources)[1]).spec.loadBalancerIPs
    error_message = "The default policy must announce LoadBalancer IPs from worker nodes."
  }
  assert {
    condition = alltrue([for name, node in harvester_virtualmachine.nodes :
      alltrue([for i, nic in ["nic1", "nic2"] :
        yamldecode(node.cloudinit[0].network_data).ethernets[nic].match.macaddress == local.node_macs[name][i] &&
        !contains(keys(yamldecode(node.cloudinit[0].network_data).ethernets[nic]), "set-name") &&
        yamldecode(node.cloudinit[0].network_data).ethernets[nic].dhcp4 == false
      ])
    ])
    error_message = "Cloud-init must match each static NIC by MAC without renaming busy interfaces."
  }
  assert {
    condition     = strcontains(local_sensitive_file.bootstrap[var.master_hostname].content, "\"disable-kube-proxy\": true") && strcontains(local_sensitive_file.bootstrap["k8s-worker-1"].content, "https://192.0.2.10:9345")
    error_message = "The server must disable kube-proxy and workers must join it on port 9345."
  }
  assert {
    condition     = output.application_settings.grafana_host == "grafana.192.0.2.205.nip.io" && output.application_settings.traefik_ip_in_default_pool
    error_message = "Grafana must use the static IP and domain, and identify an address inside the pool."
  }
}

run "outside_pool" {
  command = plan
  variables {
    traefik_load_balancer_ip = "192.0.2.221"
  }
  assert {
    condition     = !output.application_settings.traefik_ip_in_default_pool && output.application_settings.grafana_host == "grafana.192.0.2.221.nip.io"
    error_message = "An address outside the default pool must be identified and used in the hostname."
  }
}

run "cross_subnet_pool" {
  command = plan
  variables {
    load_balancer_ip_range   = { start = "192.0.2.250", stop = "192.0.3.2" }
    traefik_load_balancer_ip = "192.0.3.1"
  }
  assert {
    condition     = output.application_settings.traefik_ip_in_default_pool
    error_message = "IP range membership must compare complete IPv4 addresses."
  }
}

run "automatic_traefik_ip" {
  command = plan
  variables {
    traefik_load_balancer_ip = null
  }
  assert {
    condition     = output.application_settings.traefik_ip_in_default_pool == null && output.application_settings.grafana_host == null
    error_message = "Automatic allocation must defer the hostname until Traefik receives an IP."
  }
}

run "reject_invalid_traefik_ip" {
  command = plan
  variables {
    traefik_load_balancer_ip = "192.0.2.300"
  }
  expect_failures = [var.traefik_load_balancer_ip]
}

run "reject_node_traefik_ip" {
  command = plan
  variables {
    traefik_load_balancer_ip = "192.0.2.10"
  }
  expect_failures = [output.application_settings]
}

run "custom_interface" {
  command = plan
  variables {
    l2_announcement_interface = "^secondary0$"
    load_balancer_ip_range    = { start = "198.51.100.200", stop = "198.51.100.210" }
  }
  assert {
    condition     = yamldecode(split("\n---\n", local.cilium_resources)[1]).spec.interfaces == ["^secondary0$"] && yamldecode(split("\n---\n", local.cilium_resources)[0]).spec.blocks[0].start == "198.51.100.200"
    error_message = "Pool and interface overrides must reach the Cilium resources."
  }
}

run "custom_grafana_host" {
  command = plan
  variables {
    grafana_host = "monitor.lab.example.com"
  }
  assert {
    condition     = output.application_settings.grafana_host == "monitor.lab.example.com"
    error_message = "The Grafana hostname override must be passed to the application configuration."
  }
}

run "reject_invalid_grafana_host" {
  command = plan
  variables {
    grafana_host = "grafana.-invalid.example.com"
  }
  expect_failures = [var.grafana_host]
}

run "reject_backwards_range" {
  command = plan
  variables {
    load_balancer_ip_range = { start = "192.0.2.220", stop = "192.0.2.200" }
  }
  expect_failures = [var.load_balancer_ip_range]
}

run "reject_invalid_range" {
  command = plan
  variables {
    load_balancer_ip_range = { start = "not-an-ip", stop = "192.0.2.200" }
  }
  expect_failures = [var.load_balancer_ip_range]
}

run "reject_invalid_interface" {
  command = plan
  variables {
    l2_announcement_interface = "["
  }
  expect_failures = [var.l2_announcement_interface]
}
