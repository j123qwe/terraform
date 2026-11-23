terraform {
  required_version = ">= 1.5.0"

  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "1.8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
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

provider "harvester" {
  kubeconfig = pathexpand(var.harvester_kubeconfig)
}

provider "kubernetes" {
  config_path = pathexpand(var.harvester_kubeconfig)
}

provider "kubernetes" {
  alias       = "cluster"
  config_path = terraform_data.kubeconfig_ready.output
}

provider "helm" {
  kubernetes {
    config_path = terraform_data.kubeconfig_ready.output
  }
}
