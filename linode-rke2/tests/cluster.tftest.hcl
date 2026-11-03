mock_provider "linode" {
  override_during = plan
  mock_resource "linode_instance" {
    defaults = {
      id                 = "100"
      ipv4               = ["203.0.113.10", "192.168.128.10"]
      private_ip_address = "192.168.128.10"
    }
  }
  mock_resource "linode_nodebalancer" {
    defaults = {
      id   = "200"
      ipv4 = "203.0.113.20"
    }
  }
  mock_resource "linode_nodebalancer_config" {
    defaults = {
      id = "300"
    }
  }
}

mock_provider "random" {
  override_during = plan
  mock_resource "random_password" {
    defaults = {
      result = "test-join-token-not-a-credential"
    }
  }
}
mock_provider "local" {}

variables {
  linode_token         = "test-token-not-a-credential"
  cloud_token          = "test-cloud-token-not-a-credential"
  ssh_public_key_path  = "./tests/id_ed25519.pub"
  ssh_private_key_path = "./tests/unused-private-key"
}

run "default_ha_cluster" {
  command = plan
  assert {
    condition     = length(linode_instance.masters) == 3 && length(linode_instance.workers) == 3
    error_message = "Defaults must provision three masters and three workers."
  }
  assert {
    condition     = alltrue([for node in local.nodes : node.image == "linode/ubuntu24.04" && node.private_ip])
    error_message = "All nodes must use Ubuntu 24.04 and Linode private networking."
  }
  assert {
    condition     = length(linode_nodebalancer_node.api) == 6 && length(linode_nodebalancer_config.api) == 2
    error_message = "Both API and registration ports must have all three master backends."
  }
  assert {
    condition     = length(terraform_data.masters) == 2 && length(terraform_data.workers) == 3
    error_message = "Only additional masters join after the seed; all workers must be installed."
  }
  assert {
    condition     = !strcontains(local_sensitive_file.bootstrap[local.seed].content, "\"server\":") && strcontains(local_sensitive_file.bootstrap["dev-rke2-worker-1"].content, "\"server\": \"https://203.0.113.20:9345\"")
    error_message = "The seed must initialize etcd and workers must join through the API NodeBalancer."
  }
  assert {
    condition     = yamldecode(local.cilium_config).spec.valuesContent == yamlencode({ cni = { exclusive = false }, kubeProxyReplacement = false, routingMode = "tunnel", tunnelProtocol = "vxlan", ipam = { mode = "kubernetes" } })
    error_message = "Cilium must be Multus-compatible and use Kubernetes IPAM with encapsulation."
  }
  assert {
    condition     = strcontains(local_sensitive_file.bootstrap[local.seed].content, "\"cni\":\n- \"multus\"\n- \"cilium\"") && strcontains(local_sensitive_file.bootstrap[local.seed].content, "\"cloud-provider-name\": \"external\"")
    error_message = "Servers must enable Multus before Cilium and kubelets must use the external cloud provider."
  }
  assert {
    condition     = strcontains(local.cloud_manifests, "\"defaultStorageClass\": \"linode-block-storage\"") && strcontains(local.cloud_manifests, "\"chart\": \"ccm-linode\"") && strcontains(local.cloud_manifests, "\"bootstrap\": true")
    error_message = "Bootstrap must install Linode CCM and the CSI Delete-policy default storage class."
  }
  assert {
    condition     = !strcontains(local_sensitive_file.bootstrap["dev-rke2-worker-1"].content, "test-cloud-token") && !strcontains(local_sensitive_file.bootstrap["dev-rke2-worker-1"].content, "LINODE_CLOUD")
    error_message = "Cloud API credentials must only be uploaded to the seed server."
  }
  assert {
    condition     = linode_firewall.nodes.inbound_policy == "DROP" && linode_firewall.api.inbound_policy == "DROP"
    error_message = "Node and API firewalls must deny unsolicited inbound traffic."
  }
  assert {
    condition     = one([for rule in linode_firewall.nodes.inbound : rule.ipv4 if rule.label == "admin-ssh"]) == tolist(["0.0.0.0/0"]) && contains(one([for rule in linode_firewall.api.inbound : rule.ipv4 if rule.label == "kubernetes-api"]), "0.0.0.0/0")
    error_message = "Omitting admin_allowed_cidrs must allow public IPv4 SSH and Kubernetes API access."
  }
  assert {
    condition     = !contains(one([for rule in linode_firewall.api.inbound : rule.ipv4 if rule.label == "rke2-registration"]), "0.0.0.0/0")
    error_message = "Public administration must not expose RKE2 registration to all sources."
  }
  assert {
    condition     = one([for toleration in yamldecode(yamldecode(file("./templates/linode-ccm-config.yaml")).spec.valuesContent).tolerations : toleration.operator if toleration.key == "node-role.kubernetes.io/control-plane"]) == "Exists" && strcontains(local_sensitive_file.bootstrap[local.seed].content, "LINODE_CCM_CONFIG")
    error_message = "The seed must deploy a CCM toleration accepting the servers' non-empty control-plane taint."
  }
}

run "single_master" {
  command = plan
  variables {
    master_count = 1
  }
  assert {
    condition     = length(linode_instance.masters) == 1 && length(terraform_data.masters) == 0 && length(linode_instance.workers) == 3 && length(linode_nodebalancer_node.api) == 2
    error_message = "Single-master mode must still install three workers and both API backend ports."
  }
}

run "custom_workers" {
  command = plan
  variables {
    worker_count = 5
  }
  assert {
    condition     = length(linode_instance.workers) == 5 && length(terraform_data.workers) == 5
    error_message = "worker_count must control the number of provisioned and installed agents."
  }
}

run "reject_two_masters" {
  command = plan
  variables {
    master_count = 2
  }
  expect_failures = [var.master_count]
}

run "reject_fractional_workers" {
  command = plan
  variables {
    worker_count = 1.5
  }
  expect_failures = [var.worker_count]
}

run "restricted_administration" {
  command = plan
  variables {
    admin_allowed_cidrs = ["203.0.113.5/32"]
  }
  assert {
    condition     = one([for rule in linode_firewall.nodes.inbound : rule.ipv4 if rule.label == "admin-ssh"]) == tolist(["203.0.113.5/32"]) && !contains(one([for rule in linode_firewall.api.inbound : rule.ipv4 if rule.label == "kubernetes-api"]), "0.0.0.0/0")
    error_message = "An optional administration override must still restrict SSH and API access."
  }
}

run "reject_invalid_administration_cidr" {
  command = plan
  variables {
    admin_allowed_cidrs = ["not-a-cidr"]
  }
  expect_failures = [var.admin_allowed_cidrs]
}

run "reject_empty_administration_cidrs" {
  command = plan
  variables {
    admin_allowed_cidrs = []
  }
  expect_failures = [var.admin_allowed_cidrs]
}
