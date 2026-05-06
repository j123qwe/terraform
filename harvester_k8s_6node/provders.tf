terraform {
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "1.8.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
  }
}

provider "harvester" {
  kubeconfig = "~/.kube/config"
  # kubecontext = "mycontext"
}

provider "kubernetes" {
  config_path = "~/.kube/config"
  # config_context = "mycontext"
}
