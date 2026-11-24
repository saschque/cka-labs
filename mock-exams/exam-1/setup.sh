#!/usr/bin/env bash
# Prepares CKA mock exam 1. Run before starting the timer.
set -euo pipefail
CP=cka-control-plane
BK=/root/cka-backup

for ns in m1-app m1-db m1-helm m1-staging m1-incident m1-load; do
  kubectl create ns "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: api, namespace: m1-app}
spec:
  replicas: 3
  selector: {matchLabels: {app: api}}
  template:
    metadata: {labels: {app: api}}
    spec:
      containers: [{name: nginx, image: "nginx:1.26"}]
---
apiVersion: v1
kind: Service
metadata: {name: api, namespace: m1-app}
spec:
  selector: {app: api}
  ports: [{port: 80}]
---
apiVersion: v1
kind: Secret
metadata: {name: m1-secrets, namespace: m1-app}
stringData: {api-key: "k3y-12345", other: "x"}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: m1-settings, namespace: m1-app}
data: {theme: dark, timeout: "30"}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: postgres, namespace: m1-db}
spec:
  selector: {matchLabels: {app: postgres}}
  template:
    metadata: {labels: {app: postgres}}
    spec:
      containers: [{name: pg, image: "registry.k8s.io/pause:3.10", ports: [{containerPort: 5432}]}]
---
# Task 17: two problems
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: m1-incident}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web, version: v2}}
    spec:
      containers: [{name: web, image: "nginx:1.27-alpinee", ports: [{containerPort: 80}]}]
---
apiVersion: v1
kind: Service
metadata: {name: web, namespace: m1-incident}
spec:
  selector: {app: web, version: v1}
  ports: [{port: 80, targetPort: 80}]
---
# Task 18
apiVersion: apps/v1
kind: Deployment
metadata: {name: burner, namespace: m1-load}
spec:
  selector: {matchLabels: {app: burner}}
  template:
    metadata: {labels: {app: burner}}
    spec:
      containers:
        - {name: c, image: "busybox:1.36", command: ["sh", "-c", "while true; do :; done"], resources: {limits: {cpu: 250m}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: keeper, namespace: m1-load}
spec:
  selector: {matchLabels: {app: keeper}}
  template:
    metadata: {labels: {app: keeper}}
    spec:
      containers:
        - {name: c, image: polinux/stress, command: ["stress", "--vm", "1", "--vm-bytes", "150M", "--vm-hang", "0"], resources: {limits: {memory: 256Mi}}}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: sleeper, namespace: m1-load}
spec:
  replicas: 2
  selector: {matchLabels: {app: sleeper}}
  template:
    metadata: {labels: {app: sleeper}}
    spec:
      containers: [{name: c, image: "registry.k8s.io/pause:3.10"}]
EOF

# Task 5: Kustomize base
mkdir -p /tmp/m1-kustomize/base
cat > /tmp/m1-kustomize/base/kustomization.yaml <<'EOF'
resources: [deployment.yaml, service.yaml]
EOF
cat > /tmp/m1-kustomize/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop}
spec:
  replicas: 1
  selector: {matchLabels: {app: shop}}
  template:
    metadata: {labels: {app: shop}}
    spec:
      containers: [{name: shop, image: "nginx:1.27"}]
EOF
cat > /tmp/m1-kustomize/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: shop}
spec:
  selector: {app: shop}
  ports: [{port: 80}]
EOF

# Task 8: GPU node
kubectl label node cka-worker2 accelerator=gpu --overwrite
kubectl taint node cka-worker2 gpu=true:NoSchedule --overwrite

# Task 15: break the scheduler (wrong kubeconfig)
docker exec $CP sh -c "mkdir -p $BK && cp -n /etc/kubernetes/manifests/kube-scheduler.yaml $BK/"
docker exec $CP sed -i 's#--kubeconfig=/etc/kubernetes/scheduler.conf#--kubeconfig=/etc/kubernetes/scheduler.config#' \
  /etc/kubernetes/manifests/kube-scheduler.yaml

# Task 16: stop the kubelet on cka-worker
docker exec cka-worker sh -c 'systemctl stop kubelet && systemctl disable kubelet'

echo "✅ Mock exam 1 ready. Start the timer: 120 minutes."
echo "   Clean up afterwards: kubectl taint node cka-worker2 gpu- ; kubectl label node cka-worker2 accelerator-"
