#!/usr/bin/env bash
# Emergency reset for all break.sh scenarios and mock exam breakages.
set -uo pipefail
BK=/root/cka-backup

for node in cka-control-plane cka-worker cka-worker2; do
  docker exec "$node" sh -c "
    [ -d $BK ] || exit 0
    for f in $BK/*; do
      [ -e \"\$f\" ] || continue
      case \$(basename \"\$f\") in
        kube-*.yaml|etcd.yaml) cp \"\$f\" /etc/kubernetes/manifests/ ;;
        config.yaml|kubeadm-flags.env) cp \"\$f\" /var/lib/kubelet/ ;;
      esac
      echo \"$node: restored \$(basename \"\$f\")\"; rm \"\$f\"
    done
    systemctl daemon-reload; systemctl enable containerd kubelet >/dev/null 2>&1; systemctl restart containerd kubelet"
done

echo "waiting for the API server ..."
until kubectl get --raw /readyz >/dev/null 2>&1; do sleep 3; done
if [ -f /tmp/.coredns-corefile ]; then
  kubectl -n kube-system patch cm coredns --type=merge -p "$(jq -n --rawfile c /tmp/.coredns-corefile '{data:{Corefile:$c}}')" \
    && rm /tmp/.coredns-corefile
fi
kubectl -n kube-system patch svc kube-dns --type=merge -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}' >/dev/null
kubectl -n kube-system scale deploy coredns --replicas=2 >/dev/null
kubectl -n kube-system rollout restart deploy coredns >/dev/null
echo "✅ Restored. Give the control plane ~1 minute."
