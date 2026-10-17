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
