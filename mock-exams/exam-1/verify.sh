#!/usr/bin/env bash
# Scoring for CKA mock exam 1
source "$(dirname "$0")/../../setup/exam-lib.sh"
SA=system:serviceaccount:m1-app:m1-deployer

t1()  { is yes "$(k auth can-i delete deployments -n m1-app --as=$SA)" &&
        is no "$(k auth can-i delete deployments -n default --as=$SA)" &&
        is no "$(k auth can-i get secrets -n m1-app --as=$SA)"; }
t2()  { docker exec cka-control-plane test -s /var/lib/etcd/m1-snapshot.db && [[ $(cat /tmp/m1-etcd-keys.txt) =~ ^[0-9]+$ ]]; }
t3()  { is 2 "$(jp -n m1-helm get deploy m1-web-podinfo -o jsonpath='{.spec.replicas}')" &&
        helm get values m1-web -n m1-helm 2>/dev/null | grep -q '34577c'; }
t4()  { is True "$(jp -n m1-app get certificate m1-cert -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" &&
        is Issuer "$(jp -n m1-app get certificate m1-cert -o jsonpath='{.spec.issuerRef.kind}')" &&
        k -n m1-app get secret m1-tls >/dev/null; }
t5()  { is 2 "$(jp -n m1-staging get deploy shop -o jsonpath='{.spec.replicas}')" &&
        is staging "$(jp -n m1-staging get deploy shop -o jsonpath='{.spec.selector.matchLabels.env}')"; }
t6()  { is nginx:1.27 "$(jp -n m1-app get deploy api -o jsonpath='{.spec.template.spec.containers[0].image}')" &&
        is 2 "$(jp -n m1-app get deploy api -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}')" &&
        is 3 "$(jp -n m1-app get deploy api -o jsonpath='{.status.updatedReplicas}')"; }
t7()  { is k3y-12345 "$(k -n m1-app exec config-pod -- printenv API_KEY)" &&
        k -n m1-app exec config-pod -- cat /etc/settings/theme | grep -q dark; }
t8()  { is cka-worker2 "$(jp -n m1-app get pod gpu-job -o jsonpath='{.spec.nodeName}')" &&
        is Running "$(jp -n m1-app get pod gpu-job -o jsonpath='{.status.phase}')"; }
t9()  { is 31081 "$(jp -n m1-app get svc api-np -o jsonpath='{.spec.ports[0].nodePort}')" &&
        docker exec cka-control-plane curl -sf -m 5 localhost:31081 >/dev/null; }
t10() { k -n m1-db get netpol postgres-access -o json | jq -e '.spec.ingress[0] as $i
          | ($i.ports[0].port == 5432) and ($i.from | length == 1) and ($i.from[0].namespaceSelector != null) and ($i.from[0].podSelector.matchLabels.app == "api")'; }
t11() { is True "$(jp -n m1-app get gateway m1-gw -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}')" &&
        curl -s -m 5 -H 'Host: m1.example.com' localhost:30080/api -o /dev/null -w '%{http_code}' | grep -qE '200|404'; }
t12() { k run m1-vdns --rm -i --image=busybox:1.36 --restart=Never -- nslookup legacy.m1.lab | grep -q 10.10.10.10; }
t13() { is Bound "$(jp -n m1-app get pvc m1-pvc -o jsonpath='{.status.phase}')" &&
        is m1-pv "$(jp -n m1-app get pvc m1-pvc -o jsonpath='{.spec.volumeName}')" &&
        is Running "$(jp -n m1-app get pod m1-storage -o jsonpath='{.status.phase}')"; }
t14() { is Retain "$(jp get sc m1-fast -o jsonpath='{.reclaimPolicy}')" &&
        is Bound "$(jp -n m1-app get pvc fast-data -o jsonpath='{.status.phase}')"; }
t15() { is Running "$(jp -n kube-system get pod kube-scheduler-cka-control-plane -o jsonpath='{.status.phase}')" &&
        docker exec cka-control-plane grep -q -- '--kubeconfig=/etc/kubernetes/scheduler.conf' /etc/kubernetes/manifests/kube-scheduler.yaml; }
t16() { is True "$(jp get node cka-worker -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" &&
        docker exec cka-worker systemctl is-enabled kubelet >/dev/null; }
t17() { is 2 "$(jp -n m1-incident get deploy web -o jsonpath='{.status.readyReplicas}')" &&
        [[ -n $(jp -n m1-incident get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{.items[*].endpoints[*].addresses[0]}') ]] &&
        [[ $(grep -c . /tmp/m1-incident.txt) -ge 2 ]]; }
t18() { grep -q '^keeper-' /tmp/m1-top-mem.txt && grep -q '^burner-' /tmp/m1-top-cpu.txt; }

run_exam "4:RBAC" "5:etcd backup" "5:Helm" "6:Operator (cert-manager)" "5:Kustomize" \
  "5:Rolling update" "5:Configuration" "5:Scheduling" "4:NodePort" "6:NetworkPolicy" \
  "6:Gateway API" "4:CoreDNS" "5:Static provisioning" "5:StorageClass" \
  "8:Scheduler fixed" "8:Node fixed" "7:Application fixed" "7:Resource usage"
