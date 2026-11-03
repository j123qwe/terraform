locals {
  cilium_config = yamlencode({
    apiVersion = "helm.cattle.io/v1"
    kind       = "HelmChartConfig"
    metadata   = { name = "rke2-cilium", namespace = "kube-system" }
    spec = {
      valuesContent = yamlencode({
        cni                  = { exclusive = false }
        kubeProxyReplacement = false
        routingMode          = "tunnel"
        tunnelProtocol       = "vxlan"
        ipam                 = { mode = "kubernetes" }
      })
    }
  })

  cloud_manifests = join("\n---\n", [
    yamlencode({
      apiVersion = "v1"
      kind       = "Secret"
      metadata   = { name = "linode-cloud", namespace = "kube-system" }
      type       = "Opaque"
      data       = { token = base64encode(local.cloud_token), region = base64encode(var.region) }
    }),
    yamlencode({
      apiVersion = "helm.cattle.io/v1"
      kind       = "HelmChart"
      metadata   = { name = "linode-ccm", namespace = "kube-system" }
      spec = {
        chart           = "ccm-linode"
        repo            = "https://linode.github.io/linode-cloud-controller-manager"
        version         = var.ccm_chart_version
        targetNamespace = "kube-system"
        bootstrap       = true
        valuesContent = yamlencode({
          secretRef                      = { name = "linode-cloud", apiTokenRef = "token", regionRef = "region" }
          k8sServiceHost                 = "127.0.0.1"
          k8sServicePort                 = "6443"
          enableHostNetwork              = true
          disableNodeBalancerVPCBackends = true
        })
      }
    }),
    yamlencode({
      apiVersion = "helm.cattle.io/v1"
      kind       = "HelmChart"
      metadata   = { name = "linode-csi", namespace = "kube-system" }
      spec = {
        chart           = "linode-blockstorage-csi-driver"
        repo            = "https://linode.github.io/linode-blockstorage-csi-driver"
        version         = var.csi_chart_version
        targetNamespace = "kube-system"
        valuesContent = yamlencode({
          secretRef           = { name = "linode-cloud", apiTokenRef = "token", regionRef = "region" }
          defaultStorageClass = "linode-block-storage"
          volumeTags          = var.tags
          kubeletPath         = "/var/lib/kubelet"
          csiLinodePlugin     = { podsMountDir = "/var/lib/kubelet" }
        })
      }
    }),
  ])
}

resource "local_sensitive_file" "bootstrap" {
  for_each             = local.nodes
  filename             = "${local.bootstrap_dir}/${each.key}.sh"
  file_permission      = "0600"
  directory_permission = "0700"
  content = templatefile("${path.module}/templates/install-rke2.sh.tftpl", {
    node_name       = each.key
    is_server       = contains(keys(local.masters), each.key)
    is_seed         = each.key == local.seed
    rke2_version    = var.rke2_version
    cilium_config   = local.cilium_config
    ccm_config      = file("${path.module}/templates/linode-ccm-config.yaml")
    cloud_manifests = each.key == local.seed ? local.cloud_manifests : ""
    config = yamlencode(merge({
      token                 = random_password.join_token.result
      "node-name"           = each.key
      "node-ip"             = each.value.private_ip_address
      "cloud-provider-name" = "external"
      "kubelet-arg"         = ["provider-id=linode://${each.value.id}"]
      }, { for key, value in {
        cni                           = ["multus", "cilium"]
        "disable-cloud-controller"    = true
        disable                       = ["rke2-ingress-nginx", "rke2-traefik"]
        "tls-san"                     = [linode_nodebalancer.api.ipv4]
        "advertise-address"           = each.value.private_ip_address
        "ingress-controller"          = ["none"]
        "write-kubeconfig-mode"       = "0600"
        "node-taint"                  = ["node-role.kubernetes.io/control-plane=true:NoSchedule"]
        "etcd-expose-metrics"         = true
        "kube-controller-manager-arg" = ["bind-address=0.0.0.0"]
        "kube-scheduler-arg"          = ["bind-address=0.0.0.0"]
    } : key => value if contains(keys(local.masters), each.key) }, each.key == local.seed ? {} : { server = local.registration_url }))
  })
}

resource "terraform_data" "seed" {
  triggers_replace = [linode_instance.masters[local.seed].id]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" install"
    environment = {
      HELPER       = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP      = local.public_ips[local.seed]
      SSH_KEY      = local.ssh_private_key
      KNOWN_HOSTS  = "${local.bootstrap_dir}/known_hosts"
      INSTALL_FILE = local_sensitive_file.bootstrap[local.seed].filename
    }
  }

  depends_on = [linode_firewall.nodes, linode_firewall.api, linode_nodebalancer_node.api]
}

resource "terraform_data" "masters" {
  for_each         = { for name, index in local.masters : name => index if name != local.seed }
  triggers_replace = [linode_instance.masters[each.key].id]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" install"
    environment = {
      HELPER       = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP      = local.public_ips[each.key]
      SSH_KEY      = local.ssh_private_key
      KNOWN_HOSTS  = "${local.bootstrap_dir}/known_hosts"
      INSTALL_FILE = local_sensitive_file.bootstrap[each.key].filename
    }
  }

  depends_on = [terraform_data.seed]
}

resource "terraform_data" "workers" {
  for_each         = local.workers
  triggers_replace = [linode_instance.workers[each.key].id]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" install"
    environment = {
      HELPER       = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP      = local.public_ips[each.key]
      SSH_KEY      = local.ssh_private_key
      KNOWN_HOSTS  = "${local.bootstrap_dir}/known_hosts"
      INSTALL_FILE = local_sensitive_file.bootstrap[each.key].filename
    }
  }

  depends_on = [terraform_data.seed, terraform_data.masters]
}

resource "terraform_data" "kubeconfig" {
  triggers_replace = [
    terraform_data.seed.id,
    [for node in terraform_data.masters : node.id],
    [for node in terraform_data.workers : node.id],
    local.kubeconfig_out,
  ]

  provisioner "local-exec" {
    command = "bash \"$HELPER\" kubeconfig"
    environment = {
      HELPER         = abspath("${path.module}/scripts/cluster.sh")
      NODE_IP        = local.public_ips[local.seed]
      SSH_KEY        = local.ssh_private_key
      KNOWN_HOSTS    = "${local.bootstrap_dir}/known_hosts"
      KUBECONFIG     = local.kubeconfig_out
      API_URL        = local.api_url
      EXPECTED_NODES = tostring(var.master_count + var.worker_count)
    }
  }
}
