# CKA Mock Exam 4 – Solutions

> Only read after the 120 minutes are up!

Recommended order: **15 → 16** first.

### 1 – Least privilege
```bash
kubectl -n m4-app create role app-config-updater --verb=get,patch --resource=configmaps --resource-name=app-config
kubectl -n m4-app create rolebinding app-config-updater --role=app-config-updater --serviceaccount=m4-app:config-updater
SA=system:serviceaccount:m4-app:config-updater
kubectl auth can-i patch configmap/app-config -n m4-app --as=$SA      # yes
kubectl auth can-i patch configmap/other-config -n m4-app --as=$SA    # no
kubectl auth can-i list configmaps -n m4-app --as=$SA                 # no
```
`resourceNames` can't restrict `list`, `watch` or `create` – those requests have no object name.

### 2 – Query the API with a token
```bash
kubectl -n m4-ops create sa auditor
kubectl create clusterrole node-list --verb=get,list --resource=nodes
kubectl create clusterrolebinding auditor-nodes --clusterrole=node-list --serviceaccount=m4-ops:auditor
TOKEN=$(kubectl -n m4-ops create token auditor)
API=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
curl -sk -H "Authorization: Bearer $TOKEN" "$API/api/v1/nodes" | jq '.items | length' > /tmp/m4-nodes.txt
```
Use `--cacert` with the cluster CA instead of `-k` when you have it
(`kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d`).

### 3 – Helm template
```bash
helm template m4-web podinfo/podinfo --set replicaCount=4 --set service.type=NodePort -n m4-helm > /tmp/m4-rendered.yaml
kubectl apply -n m4-helm -f /tmp/m4-rendered.yaml
```
The resources are now managed by `kubectl`, not by Helm – `helm list` doesn't show them.

### 4 – Custom resource definition
```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: tenants.platform.m4.io}
spec:
  group: platform.m4.io
  scope: Cluster
  names: {kind: Tenant, plural: tenants, singular: tenant, shortNames: [tn]}
  versions:
    - name: v1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              required: [owner]
              properties:
                owner: {type: string}
                maxNamespaces: {type: integer, minimum: 1, maximum: 20, default: 5}
---
apiVersion: platform.m4.io/v1
kind: Tenant
metadata: {name: blue}
spec: {owner: team-blue}
```

### 5 – etcd snapshot status
```bash
E="kubectl -n kube-system exec etcd-cka-control-plane --"
CERTS="--cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key"
$E etcdctl --endpoints=https://127.0.0.1:2379 $CERTS snapshot save /var/lib/etcd/m4.db
$E etcdutl snapshot status /var/lib/etcd/m4.db -w json > /tmp/m4-snapshot.json
```

### 6 – Parallel Job
```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: m4-batch, namespace: m4-app}
spec:
  completions: 6
  parallelism: 3
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  template:
    spec:
      restartPolicy: Never
      containers: [{name: c, image: "busybox:1.36", command: ["echo", "processed"]}]
```

### 7 – CronJob
```bash
kubectl -n m4-app create cronjob m4-report --image=busybox:1.36 --schedule="30 6 * * 1" -- date
kubectl -n m4-app patch cronjob m4-report -p '{"spec":{"concurrencyPolicy":"Forbid","successfulJobsHistoryLimit":1}}'
kubectl -n m4-app create job m4-report-now --from=cronjob/m4-report
```

### 8 – Static pod
```bash
kubectl run m4-static --image=nginx:1.27 --labels=tier=static --dry-run=client -o yaml > /tmp/m4-static.yaml
docker cp /tmp/m4-static.yaml cka-worker2:/etc/kubernetes/manifests/m4-static.yaml
kubectl get pod m4-static-cka-worker2
```

### 9 – TLS Ingress
```bash
openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=secure.m4.lab" -keyout /tmp/m4.key -out /tmp/m4.crt
kubectl -n m4-app create secret tls m4-tls --cert=/tmp/m4.crt --key=/tmp/m4.key
kubectl -n m4-app create ingress m4-secure --class=traefik --rule="secure.m4.lab/*=web:80,tls=m4-tls"
curl -sk --resolve secure.m4.lab:30443:127.0.0.1 https://secure.m4.lab:30443/ | head -4
```

### 10 – Multi-port service
```yaml
apiVersion: v1
kind: Service
metadata: {name: multi, namespace: m4-app}
spec:
  selector: {app: multi}
  ports:
    - {name: http, port: 80, targetPort: http}
    - {name: metrics, port: 9090, targetPort: metrics}
```
Services with more than one port **must** name every port.

### 11 – Egress control
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: batch-egress, namespace: m4-app}
spec:
  podSelector: {matchLabels: {app: batch}}
  policyTypes: [Egress]
  egress:
    - to:
        - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
          podSelector: {matchLabels: {k8s-app: kube-dns}}
      ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
    - to: [{podSelector: {matchLabels: {app: web}}}]
      ports: [{protocol: TCP, port: 80}]
```

### 12 – Pod DNS settings
```yaml
apiVersion: v1
kind: Pod
metadata: {name: m4-dns, namespace: m4-app}
spec:
  dnsPolicy: "None"
  dnsConfig:
    nameservers: ["1.1.1.1"]
    searches: ["m4.lab"]
  containers: [{name: c, image: "busybox:1.36", command: ["sleep", "3600"]}]
```
dnsPolicy values: `ClusterFirst` (default), `Default` (node's resolv.conf), `ClusterFirstWithHostNet`, `None`.

### 13 – Read-only data
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: m4-data, namespace: m4-app}
spec:
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 100Mi}}
---
apiVersion: v1
kind: Pod
metadata: {name: m4-reader, namespace: m4-app}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      volumeMounts: [{name: d, mountPath: /reports, subPath: reports, readOnly: true}]
  volumes: [{name: d, persistentVolumeClaim: {claimName: m4-data}}]
```

### 14 – Ephemeral volume
```yaml
apiVersion: v1
kind: Pod
metadata: {name: m4-scratch, namespace: m4-app}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sleep", "3600"], volumeMounts: [{name: scratch, mountPath: /scratch}]}
  volumes:
    - name: scratch
      ephemeral:
        volumeClaimTemplate:
          spec:
            accessModes: [ReadWriteOnce]
            storageClassName: standard
            resources: {requests: {storage: 150Mi}}
```

### 15 – Scheduler
The scheduler pod is gone entirely – the kubelet can't parse its manifest.
```bash
kubectl -n kube-system get pods | grep scheduler                     # nothing
docker exec cka-control-plane journalctl -u kubelet --no-pager | grep -i scheduler | tail -3
# "... could not process manifest file ... yaml: line N: did not find expected key"
docker exec -it cka-control-plane vi /etc/kubernetes/manifests/kube-scheduler.yaml   # fix the indentation of "containers:"
```
Tip: validate a manifest with `kubectl apply --dry-run=client -f <file>` (copy it out with `docker cp`).

### 16 – Node
```bash
docker exec cka-worker systemctl status kubelet       # running, but errors
docker exec cka-worker journalctl -u kubelet -n 10 --no-pager   # "...containerd.sock: connect: no such file"
docker exec cka-worker systemctl status containerd    # inactive, disabled
docker exec cka-worker systemctl enable --now containerd
```

### 17 – Service
1. Service selector `app: frontend`, pods have `app: front-end`.
2. Even with the right label, the readiness probe checks `/ready` → 404 → pods never become Ready → not in endpoints.

The service must not change, so fix the pods:
```bash
kubectl -n m4-shop get deploy frontend -o yaml > /tmp/frontend.yaml
# selector is immutable → change labels in selector AND template, delete and recreate:
sed -i 's/front-end/frontend/g; s#path: /ready#path: /#' /tmp/frontend.yaml
kubectl -n m4-shop delete deploy frontend && kubectl apply -f /tmp/frontend.yaml
kubectl -n m4-shop get endpointslices -l kubernetes.io/service-name=frontend
```
(Alternative: keep the selector and only add `app: frontend` as an additional label in the pod
template – the Deployment selector stays `front-end`, the service then matches as well.)

### 18 – Monitoring
```bash
kubectl top pods -n m4-load --containers --no-headers | sort -k3 -rn | head -1 | awk '{print $1"/"$2}' > /tmp/m4-top-container.txt
kubectl -n m4-load get events --field-selector type=Warning --sort-by=.lastTimestamp -o jsonpath='{.items[-1].reason}' > /tmp/m4-warning.txt
```
The most recent warning is typically `Failed` or `BackOff` from the pod `badimage`.
