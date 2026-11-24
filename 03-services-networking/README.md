# Domain 3 – Services & Networking (20 %)

Competencies from the curriculum:
- Understand connectivity between Pods
- Define and enforce Network Policies
- Use ClusterIP, NodePort, LoadBalancer service types and endpoints
- Use the Gateway API to manage Ingress traffic
- Know how to use Ingress controllers and Ingress resources
- Understand and use CoreDNS

Add-ons needed: `./setup/install.sh traefik` (Ingress + Gateway API, tasks 3.6–3.8)

Preparation:
```bash
kubectl create ns net
kubectl -n net create deploy web --image=nginx:1.27 --replicas=2
kubectl -n net create deploy echo --image=registry.k8s.io/e2e-test-images/agnhost:2.53 -- /agnhost netexec --http-port=8080
```

---

## Task 3.1 – Pod-to-pod connectivity ⏱ 4 min

1. Find the IPs of the `web` pods and which node each runs on.
2. From a temporary pod in namespace `default`, reach one `web` pod directly by its IP.
3. Resolve the DNS name of a pod (`<ip-with-dashes>.net.pod.cluster.local`).
4. Which component makes pod IPs routable across nodes in this cluster?

---

## Task 3.2 – ClusterIP & NodePort ⏱ 5 min

1. Expose `web` as a ClusterIP service `web` on port 80.
2. Expose `web` as a NodePort service `web-np` on port 80 with the fixed node port `31080`.
3. Reach `web-np` from a node: `docker exec cka-worker curl -s localhost:31080`.
4. List the EndpointSlices of `web` and show that they contain the pod IPs. What happens to the
   endpoints when you scale `web` to 0?

---

## Task 3.3 – Headless service & ExternalName ⏱ 4 min

1. Create a headless service `web-headless` for the `web` pods. Compare `nslookup web` with
   `nslookup web-headless` from a pod.
2. Create an ExternalName service `docs` in `net` that points to `kubernetes.io`.

---

## Task 3.4 – Service without a selector ⏱ 5 min

Create a service `legacy-db` (port 5432, **no selector**) and an `EndpointSlice` that points to
the IP `10.0.0.50` port 5432. Why would you do this?

---

## Task 3.5 – LoadBalancer ⏱ 3 min

Create a service `web-lb` of type `LoadBalancer`. What is its `EXTERNAL-IP` in kind and why?
Which node port did it get anyway? Name two ways to get real LoadBalancer IPs on bare metal.

---

## Task 3.6 – NetworkPolicies ⏱ 8 min

In namespace `net`:
1. `default-deny`: deny all ingress **and** egress for all pods.
2. `allow-dns`: allow egress to CoreDNS for all pods.
3. `web-from-frontend`: allow ingress to `app=web` on port 80 only from pods with
   `role=frontend` in the same namespace **and** from all pods in namespaces labeled
   `team=monitoring`.
4. `frontend-egress`: allow pods with `role=frontend` egress to `app=web` on port 80.
5. Test with `kubectl -n net run fe --labels=role=frontend --image=busybox:1.36 --rm -it -- wget -qO- -T 3 web`
   and with a pod **without** the label.

---

## Task 3.7 – Ingress ⏱ 6 min

With the Traefik Ingress controller (IngressClass `traefik`):
1. Create a ClusterIP service `echo` (port 80 → 8080) for the `echo` Deployment.
2. Create an Ingress `apps` for host `apps.example.com`:
   - `/web` → service `web:80`
   - `/echo` → service `echo:80` (pathType `Prefix`)
3. Test from your machine: `curl -H 'Host: apps.example.com' localhost:30080/echo`.
4. Add a second Ingress `default-backend` that sends all requests without a matching host to `web`.

---

## Task 3.8 – Gateway API ⏱ 8 min

1. Create a `Gateway` `main` in namespace `net` (GatewayClass `traefik`, HTTP listener on port
   8000 – Traefik's `web` entrypoint, hostname `*.example.com`).
2. Create an `HTTPRoute` `split` for `shop.example.com` that sends **80 %** of requests to `web`
   and **20 %** to `echo`.
3. Create an `HTTPRoute` `header-route` for `shop.example.com` that sends requests with header
   `x-beta: true` always to `echo`.
4. Test: `curl -H 'Host: shop.example.com' localhost:30080/` a few times.
5. Bonus: TLS termination with an HTTPS listener (port 8443) and a self-signed certificate secret.

---

## Task 3.9 – CoreDNS ⏱ 6 min

1. Find the CoreDNS ConfigMap and the service IP of the cluster DNS. Which search domains does a
   pod in namespace `net` have (`/etc/resolv.conf`)?
2. Make `db.internal.lab` resolve to `10.0.0.50` for the whole cluster (CoreDNS `hosts` plugin).
3. Add a `rewrite` so that `web.lab` resolves to `web.net.svc.cluster.local`.
4. Test both names from a pod.

---

✅ Check: `./03-services-networking/verify.sh`
📖 Solutions: [`SOLUTIONS.md`](SOLUTIONS.md)
