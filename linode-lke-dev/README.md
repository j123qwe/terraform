# Linode LKE dev cluster

3 x g6-standard-2 (2 vCPU / 4GB / 80GB), latest GA K8s, non-HA control plane, no control-plane ACL.
Kubeconfig is written to `./kubeconfig-<label>.yaml` (mode 0600).

```sh
# Token (PAT with LKE + Linodes read/write) - pick one:
cp .env.example .env && chmod 600 .env && $EDITOR .env   # file (default ./.env)
# export LINODE_TOKEN=<token>                            # or env var
cp terraform.tfvars.example terraform.tfvars   # optional
terraform init
terraform apply

export KUBECONFIG=$(terraform output -raw kubeconfig_path)
kubectl get nodes

terraform destroy
```

Use a different secrets file with `-var env_file=~/.secrets/linode.env` (or `env_file` in tfvars).
The .env file wins over the env var when it contains LINODE_TOKEN.

Note: the kubeconfig contents also live in Terraform state - keep the state file private.

## Test OpenLDAP

Terraform asks `Deploy the test OpenLDAP server? (true/false)` on every run (`var.deploy_ldap` has no
default). Answer `false` to skip LDAP and get a faster cluster build; `true` deploys it. Skip the prompt with
`-var deploy_ldap=false` or `deploy_ldap = false` in `terraform.tfvars`.

Deployed into the `ldap` namespace (chart: `charts/openldap`, osixia/openldap + phpLDAPadmin).

- Base DN is derived from `domain` (`k8s.example.com` -> `dc=k8s,dc=example,dc=com`).
- `ldap://ldap.<domain>:389` (STARTTLS works) and `ldaps://ldap.<domain>:636`. TLS passes through
  Traefik, so slapd presents the cert-manager certificate for `cert_issuer`; connect by hostname (SNI).
- GUI: `https://ldapadmin.<domain>`, log in as the admin DN.
- 5 random users and 3 random groups (`memberOf` overlay enabled). Terraform writes
  `ldap-users.csv` (gitignored, 0600) with username, full name, groups and password, plus rows for `admin` and `svc-bind`.
- `cn=svc-bind,ou=services,<base>` is a read-only service account; credentials are sensitive outputs:

```sh
terraform output ldap_bind_dn
terraform output -raw ldap_bind_password
terraform output -raw ldap_admin_password
```

Notes:
- The directory seeds once, on an empty volume. Later GUI changes persist; changing the seed in
  Terraform needs the PVC deleted (`kubectl -n ldap delete sts openldap pvc/data-openldap-0`, then apply).
- Passwords in the CSV are the initial ones, not updated if changed in the GUI.
- slapd reads its certificate at startup; after a renewal run `kubectl -n ldap rollout restart sts/openldap`.
- `ldap_allowed_cidrs` uses a NodeBalancer firewall, which covers every port on the shared NodeBalancer.
