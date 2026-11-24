#!/usr/bin/env bash
# Prepares CKA mock exam 3. Run before starting the timer.
set -euo pipefail
CP=cka-control-plane
BK=/root/cka-backup

for ns in m3-ci m3-app m3-prod m3-helm m3-isolated m3-incident; do
  kubectl create ns "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl -n m3-ci create sa ci-bot --dry-run=client -o yaml | kubectl apply -f -

# Task 6: three revisions
kubectl -n m3-app create deploy frontend --image=nginx:1.25 --replicas=2 --dry-run=client -o yaml | kubectl apply -f -
kubectl -n m3-app rollout status deploy/frontend --timeout=120s
kubectl -n m3-app set image deploy/frontend nginx=nginx:1.26 && kubectl -n m3-app rollout status deploy/frontend --timeout=120s
kubectl -n m3-app set image deploy/frontend nginx=nginx:1.27 && kubectl -n m3-app rollout status deploy/frontend --timeout=120s

kubectl apply -f - <<'EOF'
# Task 9
apiVersion: apps/v1
kind: Deployment
metadata: {name: v1, namespace: m3-app}
spec:
  selector: {matchLabels: {app: v1}}
  template:
    metadata: {labels: {app: v1}}
    spec:
      containers: [{name: c, image: "registry.k8s.io/e2e-test-images/agnhost:2.53", args: ["netexec", "--http-port=8080"]}]
---
apiVersion: v1
kind: Service
metadata: {name: v1, namespace: m3-app}
spec: {selector: {app: v1}, ports: [{port: 80, targetPort: 8080}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: v2, namespace: m3-app}
spec:
  selector: {matchLabels: {app: v2}}
  template:
    metadata: {labels: {app: v2}}
    spec:
      containers: [{name: c, image: "nginx:1.27"}]
---
apiVersion: v1
kind: Service
metadata: {name: v2, namespace: m3-app}
spec: {selector: {app: v2}, ports: [{port: 80}]}
---
apiVersion: v1
kind: Service
metadata: {name: frontend, namespace: m3-app}
spec: {selector: {app: frontend}, ports: [{port: 80}]}
---
# Task 11
apiVersion: v1
kind: Pod
metadata: {name: inside, namespace: m3-isolated, labels: {app: inside}}
spec:
  containers: [{name: web, image: "nginx:1.27"}]
---
# Task 17
apiVersion: apps/v1
kind: Deployment
metadata: {name: reports, namespace: m3-incident}
spec:
  replicas: 1
  selector: {matchLabels: {app: reports}}
  template:
    metadata: {labels: {app: reports}}
    spec:
      containers:
        - name: reports
          image: busybox:1.36
          command: ["sh", "-c", "echo running; sleep 3600"]
          env:
            - name: DB_PASSWORD
              valueFrom: {secretKeyRef: {name: reports-db, key: password}}
---
apiVersion: v1
kind: Secret
metadata: {name: reports-db-secret, namespace: m3-incident}
stringData: {password: "pa55"}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: cache, namespace: m3-incident}
spec:
  replicas: 1
  selector: {matchLabels: {app: cache}}
  template:
    metadata: {labels: {app: cache}}
    spec:
      containers:
        - name: redis
          image: redis:7
          resources: {requests: {cpu: "64"}}
---
# Task 18
apiVersion: apps/v1
kind: Deployment
metadata: {name: payments, namespace: m3-app}
spec:
  replicas: 2
  selector: {matchLabels: {app: payments}}
  template:
    metadata: {labels: {app: payments}}
    spec:
      nodeSelector: {kubernetes.io/hostname: cka-worker}
      containers: [{name: c, image: "registry.k8s.io/pause:3.10"}]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: payments, namespace: m3-app}
spec:
  maxUnavailable: 0
  selector: {matchLabels: {app: payments}}
EOF

# Task 3: Kustomize base
mkdir -p /tmp/m3-kustomize/base
cat > /tmp/m3-kustomize/base/kustomization.yaml <<'EOF'
resources: [deployment.yaml]
EOF
cat > /tmp/m3-kustomize/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api}
spec:
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers: [{name: api, image: "nginx:1.27"}]
EOF

# Task 16: break the container runtime endpoint of the kubelet on cka-worker2
# (depending on the kubeadm version it is set in kubeadm-flags.env or in config.yaml – break both)
docker exec cka-worker2 sh -c "mkdir -p $BK && cp -n /var/lib/kubelet/kubeadm-flags.env /var/lib/kubelet/config.yaml $BK/ \
  && sed -i 's#containerd/containerd.sock#containerd/containerd.socket#' /var/lib/kubelet/kubeadm-flags.env /var/lib/kubelet/config.yaml \
  && systemctl restart kubelet"

# Task 15: break the API server (wrong TLS certificate path) – do this last!
docker exec $CP sh -c "mkdir -p $BK && cp -n /etc/kubernetes/manifests/kube-apiserver.yaml $BK/"
docker exec $CP sed -i 's#--tls-cert-file=/etc/kubernetes/pki/apiserver.crt#--tls-cert-file=/etc/kubernetes/pki/api-server.crt#' \
  /etc/kubernetes/manifests/kube-apiserver.yaml

echo "✅ Mock exam 3 ready. Start the timer: 120 minutes."
