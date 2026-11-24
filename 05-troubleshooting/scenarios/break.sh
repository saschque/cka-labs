#!/usr/bin/env bash
# Breaks the kind cluster on purpose for the troubleshooting tasks.
# Usage: ./break.sh <scenario>     scenarios: node kubelet scheduler controller-manager apiserver dns
# Undo everything (if you get stuck): ./restore.sh
set -euo pipefail
CP=cka-control-plane
BK=/root/cka-backup           # backups live OUTSIDE the manifests dir (the kubelet runs every file there)

backup() {   # backup <node> <file>
  docker exec "$1" sh -c "mkdir -p $BK && [ -f $BK/$(basename "$2") ] || cp $2 $BK/"
}

case "${1:-}" in
  node)        # task 5.1
    docker exec cka-worker2 sh -c 'systemctl stop kubelet && systemctl disable kubelet' ;;
  kubelet)     # task 5.2
    backup cka-worker /var/lib/kubelet/config.yaml
    docker exec cka-worker sh -c "sed -i 's#clientCAFile: /etc/kubernetes/pki/ca.crt#clientCAFile: /etc/kubernetes/pki/client-ca.crt#' /var/lib/kubelet/config.yaml && systemctl restart kubelet" ;;
  scheduler)   # task 5.3
    backup $CP /etc/kubernetes/manifests/kube-scheduler.yaml
    docker exec $CP sed -i 's/- kube-scheduler$/- kube-schedular/' /etc/kubernetes/manifests/kube-scheduler.yaml ;;
  controller-manager)   # task 5.4
    backup $CP /etc/kubernetes/manifests/kube-controller-manager.yaml
    docker exec $CP sed -i 's#--kubeconfig=/etc/kubernetes/controller-manager.conf#--kubeconfig=/etc/kubernetes/controller-manager.config#' \
      /etc/kubernetes/manifests/kube-controller-manager.yaml ;;
  apiserver)   # task 5.5
    backup $CP /etc/kubernetes/manifests/kube-apiserver.yaml
    docker exec $CP sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2399#' \
      /etc/kubernetes/manifests/kube-apiserver.yaml ;;
  dns)         # task 5.6
    [ -f /tmp/.coredns-corefile ] || kubectl -n kube-system get cm coredns -o jsonpath='{.data.Corefile}' > /tmp/.coredns-corefile
    kubectl -n kube-system get cm coredns -o json \
      | jq '.data.Corefile |= sub("kubernetes cluster.local"; "kubernetes cluster.locl")' \
      | kubectl apply -f -
    kubectl -n kube-system rollout restart deploy coredns ;;
  *) echo "Usage: $0 node|kubelet|scheduler|controller-manager|apiserver|dns"; exit 1 ;;
esac
echo "💥 Scenario '$1' is active. Good luck!"
