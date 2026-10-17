terraform {
  required_version = ">= 1.5.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.38"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

# Auth (first match wins):
#   1. LINODE_TOKEN=... in the secrets file (var.env_file, default ./.env)
#   2. LINODE_TOKEN environment variable
# The token needs LKE + Linodes read/write scopes.
provider "linode" {
  # null when the file/key is absent -> provider falls back to $LINODE_TOKEN
  token = local.linode_token
}

# Talk to the cluster using the kubeconfig LKE returns (no dependency on the local file).
locals {
  kubeconfig = yamldecode(base64decode(linode_lke_cluster.dev.kubeconfig))
  kube_host  = local.kubeconfig.clusters[0].cluster.server
  kube_ca    = base64decode(local.kubeconfig.clusters[0].cluster["certificate-authority-data"])
  kube_token = local.kubeconfig.users[0].user.token
}

provider "kubernetes" {
  host                   = local.kube_host
  cluster_ca_certificate = local.kube_ca
  token                  = local.kube_token
}

provider "helm" {
  kubernetes {
    host                   = local.kube_host
    cluster_ca_certificate = local.kube_ca
    token                  = local.kube_token
  }
}
