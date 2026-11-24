# Domain 3 – Solutions

> Only look after your own attempt!

## 3.1 – Pod-to-pod connectivity
```bash
kubectl -n net get pods -o wide -l app=web
IP=$(kubectl -n net get pods -l app=web -o jsonpath='{.items[0].status.podIP}')
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 3 "$IP"
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- nslookup "${IP//./-}.net.pod.cluster.local"
```
The **CNI plugin** (in kind: kindnet) assigns pod IPs from each node's pod CIDR and sets up routes
between the nodes. Kubernetes requires every pod to reach every other pod without NAT.

## 3.2 – ClusterIP & NodePort
```bash
kubectl -n net expose deploy web --port=80
kubectl -n net create svc nodeport web-np --tcp=80:80 --node-port=31080
kubectl -n net set selector svc web-np app=web     # create svc sets selector app=web-np → fix it
docker exec cka-worker curl -s localhost:31080 | head -4
kubectl -n net get endpointslices -l kubernetes.io/service-name=web -o wide
kubectl -n net scale deploy web --replicas=0 && kubectl -n net get endpointslices -l kubernetes.io/service-name=web
kubectl -n net scale deploy web --replicas=2
```
Alternative for the NodePort: `kubectl -n net expose deploy web --name=web-np --type=NodePort --port=80`
and then `kubectl edit` the `nodePort`. With 0 replicas, the EndpointSlice has no endpoints →
connections are refused.

## 3.3 – Headless service & ExternalName
```bash
kubectl -n net create svc clusterip web-headless --clusterip=None --tcp=80:80
kubectl -n net set selector svc web-headless app=web
kubectl -n net run dns --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'nslookup web; nslookup web-headless'
kubectl -n net create svc externalname docs --external-name=kubernetes.io
```
`web` returns the single ClusterIP, `web-headless` returns one A record per ready pod.
ExternalName creates a CNAME – no proxying, no ports.

## 3.4 – Service without a selector
```yaml
apiVersion: v1
kind: Service
metadata: {name: legacy-db, namespace: net}
spec:
  ports: [{name: pg, port: 5432, targetPort: 5432}]
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: legacy-db-1
  namespace: net
  labels:
    kubernetes.io/service-name: legacy-db       # links the slice to the service
addressType: IPv4
ports: [{name: pg, port: 5432, protocol: TCP}]
endpoints:
  - addresses: ["10.0.0.50"]
```
Use case: a stable in-cluster name/IP for something outside the cluster (a database VM, a
service in another cluster), or during a migration. The port name must match the service port name.

## 3.5 – LoadBalancer
```bash
kubectl -n net expose deploy web --name=web-lb --type=LoadBalancer --port=80
kubectl -n net get svc web-lb       # EXTERNAL-IP <pending>
```
There is no cloud controller manager in kind that provisions load balancers, so the IP stays
`<pending>`. A LoadBalancer service is still a NodePort service + ClusterIP underneath (see
`PORT(S)`). Bare metal options: **MetalLB**, **cloud-provider-kind** (for kind), Cilium LB IPAM,
kube-vip.

## 3.6 – NetworkPolicies
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: net}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: allow-dns, namespace: net}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web-from-frontend, namespace: net}
spec:
  podSelector: {matchLabels: {app: web}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector: {matchLabels: {role: frontend}}               # entry 1 …
        - namespaceSelector: {matchLabels: {team: monitoring}}       # … OR entry 2
      ports: [{protocol: TCP, port: 80}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: frontend-egress, namespace: net}
spec:
  podSelector: {matchLabels: {role: frontend}}
  policyTypes: [Egress]
  egress:
    - to: [{podSelector: {matchLabels: {app: web}}}]
      ports: [{protocol: TCP, port: 80}]
```
Two list entries under `from` = OR. `namespaceSelector` + `podSelector` **in the same entry** = AND.
With `default-deny` on egress, both sides need a policy: egress from the client and ingress to the server.

## 3.7 – Ingress
```bash
kubectl -n net expose deploy echo --port=80 --target-port=8080
```
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: apps, namespace: net}
spec:
  ingressClassName: traefik
  rules:
    - host: apps.example.com
      http:
        paths:
          - path: /web
            pathType: Prefix
            backend: {service: {name: web, port: {number: 80}}}
          - path: /echo
            pathType: Prefix
            backend: {service: {name: echo, port: {number: 80}}}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: default-backend, namespace: net}
spec:
  ingressClassName: traefik
  defaultBackend:
    service: {name: web, port: {number: 80}}
```
```bash
curl -s -H 'Host: apps.example.com' localhost:30080/echo
curl -s localhost:30080/ | head -4      # default backend → nginx
```
Imperative: `kubectl -n net create ingress apps --class=traefik --rule="apps.example.com/web*=web:80" --rule="apps.example.com/echo*=echo:80"`.
Note: `/web` on nginx returns 404 (no rewrite) – the routing still works, as the nginx 404 page shows.
If the default NetworkPolicies from 3.6 are active, allow ingress from namespace `traefik`.

## 3.8 – Gateway API
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: main, namespace: net}
spec:
  gatewayClassName: traefik
  listeners:
    - name: http
      protocol: HTTP
      port: 8000                    # Traefik's "web" entrypoint (exposed as NodePort 30080)
      hostname: "*.example.com"
      allowedRoutes:
        namespaces: {from: Same}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: split, namespace: net}
spec:
  parentRefs: [{name: main}]
  hostnames: ["shop.example.com"]
  rules:
    - backendRefs:
        - {name: web, port: 80, weight: 80}
        - {name: echo, port: 80, weight: 20}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: header-route, namespace: net}
spec:
  parentRefs: [{name: main}]
  hostnames: ["shop.example.com"]
  rules:
    - matches:
        - headers: [{name: x-beta, value: "true"}]
      backendRefs: [{name: echo, port: 80}]
```
```bash
kubectl -n net get gateway main         # PROGRAMMED True
for i in $(seq 10); do curl -s -H 'Host: shop.example.com' localhost:30080/ | head -c 40; echo; done
curl -s -H 'Host: shop.example.com' -H 'x-beta: true' localhost:30080/
```
More specific matches (headers) win over the catch-all route. **Bonus TLS:**
```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=shop.example.com" -keyout /tmp/tls.key -out /tmp/tls.crt
kubectl -n net create secret tls shop-tls --cert=/tmp/tls.crt --key=/tmp/tls.key
```
```yaml
    - name: https                     # add to Gateway.spec.listeners
      protocol: HTTPS
      port: 8443                      # Traefik's "websecure" entrypoint (NodePort 30443)
      hostname: "shop.example.com"
      tls:
        mode: Terminate
        certificateRefs: [{name: shop-tls}]
```
`curl -sk --resolve shop.example.com:30443:127.0.0.1 https://shop.example.com:30443/`

Concepts: **GatewayClass** (infra provider) → **Gateway** (cluster operator: listeners, ports, TLS)
→ **HTTPRoute** (app team: routing). Listener ports must match what the implementation listens on.

## 3.9 – CoreDNS
```bash
kubectl -n kube-system get cm coredns -o yaml
kubectl -n kube-system get svc kube-dns            # 10.96.0.10
kubectl -n net run r --rm -it --image=busybox:1.36 --restart=Never -- cat /etc/resolv.conf
# search net.svc.cluster.local svc.cluster.local cluster.local
kubectl -n kube-system edit cm coredns
```
```
.:53 {
    errors
    health { lameduck 5s }
    ready
    hosts {
        10.0.0.50 db.internal.lab
        fallthrough
    }
    rewrite name web.lab web.net.svc.cluster.local
    kubernetes cluster.local in-addr.arpa ip6.arpa {
       pods insecure
       fallthrough in-addr.arpa ip6.arpa
       ttl 30
    }
    ...
}
```
```bash
kubectl -n kube-system rollout restart deploy coredns    # or wait for the reload plugin (~30 s)
kubectl run d --rm -it --image=busybox:1.36 --restart=Never -- sh -c 'nslookup db.internal.lab; nslookup web.lab'
```
`fallthrough` in `hosts` is important – without it, every name not in the hosts list returns NXDOMAIN.
