locals {
  ldap_count = var.deploy_ldap ? 1 : 0

  ldap_host       = coalesce(var.ldap_host, "ldap.${var.domain}")
  ldap_admin_host = coalesce(var.ldap_admin_host, "ldapadmin.${var.domain}")

  # k8s.sulaco.dev -> dc=k8s,dc=sulaco,dc=dev
  ldap_base_dn  = join(",", [for label in split(".", var.domain) : "dc=${label}"])
  ldap_admin_dn = "cn=admin,${local.ldap_base_dn}"
  ldap_bind_dn  = "cn=svc-bind,ou=services,${local.ldap_base_dn}"

  # Word lists the random users/groups are drawn from (keep last names and groups lowercase-safe)
  ldap_first_names = ["Alice", "Bruno", "Carla", "Dmitri", "Elena", "Farid", "Greta", "Hiroshi", "Imani", "Jonas", "Keiko", "Liam"]
  ldap_last_names  = ["Archer", "Bennett", "Castillo", "Dubois", "Eriksen", "Fontaine", "Garcia", "Haddad", "Ivanov", "Jensen", "Kowalski", "Lindqvist"]
  ldap_group_names = ["engineering", "finance", "operations", "support", "sales", "marketing", "admins", "developers"]

  ldap_user_count  = 5
  ldap_group_count = 3

  # Users without passwords: safe to pass to Helm and use in outputs
  ldap_users = !var.deploy_ldap ? [] : [for i in range(local.ldap_user_count) : {
    uid       = lower("${substr(random_shuffle.ldap_first[0].result[i], 0, 1)}${random_shuffle.ldap_last[0].result[i]}")
    givenName = random_shuffle.ldap_first[0].result[i]
    sn        = random_shuffle.ldap_last[0].result[i]
    cn        = "${random_shuffle.ldap_first[0].result[i]} ${random_shuffle.ldap_last[0].result[i]}"
    mail      = lower("${substr(random_shuffle.ldap_first[0].result[i], 0, 1)}${random_shuffle.ldap_last[0].result[i]}@${var.domain}")
    uidNumber = 10001 + i
    gidNumber = 10000
  }]
  ldap_uids = [for u in local.ldap_users : u.uid]

  # Group i always holds users i and (i+3) mod 5, which together cover all five users, plus 1-2 random extras
  ldap_groups = !var.deploy_ldap ? [] : [for i in range(local.ldap_group_count) : {
    name      = random_shuffle.ldap_groups[0].result[i]
    gidNumber = 20001 + i
    members = distinct(concat(
      [local.ldap_uids[i], local.ldap_uids[(i + 3) % local.ldap_user_count]],
      random_shuffle.ldap_extra_members[i].result,
    ))
  }]

  ldap_password_entries = concat(
    [{ dn = local.ldap_bind_dn, secretKey = "bind" }],
    [for i, u in local.ldap_users : { dn = "uid=${u.uid},ou=people,${local.ldap_base_dn}", secretKey = "user-${i}" }],
  )

  ldap_csv = !var.deploy_ldap ? "" : join("\n", concat(
    ["username,full_name,groups,password,dn,email"],
    [
      "admin,\"Directory Administrator\",\"\",${random_password.ldap_admin[0].result},\"${local.ldap_admin_dn}\",",
      "svc-bind,\"Service Account (read-only)\",\"\",${random_password.ldap_bind[0].result},\"${local.ldap_bind_dn}\",",
    ],
    [for i, u in local.ldap_users : join(",", [
      u.uid,
      "\"${u.cn}\"",
      "\"${join(";", [for g in local.ldap_groups : g.name if contains(g.members, u.uid)])}\"",
      random_password.ldap_user[i].result,
      "\"uid=${u.uid},ou=people,${local.ldap_base_dn}\"",
      u.mail,
    ])],
    [""],
  ))
}

# ---------------------------------------------------------- random data
resource "random_shuffle" "ldap_first" {
  count        = local.ldap_count
  input        = local.ldap_first_names
  result_count = local.ldap_user_count
}

resource "random_shuffle" "ldap_last" {
  count        = local.ldap_count
  input        = local.ldap_last_names
  result_count = local.ldap_user_count
}

resource "random_shuffle" "ldap_groups" {
  count        = local.ldap_count
  input        = local.ldap_group_names
  result_count = local.ldap_group_count
}

resource "random_integer" "ldap_extra_count" {
  count = local.ldap_count * local.ldap_group_count
  min   = 1
  max   = 2
}

resource "random_shuffle" "ldap_extra_members" {
  count        = local.ldap_count * local.ldap_group_count
  input        = local.ldap_uids
  result_count = random_integer.ldap_extra_count[count.index].result
}

resource "random_password" "ldap_user" {
  count   = local.ldap_count * local.ldap_user_count
  length  = 16
  special = false
}

resource "random_password" "ldap_bind" {
  count   = local.ldap_count
  length  = 24
  special = false
}

resource "random_password" "ldap_admin" {
  count   = local.ldap_count
  length  = 24
  special = false
}

resource "random_password" "ldap_config" {
  count   = local.ldap_count
  length  = 24
  special = false
}

# ------------------------------------------------------------------- DNS
resource "linode_domain_record" "ldap" {
  count       = local.ldap_count
  domain_id   = data.linode_domain.zone.id
  name        = trimsuffix(local.ldap_host, ".${var.domain}")
  record_type = "A"
  target      = local.traefik_lb_ip
  ttl_sec     = 300
}

resource "linode_domain_record" "ldap_admin" {
  count       = local.ldap_count
  domain_id   = data.linode_domain.zone.id
  name        = trimsuffix(local.ldap_admin_host, ".${var.domain}")
  record_type = "A"
  target      = local.traefik_lb_ip
  ttl_sec     = 300
}

# ---------------------------------------------------------------- OpenLDAP
resource "kubernetes_namespace_v1" "ldap" {
  count = local.ldap_count
  metadata { name = "ldap" }
  depends_on = [linode_lke_cluster.dev]
}

resource "kubernetes_secret_v1" "ldap_credentials" {
  count = local.ldap_count

  metadata {
    name      = "openldap-credentials"
    namespace = kubernetes_namespace_v1.ldap[0].metadata[0].name
  }
  data = {
    admin-password  = random_password.ldap_admin[0].result
    config-password = random_password.ldap_config[0].result
  }
}

resource "kubernetes_secret_v1" "ldap_passwords" {
  count = local.ldap_count

  metadata {
    name      = "openldap-passwords"
    namespace = kubernetes_namespace_v1.ldap[0].metadata[0].name
  }
  data = merge(
    { bind = random_password.ldap_bind[0].result },
    { for i in range(local.ldap_user_count) : "user-${i}" => random_password.ldap_user[i].result },
  )
}

resource "helm_release" "openldap" {
  count = local.ldap_count

  name      = "openldap"
  namespace = kubernetes_namespace_v1.ldap[0].metadata[0].name
  chart     = "${path.module}/charts/openldap"
  # Waits on the certificate (DNS-01 can take a few minutes) and the password Job
  timeout = 1500

  values = [yamlencode({
    baseDn          = local.ldap_base_dn
    domain          = var.domain
    organisation    = "${var.domain} test directory"
    host            = local.ldap_host
    adminHost       = local.ldap_admin_host
    certIssuer      = var.cert_issuer
    tlsEnforce      = var.ldap_tls_enforce
    adminDn         = local.ldap_admin_dn
    bindDn          = local.ldap_bind_dn
    passwordEntries = local.ldap_password_entries
    users           = local.ldap_users
    groups          = local.ldap_groups
  })]

  depends_on = [
    helm_release.traefik, # IngressRouteTCP CRDs + ldap/ldaps entrypoints
    helm_release.cluster_issuers,
    kubernetes_annotations.sc_delete_default, # PVC must pick up the Delete-policy default class
    kubernetes_annotations.sc_retain_not_default,
    kubernetes_secret_v1.ldap_credentials,
    kubernetes_secret_v1.ldap_passwords,
    linode_domain_record.ldap,
    linode_domain_record.ldap_admin,
  ]
}

# Written once the directory is bootstrapped. Passwords here are the initial ones; changes made in the GUI are not reflected.
resource "local_sensitive_file" "ldap_users_csv" {
  count = local.ldap_count

  content         = local.ldap_csv
  filename        = "${path.module}/ldap-users.csv"
  file_permission = "0600"

  depends_on = [helm_release.openldap]
}

# State migration from before the deploy_ldap toggle (resources gained count)
moved {
  from = random_shuffle.ldap_first
  to   = random_shuffle.ldap_first[0]
}

moved {
  from = random_shuffle.ldap_last
  to   = random_shuffle.ldap_last[0]
}

moved {
  from = random_shuffle.ldap_groups
  to   = random_shuffle.ldap_groups[0]
}

moved {
  from = random_password.ldap_bind
  to   = random_password.ldap_bind[0]
}

moved {
  from = random_password.ldap_admin
  to   = random_password.ldap_admin[0]
}

moved {
  from = random_password.ldap_config
  to   = random_password.ldap_config[0]
}

moved {
  from = linode_domain_record.ldap
  to   = linode_domain_record.ldap[0]
}

moved {
  from = linode_domain_record.ldap_admin
  to   = linode_domain_record.ldap_admin[0]
}

moved {
  from = kubernetes_namespace_v1.ldap
  to   = kubernetes_namespace_v1.ldap[0]
}

moved {
  from = kubernetes_secret_v1.ldap_credentials
  to   = kubernetes_secret_v1.ldap_credentials[0]
}

moved {
  from = kubernetes_secret_v1.ldap_passwords
  to   = kubernetes_secret_v1.ldap_passwords[0]
}

moved {
  from = helm_release.openldap
  to   = helm_release.openldap[0]
}

moved {
  from = local_sensitive_file.ldap_users_csv
  to   = local_sensitive_file.ldap_users_csv[0]
}
