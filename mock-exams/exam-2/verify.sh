#!/usr/bin/env bash
# Scoring for CKA mock exam 2
source "$(dirname "$0")/../../setup/exam-lib.sh"

t1()  { is Approved "$(jp get csr carol -o jsonpath='{.status.conditions[0].type}')" &&
        openssl x509 -in /tmp/carol.crt -noout -subject 2>/dev/null | grep -q 'CN *= *carol' &&
        is yes "$(k auth can-i list services -n m2-qa --as=carol --as-group=qa)" &&
        is no "$(k auth can-i delete pods -n m2-qa --as=carol --as-group=qa)"; }
t2()  { k get clusterrole m2-monitoring -o jsonpath='{.aggregationRule}' | grep -q aggregate-to-monitoring &&
        is yes "$(k auth can-i list nodes --as=x --as-group=monitoring-team)"; }
t3()  { grep -q containerd /tmp/m2-cri.txt && grep -q kindnet /tmp/m2-cni.txt; }
t4()  { ! helm status m2-old -n m2-helm >/dev/null 2>&1 &&
        [[ $(helm history m2-podinfo -n m2-helm -o json 2>/dev/null | jq length) -ge 2 ]] &&
        helm get values m2-podinfo -n m2-helm 2>/dev/null | grep -q m2; }
t5()  { is 14 "$(jp -n m2-ops get backup nightly -o jsonpath='{.spec.retentionDays}')" && grep -qx bkp /tmp/m2-shortname.txt; }
t6()  { is 8 "$(jp -n m2-app get hpa m2-web -o jsonpath='{.spec.maxReplicas}')" &&
        is 2 "$(k -n m2-app get hpa m2-web -o json | jq '.spec.metrics | length')"; }
t7()  { [[ $(jp -n m2-sys get ds m2-logger -o jsonpath='{.status.numberReady}') -eq $(k get nodes --no-headers | wc -l) ]]; }
t8()  { is 128Mi "$(jp -n m2-team get limitrange m2-limits -o jsonpath='{.spec.limits[0].max.memory}')" &&
        is 5 "$(jp -n m2-team get quota m2-quota -o jsonpath='{.spec.hard.pods}')"; }
t9()  { curl -sf -m 5 -H 'Host: shop.m2.lab' localhost:30080/ | grep -qi nginx; }
t10() { is None "$(jp -n m2-app get svc web-headless -o jsonpath='{.spec.clusterIP}')" &&
        is payments.example.com "$(jp -n m2-app get svc payments -o jsonpath='{.spec.externalName}')"; }
t11() { k -n m2-secure exec tester -- wget -qO- -T 5 web.m2-app >/dev/null &&
        k -n m2-secure get netpol -o json | jq -e '[.items[] | select((.spec.podSelector | length) == 0 and (.spec.policyTypes | index("Egress")))] | length > 0'; }
t12() { [[ -z $(jp -n m2-app get svc ext-db -o jsonpath='{.spec.selector}') ]] &&
        k -n m2-app get endpointslices -l kubernetes.io/service-name=ext-db -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | grep -q 192.168.100.20; }
t13() { is 2 "$(jp -n m2-data get sts kv -o jsonpath='{.status.readyReplicas}')" &&
        is None "$(jp -n m2-data get svc kv -o jsonpath='{.spec.clusterIP}')"; }
t14() { is m2-archive "$(jp -n m2-data get pvc archive -o jsonpath='{.spec.volumeName}')" &&
        is Bound "$(jp get pv m2-archive -o jsonpath='{.status.phase}')"; }
t15() { is Running "$(jp -n kube-system get pod kube-controller-manager-cka-control-plane -o jsonpath='{.status.phase}')" &&
        ! docker exec cka-control-plane grep -q v9.99.9 /etc/kubernetes/manifests/kube-controller-manager.yaml; }
t16() { k run m2-vdns --rm -i --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local >/dev/null; }
t17() { k -n m2-net exec client -- wget -qO- -T 5 api >/dev/null; }
t18() { grep -qx indexer /tmp/m2-oom-pod.txt && grep -q 'OutOfMemory: heap exhausted' /tmp/m2-oom-line.txt; }

run_exam "5:New user (CSR)" "5:Aggregated ClusterRole" "5:Extension interfaces" "5:Helm" "5:Custom resources" \
  "5:Autoscaling" "5:DaemonSet" "5:Admission limits" "5:Ingress" "5:Service types" \
  "6:Egress policy" "4:External endpoint" "5:StatefulSet" "5:Reuse a volume" \
  "8:Controller manager fixed" "8:DNS fixed" "7:Service fixed" "7:Logs"
