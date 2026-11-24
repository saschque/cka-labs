# CKA Mock Exam 2 – Solutions

> Only read after the 120 minutes are up!

Recommended order: **15 → 16** first – without the controller manager, nothing reconciles
(no ReplicaSets, no PV binding), and without DNS many tests fail.

### 1 – New user
```bash
openssl genrsa -out /tmp/carol.key 2048
openssl req -new -key /tmp/carol.key -subj "/CN=carol/O=qa" -out /tmp/carol.csr
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata: {name: carol}
spec:
  request: $(base64 -w0 < /tmp/carol.csr)
  signerName: kubernetes.io/kube-apiserver-client
  usages: ["client auth"]
EOF
kubectl certificate approve carol
kubectl get csr carol -o jsonpath='{.status.certificate}' | base64 -d > /tmp/carol.crt
kubectl -n m2-qa create role qa-read --verb=get,list,watch --resource=pods,services
kubectl -n m2-qa create rolebinding qa-read --role=qa-read --group=qa
```
The certificate is only issued once the controller manager runs again (task 15) – it contains the signer.

### 2 – Aggregated ClusterRole
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: m2-monitoring}
aggregationRule:
  clusterRoleSelectors:
    - matchLabels: {rbac.m2.io/aggregate-to-monitoring: "true"}
rules: []                         # filled in automatically by the controller manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: m2-metrics-reader
  labels: {rbac.m2.io/aggregate-to-monitoring: "true"}
rules:
  - apiGroups: [""]
    resources: [pods, nodes]
    verbs: [get, list]
```
```bash
kubectl create clusterrolebinding m2-monitoring --clusterrole=m2-monitoring --group=monitoring-team
kubectl auth can-i list nodes --as=x --as-group=monitoring-team     # yes
```

### 3 – Extension interfaces
```bash
kubectl get node cka-worker2 -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}' > /tmp/m2-cri.txt
docker exec cka-worker2 ls /etc/cni/net.d/ > /tmp/m2-cni.txt     # 10-kindnet.conflist
```

### 4 – Helm
```bash
helm list -n m2-helm
helm upgrade m2-podinfo podinfo/podinfo -n m2-helm --reuse-values
helm uninstall m2-old -n m2-helm
```

### 5 – Custom resources
```bash
kubectl get crd | grep -i backup
kubectl api-resources | grep -i backup            # bkp  ops.m2.io/v1beta1  true  Backup
echo bkp > /tmp/m2-shortname.txt
kubectl apply -f - <<'EOF'
apiVersion: ops.m2.io/v1beta1
kind: Backup
metadata: {name: nightly, namespace: m2-ops}
spec: {schedule: "0 2 * * *", retentionDays: 14}
EOF
```

### 6 – Autoscaling
```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: m2-web, namespace: m2-app}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: web}
  minReplicas: 2
  maxReplicas: 8
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 60}}
    - type: Resource
      resource: {name: memory, target: {type: Utilization, averageUtilization: 70}}
```

### 7 – DaemonSet
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: m2-logger, namespace: m2-sys}
spec:
  selector: {matchLabels: {app: m2-logger}}
  template:
    metadata: {labels: {app: m2-logger}}
    spec:
      tolerations:
        - {key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}
      containers:
        - {name: c, image: "busybox:1.36", command: ["sleep", "infinity"]}
```

### 8 – Admission limits
```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: m2-limits, namespace: m2-team}
spec:
  limits:
    - type: Container
      defaultRequest: {cpu: 50m, memory: 32Mi}
      default: {cpu: 100m, memory: 64Mi}
      max: {memory: 128Mi}
---
apiVersion: v1
kind: ResourceQuota
metadata: {name: m2-quota, namespace: m2-team}
spec:
  hard: {pods: "5", limits.memory: 512Mi}
```

### 9 – Ingress
```bash
kubectl -n m2-app create ingress m2-shop --class=traefik --rule="shop.m2.lab/*=web:80"
curl -s -H 'Host: shop.m2.lab' localhost:30080/ | head -4
```

### 10 – Service types
```bash
kubectl -n m2-app create svc clusterip web-headless --clusterip=None --tcp=80:80
kubectl -n m2-app set selector svc web-headless app=web
kubectl -n m2-app create svc externalname payments --external-name=payments.example.com
```

### 11 – Egress policy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: restrict-egress, namespace: m2-secure}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: m2-app}}
          podSelector: {matchLabels: {app: web}}
      ports: [{protocol: TCP, port: 80}]
```
A policy with `policyTypes: [Egress]` that selects all pods denies everything not listed.

### 12 – External endpoint
```yaml
apiVersion: v1
kind: Service
metadata: {name: ext-db, namespace: m2-app}
spec:
  ports: [{name: mysql, port: 3306}]
---
apiVersion: discovery.k8s.io/v1
kind: EndpointSlice
metadata:
  name: ext-db-1
  namespace: m2-app
  labels: {kubernetes.io/service-name: ext-db}
addressType: IPv4
ports: [{name: mysql, port: 3306, protocol: TCP}]
endpoints: [{addresses: ["192.168.100.20"]}]
```

### 13 – StatefulSet
```yaml
apiVersion: v1
kind: Service
metadata: {name: kv, namespace: m2-data}
spec:
  clusterIP: None
  selector: {app: kv}
  ports: [{port: 6379}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: kv, namespace: m2-data}
spec:
  serviceName: kv
  replicas: 2
  selector: {matchLabels: {app: kv}}
  template:
    metadata: {labels: {app: kv}}
    spec:
      containers:
        - {name: redis, image: "redis:7", volumeMounts: [{name: data, mountPath: /data}]}
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        resources: {requests: {storage: 128Mi}}
```

### 14 – Reuse a volume
```bash
kubectl get pv m2-archive                    # Released, claimRef → m2-data/old-archive
kubectl patch pv m2-archive --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: archive, namespace: m2-data}
spec:
  storageClassName: archive
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 500Mi}}
  volumeName: m2-archive          # optional: bind explicitly
EOF
```
Never delete and recreate the PV for this – removing `claimRef` keeps everything else (and the data).

### 15 – Control plane
```bash
kubectl -n kube-system get pods | grep controller-manager       # ErrImagePull / ImagePullBackOff
kubectl -n kube-system describe pod kube-controller-manager-cka-control-plane | grep -i image
docker exec cka-control-plane grep image: /etc/kubernetes/manifests/kube-apiserver.yaml   # the correct version
docker exec -it cka-control-plane vi /etc/kubernetes/manifests/kube-controller-manager.yaml   # v9.99.9 → same tag as the API server
```

### 16 – DNS
1. CoreDNS is scaled to 0. 2. The `kube-dns` service selects `k8s-app: core-dns`, the pods have `k8s-app: kube-dns`.
```bash
kubectl -n kube-system get deploy coredns                       # 0/0
kubectl -n kube-system scale deploy coredns --replicas=2
kubectl -n kube-system get endpointslices -l kubernetes.io/service-name=kube-dns   # empty
kubectl -n kube-system patch svc kube-dns --type=merge -p '{"spec":{"selector":{"k8s-app":"kube-dns"}}}'
```

### 17 – Service
1. `targetPort: web`, but the container port is named `http` → no matching port.
2. NetworkPolicy only allows `role=client`, the client pod has `app=client`.
```bash
kubectl -n m2-net patch svc api --type=json -p='[{"op":"replace","path":"/spec/ports/0/targetPort","value":"http"}]'
kubectl -n m2-net patch netpol api-ingress --type=json -p='[
  {"op":"add","path":"/spec/ingress/0/from/-","value":{"podSelector":{"matchLabels":{"app":"client"}}}}]'
kubectl -n m2-net exec client -- wget -qO- -T 3 api
```
(Labeling the client pod `role=client` also works.)

### 18 – Logs
```bash
for p in $(kubectl -n m2-logs get pods -o name); do
  kubectl -n m2-logs logs $p --previous 2>/dev/null | grep -H --label=$p OutOfMemory
done
kubectl -n m2-logs logs indexer --previous | grep OutOfMemory > /tmp/m2-oom-line.txt
echo indexer > /tmp/m2-oom-pod.txt
```
Depending on timing the line is in the current or the previous container's log – check both.
