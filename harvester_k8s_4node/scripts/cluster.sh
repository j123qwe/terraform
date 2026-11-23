#!/usr/bin/env bash
set -euo pipefail
umask 077

mode=${1:?Expected install or configure}
: "${NODE_IP:?}" "${SSH_USER:?}" "${SSH_KEY:?}" "${KNOWN_HOSTS:?}" "${VERIFY_SSH_HOST_KEYS:?}"
command -v ssh >/dev/null
test -r "$SSH_KEY" || { echo "Cannot read SSH key: $SSH_KEY" >&2; exit 1; }
ssh_args=(-i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes
  -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=4)
case "$VERIFY_SSH_HOST_KEYS" in
  true)
    mkdir -p "$(dirname "$KNOWN_HOSTS")"
    ssh_args+=(-o StrictHostKeyChecking=accept-new)
    ;;
  false)
    ssh_args+=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
      -o GlobalKnownHostsFile=/dev/null -o VerifyHostKeyDNS=no -o CheckHostIP=no)
    ;;
  *)
    echo "VERIFY_SSH_HOST_KEYS must be true or false." >&2
    exit 1
    ;;
esac

ssh_to_node() {
  local known_hosts=$1
  shift
  if [[ "$VERIFY_SSH_HOST_KEYS" == true ]]; then
    ssh "${ssh_args[@]}" -o "UserKnownHostsFile=$known_hosts" "$@"
  else
    ssh "${ssh_args[@]}" "$@"
  fi
}
host="$SSH_USER@$NODE_IP"

connected=false
for attempt in $(seq 1 60); do
  if ssh_to_node "$KNOWN_HOSTS" "$host" true; then
    connected=true
    break
  fi
  echo "Waiting for SSH on $NODE_IP ($attempt/60)..." >&2
  sleep 5
done
if [[ "$connected" != true ]]; then
  echo "SSH did not become available on $NODE_IP; check networking and SSH keys." >&2
  exit 1
fi

case "$mode" in
  install)
    : "${INSTALL_FILE:?}"
    ssh_to_node "$KNOWN_HOSTS" "$host" 'sudo -A bash -s' < "$INSTALL_FILE"
    ;;
  configure)
    : "${MANIFEST_FILE:?}" "${KUBECONFIG:?}" "${DETECT_L2:?}"
    command -v kubectl >/dev/null
    mkdir -p "$(dirname "$KUBECONFIG")"
    temp=$(mktemp "${KUBECONFIG}.XXXXXX")
    trap 'rm -f "$temp"' EXIT
    ssh_to_node "$KNOWN_HOSTS" "$host" 'sudo -A cat /etc/rancher/rke2/rke2.yaml' > "$temp"
    sed -i "s|https://127.0.0.1:6443|https://$NODE_IP:6443|" "$temp"
    chmod 0600 "$temp"
    mv "$temp" "$KUBECONFIG"

    registered=false
    for attempt in $(seq 1 120); do
      count=$(kubectl get nodes -o name | wc -l)
      if [[ "$count" -eq 4 ]]; then registered=true; break; fi
      echo "Waiting for nodes to register ($count/4)..." >&2
      sleep 5
    done
    if [[ "$registered" != true ]]; then
      echo "Expected four registered nodes; found $count." >&2
      exit 1
    fi
    kubectl wait --for=condition=Ready nodes --all --timeout=900s
    for resource in daemonset/cilium deployment/cilium-operator daemonset/rke2-multus; do
      found=false
      for attempt in $(seq 1 120); do
        if kubectl -n kube-system get "$resource" >/dev/null 2>&1; then found=true; break; fi
        sleep 5
      done
      if [[ "$found" != true ]]; then
        echo "$resource was not created; inspect kube-system Helm jobs and pods." >&2
        exit 1
      fi
      kubectl -n kube-system rollout status "$resource" --timeout=600s
    done
    kubectl wait --for=condition=Established crd/ciliumloadbalancerippools.cilium.io crd/ciliuml2announcementpolicies.cilium.io --timeout=300s
    if [[ "$DETECT_L2" == true ]]; then
      : "${WORKER_NAMES:?}" "${WORKER_IPS:?}" "${BOOTSTRAP_DIR:?}"
      read -r -a worker_names <<< "$WORKER_NAMES"
      read -r -a worker_ips <<< "$WORKER_IPS"
      if [[ ${#worker_names[@]} -ne 3 || ${#worker_ips[@]} -ne 3 ]]; then
        echo "Expected exactly three worker names and addresses." >&2
        exit 1
      fi
      primary_interface=""
      for i in "${!worker_names[@]}"; do
        name=${worker_names[$i]}
        ip=${worker_ips[$i]}
        interface=$(ssh_to_node "$BOOTSTRAP_DIR/known_hosts-$name" \
          "$SSH_USER@$ip" "ip -o -4 addr show to $ip/32" | awk '{print $2}')
        if [[ ! "$interface" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
          echo "Could not identify one primary interface for $name at $ip." >&2
          exit 1
        fi
        if [[ -n "$primary_interface" && "$primary_interface" != "$interface" ]]; then
          echo "Workers have different primary interface names; set l2_announcement_interface explicitly." >&2
          exit 1
        fi
        primary_interface=$interface
      done
      pattern="^${primary_interface//./[.]}$"
      manifest=$(mktemp "${KUBECONFIG}.manifest.XXXXXX")
      trap 'rm -f "$temp" "$manifest"' EXIT
      sed "s|__DETECT_PRIMARY_INTERFACE__|$pattern|g" "$MANIFEST_FILE" > "$manifest"
      kubectl apply -f "$manifest"
    else
      kubectl apply -f "$MANIFEST_FILE"
    fi
    kubectl wait --for='jsonpath={.status.conditions[?(@.type=="cilium.io/PoolConflict")].status}=False' ciliumloadbalancerippool/default --timeout=120s
    kubectl get nodes -o wide
    kubectl get ciliumloadbalancerippools,ciliuml2announcementpolicies
    ;;
  *)
    echo "Unknown mode: $mode" >&2
    exit 1
    ;;
esac
