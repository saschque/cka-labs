# CKA Mock Exam 1 – 120 minutes

**Rules:** Set a 120-minute timer. Only use kubernetes.io/docs, kubernetes.io/blog, helm.sh/docs
(and the docs of the add-ons used here). No reference solutions. Pass mark: **66 out of 100 points**.

Preparation (before starting the timer, ideally on a fresh cluster):
```bash
./setup/create-cluster.sh
./setup/install.sh traefik cert-manager
./mock-exams/exam-1/setup.sh
```
> ⚠️ The real exam gives every task its own cluster/context. Here, one kind cluster does it all:
> the troubleshooting tasks break things for the **whole** cluster. If pods in other tasks stay
> `Pending`, triage the troubleshooting tasks first – deciding what to fix first is part of the exercise.
> If you get completely stuck: `./05-troubleshooting/scenarios/restore.sh`.

---

### Task 1 – RBAC (4 points) · Cluster architecture
Create the ServiceAccount `m1-deployer` in namespace `m1-app`. It may `create`, `update`,
`patch` and `delete` Deployments in `m1-app` only – nothing else.

### Task 2 – etcd backup (5 points) · Cluster architecture
Create an etcd snapshot at `/var/lib/etcd/m1-snapshot.db` on the control-plane node. Write the
number of keys in the snapshot to `/tmp/m1-etcd-keys.txt`.

### Task 3 – Helm (5 points) · Cluster architecture
Install the chart `podinfo` from `https://stefanprodan.github.io/podinfo` as release `m1-web` in
namespace `m1-helm` with 2 replicas. Then upgrade it so that `ui.color` is `#34577c` while
keeping 2 replicas.

### Task 4 – Operator (6 points) · Cluster architecture
cert-manager is installed. In namespace `m1-app`, create a self-signed **Issuer** `m1-selfsigned`
and a Certificate `m1-cert` for `api.m1.lab` whose key pair is stored in the secret `m1-tls`.

### Task 5 – Kustomize (5 points) · Cluster architecture
A base exists in `/tmp/m1-kustomize/base`. Create an overlay in `/tmp/m1-kustomize/staging` that
deploys it to namespace `m1-staging` with 2 replicas and the label `env: staging` on all
resources (incl. selectors). Apply it.

### Task 6 – Rolling update (5 points) · Workloads
Update the Deployment `m1-app/api` to `nginx:1.27` with a rolling update strategy of
`maxSurge: 2` and `maxUnavailable: 1`. The rollout must complete.

### Task 7 – Configuration (5 points) · Workloads
Create a pod `config-pod` in `m1-app` (image `busybox:1.36`, command `sleep 3600`) that gets the
key `api-key` of the existing Secret `m1-secrets` as env `API_KEY` and mounts the ConfigMap
`m1-settings` at `/etc/settings`.

### Task 8 – Scheduling (5 points) · Workloads
Node `cka-worker2` has the label `accelerator=gpu` and the taint `gpu=true:NoSchedule`.
Create a pod `gpu-job` in `m1-app` (image `registry.k8s.io/pause:3.10`) that runs **only** there.

### Task 9 – NodePort (4 points) · Services & networking
Expose the Deployment `m1-app/api` as service `api-np` of type NodePort on port 80 with node
port `31081`.

### Task 10 – NetworkPolicy (6 points) · Services & networking
In namespace `m1-db`, pods with `app=postgres` may only receive traffic on TCP 5432 from pods
with `app=api` in namespace `m1-app`. Name: `postgres-access`.

### Task 11 – Gateway API (6 points) · Services & networking
Create a Gateway `m1-gw` in namespace `m1-app` (GatewayClass `traefik`, HTTP listener on port
8000, hostname `m1.example.com`) and an HTTPRoute `m1-api` that routes the path prefix `/api`
to service `api` (port 80). Test via `curl -H 'Host: m1.example.com' localhost:30080/api`.

### Task 12 – CoreDNS (4 points) · Services & networking
Make `legacy.m1.lab` resolve to `10.10.10.10` for all pods in the cluster.

### Task 13 – Static provisioning (5 points) · Storage
Create a PV `m1-pv` (2Gi, `ReadWriteOnce`, `Retain`, class `m1-manual`, hostPath `/mnt/m1`) and a
PVC `m1-pvc` (1Gi, class `m1-manual`) in `m1-app`. Create a pod `m1-storage` (busybox, sleep)
that mounts the claim at `/data`.

### Task 14 – StorageClass (5 points) · Storage
Create a StorageClass `m1-fast` (provisioner `rancher.io/local-path`, `Retain`,
`WaitForFirstConsumer`). Create a PVC `fast-data` (200Mi) in `m1-app` that uses it and a pod
`fast-pod` that mounts it so the claim gets bound.

### Task 15 – Cluster component (8 points) · Troubleshooting
New pods in the cluster stay `Pending` without any events. Fix the cluster.

### Task 16 – Node (8 points) · Troubleshooting
Node `cka-worker` is `NotReady`. Fix it so it stays healthy after a reboot.

### Task 17 – Application (7 points) · Troubleshooting
The application `web` in namespace `m1-incident` is not reachable through its service `web`
(two problems). Fix it and write the two root causes to `/tmp/m1-incident.txt` (one per line).

### Task 18 – Resource usage (7 points) · Troubleshooting
Write the name of the pod in namespace `m1-load` that uses the most **memory** to
`/tmp/m1-top-mem.txt`, and the name of the pod that uses the most **CPU** to `/tmp/m1-top-cpu.txt`.

---

**Total: 100 points.** Solutions: [`SOLUTIONS.md`](SOLUTIONS.md) · Scoring: `./mock-exams/exam-1/verify.sh`
