locals {
  cilium_config = yamlencode({
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata   = { name = "rke2-cilium", namespace = "kube-system" }
    spec = { valuesContent = yamlencode({
      cni                  = { exclusive = false }
      kubeProxyReplacement = true
      k8sServiceHost       = local.server_ip
      k8sServicePort       = 6443
      k8sClientRateLimit   = { qps = 20, burst = 40 }
      l2announcements      = { enabled = true }
      bgpControlPlane      = { enabled = true }
      routingMode          = "tunnel"
      tunnelProtocol       = "vxlan"
      ipam                 = { mode = "kubernetes" }
    }) }
  })
  cilium_resources = join("\n---\n", [
    yamlencode({
      apiVersion = "cilium.io/v2"
      kind       = "CiliumLoadBalancerIPPool"
      metadata   = { name = "default" }
      spec       = { blocks = [var.load_balancer_ip_range] }
    }),
    yamlencode({
      apiVersion = "cilium.io/v2alpha1"
      kind       = "CiliumL2AnnouncementPolicy"
      metadata   = { name = "default" }
      spec = {
        nodeSelector    = { matchExpressions = [{ key = "node-role.kubernetes.io/control-plane", operator = "DoesNotExist" }] }
        interfaces      = [var.l2_announcement_interface == null ? "__DETECT_PRIMARY_INTERFACE__" : var.l2_announcement_interface]
        loadBalancerIPs = true
      }
    }),
  ])
}

resource "random_password" "join_token" {
  length  = 48
  special = false
}

resource "local_sensitive_file" "bootstrap" {
  for_each             = local.nodes
  filename             = "${local.bootstrap_dir}/${each.key}.sh"
  file_permission      = "0600"
  directory_permission = "0700"
  content = templatefile("${path.module}/templates/install-rke2.sh.tftpl", {
    node_name     = each.key
    is_server     = each.value.server
    rke2_version  = var.rke2_version
    cilium_config = local.cilium_config
    config = yamlencode(merge({
      token       = random_password.join_token.result
      "node-name" = each.key
      "node-ip"   = split("/", each.value.nic1)[0]
      }, { for key, value in {
        cni                     = ["multus", "cilium"]
        "disable-kube-proxy"    = true
        "disable"               = ["rke2-ingress-nginx", "rke2-traefik"]
        "ingress-controller"    = ["none"]
        "tls-san"               = [local.server_ip]
        "advertise-address"     = local.server_ip
        "write-kubeconfig-mode" = "0600"
        "node-taint"            = ["node-role.kubernetes.io/control-plane=true:NoSchedule"]
        } : key => value if each.value.server }, { for key, value in {
        server = "https://${local.server_ip}:9345"
    } : key => value if !each.value.server }))
  })
}

resource "local_file" "cilium_resources" {
  filename             = "${local.bootstrap_dir}/cilium-resources.yaml"
  file_permission      = "0600"
  directory_permission = "0700"
  content              = local.cilium_resources
}

resource "terraform_data" "server" {
  triggers_replace = [harvester_virtualmachine.nodes[var.master_hostname].id]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" install"
    environment = {
      HELPER               = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP              = local.server_ip
      SSH_USER             = var.vm_username
      SSH_KEY              = pathexpand(var.ssh_private_key_path)
      VERIFY_SSH_HOST_KEYS = tostring(var.verify_ssh_host_keys)
      KNOWN_HOSTS          = "${local.bootstrap_dir}/known_hosts"
      INSTALL_FILE         = local_sensitive_file.bootstrap[var.master_hostname].filename
    }
  }
}

resource "terraform_data" "workers" {
  for_each         = { for name, node in local.nodes : name => node if !node.server }
  triggers_replace = [harvester_virtualmachine.nodes[each.key].id]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" install"
    environment = {
      HELPER               = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP              = split("/", each.value.nic1)[0]
      SSH_USER             = var.vm_username
      SSH_KEY              = pathexpand(var.ssh_private_key_path)
      VERIFY_SSH_HOST_KEYS = tostring(var.verify_ssh_host_keys)
      KNOWN_HOSTS          = "${local.bootstrap_dir}/known_hosts-${each.key}"
      INSTALL_FILE         = local_sensitive_file.bootstrap[each.key].filename
    }
  }

  depends_on = [terraform_data.server]
}

resource "terraform_data" "cluster_config" {
  input = abspath("${path.module}/kubeconfig-${var.namespace}.yaml")

  triggers_replace = [
    terraform_data.server.id,
    [for node in terraform_data.workers : node.id],
    sha256(local.cilium_resources),
    [for name, node in local.nodes : "${name}=${node.nic1}" if !node.server],
  ]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" configure"
    environment = {
      HELPER               = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP              = local.server_ip
      SSH_USER             = var.vm_username
      SSH_KEY              = pathexpand(var.ssh_private_key_path)
      VERIFY_SSH_HOST_KEYS = tostring(var.verify_ssh_host_keys)
      KNOWN_HOSTS          = "${local.bootstrap_dir}/known_hosts"
      MANIFEST_FILE        = local_file.cilium_resources.filename
      KUBECONFIG           = self.input
      DETECT_L2            = tostring(var.l2_announcement_interface == null)
      WORKER_NAMES         = join(" ", [for name, node in local.nodes : name if !node.server])
      WORKER_IPS           = join(" ", [for name, node in local.nodes : split("/", node.nic1)[0] if !node.server])
      BOOTSTRAP_DIR        = local.bootstrap_dir
    }

  }
}

resource "terraform_data" "kubeconfig_ready" {
  input      = abspath("${path.module}/kubeconfig-${var.namespace}.yaml")
  depends_on = [terraform_data.cluster_config]
}
