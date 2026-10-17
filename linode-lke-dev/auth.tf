# Read LINODE_TOKEN from a .env-style file if present.
# Accepts: LINODE_TOKEN=abc | export LINODE_TOKEN=abc | LINODE_TOKEN="abc" ; ignores # comments.
locals {
  env_file  = pathexpand(coalesce(var.env_file, "${path.module}/.env"))
  env_raw   = fileexists(local.env_file) ? file(local.env_file) : ""
  env_match = regexall("(?m)^[ \\t]*(?:export[ \\t]+)?LINODE_TOKEN[ \\t]*=[ \\t]*[\"']?([^\"'\\s#]+)", local.env_raw)

  linode_token = length(local.env_match) > 0 ? sensitive(local.env_match[0][0]) : null
}
