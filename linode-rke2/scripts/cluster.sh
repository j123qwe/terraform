#!/usr/bin/env bash
set -euo pipefail
umask 077

mode=${1:?Expected install or kubeconfig}
: "${NODE_IP:?}" "${SSH_KEY:?}" "${KNOWN_HOSTS:?}"
command -v ssh >/dev/null
test -r "$SSH_KEY" || { echo "Cannot read SSH key: $SSH_KEY" >&2; exit 1; }
mkdir -p "$(dirname "$KNOWN_HOSTS")"
ssh_args=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes
  -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$KNOWN_HOSTS"
  -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
host="root@$NODE_IP"

connected=false
for attempt in $(seq 1 60); do
  if ssh "${ssh_args[@]}" "$host" true; then
    connected=true
    break
  fi
  echo "Waiting for SSH on $NODE_IP ($attempt/60)..." >&2
  sleep 5
done
if [[ "$connected" != true ]]; then
  echo "SSH did not become available on $NODE_IP. Check admin_allowed_cidrs, your key and the node firewall." >&2
  exit 1
fi

case "$mode" in
  install)
    : "${INSTALL_FILE:?}"
    ssh "${ssh_args[@]}" "$host" 'bash -s' < "$INSTALL_FILE"
    ;;
  kubeconfig)
    : "${KUBECONFIG:?}" "${API_URL:?}" "${EXPECTED_NODES:?}"
    command -v kubectl >/dev/null
    mkdir -p "$(dirname "$KUBECONFIG")"
    temp=$(mktemp "${KUBECONFIG}.XXXXXX")
    trap 'rm -f "$temp"' EXIT
    ssh "${ssh_args[@]}" "$host" 'cat /etc/rancher/rke2/rke2.yaml' > "$temp"
    sed -i "s|https://127.0.0.1:6443|$API_URL|" "$temp"
    chmod 0600 "$temp"
    mv "$temp" "$KUBECONFIG"

    registered=false
    for attempt in $(seq 1 120); do
      count=$(kubectl get nodes -o name | wc -l)
      if [[ "$count" -eq "$EXPECTED_NODES" ]]; then
        registered=true
        break
      fi
      echo "Waiting for nodes to register ($count/$EXPECTED_NODES)..." >&2
      sleep 5
    done
    if [[ "$registered" != true ]]; then
      echo "Expected $EXPECTED_NODES registered nodes, found $count." >&2
      exit 1
    fi
    kubectl wait --for=condition=Ready nodes --all --timeout=900s
    for resource in daemonset/ccm-linode daemonset/rke2-multus daemonset/cilium daemonset/csi-linode-node statefulset/csi-linode-controller; do
      echo "Waiting for $resource to be created and become ready..."
      found=false
      for attempt in $(seq 1 120); do
        if kubectl get "$resource" -n kube-system >/dev/null 2>&1; then
          found=true
          break
        fi
        sleep 5
      done
      if [[ "$found" != true ]]; then
        echo "$resource was not created. Inspect kubectl -n kube-system get helmcharts,jobs,pods." >&2
        exit 1
      fi
      kubectl rollout status "$resource" -n kube-system --timeout=600s
    done
    kubectl rollout status daemonset -n kube-system --timeout=600s
    for attempt in $(seq 1 120); do
      uninitialized=$(kubectl get nodes -o jsonpath='{range .items[*]}{range .spec.taints[?(@.key=="node.cloudprovider.kubernetes.io/uninitialized")]}{.key}{"\n"}{end}{end}')
      if [[ -z "$uninitialized" ]]; then
        break
      fi
      sleep 5
    done
    if [[ -n "$uninitialized" ]]; then
      echo "The Linode CCM has not initialized all nodes. Inspect kubectl -n kube-system logs daemonset/ccm-linode." >&2
      exit 1
    fi
    storage_default=$(kubectl get storageclass linode-block-storage -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}|{.reclaimPolicy}')
    if [[ "$storage_default" != "true|Delete" ]]; then
      echo "linode-block-storage must be the default class with Delete reclaim policy; found $storage_default." >&2
      exit 1
    fi
    kubectl get nodes -o wide
    kubectl get storageclass
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    exit 1
    ;;
esac
