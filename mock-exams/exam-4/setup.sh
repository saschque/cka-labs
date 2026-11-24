#!/usr/bin/env bash
# Prepares CKA mock exam 4. Run before starting the timer.
set -euo pipefail
CP=cka-control-plane
BK=/root/cka-backup

for ns in m4-app m4-ops m4-helm m4-shop m4-load; do
  kubectl create ns "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
helm repo add podinfo https://stefanprodan.github.io/podinfo >/dev/null 2>&1 || true
helm repo update podinfo >/dev/null

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata: {name: config-updater, namespace: m4-app}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: app-config, namespace: m4-app}
data: {mode: blue}
---
apiVersion: v1
kind: ConfigMap
metadata: {name: other-config, namespace: m4-app}
data: {mode: red}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: m4-app}
spec:
  replicas: 2
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers: [{name: web, image: "nginx:1.27"}]
---
apiVersion: v1
kind: Service
metadata: {name: web, namespace: m4-app}
spec: {selector: {app: web}, ports: [{port: 80}]}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: multi, namespace: m4-app}
spec:
  selector: {matchLabels: {app: multi}}
  template:
    metadata: {labels: {app: multi}}
    spec:
      containers:
        - name: app
          image: registry.k8s.io/e2e-test-images/agnhost:2.53
          args: ["netexec", "--http-port=8080"]
          ports: [{name: http, containerPort: 8080}, {name: metrics, containerPort: 9090}]
---
apiVersion: v1
kind: Pod
metadata: {name: batch-runner, namespace: m4-app, labels: {app: batch}}
spec:
  containers: [{name: c, image: "busybox:1.36", command: ["sleep", "infinity"]}]
---
# Task 17: pods with the wrong label + not ready
apiVersion: apps/v1
kind: Deployment
metadata: {name: frontend, namespace: m4-shop}
spec:
  replicas: 2
  selector: {matchLabels: {app: front-end}}
  template:
    metadata: {labels: {app: front-end}}
    spec:
      containers:
        - name: web
          image: nginx:1.27
          readinessProbe:
            httpGet: {path: /ready, port: 80}
            periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata: {name: frontend, namespace: m4-shop}
spec: {selector: {app: frontend}, ports: [{port: 80}]}
---
# Task 18
apiVersion: v1
kind: Pod
metadata: {name: mixed, namespace: m4-load}
spec:
  containers:
    - {name: idle, image: "registry.k8s.io/pause:3.10"}
    - {name: spinner, image: "busybox:1.36", command: ["sh", "-c", "while true; do :; done"], resources: {limits: {cpu: 300m}}}
---
apiVersion: v1
kind: Pod
metadata: {name: light, namespace: m4-load}
spec:
  containers:
    - {name: worker, image: "busybox:1.36", command: ["sh", "-c", "while true; do sleep 0.5; done"]}
---
apiVersion: v1
kind: Pod
metadata: {name: badimage, namespace: m4-load}
spec:
  containers: [{name: c, image: "busybox:9.9.9-nope"}]
EOF

# Task 15: YAML error in the scheduler manifest (bad indentation)
docker exec $CP sh -c "mkdir -p $BK && cp -n /etc/kubernetes/manifests/kube-scheduler.yaml $BK/"
docker exec $CP sed -i 's/^  containers:/   containers:/' /etc/kubernetes/manifests/kube-scheduler.yaml

# Task 16: containerd stopped and disabled on cka-worker
docker exec cka-worker sh -c 'systemctl stop containerd && systemctl disable containerd'

echo "✅ Mock exam 4 ready. Start the timer: 120 minutes."
