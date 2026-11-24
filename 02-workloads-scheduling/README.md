# Domain 2 – Workloads & Scheduling (15 %)

Competencies from the curriculum:
- Understand application deployments and how to perform rolling update and rollbacks
- Use ConfigMaps and Secrets to configure applications
- Configure workload autoscaling
- Understand the primitives used to create robust, self-healing, application deployments
- Configure Pod admission and scheduling (limits, node affinity, etc.)

All tasks run in namespace `apps` unless stated otherwise: `kubectl create ns apps`

---

## Task 2.1 – Rolling update & rollback ⏱ 5 min

1. Create a Deployment `web` (image `nginx:1.26`, 4 replicas) with the strategy
   `maxSurge: 1`, `maxUnavailable: 0`.
2. Update the image to `nginx:1.27` and set the change cause annotation
   `kubernetes.io/change-cause: "upgrade to 1.27"`.
3. Update to the broken image `nginx:1.27-doesnotexist`. Watch the rollout get stuck – how many
   old pods are still running, and why?
4. Roll back to the revision with `nginx:1.27` (by revision number, not just "undo").

---

## Task 2.2 – ConfigMaps ⏱ 5 min

1. Create a ConfigMap `app-config` with `APP_MODE=production` and `APP_PORT=8080` (literals) and
   a key `nginx.conf` from a local file with any content.
2. Create a pod `config-demo` (image `busybox:1.36`, command `sleep 3600`) that
   - loads `APP_MODE` and `APP_PORT` as environment variables (`envFrom`),
   - mounts only the key `nginx.conf` as `/etc/nginx/nginx.conf` (`subPath`).
3. Change `APP_MODE` in the ConfigMap. Which of the two consumers sees the change without a
   restart, and why?

---

## Task 2.3 – Secrets ⏱ 5 min

1. Create a generic Secret `db-credentials` with `username=admin` and `password=S3cr3t!`.
2. Create a pod `secret-demo` (busybox, `sleep 3600`) that exposes `password` as env `DB_PASSWORD`
   and mounts the whole secret read-only under `/etc/db` with file mode `0400`.
3. Decode the password from the Secret with a single `kubectl` command.
4. Make the Secret immutable.

---

## Task 2.4 – Horizontal Pod Autoscaler ⏱ 5 min

1. Create a Deployment `php` (image `registry.k8s.io/hpa-example`, request `cpu: 100m`) and a
   service `php` on port 80.
2. Create an HPA `php` (`autoscaling/v2`): 1–5 replicas, average CPU utilization 50 %.
3. Generate load and watch the scaling; then configure a scale-down stabilization window of 60 s.

---

## Task 2.5 – Self-healing: probes & restart behavior ⏱ 6 min

Create a Deployment `healthy` (image `nginx:1.27`, 2 replicas) with
- a `startupProbe` (HTTP `/`, port 80, up to 30 s),
- a `readinessProbe` (HTTP `/`, every 5 s),
- a `livenessProbe` (TCP port 80, every 10 s, 3 failures).

Then delete one pod and kill the nginx process in the other
(`kubectl exec ... -- nginx -s stop`). Describe what the controller and the kubelet do in each case.

---

## Task 2.6 – DaemonSet on every node ⏱ 4 min

Create a DaemonSet `node-agent` in namespace `kube-system` (image `registry.k8s.io/pause:3.10`)
that runs on **all** nodes, including the control-plane node. Requests: `cpu: 10m`, `memory: 16Mi`.

---

## Task 2.7 – Node affinity, taints and tolerations ⏱ 6 min

1. Label `cka-worker` with `disk=ssd` and `cka-worker2` with `disk=hdd`.
2. Create a Deployment `fast` (3 replicas, `nginx:1.27`) that **must** run on `disk=ssd` nodes.
3. Create a Deployment `flexible` (3 replicas) that **prefers** `disk=hdd` (weight 80) but may run
   anywhere.
4. Taint `cka-worker2` with `maintenance=true:NoExecute`. What happens to the `flexible` pods there?
   Add a toleration that lets them stay for 60 s.
5. Remove the taint afterwards.

---

## Task 2.8 – Pod admission: LimitRange & ResourceQuota ⏱ 5 min

In namespace `limited`:
1. LimitRange `defaults`: container default request `100m`/`64Mi`, default limit `200m`/`128Mi`,
   max limit `500m`/`256Mi`.
2. ResourceQuota `quota`: max. 4 pods, `requests.cpu: 1`, `limits.memory: 1Gi`.
3. Show that a pod requesting a `1Gi` memory limit is rejected, and explain the error message.
4. Create a Deployment with 6 replicas – how many pods get created, and where do you see why?

---

## Task 2.9 – Static pod ⏱ 4 min

Create a static pod `static-web` (image `nginx:1.27`) on node `cka-worker`
(tip: `docker exec -it cka-worker bash`, kubelet `staticPodPath`).
Check that the mirror pod `static-web-cka-worker` appears. What happens if you `kubectl delete` it?

---

## Task 2.10 – Jobs & CronJobs ⏱ 5 min

1. Job `pi`: computes pi to 500 digits (`perl:5.40`, `perl -Mbignum=bpi -wle "print bpi(500)"`),
   `completions: 5`, `parallelism: 2`, `backoffLimit: 2`, done pods cleaned up after 120 s.
2. CronJob `cleanup`: every 15 minutes, `busybox` prints the date, keeps 2 successful and 1 failed
   job, `concurrencyPolicy: Forbid`, `startingDeadlineSeconds: 60`.
3. Trigger the CronJob manually once (`kubectl create job --from=...`).

---

## Task 2.11 – Init containers & native sidecars ⏱ 6 min

Create a pod `sidecar-demo`:
- init container `setup` (busybox) writes `<h1>ready</h1>` to a shared `emptyDir` at `/work/index.html`,
- **native sidecar** `log-shipper` (an init container with `restartPolicy: Always`, busybox) that
  runs `tail -F /logs/access.log`,
- main container `web` (`nginx:1.27`) serving `/usr/share/nginx/html` from the shared volume and
  writing logs to the second volume `/logs` (tip: `nginx` writes to `/var/log/nginx` – mount the
  log volume there).

Why is a native sidecar better than a regular second container for Jobs?

---

## Task 2.12 – PriorityClass & preemption ⏱ 5 min

1. Create PriorityClasses `low` (value 100) and `high` (value 10000, `preemptionPolicy: PreemptLowerPriority`).
2. Fill one worker with `low` pods (use large requests and a nodeSelector to `cka-worker`).
3. Create a `high` pod with the same nodeSelector that does not fit anymore. Observe the preemption
   in the events.

---

✅ Check: `./02-workloads-scheduling/verify.sh`
📖 Solutions: [`SOLUTIONS.md`](SOLUTIONS.md)
