terraform {
  required_version = ">= 1.5.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 3.0"
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
