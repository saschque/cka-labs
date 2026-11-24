#!/usr/bin/env bash
# Prepares CKA mock exam 2. Run before starting the timer.
set -euo pipefail
CP=cka-control-plane
BK=/root/cka-backup

for ns in m2-qa m2-helm m2-ops m2-app m2-sys m2-team m2-secure m2-data m2-net m2-logs; do
  kubectl create ns "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# Task 4: two releases with an older chart version
helm repo add podinfo https://stefanprodan.github.io/podinfo >/dev/null 2>&1 || true
helm repo update podinfo >/dev/null
OLD=$(helm search repo podinfo/podinfo --versions -o json | jq -r '.[5].version')
helm upgrade --install m2-podinfo podinfo/podinfo -n m2-helm --version "$OLD" --set replicaCount=2 --set ui.message=m2
helm upgrade --install m2-old podinfo/podinfo -n m2-helm --version "$OLD"

kubectl apply -f - <<'EOF'
# Task 5
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: backups.ops.m2.io}
spec:
  group: ops.m2.io
  scope: Namespaced
  names: {kind: Backup, plural: backups, singular: backup, shortNames: [bkp]}
  versions:
    - name: v1beta1
      served: true
      storage: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                schedule: {type: string}
                retentionDays: {type: integer}
---
# Task 6, 9, 10, 11
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: m2-app}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
        - {name: web, image: "nginx:1.27", resources: {requests: {cpu: 50m, memory: 32Mi}}}
---
apiVersion: v1
kind: Service
metadata: {name: web, namespace: m2-app}
spec:
  selector: {app: web}
  ports: [{port: 80}]
---
apiVersion: v1
kind: Pod
metadata: {name: tester, namespace: m2-secure, labels: {app: tester}}
spec:
  containers: [{name: c, image: "busybox:1.36", command: ["sleep", "infinity"]}]
---
# Task 14: a PV that was used before
apiVersion: v1
kind: PersistentVolume
metadata: {name: m2-archive}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath: {path: /mnt/m2-archive, type: DirectoryOrCreate}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: {name: old-archive, namespace: m2-data}
spec:
  storageClassName: archive
  accessModes: [ReadWriteOnce]
  resources: {requests: {storage: 1Gi}}
---
# Task 17: wrong port name + NetworkPolicy
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: m2-net}
spec:
  replicas: 2
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers:
        - name: api
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          args: ["netexec", "--http-port=8080"]
          ports: [{name: http, containerPort: 8080}]
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: m2-net}
spec:
  selector: {app: api}
  ports: [{port: 80, targetPort: web}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-ingress, namespace: m2-net}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress]
  ingress:
    - from: [{podSelector: {matchLabels: {role: client}}}]
---
apiVersion: v1
kind: Pod
metadata: {name: client, namespace: m2-net, labels: {app: client}}
spec:
  containers: [{name: c, image: "busybox:1.36", command: ["sleep", "infinity"]}]
---
# Task 18
apiVersion: v1
kind: Pod
metadata: {name: billing, namespace: m2-logs}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sh", "-c", "while true; do echo 'billing ok'; sleep 5; done"]}
---
apiVersion: v1
kind: Pod
metadata: {name: indexer, namespace: m2-logs}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sh", "-c", "echo 'indexing batch 1'; sleep 8; echo 'OutOfMemory: heap exhausted at batch 2' >&2; exit 137"]}
---
apiVersion: v1
kind: Pod
metadata: {name: mailer, namespace: m2-logs}
spec:
  containers:
    - {name: c, image: "busybox:1.36", command: ["sh", "-c", "echo 'warning: memory high'; sleep 3600"]}
EOF

# Task 14: write data, then release the PV
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: archive-writer, namespace: m2-data}
spec:
  restartPolicy: Never
  containers:
    - {name: c, image: "busybox:1.36", command: ["sh", "-c", "echo 'invoices 2025' > /data/archive.txt"], volumeMounts: [{name: d, mountPath: /data}]}
  volumes: [{name: d, persistentVolumeClaim: {claimName: old-archive}}]
EOF
kubectl -n m2-data wait --for=jsonpath='{.status.phase}'=Succeeded pod/archive-writer --timeout=120s
kubectl -n m2-data delete pod archive-writer
kubectl -n m2-data delete pvc old-archive
until [[ $(kubectl get pv m2-archive -o jsonpath='{.status.phase}') == Released ]]; do sleep 2; done

# Task 15: break the controller manager (image that does not exist)
docker exec $CP sh -c "mkdir -p $BK && cp -n /etc/kubernetes/manifests/kube-controller-manager.yaml $BK/"
docker exec $CP sed -i -E 's#(image: .*kube-controller-manager):v[0-9.]+#\1:v9.99.9#' /etc/kubernetes/manifests/kube-controller-manager.yaml

# Task 16: break DNS twice
kubectl -n kube-system scale deploy coredns --replicas=0
kubectl -n kube-system patch svc kube-dns --type=merge -p '{"spec":{"selector":{"k8s-app":"core-dns"}}}'

echo "✅ Mock exam 2 ready. Start the timer: 120 minutes."
