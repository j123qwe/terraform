# All Kubernetes versions LKE currently offers (standard tier = GA releases)
data "linode_lke_versions" "available" {}

locals {
  # Versions are "1.NN" - pick the highest minor numerically (not lexically)
  k8s_minors     = [for v in data.linode_lke_versions.available.versions : tonumber(split(".", v.id)[1])]
  latest_k8s     = "1.${max(local.k8s_minors...)}"
  k8s_version    = coalesce(var.k8s_version, local.latest_k8s)
  kubeconfig_out = pathexpand(coalesce(var.kubeconfig_path, "${path.module}/kubeconfig-${var.cluster_label}.yaml"))
}

resource "linode_lke_cluster" "dev" {
  label       = var.cluster_label
  region      = var.region
  k8s_version = local.k8s_version
  tags        = var.tags

  pool {
    type  = var.node_type
    count = var.node_count
  }

  control_plane {
    high_availability = false

    acl {
      enabled = false
    }
  }

  # Once built, don't let a newer LKE release silently trigger an upgrade on the
  # next apply. Remove this (or set var.k8s_version) when you want to upgrade.
  lifecycle {
    ignore_changes = [k8s_version]
  }
}

# LKE returns the kubeconfig base64-encoded; decode and write it locally (0600)
resource "local_sensitive_file" "kubeconfig" {
  content         = base64decode(linode_lke_cluster.dev.kubeconfig)
  filename        = local.kubeconfig_out
  file_permission = "0600"
}
