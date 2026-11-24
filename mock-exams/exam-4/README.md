# CKA Mock Exam 4 – 120 minutes

**Rules:** 120-minute timer, only the official docs, no reference solutions. Pass mark: 66 %.

Preparation (fresh cluster recommended):
```bash
./setup/create-cluster.sh
./setup/install.sh traefik
./mock-exams/exam-4/setup.sh
```
> ⚠️ One kind cluster replaces the exam's separate clusters – the troubleshooting tasks affect the
> whole cluster. Emergency reset: `./05-troubleshooting/scenarios/restore.sh`.

---

### Task 1 – Least privilege (5 points) · Cluster architecture
The ServiceAccount `config-updater` in namespace `m4-app` may only `get` and `patch` the
ConfigMap named `app-config` in `m4-app` – no other ConfigMaps, no other verbs.

### Task 2 – Query the API with a token (5 points) · Cluster architecture
Create the ServiceAccount `auditor` in `m4-ops` with read access to nodes. Using **only** a token of
this ServiceAccount and `curl` against the API server, write the number of nodes to
`/tmp/m4-nodes.txt`.

### Task 3 – Helm template (5 points) · Cluster architecture
Render (do **not** install) the chart `podinfo/podinfo` with `replicaCount=4` and
`service.type=NodePort` into the file `/tmp/m4-rendered.yaml`. Then install exactly these manifests
with `kubectl` into namespace `m4-helm`.

### Task 4 – Custom resource definition (5 points) · Cluster architecture
Create the CRD `tenants.platform.m4.io` (kind `Tenant`, **cluster-scoped**, version `v1`,
short name `tn`) with `spec.owner` (string, required) and `spec.maxNamespaces` (integer,
1–20, default 5). Create the tenant `blue` with owner `team-blue`.

### Task 5 – etcd snapshot status (5 points) · Cluster architecture
Create an etcd snapshot at `/var/lib/etcd/m4.db` on the control-plane node and write its status
as **JSON** to `/tmp/m4-snapshot.json`.

### Task 6 – Parallel Job (5 points) · Workloads
Create a Job `m4-batch` in `m4-app` (image `busybox:1.36`, command `echo processed`) that must
complete 6 times with at most 3 pods running in parallel, gives up after 3 failures and is
cleaned up 300 s after it finished.

### Task 7 – CronJob (5 points) · Workloads
Create a CronJob `m4-report` in `m4-app` that runs at 06:30 every Monday (image `busybox:1.36`,
command `date`), never runs two jobs at the same time and keeps only the last successful job.
Trigger one run manually as Job `m4-report-now`.

### Task 8 – Static pod (5 points) · Workloads
Create a static pod `m4-static` (image `nginx:1.27`, label `tier=static`) on node `cka-worker2`.

### Task 9 – TLS Ingress (5 points) · Services & networking
Create a self-signed certificate for `secure.m4.lab`, store it in the TLS secret `m4-tls` in
`m4-app` and create an Ingress `m4-secure` (class `traefik`) that terminates TLS for
`secure.m4.lab` and routes `/` to service `web:80`.

### Task 10 – Multi-port service (5 points) · Services & networking
The Deployment `m4-app/multi` exposes HTTP on 8080 and metrics on 9090 (named container ports
`http` and `metrics`). Create a service `multi` with two ports – `http` (80 → `http`) and
`metrics` (9090 → `metrics`) – using the **named** target ports.

### Task 11 – Egress control (6 points) · Services & networking
Pods with `app=batch` in `m4-app` may only send traffic to DNS and to pods with `app=web` on
TCP 80 in the same namespace. All other pods in `m4-app` stay unrestricted.

### Task 12 – Pod DNS settings (4 points) · Services & networking
Create a pod `m4-dns` (busybox, sleep) whose `/etc/resolv.conf` contains **only** the nameserver
`1.1.1.1` and the search domain `m4.lab`.

### Task 13 – Read-only data (5 points) · Storage
Create a PVC `m4-data` (100Mi) in `m4-app` and a pod `m4-reader` (busybox, sleep) that mounts only
the sub-directory `reports` of the volume **read-only** at `/reports`.

### Task 14 – Ephemeral volume (5 points) · Storage
Create a pod `m4-scratch` in `m4-app` with a **generic ephemeral volume** (150Mi, class
`standard`) at `/scratch`.

### Task 15 – Scheduler (8 points) · Troubleshooting
New pods don't get scheduled. Fix the cluster.

### Task 16 – Node (8 points) · Troubleshooting
Node `cka-worker` is `NotReady`. Fix it permanently.

### Task 17 – Service (7 points) · Troubleshooting
The service `m4-shop/frontend` has no endpoints although its pods are running (two problems).
Fix it without changing the service.

### Task 18 – Monitoring (7 points) · Troubleshooting
Write the name of the **container** (not pod) that uses the most CPU in namespace `m4-load` to
`/tmp/m4-top-container.txt` (format `<pod>/<container>`), and the reason of the most recent
`Warning` event in namespace `m4-load` to `/tmp/m4-warning.txt`.

---

**Total: 100 points.** Solutions: [`SOLUTIONS.md`](SOLUTIONS.md) · Scoring: `./mock-exams/exam-4/verify.sh`
