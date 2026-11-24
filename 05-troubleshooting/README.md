# Domain 5 – Troubleshooting (30 %)

Competencies from the curriculum:
- Troubleshoot clusters and nodes
- Troubleshoot cluster components
- Monitor cluster and application resource usage
- Manage and evaluate container output streams
- Troubleshoot services and networking

The biggest domain. Most tasks start with a script that breaks something:

```bash
./05-troubleshooting/scenarios/break.sh <scenario>   # node | kubelet | scheduler | controller-manager | apiserver | dns
./05-troubleshooting/scenarios/restore.sh            # emergency reset if you get completely stuck
```

In kind, a "node" is a Docker container: `docker exec -it cka-control-plane bash` is your SSH.
`systemctl`, `journalctl`, `crictl` work inside it exactly as on a real node.

**Run one break scenario at a time** and fix it before starting the next one.

---

## Task 5.1 – Node NotReady ⏱ 5 min

```bash
./05-troubleshooting/scenarios/break.sh node
```
One node is `NotReady`. Find out which one and why, fix it permanently (it must survive a reboot)
and check that pods get scheduled on it again.

---

## Task 5.2 – kubelet doesn't start ⏱ 7 min

```bash
./05-troubleshooting/scenarios/break.sh kubelet
```
`cka-worker` is `NotReady`, and this time the kubelet is running into an error on startup. Find
the error in the kubelet logs and fix the configuration.

---

## Task 5.3 – New pods stay Pending ⏱ 6 min

```bash
./05-troubleshooting/scenarios/break.sh scheduler
```
Create a Deployment `probe` with 2 replicas. Its pods stay `Pending` and have **no events**.
Find the broken component and fix it.

---

## Task 5.4 – Deployments don't create pods ⏱ 6 min

```bash
./05-troubleshooting/scenarios/break.sh controller-manager
```
`kubectl create deploy demo --image=nginx:1.27` succeeds, but no ReplicaSet and no pods appear.
Scaling existing Deployments has no effect either. Fix it.

---

## Task 5.5 – The API server is down ⏱ 8 min

```bash
./05-troubleshooting/scenarios/break.sh apiserver
```
`kubectl` returns `connection refused` (wait ~30 s after running the script). Without a working
`kubectl`, find out why the API server doesn't come up and fix it.
Tools: `docker exec`, `crictl ps -a`, `crictl logs`, `/var/log/pods/`, `journalctl -u kubelet`.

---

## Task 5.6 – Service DNS doesn't work ⏱ 6 min

```bash
./05-troubleshooting/scenarios/break.sh dns
```
Pods can still resolve external names, but `kubernetes.default.svc.cluster.local` returns
`NXDOMAIN`. CoreDNS pods are `Running`. Find the problem and fix it.

---

## Task 5.7 – Monitor resource usage ⏱ 5 min

```bash
kubectl apply -f 05-troubleshooting/scenarios/load.yaml
```
Wait ~1 minute for metrics, then:
1. Write the name of the pod in namespace `load` with the **highest CPU** usage to `/tmp/top-cpu-pod.txt`.
2. Write the name of the node with the highest **memory usage in percent** to `/tmp/top-mem-node.txt`.
3. Show the CPU usage per **container** of the pod `chatter`.
4. Which pods in `load` have no resource requests at all (QoS class `BestEffort`)? → `/tmp/besteffort.txt`

---

## Task 5.8 – Container output streams ⏱ 6 min

Using the pods in namespace `load`:
1. Write all `ERROR` lines of the container `app` of pod `chatter` from the **last 2 minutes** to
   `/tmp/chatter-errors.log`.
2. Show the logs of the **audit** container only, with timestamps.
3. The pod `crasher` keeps restarting. Write the last line it printed **before its last crash**
   to `/tmp/crasher-reason.txt`.
4. Where are container logs stored on the node, and how do you read the logs of a container when
   the API server is down?

---

## Task 5.9 – Troubleshoot services and networking ⏱ 10 min

```bash
kubectl apply -f 05-troubleshooting/scenarios/network.yaml
```
From the pod `shop/client`, all three services must answer:
```bash
kubectl -n shop exec client -- wget -qO- -T 3 catalog
kubectl -n shop exec client -- wget -qO- -T 3 cart
kubectl -n shop exec client -- wget -qO- -T 3 checkout
```
None of them works. Find and fix the problem of each service **without** changing the Deployments'
pod templates. For `checkout`, the existing access for the `payments` team must stay in place.

---

## Task 5.10 – Broken workloads ⏱ 15 min

```bash
kubectl apply -f 05-troubleshooting/scenarios/apps.yaml
```
Six Deployments in namespace `broken` don't reach `READY`. Fix all of them. For each one, write
the root cause (one line, `<name>: <cause>`) to `/tmp/broken-causes.txt`.

| Deployment | Symptom |
|------------|---------|
| `a1-frontend` | Pods don't start |
| `a2-api` | Pods don't start |
| `a3-worker` | Pods restart constantly |
| `a4-cache` | Pods stay `Pending` |
| `a5-reports` | Only 1 of 2 replicas |
| `a6-db` | Pod stays `Pending` |

---

## Task 5.11 – Node maintenance ⏱ 5 min

`cka-worker` needs maintenance. Drain it (respecting DaemonSets and emptyDir data).
The drain hangs – find out why, fix it in a way that keeps the application available with at least
one pod, finish the drain and then make the node schedulable again.

---

✅ Check: `./05-troubleshooting/verify.sh`
📖 Solutions: [`SOLUTIONS.md`](SOLUTIONS.md)
