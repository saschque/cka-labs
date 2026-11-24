#!/usr/bin/env bash
source "$(dirname "$0")/../setup/lib.sh"
k() { kubectl "$@"; }
NS=net

section "3.2 ClusterIP & NodePort"
eq "Service web is ClusterIP" "ClusterIP" k -n $NS get svc web -o jsonpath='{.spec.type}'
eq "web-np nodePort 31080" "31080" k -n $NS get svc web-np -o jsonpath='{.spec.ports[0].nodePort}'
check "web-np answers on cka-worker:31080" docker exec cka-worker curl -sf -m 5 localhost:31080

section "3.3 Headless & ExternalName"
eq "web-headless is headless" "None" k -n $NS get svc web-headless -o jsonpath='{.spec.clusterIP}'
eq "docs → kubernetes.io" "kubernetes.io" k -n $NS get svc docs -o jsonpath='{.spec.externalName}'

section "3.4 Service without a selector"
eq "legacy-db has no selector" "" k -n $NS get svc legacy-db -o jsonpath='{.spec.selector}'
check "EndpointSlice with 10.0.0.50" bash -c \
  "kubectl -n $NS get endpointslices -l kubernetes.io/service-name=legacy-db -o jsonpath='{.items[*].endpoints[*].addresses[*]}' | grep -q 10.0.0.50"

section "3.5 LoadBalancer"
eq "web-lb is LoadBalancer" "LoadBalancer" k -n $NS get svc web-lb -o jsonpath='{.spec.type}'

section "3.6 NetworkPolicies"
for np in default-deny allow-dns web-from-frontend frontend-egress; do
  check "NetworkPolicy $np exists" k -n $NS get netpol $np
done
check "Frontend pod reaches web" kubectl -n $NS run vfe --labels=role=frontend --image=busybox:1.36 --rm -i --restart=Never -- wget -qO- -T 5 web
check "Pod without label is blocked" bash -c "! kubectl -n $NS run vno --image=busybox:1.36 --rm -i --restart=Never -- wget -qO- -T 5 web"

section "3.7 Ingress"
eq "Ingress apps uses class traefik" "traefik" k -n $NS get ingress apps -o jsonpath='{.spec.ingressClassName}'
check "Ingress routes /echo" bash -c "curl -sf -m 5 -H 'Host: apps.example.com' localhost:30080/echo >/dev/null"

section "3.8 Gateway API"
eq "Gateway main programmed" "True" k -n $NS get gateway main -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
eq "split: weight 80 for web" "80" k -n $NS get httproute split -o jsonpath='{.spec.rules[0].backendRefs[?(@.name=="web")].weight}'
check "header-route matches x-beta" bash -c "kubectl -n $NS get httproute header-route -o yaml | grep -q x-beta"

section "3.9 CoreDNS"
check "db.internal.lab resolves to 10.0.0.50" bash -c \
  "kubectl run vdns --rm -i --image=busybox:1.36 --restart=Never -- nslookup db.internal.lab | grep -q 10.0.0.50"
check "web.lab resolves" bash -c "kubectl run vdns2 --rm -i --image=busybox:1.36 --restart=Never -- nslookup web.lab | grep -q Address"

summary
