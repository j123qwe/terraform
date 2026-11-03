locals {
  env_file     = pathexpand(coalesce(var.env_file, "${path.module}/.env"))
  env_raw      = fileexists(local.env_file) ? file(local.env_file) : ""
  env_match    = regexall("(?m)^[ \\t]*(?:export[ \\t]+)?LINODE_TOKEN[ \\t]*=[ \\t]*[\"']?([^\"'\\s#]+)", local.env_raw)
  linode_token = length(local.env_match) > 0 ? sensitive(local.env_match[0][0]) : var.linode_token
  cloud_token  = var.cloud_token != null ? var.cloud_token : local.linode_token
}
