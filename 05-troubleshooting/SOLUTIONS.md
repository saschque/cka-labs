# Domain 5 – Solutions

> Only look after your own attempt!

## General approach for cluster problems

```
kubectl get nodes / get pods -A          → what is broken?
kubectl describe node|pod / get events   → what does Kubernetes say?
node: systemctl status kubelet           → is the kubelet running?
node: journalctl -u kubelet -n 50        → why not?
node: crictl ps -a / crictl logs <id>    → control plane containers (static pods)
node: /etc/kubernetes/manifests/*.yaml   → static pod definitions
node: /var/lib/kubelet/config.yaml       → kubelet configuration
```

## 5.1 – Node NotReady
```bash
kubectl get nodes                                # cka-worker2 NotReady
kubectl describe node cka-worker2 | grep -A5 Conditions   # "Kubelet stopped posting node status"
docker exec -it cka-worker2 bash
systemctl status kubelet                         # inactive (dead), disabled
systemctl enable --now kubelet
exit
kubectl get nodes -w
```
`enable` = starts on boot, `--now` = starts immediately. "Permanently" means both.

## 5.2 – kubelet doesn't start
```bash
docker exec -it cka-worker bash
systemctl status kubelet                         # activating (auto-restart)
journalctl -u kubelet -n 30 --no-pager           # "unable to load client CA file /etc/kubernetes/pki/client-ca.crt: no such file"
ls /etc/kubernetes/pki/                          # only ca.crt exists
grep -n clientCAFile /var/lib/kubelet/config.yaml
sed -i 's#/etc/kubernetes/pki/client-ca.crt#/etc/kubernetes/pki/ca.crt#' /var/lib/kubelet/config.yaml
systemctl restart kubelet && systemctl status kubelet
```
Where the kubelet configuration lives: `/var/lib/kubelet/config.yaml` (KubeletConfiguration),
`/var/lib/kubelet/kubeadm-flags.env` (extra flags), the systemd drop-in
`/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf` and `/etc/kubernetes/kubelet.conf`
(kubeconfig to reach the API server). After editing the drop-in: `systemctl daemon-reload`.

## 5.3 – New pods stay Pending
```bash
kubectl create deploy probe --image=nginx:1.27 --replicas=2
kubectl get pods -l app=probe                    # Pending, no events → nobody schedules them
kubectl -n kube-system get pods | grep scheduler # CrashLoopBackOff / Error
kubectl -n kube-system logs kube-scheduler-cka-control-plane   # or: describe → "exec: kube-schedular: not found"
docker exec -it cka-control-plane bash
vi /etc/kubernetes/manifests/kube-scheduler.yaml # command: - kube-schedular  →  - kube-scheduler
# the kubelet notices the change and recreates the static pod automatically
crictl ps | grep scheduler
```
Pending pods **without** events = scheduler problem. Pending pods **with** `FailedScheduling`
events = the scheduler works but can't find a node (resources, taints, affinity).

## 5.4 – Deployments don't create pods
```bash
kubectl create deploy demo --image=nginx:1.27
kubectl get rs -l app=demo                       # nothing → the deployment controller doesn't run
kubectl -n kube-system get pods | grep controller-manager       # CrashLoopBackOff
kubectl -n kube-system logs kube-controller-manager-cka-control-plane
# "stat /etc/kubernetes/controller-manager.config: no such file or directory"
docker exec cka-control-plane ls /etc/kubernetes/                # controller-manager.conf
docker exec cka-control-plane sed -i 's#controller-manager.config#controller-manager.conf#' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml
```
The controller manager runs all controllers (Deployment, ReplicaSet, Node, Job, EndpointSlice …).
When it's down, nothing reconciles – existing pods keep running, but nothing changes.

## 5.5 – The API server is down
```bash
kubectl get nodes                                # connection refused
docker exec -it cka-control-plane bash
crictl ps -a | grep kube-apiserver               # Exited, restarting
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -5
# "Error while dialing: dial tcp 127.0.0.1:2399: connect: connection refused"  → wrong etcd address
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml        # etcd listens on 2379
sed -i 's#127.0.0.1:2399#127.0.0.1:2379#' /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps                                  # wait until kube-apiserver is Running
exit
kubectl get nodes
```
If `crictl logs` shows nothing useful: `ls /var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/`
and `journalctl -u kubelet | grep apiserver` (YAML syntax errors in the manifest only show up there).

## 5.6 – Service DNS doesn't work
```bash
kubectl run d --rm -it --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default.svc.cluster.local
kubectl -n kube-system get pods -l k8s-app=kube-dns         # Running
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
kubectl -n kube-system get cm coredns -o yaml               # "kubernetes cluster.locl in-addr.arpa ..."
kubectl -n kube-system edit cm coredns                      # cluster.locl → cluster.local
kubectl -n kube-system rollout restart deploy coredns
```
DNS checklist: CoreDNS pods running? Service `kube-dns` has endpoints? Pod `/etc/resolv.conf`
points to the kube-dns ClusterIP? Corefile correct? NetworkPolicies allow UDP/TCP 53?

## 5.7 – Monitor resource usage
```bash
kubectl top pods -n load --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /tmp/top-cpu-pod.txt
kubectl top nodes --sort-by=memory                          # the MEMORY% column
kubectl top nodes --no-headers | sort -k5 -rn | head -1 | awk '{print $1}' > /tmp/top-mem-node.txt
kubectl top pod chatter -n load --containers
kubectl -n load get pods -o json | jq -r '.items[] | select(.status.qosClass=="BestEffort") | .metadata.name' > /tmp/besteffort.txt
```
`--sort-by=memory` sorts by absolute usage; the task asks for **percent** (column 5).
QoS classes: **Guaranteed** (requests = limits for all containers), **Burstable** (some
requests/limits), **BestEffort** (none) – BestEffort pods are evicted first under node pressure.

## 5.8 – Container output streams
```bash
kubectl -n load logs chatter -c app --since=2m | grep ERROR > /tmp/chatter-errors.log
kubectl -n load logs chatter -c audit --timestamps
kubectl -n load logs crasher --previous | tail -1 > /tmp/crasher-reason.txt     # "FATAL: license key expired"
```
- `kubectl logs` shows **stdout and stderr** together.
- `--previous` = the previous (crashed) instance of the container.
- On the node: `/var/log/pods/<ns>_<pod>_<uid>/<container>/0.log` (symlinked from `/var/log/containers/`).
- Without an API server: `crictl ps -a`, `crictl logs <container-id>`.
- Logs rotate (kubelet `containerLogMaxSize`) – for history you need central log collection.

## 5.9 – Troubleshoot services and networking
```bash
kubectl -n shop get endpointslices
kubectl -n shop describe svc catalog cart checkout
```
| Service | Problem | Fix |
|---------|---------|-----|
| `catalog` | Selector `tier: frontend`, pods have `tier: backend` → no endpoints | `kubectl -n shop patch svc catalog --type=json -p='[{"op":"replace","path":"/spec/selector/tier","value":"backend"}]'` |
| `cart` | Endpoints exist, but `targetPort: 8080` – nginx listens on 80 → connection refused | `kubectl -n shop patch svc cart --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":80}]'` |
| `checkout` | NetworkPolicy only allows namespace `team=payments` → timeout | Add a second `from` entry for the client (keep the existing one) |

```bash
kubectl -n shop patch netpol checkout-lockdown --type=json -p='[
  {"op":"add","path":"/spec/ingress/0/from/-","value":{"podSelector":{"matchLabels":{"app":"client"}}}}]'
```
Symptoms tell you where to look: **"connection refused"** = endpoint exists but nothing listens on
the port (targetPort); **timeout** = no endpoints or a NetworkPolicy drops the packets;
**"bad address"** = DNS.

## 5.10 – Broken workloads
| Deployment | Diagnosis | Cause | Fix |
|------------|-----------|-------|-----|
| a1-frontend | `ErrImagePull`: `ngnix` not found | Typo in the image name | `kubectl -n broken set image deploy/a1-frontend web=nginx:1.27` |
| a2-api | `ContainerCreating`, event `configmap "a2-api-config" not found` | Wrong ConfigMap name (it's `api-config`) | Patch the volume to `configMap.name: api-config` |
| a3-worker | `CrashLoopBackOff`, exit code 3 | The command exits immediately | Change the command so it keeps running, e.g. `["sh","-c","echo starting; sleep 3600"]` |
| a4-cache | `Pending`: `untolerated taint {node-role.kubernetes.io/control-plane}` | nodeSelector to the control plane without toleration | Remove the nodeSelector (or add the toleration) |
| a5-reports | 1/2, RS event `exceeded quota ... requests.memory` | 2 × 600Mi > quota 1Gi | Lower the request (e.g. 200Mi) or raise the quota |
| a6-db | PVC `Pending`, event: provisioning failed – only `ReadWriteOnce` supported | local-path does not support RWX | Recreate the PVC with `ReadWriteOnce` |

```bash
kubectl -n broken patch deploy a2-api --type=json -p='[{"op":"replace","path":"/spec/template/spec/volumes/0/configMap/name","value":"api-config"}]'
kubectl -n broken patch deploy a4-cache --type=json -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl -n broken set resources deploy a5-reports --requests=memory=200Mi
kubectl -n broken get pvc a6-data -o yaml > /tmp/pvc.yaml && kubectl -n broken delete pvc a6-data
# edit /tmp/pvc.yaml: accessModes [ReadWriteOnce], remove status/uid/resourceVersion; then
kubectl apply -f /tmp/pvc.yaml
```

## 5.11 – Node maintenance
```bash
kubectl drain cka-worker --ignore-daemonsets --delete-emptydir-data
# hangs: "Cannot evict pod as it would violate the pod's disruption budget."
kubectl -n load get pdb critical                 # minAvailable 2, replicas 2 → ALLOWED DISRUPTIONS 0
kubectl -n load patch pdb critical --type=merge -p '{"spec":{"minAvailable":1}}'
```
The `critical` pods are pinned to `cka-worker` via nodeSelector – after the eviction they can't be
rescheduled anywhere else. To really keep the app available, also remove the nodeSelector (or
scale up first):
```bash
kubectl -n load patch deploy critical --type=json -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl drain cka-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon cka-worker
```
`cordon` = no new pods; `drain` = cordon + evict (respects PDBs); `uncordon` = schedulable again.
