# CKA Mock Exam 2 – 120 minutes

**Rules:** 120-minute timer, only the official docs, no reference solutions. Pass mark: 66 %.

Preparation (fresh cluster recommended):
```bash
./setup/create-cluster.sh
./setup/install.sh traefik
./mock-exams/exam-2/setup.sh
```
> ⚠️ One kind cluster replaces the exam's separate clusters – the troubleshooting tasks affect the
> whole cluster. Emergency reset: `./05-troubleshooting/scenarios/restore.sh`.

---

### Task 1 – New user (5 points) · Cluster architecture
Create a client certificate for the user `carol` (group `qa`) via a Kubernetes
CertificateSigningRequest named `carol` and approve it. Save the certificate to `/tmp/carol.crt`.
The group `qa` may `get`, `list` and `watch` pods and services in namespace `m2-qa`.

### Task 2 – Aggregated ClusterRole (5 points) · Cluster architecture
Create a ClusterRole `m2-monitoring` that aggregates all ClusterRoles with the label
`rbac.m2.io/aggregate-to-monitoring: "true"`. Create a ClusterRole `m2-metrics-reader`
(`get`, `list` on `pods` and `nodes`) with that label. Bind `m2-monitoring` cluster-wide to the
group `monitoring-team`.

### Task 3 – Extension interfaces (5 points) · Cluster architecture
Write the container runtime (with version) of node `cka-worker2` to `/tmp/m2-cri.txt` and the
file name of the CNI configuration on that node to `/tmp/m2-cni.txt`.

### Task 4 – Helm (5 points) · Cluster architecture
The releases `m2-podinfo` and `m2-old` are installed in namespace `m2-helm`. Upgrade `m2-podinfo`
to the newest chart version while keeping its current values, and uninstall `m2-old`.

### Task 5 – Custom resources (5 points) · Cluster architecture
A CRD for `Backup` objects is installed. Find its API group and version and create a `Backup`
named `nightly` in namespace `m2-ops` with `spec.schedule: "0 2 * * *"` and
`spec.retentionDays: 14`. Write the CRD's short name to `/tmp/m2-shortname.txt`.

### Task 6 – Autoscaling (5 points) · Workloads
Create an HPA `m2-web` for the Deployment `m2-app/web`: 2–8 replicas, average CPU 60 %
**and** average memory 70 %.

### Task 7 – DaemonSet (5 points) · Workloads
Create a DaemonSet `m2-logger` in namespace `m2-sys` (image `busybox:1.36`,
command `sleep infinity`) that runs on every node including the control plane.

### Task 8 – Admission limits (5 points) · Workloads
In namespace `m2-team`: a LimitRange `m2-limits` (container default request `50m`/`32Mi`, default
limit `100m`/`64Mi`, max memory `128Mi`) and a ResourceQuota `m2-quota` (max. 5 pods,
`limits.memory: 512Mi`).

### Task 9 – Ingress (5 points) · Services & networking
Create an Ingress `m2-shop` in namespace `m2-app` (class `traefik`) for host `shop.m2.lab` that
routes `/` to service `web` (port 80).

### Task 10 – Service types (5 points) · Services & networking
In namespace `m2-app`: a headless service `web-headless` for the `web` pods (port 80) and an
ExternalName service `payments` that points to `payments.example.com`.

### Task 11 – Egress policy (6 points) · Services & networking
In namespace `m2-secure`, all egress traffic is denied, **except** DNS to CoreDNS and TCP 80 to
pods with `app=web` in namespace `m2-app`. Use as few policies as you like.

### Task 12 – External endpoint (4 points) · Services & networking
Create a service `ext-db` (port 3306, no selector) in `m2-app` whose EndpointSlice points to
`192.168.100.20:3306`.

### Task 13 – StatefulSet (5 points) · Storage
In namespace `m2-data`, create a headless service `kv` and a StatefulSet `kv` (2 replicas,
`redis:7`) with a 128Mi PVC per replica mounted at `/data`.

### Task 14 – Reuse a volume (5 points) · Storage
The PV `m2-archive` is `Released`. Make it available again and bind the new PVC `archive`
(namespace `m2-data`, 500Mi, class `archive`) to it. The data on it must stay.

### Task 15 – Control plane (8 points) · Troubleshooting
Deployments don't create ReplicaSets anymore. Fix the cluster.

### Task 16 – DNS (8 points) · Troubleshooting
Service names don't resolve anywhere in the cluster (two problems). Fix it.

### Task 17 – Service (7 points) · Troubleshooting
The pod `m2-net/client` cannot reach the service `api` in the same namespace. Fix it without
changing the `api` Deployment.

### Task 18 – Logs (7 points) · Troubleshooting
One of the pods in namespace `m2-logs` printed the line `OutOfMemory: heap exhausted` before it
crashed. Write the pod's name to `/tmp/m2-oom-pod.txt` and that full log line to
`/tmp/m2-oom-line.txt`.

---

**Total: 100 points.** Solutions: [`SOLUTIONS.md`](SOLUTIONS.md) · Scoring: `./mock-exams/exam-2/verify.sh`
