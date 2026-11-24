#!/usr/bin/env bash
# Scoring for CKA mock exam 3
source "$(dirname "$0")/../../setup/exam-lib.sh"
SA=system:serviceaccount:m3-ci:ci-bot

t1()  { docker exec cka-control-plane test -s /var/lib/etcd/m3-backup.db && [[ $(cat /tmp/m3-revision.txt) =~ ^[0-9]+$ ]]; }
t2()  { is yes "$(k auth can-i create deployments -n m3-app --as=$SA)" &&
        is no "$(k auth can-i create deployments -n m3-ci --as=$SA)" &&
        k --token="$(cat /tmp/m3-token.txt)" -n m3-app get pods >/dev/null; }
t3()  { is 64Mi "$(jp -n m3-prod get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}')" &&
        is 128Mi "$(jp -n m3-prod get deploy api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}')"; }
t4()  { grep -q 'replicaCount: 3' /tmp/m3-values.yaml && is 3 "$(jp -n m3-helm get deploy m3-web-podinfo -o jsonpath='{.spec.replicas}')"; }
t5()  { local tok; tok=$(grep -oP -- '--token \K\S+' /tmp/m3-join.txt) && [[ -n $tok ]] &&
        grep -q 'kubeadm join' /tmp/m3-join.txt && ! grep -q -- '--control-plane' /tmp/m3-join.txt &&
        docker exec cka-control-plane kubeadm token list 2>/dev/null | grep -q "$tok"; }
t6()  { is nginx:1.26 "$(jp -n m3-app get deploy frontend -o jsonpath='{.spec.template.spec.containers[0].image}')"; }
t7()  { is Always "$(jp -n m3-app get pod m3-sidecar -o jsonpath='{.spec.initContainers[?(@.name=="shipper")].restartPolicy}')" &&
        k -n m3-app logs m3-sidecar -c shipper --tail=3 | grep -q '[0-9]'; }
t8()  { is kubernetes.io/hostname "$(jp -n m3-app get deploy m3-ha -o jsonpath='{.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[0].topologyKey}')" &&
        is 2 "$(jp -n m3-app get deploy m3-ha -o jsonpath='{.status.readyReplicas}')"; }
t9()  { curl -s -m 5 -H 'Host: app.m3.lab' -H 'x-version: v2' localhost:30080/ | grep -qi nginx &&
        ! curl -s -m 5 -H 'Host: app.m3.lab' localhost:30080/ | grep -qi nginx; }
t10() { is Local "$(jp -n m3-app get svc frontend-np -o jsonpath='{.spec.externalTrafficPolicy}')" &&
        is NodePort "$(jp -n m3-app get svc frontend-np -o jsonpath='{.spec.type}')"; }
t11() { k -n m3-isolated run m3-v1 --rm -i --image=busybox:1.36 --restart=Never -- wget -qO- -T 5 "$(jp -n m3-isolated get pod inside -o jsonpath='{.status.podIP}')" >/dev/null &&
        ! k -n default run m3-v2 --rm -i --image=busybox:1.36 --restart=Never -- wget -qO- -T 5 "$(jp -n m3-isolated get pod inside -o jsonpath='{.status.podIP}')" >/dev/null; }
t12() { k run m3-vdns --rm -i --image=busybox:1.36 --restart=Never -- nslookup frontend.m3 | grep -q Address; }
t13() { is true "$(jp get sc m3-standard -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}')" &&
        [[ $(k get sc -o json | jq '[.items[] | select(.metadata.annotations["storageclass.kubernetes.io/is-default-class"]=="true")] | length') -eq 1 ]]; }
t14() { is true "$(jp -n m3-app get pod m3-shared -o jsonpath='{.spec.containers[?(@.name=="reader")].volumeMounts[0].readOnly}')" &&
        is hello "$(k -n m3-app exec m3-shared -c reader -- cat /shared/msg)"; }
t15() { k get --raw /readyz >/dev/null && docker exec cka-control-plane grep -q 'pki/apiserver.crt' /etc/kubernetes/manifests/kube-apiserver.yaml; }
t16() { is True "$(jp get node cka-worker2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')"; }
t17() { is 1 "$(jp -n m3-incident get deploy reports -o jsonpath='{.status.readyReplicas}')" &&
        is 1 "$(jp -n m3-incident get deploy cache -o jsonpath='{.status.readyReplicas}')" &&
        [[ $(grep -c . /tmp/m3-incident.txt) -ge 2 ]]; }
t18() { [[ -z $(jp get node cka-worker -o jsonpath='{.spec.unschedulable}') ]] &&
        [[ $(jp -n m3-app get deploy payments -o jsonpath='{.status.readyReplicas}') -ge 1 ]] &&
        [[ $(jp -n m3-app get pdb payments -o jsonpath='{.spec.maxUnavailable}') != 0 ]]; }

run_exam "5:etcd snapshot" "5:ServiceAccount permissions" "5:Kustomize patch" "5:Helm values file" "5:Joining nodes" \
  "5:Rollback" "5:Sidecar" "5:Spread" "5:Header routing" "5:Preserve client IPs" \
  "5:Namespace isolation" "5:DNS rewrite" "5:Default StorageClass" "5:Shared scratch space" \
  "8:API server fixed" "8:Node fixed" "7:Workloads fixed" "7:Maintenance"
