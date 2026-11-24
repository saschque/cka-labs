# Domain 4 – Solutions

> Only look after your own attempt!

## 4.1 – Dynamic provisioning
```bash
kubectl get sc       # standard (default), rancher.io/local-path, Delete, WaitForFirstConsumer
kubectl -n storage apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: data}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 500Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: writer}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /data/hello.txt && sleep 3600"]
      volumeMounts: [{name: data, mountPath: /data}]
  volumes:
    - name: data
      persistentVolumeClaim: {claimName: data}
EOF
kubectl -n storage get pvc data          # Bound after the pod was scheduled
kubectl get pv -o wide
kubectl get pv $(kubectl -n storage get pvc data -o jsonpath='{.spec.volumeName}') -o jsonpath='{.spec.nodeAffinity}'
```
Without `storageClassName`, the **default** StorageClass is used. It stays `Pending` until a pod
uses it because of `WaitForFirstConsumer`. The local-path PV has a node affinity to the node the
pod landed on – the data lives under `/var/local-path-provisioner/` on that node.

## 4.2 – Your own StorageClass & default class
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: {name: retain-local}
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```
```bash
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch sc retain-local -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
kubectl get sc
# back
kubectl patch sc retain-local -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
kubectl patch sc standard -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```
With two default classes, new PVCs without a class get the most recently created default.
`reclaimPolicy` and `provisioner` are immutable – change them by recreating the class.

## 4.3 – Static PV & binding
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-manual
  labels: {tier: gold}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: manual
  hostPath:
    path: /mnt/manual
    type: DirectoryOrCreate
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - {key: kubernetes.io/hostname, operator: In, values: [cka-worker]}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: claim-manual, namespace: storage}
spec:
  storageClassName: manual
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 500Mi}}
  selector:
    matchLabels: {tier: gold}
```
A claim binds to a PV that has **at least** the requested capacity, matching access modes,
class and selector. PV and PVC are 1:1 – the remaining 500Mi are not usable by others.
`storageClassName: manual` doesn't need an existing StorageClass object for static binding.

## 4.4 – Reclaim policies
```bash
kubectl -n storage delete pvc claim-manual
kubectl get pv pv-manual        # STATUS Released – spec.claimRef still points to the deleted claim
kubectl patch pv pv-manual --type=json -p='[{"op":"remove","path":"/spec/claimRef"}]'
kubectl get pv pv-manual        # Available
```
`Retain` keeps the PV and its data; an admin has to clean up and release it manually.
With `Delete`, the PV (and, for dynamic provisioners, the backing storage) would be deleted together
with the PVC. `Recycle` is deprecated.

## 4.5 – Volume types
```bash
kubectl -n storage create cm app-settings --from-literal=color=blue
```
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: volumes
  namespace: storage
  labels: {app: volumes, tier: demo}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts:
        - {name: cache, mountPath: /cache}
        - {name: info, mountPath: /etc/info}
        - {name: host-logs, mountPath: /host/logs, readOnly: true}
  volumes:
    - name: cache
      emptyDir: {medium: Memory, sizeLimit: 64Mi}
    - name: info
      projected:
        sources:
          - downwardAPI:
              items:
                - path: labels
                  fieldRef: {fieldPath: metadata.labels}
          - configMap:
              name: app-settings
          - serviceAccountToken:
              audience: vault
              expirationSeconds: 600
              path: vault-token
    - name: host-logs
      hostPath: {path: /var/log, type: Directory}
```
`kubectl -n storage exec volumes -- ls /etc/info` → `color labels vault-token`.
`medium: Memory` uses tmpfs – it counts against the container's memory limit.

## 4.6 – StatefulSet storage
```yaml
apiVersion: v1
kind: Service
metadata: {name: db, namespace: storage}
spec:
  clusterIP: None
  selector: {app: db}
  ports: [{port: 80}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: db, namespace: storage}
spec:
  serviceName: db
  replicas: 2
  selector: {matchLabels: {app: db}}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: c
          image: busybox:1.36
          command: ["sh", "-c", "hostname >> /data/id.txt; sleep 3600"]
          volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:
    - metadata: {name: data}
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: standard
        resources: {requests: {storage: 100Mi}}
```
```bash
kubectl -n storage delete pod db-0 && kubectl -n storage exec db-0 -- cat /data/id.txt   # db-0 twice
kubectl -n storage scale sts db --replicas=0 && kubectl -n storage get pvc               # data-db-0/1 stay
```
Each replica keeps its own PVC (`data-db-0`, `data-db-1`) across restarts and scaling. They are only
deleted with `persistentVolumeClaimRetentionPolicy` `Delete` or manually.

## 4.7 – Access modes & generic ephemeral volumes
- **RWO** – read-write by **one node** (several pods on that node may share it)
- **ROX** – read-only by many nodes
- **RWX** – read-write by many nodes (NFS, CephFS, cloud file storage)
- **RWOP** – read-write by **one pod** only

`local-path` only supports `ReadWriteOnce`.
```yaml
apiVersion: v1
kind: Pod
metadata: {name: scratch, namespace: storage}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts: [{name: scratch, mountPath: /scratch}]
  volumes:
    - name: scratch
      ephemeral:
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: standard
            resources: {requests: {storage: 200Mi}}
```
The PVC `scratch-scratch` is owned by the pod (ownerReference) and is deleted together with it.
