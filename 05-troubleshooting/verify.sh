#!/usr/bin/env bash
source "$(dirname "$0")/../setup/lib.sh"
k() { kubectl "$@"; }

section "5.1 – 5.5 Cluster components"
for n in cka-control-plane cka-worker cka-worker2; do
  eq "Node $n Ready" "True" k get node $n -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
done
check "kubelet on cka-worker2 enabled" docker exec cka-worker2 systemctl is-enabled kubelet
check "kubelet config uses ca.crt" docker exec cka-worker grep -q 'clientCAFile: /etc/kubernetes/pki/ca.crt' /var/lib/kubelet/config.yaml
for c in kube-apiserver kube-scheduler kube-controller-manager; do
  eq "$c running" "Running" k -n kube-system get pod $c-cka-control-plane -o jsonpath='{.status.phase}'
done
check "Deployment probe has 2 ready pods" bash -c "[[ \$(kubectl get deploy probe -o jsonpath='{.status.readyReplicas}') == 2 ]]"

section "5.6 DNS"
check "kubernetes.default resolves" kubectl run vdns --rm -i --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local

section "5.7 Resource usage"
eq "Top CPU pod is cruncher" "cruncher" bash -c "cut -d- -f1 /tmp/top-cpu-pod.txt"
check "/tmp/top-mem-node.txt names a node" bash -c "kubectl get node \$(cat /tmp/top-mem-node.txt)"
check "/tmp/besteffort.txt lists idle pods" grep -q idle /tmp/besteffort.txt

section "5.8 Container output streams"
check "/tmp/chatter-errors.log only contains ERROR lines" bash -c "[[ -s /tmp/chatter-errors.log ]] && ! grep -v ERROR /tmp/chatter-errors.log"
check "/tmp/crasher-reason.txt contains the FATAL line" grep -q 'license key expired' /tmp/crasher-reason.txt

section "5.9 Services & networking"
for s in catalog cart checkout; do
  check "client reaches $s" kubectl -n shop exec client -- wget -qO- -T 5 $s
done
check "payments access still allowed" bash -c "kubectl -n shop get netpol checkout-lockdown -o yaml | grep -q payments"

section "5.10 Broken workloads"
for d in a1-frontend a2-api a3-worker a4-cache a5-reports a6-db; do
  eq "$d fully ready" "$(k -n broken get deploy $d -o jsonpath='{.spec.replicas}' 2>/dev/null)" \
    k -n broken get deploy $d -o jsonpath='{.status.readyReplicas}'
done
check "/tmp/broken-causes.txt has 6 lines" bash -c "[[ \$(grep -c . /tmp/broken-causes.txt) -ge 6 ]]"

section "5.11 Node maintenance"
eq "cka-worker schedulable again" "" k get node cka-worker -o jsonpath='{.spec.unschedulable}'
check "critical has ≥ 1 ready pod" bash -c "[[ \$(kubectl -n load get deploy critical -o jsonpath='{.status.readyReplicas}') -ge 1 ]]"

summary
