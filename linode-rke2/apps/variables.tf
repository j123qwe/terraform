variable "cluster_label" {
  description = "Match the infrastructure cluster_label for the default kubeconfig filename."
  type        = string
  default     = "dev-rke2"
}

variable "kubeconfig_path" {
  description = "Kubeconfig written by the infrastructure root. Override if using a custom location."
  type        = string
  default     = null
}

variable "env_file" {
  description = "Secrets file containing LINODE_TOKEN; defaults to ../.env."
  type        = string
  default     = null
}

variable "linode_token" {
  description = "API token fallback when not using .env; needs Domains read/write for app DNS."
  type        = string
  default     = null
  sensitive   = true
}

variable "dns_token" {
  description = "Optional separate Domains read/write token for the cert-manager webhook."
  type        = string
  default     = null
  sensitive   = true
}

variable "domain" {
  description = "Existing Linode-hosted DNS zone used for Grafana DNS and DNS-01 challenges."
  type        = string
}

variable "acme_email" {
  description = "Email address for the Let's Encrypt account."
  type        = string
}

variable "cert_issuer" {
  description = "selfsigned, letsencrypt-staging or letsencrypt-prod."
  type        = string
  default     = "selfsigned"
  validation {
    condition     = contains(["selfsigned", "letsencrypt-staging", "letsencrypt-prod"], var.cert_issuer)
    error_message = "Select selfsigned, letsencrypt-staging or letsencrypt-prod."
  }
}

variable "grafana_host" {
  description = "Grafana hostname; defaults to grafana.<domain>."
  type        = string
  default     = null
}

variable "ingress_allowed_cidrs" {
  description = "IPv4 CIDRs allowed through the Traefik NodeBalancer firewall. Empty means public HTTP/HTTPS."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for cidr in var.ingress_allowed_cidrs : can(cidrnetmask(cidr))])
    error_message = "All ingress_allowed_cidrs entries must be IPv4 CIDRs."
  }
}
