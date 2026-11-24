#!/usr/bin/env bash
# Scoring for CKA mock exam 4
source "$(dirname "$0")/../../setup/exam-lib.sh"
SA=system:serviceaccount:m4-app:config-updater

t1()  { is yes "$(k auth can-i patch configmap/app-config -n m4-app --as=$SA)" &&
        is no "$(k auth can-i patch configmap/other-config -n m4-app --as=$SA)" &&
        is no "$(k auth can-i delete configmap/app-config -n m4-app --as=$SA)"; }
t2()  { is "$(k get nodes --no-headers | wc -l | tr -d ' ')" "$(tr -d ' \n' < /tmp/m4-nodes.txt)" &&
        is yes "$(k auth can-i list nodes --as=system:serviceaccount:m4-ops:auditor)"; }
t3()  { grep -q 'replicas: 4' /tmp/m4-rendered.yaml && is 4 "$(jp -n m4-helm get deploy m4-web-podinfo -o jsonpath='{.spec.replicas}')" &&
        is NodePort "$(jp -n m4-helm get svc m4-web-podinfo -o jsonpath='{.spec.type}')"; }
t4()  { is Cluster "$(jp get crd tenants.platform.m4.io -o jsonpath='{.spec.scope}')" &&
        is 5 "$(jp get tenant blue -o jsonpath='{.spec.maxNamespaces}')"; }
t5()  { docker exec cka-control-plane test -s /var/lib/etcd/m4.db && jq -e .totalKey /tmp/m4-snapshot.json >/dev/null; }
t6()  { is 6/3/3/300 "$(jp -n m4-app get job m4-batch -o jsonpath='{.spec.completions}/{.spec.parallelism}/{.spec.backoffLimit}/{.spec.ttlSecondsAfterFinished}')"; }
t7()  { is "30 6 * * 1" "$(jp -n m4-app get cronjob m4-report -o jsonpath='{.spec.schedule}')" &&
        is Forbid "$(jp -n m4-app get cronjob m4-report -o jsonpath='{.spec.concurrencyPolicy}')" &&
        is 1 "$(jp -n m4-app get cronjob m4-report -o jsonpath='{.spec.successfulJobsHistoryLimit}')" &&
        k -n m4-app get job m4-report-now >/dev/null; }
t8()  { is Running "$(k get pods -A -l tier=static -o jsonpath='{.items[?(@.spec.nodeName=="cka-worker2")].status.phase}')" &&
        docker exec cka-worker2 ls /etc/kubernetes/manifests/ | grep -q .; }
t9()  { is m4-tls "$(jp -n m4-app get ingress m4-secure -o jsonpath='{.spec.tls[0].secretName}')" &&
        curl -sk -m 5 --resolve secure.m4.lab:30443:127.0.0.1 https://secure.m4.lab:30443/ | grep -qi nginx; }
t10() { is "http metrics" "$(jp -n m4-app get svc multi -o jsonpath='{.spec.ports[*].targetPort}')" &&
        [[ $(k -n m4-app get endpointslices -l kubernetes.io/service-name=multi -o jsonpath='{.items[0].ports[*].port}' | wc -w) -eq 2 ]]; }
t11() { k -n m4-app exec batch-runner -- wget -qO- -T 5 web >/dev/null &&
        is "app=batch" "$(k -n m4-app get netpol -o json | jq -r '[.items[] | select(.spec.policyTypes | index("Egress")) | .spec.podSelector.matchLabels | to_entries[] | "\(.key)=\(.value)"] | unique | join(",")')"; }
t12() { k -n m4-app exec m4-dns -- cat /etc/resolv.conf | grep -q 'nameserver 1.1.1.1' &&
        ! k -n m4-app exec m4-dns -- cat /etc/resolv.conf | grep -q cluster.local; }
t13() { is reports "$(jp -n m4-app get pod m4-reader -o jsonpath='{.spec.containers[0].volumeMounts[0].subPath}')" &&
        is true "$(jp -n m4-app get pod m4-reader -o jsonpath='{.spec.containers[0].volumeMounts[0].readOnly}')" &&
        is Running "$(jp -n m4-app get pod m4-reader -o jsonpath='{.status.phase}')"; }
t14() { is Bound "$(jp -n m4-app get pvc m4-scratch-scratch -o jsonpath='{.status.phase}')"; }
t15() { is Running "$(jp -n kube-system get pod kube-scheduler-cka-control-plane -o jsonpath='{.status.phase}')"; }
t16() { is True "$(jp get node cka-worker -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" &&
        docker exec cka-worker systemctl is-enabled containerd >/dev/null; }
t17() { is "app=frontend" "$(jp -n m4-shop get svc frontend -o jsonpath='{.spec.selector}' | jq -r 'to_entries[] | "\(.key)=\(.value)"')" &&
        [[ $(k -n m4-shop get endpointslices -l kubernetes.io/service-name=frontend -o json | jq '[.items[].endpoints[]? | select(.conditions.ready)] | length') -ge 2 ]]; }
t18() { grep -qx 'mixed/spinner' /tmp/m4-top-container.txt && grep -qE '^(Failed|BackOff|ErrImagePull|InspectFailed)' /tmp/m4-warning.txt; }

run_exam "5:Least privilege" "5:API query with token" "5:Helm template" "5:CRD" "5:etcd snapshot status" \
  "5:Parallel Job" "5:CronJob" "5:Static pod" "5:TLS Ingress" "5:Multi-port service" \
  "6:Egress control" "4:Pod DNS settings" "5:Read-only data" "5:Ephemeral volume" \
  "8:Scheduler fixed" "8:Node fixed" "7:Service fixed" "7:Monitoring"
