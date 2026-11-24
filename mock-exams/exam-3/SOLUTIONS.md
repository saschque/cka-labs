# CKA Mock Exam 3 – Solutions

> Only read after the 120 minutes are up!

Recommended order: **15** first (nothing works without the API server), then **16**.

### 1 – etcd snapshot
```bash
E="kubectl -n kube-system exec etcd-cka-control-plane --"
CERTS="--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$E etcdctl --endpoints=https://127.0.0.1:2379 $CERTS snapshot save /var/lib/etcd/m3-backup.db
$E etcdutl snapshot status /var/lib/etcd/m3-backup.db -w json | jq .revision > /tmp/m3-revision.txt
```

### 2 – ServiceAccount permissions
```bash
kubectl -n m3-app create rolebinding ci-bot-edit --clusterrole=edit --serviceaccount=m3-ci:ci-bot
kubectl -n m3-ci create token ci-bot --duration=2h > /tmp/m3-token.txt
kubectl auth can-i create deploy -n m3-app --as=system:serviceaccount:m3-ci:ci-bot    # yes
kubectl auth can-i create deploy -n m3-ci --as=system:serviceaccount:m3-ci:ci-bot     # no
```

### 3 – Kustomize patch
```bash
mkdir -p /tmp/m3-kustomize/prod && cd /tmp/m3-kustomize/prod
cat > kustomization.yaml <<'EOF'
resources: [../base]
namespace: m3-prod
patches:
  - path: resources.yaml
EOF
cat > resources.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  template:
    spec:
      containers:
        - name: api                      # merge key: the container name
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits: {memory: 128Mi}
EOF
kubectl apply -k /tmp/m3-kustomize/prod
```

### 4 – Helm values file
```bash
cat > /tmp/m3-values.yaml <<'EOF'
replicaCount: 3
ui:
  message: "exam 3"
EOF
helm repo add podinfo https://stefanprodan.github.io/podinfo && helm repo update
helm install m3-web podinfo/podinfo -n m3-helm -f /tmp/m3-values.yaml
```

### 5 – Joining nodes
```bash
docker exec cka-control-plane kubeadm token create --ttl 2h --print-join-command > /tmp/m3-join.txt
docker exec cka-control-plane kubeadm token list
```
For an additional **control-plane** node you would also need `--control-plane --certificate-key`
(from `kubeadm init phase upload-certs --upload-certs`).

### 6 – Rollback
```bash
kubectl -n m3-app rollout history deploy/frontend
kubectl -n m3-app rollout history deploy/frontend --revision=2     # shows nginx:1.26
kubectl -n m3-app rollout undo deploy/frontend --to-revision=2
```

### 7 – Sidecar
```yaml
apiVersion: v1
kind: Pod
metadata: {name: m3-sidecar, namespace: m3-app}
spec:
  initContainers:
    - name: shipper
      image: busybox:1.36
      restartPolicy: Always
      command: ["sh", "-c", "touch /var/log/app.log; tail -F /var/log/app.log"]
      volumeMounts: [{name: logs, mountPath: /var/log}]
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "while true; do date >> /var/log/app.log; sleep 2; done"]
      volumeMounts: [{name: logs, mountPath: /var/log}]
  volumes:
    - {name: logs, emptyDir: {}}
```
`kubectl -n m3-app logs m3-sidecar -c shipper` shows the dates.

### 8 – Spread
```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - labelSelector: {matchLabels: {app: m3-ha}}
              topologyKey: kubernetes.io/hostname
```
Only 2 worker nodes are schedulable (the control plane has a `NoSchedule` taint) → the third pod
stays `Pending`. With `preferred...` or `topologySpreadConstraints` + `ScheduleAnyway`, all 3 would run.

### 9 – Header routing
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: m3-gw, namespace: m3-app}
spec:
  gatewayClassName: traefik
  listeners: [{name: http, protocol: HTTP, port: 8000}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: m3-canary, namespace: m3-app}
spec:
  parentRefs: [{name: m3-gw}]
  hostnames: [app.m3.lab]
  rules:
    - matches: [{headers: [{name: x-version, value: v2}]}]
      backendRefs: [{name: v2, port: 80}]
    - backendRefs: [{name: v1, port: 80}]
```

### 10 – Preserve client IPs
```bash
kubectl -n m3-app expose deploy frontend --name=frontend-np --type=NodePort --port=80
kubectl -n m3-app patch svc frontend-np -p '{"spec":{"externalTrafficPolicy":"Local"}}'
```
`Local`: no second hop to another node → source IP preserved, but nodes without a local pod drop
the traffic. `Cluster` (default): load-balanced across all nodes, source IP is SNATed.

### 11 – Namespace isolation
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: same-namespace-only, namespace: m3-isolated}
spec:
  podSelector: {}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {}}]
```

### 12 – DNS rewrite
`kubectl -n kube-system edit cm coredns` – add inside the `.:53 { }` block:
```
rewrite name frontend.m3 frontend.m3-app.svc.cluster.local
```
Then `kubectl -n kube-system rollout restart deploy coredns`.

### 13 – Default StorageClass
```bash
kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: m3-standard
  annotations: {storageclass.kubernetes.io/is-default-class: "true"}
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl get sc
```

### 14 – Shared scratch space
```yaml
apiVersion: v1
kind: Pod
metadata: {name: m3-shared, namespace: m3-app}
spec:
  containers:
    - name: writer
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /shared/msg; sleep 3600"]
      volumeMounts: [{name: shared, mountPath: /shared}]
    - name: reader
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts: [{name: shared, mountPath: /shared, readOnly: true}]
  volumes:
    - name: shared
      emptyDir: {medium: Memory, sizeLimit: 32Mi}
```

### 15 – API server
```bash
docker exec -it cka-control-plane bash
crictl ps -a | grep apiserver
crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -3
# "open /etc/kubernetes/pki/api-server.crt: no such file or directory"
ls /etc/kubernetes/pki/ | grep apiserver
sed -i 's#pki/api-server.crt#pki/apiserver.crt#' /etc/kubernetes/manifests/kube-apiserver.yaml
watch crictl ps
```

### 16 – Node
```bash
docker exec -it cka-worker2 bash
systemctl status kubelet          # running or restarting
journalctl -u kubelet -n 20 --no-pager
# "... dial unix /run/containerd/containerd.socket: connect: no such file or directory"
ls /run/containerd/               # containerd.sock
grep -rn containerd.socket /var/lib/kubelet/
sed -i 's#containerd.socket#containerd.sock#' /var/lib/kubelet/kubeadm-flags.env /var/lib/kubelet/config.yaml
systemctl restart kubelet
```

### 17 – Workloads
1. `reports`: `CreateContainerConfigError` – Secret `reports-db` doesn't exist (it's `reports-db-secret`).
2. `cache`: `Pending` – requests 64 CPUs, `Insufficient cpu` on all nodes.
```bash
kubectl -n m3-incident patch deploy reports --type=json -p='[
  {"op":"replace","path":"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef/name","value":"reports-db-secret"}]'
kubectl -n m3-incident set resources deploy cache --requests=cpu=100m
printf 'reports: secret reports-db does not exist (reports-db-secret)\ncache: requests 64 CPUs, no node fits\n' > /tmp/m3-incident.txt
```

### 18 – Maintenance
The PDB `payments` has `maxUnavailable: 0` → no eviction allowed, and both pods are pinned to `cka-worker`.
```bash
kubectl -n m3-app patch pdb payments --type=merge -p '{"spec":{"maxUnavailable":1}}'
kubectl -n m3-app patch deploy payments --type=json -p='[{"op":"remove","path":"/spec/template/spec/nodeSelector"}]'
kubectl -n m3-app rollout status deploy/payments
kubectl drain cka-worker --ignore-daemonsets --delete-emptydir-data
kubectl uncordon cka-worker
```
Removing the nodeSelector first lets the new pods start on `cka-worker2`, so the app never goes down.
