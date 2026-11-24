# CKA Mock Exam 3 – 120 minutes

**Rules:** 120-minute timer, only the official docs, no reference solutions. Pass mark: 66 %.

Preparation (fresh cluster recommended):
```bash
./setup/create-cluster.sh
./setup/install.sh traefik
./mock-exams/exam-3/setup.sh
```
> ⚠️ One kind cluster replaces the exam's separate clusters – the troubleshooting tasks affect the
> whole cluster. Emergency reset: `./05-troubleshooting/scenarios/restore.sh`.

---

### Task 1 – etcd snapshot (5 points) · Cluster architecture
Create an etcd snapshot at `/var/lib/etcd/m3-backup.db` on the control-plane node and write its
**revision** to `/tmp/m3-revision.txt`.

### Task 2 – ServiceAccount permissions (5 points) · Cluster architecture
The ServiceAccount `ci-bot` in namespace `m3-ci` should have the permissions of the built-in
ClusterRole `edit`, but only in namespace `m3-app`. Afterwards write a token for it (valid 2 h)
to `/tmp/m3-token.txt`.

### Task 3 – Kustomize patch (5 points) · Cluster architecture
`/tmp/m3-kustomize/base` contains a Deployment `api`. Create the overlay `/tmp/m3-kustomize/prod`
that deploys to namespace `m3-prod` and uses a **strategic merge patch** to set the container
`api`'s resources to requests `cpu: 100m`, `memory: 64Mi` and limits `memory: 128Mi`. Apply it.

### Task 4 – Helm values file (5 points) · Cluster architecture
Write a values file `/tmp/m3-values.yaml` that sets `replicaCount: 3` and `ui.message: "exam 3"`
and install the chart `podinfo/podinfo` (repo `https://stefanprodan.github.io/podinfo`) with it as
release `m3-web` in namespace `m3-helm`.

### Task 5 – Joining nodes (5 points) · Cluster architecture
On the control-plane node, create a new bootstrap token with a TTL of **2 hours** and write the
complete `kubeadm join` command for a **worker** to `/tmp/m3-join.txt`.

### Task 6 – Rollback (5 points) · Workloads
The Deployment `m3-app/frontend` has several revisions. Roll it back to the revision that used the
image `nginx:1.26`.

### Task 7 – Sidecar (5 points) · Workloads
Create a pod `m3-sidecar` in `m3-app`: a main container `app` (busybox) that appends the date to
`/var/log/app.log` every 2 s, and a **native sidecar** `shipper` (busybox) that runs
`tail -F /var/log/app.log`. Both share an `emptyDir`.

### Task 8 – Spread (5 points) · Workloads
Create a Deployment `m3-ha` in `m3-app` (3 replicas, `nginx:1.27`) whose pods may **never** run on
the same node as another `m3-ha` pod. Why can only 2 of the 3 pods run in this cluster?

### Task 9 – Header routing (5 points) · Services & networking
Create a Gateway `m3-gw` in `m3-app` (class `traefik`, HTTP, port 8000) and an HTTPRoute
`m3-canary` for host `app.m3.lab`: requests with header `x-version: v2` go to service `v2`,
all other requests go to service `v1`.

### Task 10 – Preserve client IPs (5 points) · Services & networking
Expose `m3-app/frontend` as NodePort service `frontend-np` (port 80) so that external traffic is
only routed to pods on the node that received it (and the client source IP is preserved).

### Task 11 – Namespace isolation (5 points) · Services & networking
Pods in namespace `m3-isolated` may only receive traffic from pods in the **same** namespace.
Egress must not be restricted.

### Task 12 – DNS rewrite (5 points) · Services & networking
Make `frontend.m3` resolve to the service `frontend` in namespace `m3-app` everywhere in the cluster.

### Task 13 – Default StorageClass (5 points) · Storage
Create a StorageClass `m3-standard` (`rancher.io/local-path`, `WaitForFirstConsumer`, `Delete`)
and make it the cluster's **only** default StorageClass.

### Task 14 – Shared scratch space (5 points) · Storage
Create a pod `m3-shared` in `m3-app` with two busybox containers (`writer`, `reader`) that share a
memory-backed `emptyDir` (max 32Mi) at `/shared`. `writer` writes `hello` to `/shared/msg`
once and sleeps; `reader` mounts the volume **read-only**.

### Task 15 – API server (8 points) · Troubleshooting
`kubectl` doesn't work anymore. Fix the cluster.

### Task 16 – Node (8 points) · Troubleshooting
Node `cka-worker2` is `NotReady`, although the kubelet service is enabled. Fix it.

### Task 17 – Workloads (7 points) · Troubleshooting
The Deployments `reports` and `cache` in namespace `m3-incident` don't become ready. Fix both and
write the root causes to `/tmp/m3-incident.txt` (one line each).

### Task 18 – Maintenance (7 points) · Troubleshooting
Drain the node `cka-worker` (ignore DaemonSets, delete emptyDir data). Make sure the drain
completes while the application `m3-app/payments` keeps at least one running pod, then make the
node schedulable again.

---

**Total: 100 points.** Solutions: [`SOLUTIONS.md`](SOLUTIONS.md) · Scoring: `./mock-exams/exam-3/verify.sh`
