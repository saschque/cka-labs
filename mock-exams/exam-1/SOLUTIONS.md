# CKA Mock Exam 1 – Solutions

> Only read after the 120 minutes are up!

Recommended order: **15 → 16** first (they block pods everywhere), then the rest.

### 1 – RBAC
```bash
kubectl -n m1-app create sa m1-deployer
kubectl -n m1-app create role m1-deployer --verb=create,update,patch,delete --resource=deployments.apps
kubectl -n m1-app create rolebinding m1-deployer --role=m1-deployer --serviceaccount=m1-app:m1-deployer
kubectl auth can-i delete deploy -n m1-app --as=system:serviceaccount:m1-app:m1-deployer    # yes
kubectl auth can-i delete deploy -n default --as=system:serviceaccount:m1-app:m1-deployer   # no
```

### 2 – etcd backup
```bash
E="kubectl -n kube-system exec etcd-cka-control-plane --"
CERTS="--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$E etcdctl --endpoints=https://127.0.0.1:2379 $CERTS snapshot save /var/lib/etcd/m1-snapshot.db
$E etcdutl snapshot status /var/lib/etcd/m1-snapshot.db -w json | jq .totalKey > /tmp/m1-etcd-keys.txt
```

### 3 – Helm
```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo && helm repo update
helm install m1-web podinfo/podinfo -n m1-helm --set replicaCount=2
helm upgrade m1-web podinfo/podinfo -n m1-helm --reuse-values --set ui.color='#34577c'
```
Without `--reuse-values` (or repeating `--set replicaCount=2`), the upgrade falls back to 1 replica.

### 4 – Operator
```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata: {name: m1-selfsigned, namespace: m1-app}
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: {name: m1-cert, namespace: m1-app}
spec:
  secretName: m1-tls
  dnsNames: [api.m1.lab]
  issuerRef: {name: m1-selfsigned, kind: Issuer}
```

### 5 – Kustomize
```bash
mkdir -p /tmp/m1-kustomize/staging
cat > /tmp/m1-kustomize/staging/kustomization.yaml <<'EOF'
resources: [../base]
namespace: m1-staging
replicas:
  - {name: shop, count: 2}
labels:
  - pairs: {env: staging}
    includeSelectors: true
EOF
kubectl apply -k /tmp/m1-kustomize/staging
```
`labels` with `includeSelectors: true` behaves like the deprecated `commonLabels`.

### 6 – Rolling update
```bash
kubectl -n m1-app patch deploy api -p '{"spec":{"strategy":{"type":"RollingUpdate","rollingUpdate":{"maxSurge":2,"maxUnavailable":1}}}}'
kubectl -n m1-app set image deploy/api nginx=nginx:1.27
kubectl -n m1-app rollout status deploy/api
```

### 7 – Configuration
```yaml
apiVersion: v1
kind: Pod
metadata: {name: config-pod, namespace: m1-app}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: API_KEY
          valueFrom: {secretKeyRef: {name: m1-secrets, key: api-key}}
      volumeMounts: [{name: settings, mountPath: /etc/settings}]
  volumes:
    - name: settings
      configMap: {name: m1-settings}
```

### 8 – Scheduling
```yaml
apiVersion: v1
kind: Pod
metadata: {name: gpu-job, namespace: m1-app}
spec:
  nodeSelector: {accelerator: gpu}
  tolerations:
    - {key: gpu, operator: Equal, value: "true", effect: NoSchedule}
  containers:
    - {name: c, image: registry.k8s.io/pause:3.10}
```

### 9 – NodePort
```bash
kubectl -n m1-app expose deploy api --name=api-np --type=NodePort --port=80
kubectl -n m1-app patch svc api-np --type=json -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":31081}]'
```

### 10 – NetworkPolicy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: postgres-access, namespace: m1-db}
spec:
  podSelector: {matchLabels: {app: postgres}}
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: m1-app}}
          podSelector: {matchLabels: {app: api}}       # same entry = AND
      ports: [{protocol: TCP, port: 5432}]
```

### 11 – Gateway API
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: m1-gw, namespace: m1-app}
spec:
  gatewayClassName: traefik
  listeners:
    - {name: http, protocol: HTTP, port: 8000, hostname: m1.example.com}
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: m1-api, namespace: m1-app}
spec:
  parentRefs: [{name: m1-gw}]
  hostnames: [m1.example.com]
  rules:
    - matches: [{path: {type: PathPrefix, value: /api}}]
      backendRefs: [{name: api, port: 80}]
```

### 12 – CoreDNS
`kubectl -n kube-system edit cm coredns` – add above the `kubernetes` block:
```
hosts {
    10.10.10.10 legacy.m1.lab
    fallthrough
}
```
Then `kubectl -n kube-system rollout restart deploy coredns`.

### 13 – Static provisioning
```yaml
apiVersion: v1
kind: PersistentVolume
metadata: {name: m1-pv}
spec:
  capacity: {storage: 2Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: m1-manual
  hostPath: {path: /mnt/m1, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: m1-pvc, namespace: m1-app}
spec:
  storageClassName: m1-manual
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
---
apiVersion: v1
kind: Pod
metadata: {name: m1-storage, namespace: m1-app}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep", "3600"], volumeMounts: [{name: d, mountPath: /data}]}
  volumes:
    - {name: d, persistentVolumeClaim: {claimName: m1-pvc}}
```

### 14 – StorageClass
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: m1-fast}
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: fast-data, namespace: m1-app}
spec:
  storageClassName: m1-fast
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 200Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: fast-pod, namespace: m1-app}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep", "3600"], volumeMounts: [{name: d, mountPath: /data}]}
  volumes:
    - {name: d, persistentVolumeClaim: {claimName: fast-data}}
```

### 15 – Cluster component
Pending without events → scheduler.
```bash
kubectl -n kube-system get pods | grep scheduler              # CrashLoopBackOff
kubectl -n kube-system logs kube-scheduler-cka-control-plane  # "stat /etc/kubernetes/scheduler.config: no such file"
docker exec cka-control-plane sed -i 's#scheduler.config#scheduler.conf#' /etc/kubernetes/manifests/kube-scheduler.yaml
```

### 16 – Node
```bash
docker exec cka-worker systemctl status kubelet     # inactive, disabled
docker exec cka-worker systemctl enable --now kubelet
```

### 17 – Application
1. Image `nginx:1.27-alpinee` does not exist → `ImagePullBackOff`.
2. Service selector `version: v1`, pods have `version: v2` → no endpoints.
```bash
kubectl -n m1-incident set image deploy/web web=nginx:1.27-alpine
kubectl -n m1-incident patch svc web --type=json -p='[{"op":"remove","path":"/spec/selector/version"}]'
printf 'image tag nginx:1.27-alpinee does not exist\nservice selector version=v1 does not match pods (v2)\n' > /tmp/m1-incident.txt
```

### 18 – Resource usage
```bash
kubectl top pods -n m1-load --sort-by=memory --no-headers | head -1 | awk '{print $1}' > /tmp/m1-top-mem.txt
kubectl top pods -n m1-load --sort-by=cpu --no-headers | head -1 | awk '{print $1}' > /tmp/m1-top-cpu.txt
```
