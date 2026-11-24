#!/usr/bin/env bash
source "$(dirname "$0")/../setup/lib.sh"
k() { kubectl "$@"; }

section "1.1 Role & RoleBinding"
eq "jane can list pods in dev" "yes" k auth can-i list pods -n dev --as=jane
eq "jane can read pod logs in dev" "yes" k auth can-i get pods/log -n dev --as=jane
eq "jane can NOT delete pods" "no" k auth can-i delete pods -n dev --as=jane
eq "jane can NOT list pods in default" "no" k auth can-i list pods -n default --as=jane

section "1.2 ServiceAccount + ClusterRole"
eq "node-viewer can list nodes" "yes" k auth can-i list nodes --as=system:serviceaccount:ops:node-viewer
eq "node-viewer can NOT delete nodes" "no" k auth can-i delete nodes --as=system:serviceaccount:ops:node-viewer

section "1.3 User bob"
eq "CSR bob approved" "Approved" k get csr bob -o jsonpath='{.status.conditions[0].type}'
check "/tmp/bob.crt contains CN=bob" bash -c "openssl x509 -in /tmp/bob.crt -noout -subject | grep -q 'CN *= *bob'"
check "Context bob@kind-cka exists" bash -c "kubectl config get-contexts -o name | grep -qx 'bob@kind-cka'"
eq "group developers can list pods in dev" "yes" k auth can-i list pods -n dev --as=bob --as-group=developers

section "1.4 etcd backup"
check "Snapshot exists on the control-plane node" docker exec cka-control-plane test -s /var/lib/etcd/backup-1.4.db
check "/tmp/etcd-keys.txt is a number" bash -c '[[ $(cat /tmp/etcd-keys.txt) =~ ^[0-9]+$ ]]'

section "1.7 Helm"
eq "Release web: 2 replicas after rollback" "2" k -n helm-demo get deploy web-podinfo -o jsonpath='{.spec.replicas}'
check "Release web has ≥ 3 revisions" bash -c "[[ \$(helm history web -n helm-demo -o json | jq length) -ge 3 ]]"
check "/tmp/web-values.yaml contains replicaCount" grep -q replicaCount /tmp/web-values.yaml

section "1.8 cert-manager"
eq "Certificate demo-cert Ready" "True" k -n certs get certificate demo-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
eq "Secret demo-tls has type kubernetes.io/tls" "kubernetes.io/tls" k -n certs get secret demo-tls -o jsonpath='{.type}'

section "1.9 Extension interfaces"
for key in cri cri_socket cni csi pod_cidr; do
  check "/tmp/interfaces.txt has $key=" grep -q "^$key=" /tmp/interfaces.txt
done
check "cni is kindnet" grep -qi "^cni=kindnet" /tmp/interfaces.txt

section "1.11 Kustomize"
eq "prod-api has 3 replicas" "3" k -n prod get deploy prod-api -o jsonpath='{.spec.replicas}'
check "Image tag 1.27-alpine" bash -c "kubectl -n prod get deploy prod-api -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q '1.27-alpine'"
check "Generated ConfigMap with hash suffix" bash -c "kubectl -n prod get cm -o name | grep -qE 'prod-api-config-[a-z0-9]+'"

summary
