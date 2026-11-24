# Domain 2 – Solutions

> Only look after your own attempt!

## 2.1 – Rolling update & rollback
```bash
kubectl -n apps create deploy web --image=nginx:1.26 --replicas=4
kubectl -n apps patch deploy web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
kubectl -n apps set image deploy/web nginx=nginx:1.27
kubectl -n apps annotate deploy web kubernetes.io/change-cause="upgrade to 1.27"
kubectl -n apps set image deploy/web nginx=nginx:1.27-doesnotexist
kubectl -n apps rollout status deploy/web --timeout=30s     # hangs
kubectl -n apps get rs,pods                                 # 4 old pods + 1 new pod in ImagePullBackOff
kubectl -n apps rollout history deploy/web
kubectl -n apps rollout undo deploy/web --to-revision=2
```
With `maxUnavailable: 0`, Kubernetes never removes an old pod before a new one is Ready → all
4 old pods keep serving traffic. `maxSurge: 1` allows exactly one extra (broken) pod.

## 2.2 – ConfigMaps
```bash
echo "worker_processes 1;" > /tmp/nginx.conf
kubectl -n apps create cm app-config --from-literal=APP_MODE=production --from-literal=APP_PORT=8080 \
  --from-file=nginx.conf=/tmp/nginx.conf
```
```yaml
apiVersion: v1
kind: Pod
metadata: {name: config-demo, namespace: apps}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      envFrom:
        - configMapRef: {name: app-config}      # also imports nginx.conf as an env var (harmless)
      volumeMounts:
        - name: cfg
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf
  volumes:
    - name: cfg
      configMap: {name: app-config}
```
Neither sees changes without a restart: **env vars** are set at container start, and a
**`subPath` mount** is never updated. Only a regular configMap volume mount (without `subPath`)
is updated automatically (after up to ~1 min).

## 2.3 – Secrets
```bash
kubectl -n apps create secret generic db-credentials --from-literal=username=admin --from-literal='password=S3cr3t!'
kubectl -n apps get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
kubectl -n apps patch secret db-credentials -p '{"immutable":true}'
```
```yaml
apiVersion: v1
kind: Pod
metadata: {name: secret-demo, namespace: apps}
spec:
  containers:
    - name: c
      image: busybox:1.36
      command: ["sleep", "3600"]
      env:
        - name: DB_PASSWORD
          valueFrom: {secretKeyRef: {name: db-credentials, key: password}}
      volumeMounts:
        - {name: db, mountPath: /etc/db, readOnly: true}
  volumes:
    - name: db
      secret:
        secretName: db-credentials
        defaultMode: 0400
```
`immutable: true` cannot be undone – to change the data, delete and recreate the Secret.

## 2.4 – Horizontal Pod Autoscaler
```bash
kubectl -n apps create deploy php --image=registry.k8s.io/hpa-example
kubectl -n apps set resources deploy php --requests=cpu=100m
kubectl -n apps expose deploy php --port=80
kubectl -n apps autoscale deploy php --min=1 --max=5 --cpu-percent=50
kubectl -n apps run load --rm -it --image=busybox:1.36 -- sh -c 'while true; do wget -q -O- http://php; done'
kubectl -n apps get hpa php -w
kubectl -n apps patch hpa php --type=merge -p '{"spec":{"behavior":{"scaleDown":{"stabilizationWindowSeconds":60}}}}'
```
No requests → no utilization percentage → the HPA shows `<unknown>`. The metrics-server must be running.

## 2.5 – Self-healing: probes
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: healthy, namespace: apps}
spec:
  replicas: 2
  selector: {matchLabels: {app: healthy}}
  template:
    metadata: {labels: {app: healthy}}
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          startupProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 3
            failureThreshold: 10        # 30 s
          readinessProbe:
            httpGet: {path: /, port: 80}
            periodSeconds: 5
          livenessProbe:
            tcpSocket: {port: 80}
            periodSeconds: 10
            failureThreshold: 3
```
- **Pod deleted** → the ReplicaSet controller notices `2 desired / 1 current` and creates a new pod.
- **Process killed** → the container exits; the **kubelet** restarts it in the same pod
  (`restartPolicy: Always`, RESTARTS +1). A liveness failure has the same effect.
- Readiness failure → no restart, the pod is just removed from the service endpoints.

## 2.6 – DaemonSet on every node
```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata: {name: node-agent, namespace: kube-system}
spec:
  selector: {matchLabels: {app: node-agent}}
  template:
    metadata: {labels: {app: node-agent}}
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: registry.k8s.io/pause:3.10
          resources: {requests: {cpu: 10m, memory: 16Mi}}
```
Tip: `kubectl create deploy ... --dry-run=client -o yaml`, change `kind` to `DaemonSet` and remove
`replicas` and `strategy`.

## 2.7 – Node affinity, taints and tolerations
```bash
kubectl label node cka-worker disk=ssd
kubectl label node cka-worker2 disk=hdd
```
```yaml
# fast: required
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions: [{key: disk, operator: In, values: [ssd]}]
---
# flexible: preferred + toleration
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 80
              preference:
                matchExpressions: [{key: disk, operator: In, values: [hdd]}]
      tolerations:
        - key: maintenance
          operator: Equal
          value: "true"
          effect: NoExecute
          tolerationSeconds: 60
```
```bash
kubectl taint node cka-worker2 maintenance=true:NoExecute
kubectl taint node cka-worker2 maintenance-
```
`NoExecute` evicts running pods **without** a matching toleration immediately; with
`tolerationSeconds: 60` they stay for 60 s and are then evicted. `NoSchedule` only affects new pods.

## 2.8 – LimitRange & ResourceQuota
```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: limited}
spec:
  limits:
    - type: Container
      defaultRequest: {cpu: 100m, memory: 64Mi}
      default: {cpu: 200m, memory: 128Mi}
      max: {cpu: 500m, memory: 256Mi}
---
apiVersion: v1
kind: ResourceQuota
metadata: {name: quota, namespace: limited}
spec:
  hard: {pods: "4", requests.cpu: "1", limits.memory: 1Gi}
```
```bash
kubectl -n limited run big --image=nginx:1.27 --overrides='{"spec":{"containers":[{"name":"big","image":"nginx:1.27","resources":{"limits":{"memory":"1Gi"}}}]}}'
# Error: maximum memory usage per Container is 256Mi, but limit is 1Gi  (LimitRanger admission plugin)
kubectl -n limited create deploy many --image=nginx:1.27 --replicas=6
kubectl -n limited get pods            # only 4
kubectl -n limited describe rs         # events: "exceeded quota: quota, requested: pods=1, used: pods=4, limited: pods=4"
```
Quota errors appear on the **ReplicaSet**, not on the Deployment – a classic exam trap.

## 2.9 – Static pod
```bash
docker exec cka-worker grep staticPodPath /var/lib/kubelet/config.yaml    # /etc/kubernetes/manifests
kubectl run static-web --image=nginx:1.27 --dry-run=client -o yaml > /tmp/static-web.yaml
docker cp /tmp/static-web.yaml cka-worker:/etc/kubernetes/manifests/static-web.yaml
kubectl get pods -A | grep static-web-cka-worker
```
`kubectl delete pod static-web-cka-worker` only deletes the mirror pod – the kubelet recreates it
immediately. To remove a static pod, delete the manifest file on the node.

## 2.10 – Jobs & CronJobs
```yaml
apiVersion: batch/v1
kind: Job
metadata: {name: pi, namespace: apps}
spec:
  completions: 5
  parallelism: 2
  backoffLimit: 2
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: pi
          image: perl:5.40
          command: ["perl", "-Mbignum=bpi", "-wle", "print bpi(500)"]
---
apiVersion: batch/v1
kind: CronJob
metadata: {name: cleanup, namespace: apps}
spec:
  schedule: "*/15 * * * *"
  concurrencyPolicy: Forbid
  startingDeadlineSeconds: 60
  successfulJobsHistoryLimit: 2
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - {name: cleanup, image: busybox:1.36, command: ["date"]}
```
```bash
kubectl -n apps create job cleanup-manual --from=cronjob/cleanup
```
Imperative start: `kubectl create cronjob cleanup --image=busybox:1.36 --schedule="*/15 * * * *" -- date`.

## 2.11 – Init containers & native sidecars
```yaml
apiVersion: v1
kind: Pod
metadata: {name: sidecar-demo, namespace: apps}
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo '<h1>ready</h1>' > /work/index.html"]
      volumeMounts: [{name: html, mountPath: /work}]
    - name: log-shipper
      image: busybox:1.36
      restartPolicy: Always                 # = native sidecar
      command: ["sh", "-c", "touch /logs/access.log; tail -F /logs/access.log"]
      volumeMounts: [{name: logs, mountPath: /logs}]
  containers:
    - name: web
      image: nginx:1.27
      volumeMounts:
        - {name: html, mountPath: /usr/share/nginx/html}
        - {name: logs, mountPath: /var/log/nginx}
  volumes:
    - {name: html, emptyDir: {}}
    - {name: logs, emptyDir: {}}
```
Native sidecars start before the main containers, are stopped **after** them and don't keep a
Job pod running forever – a regular sidecar container would prevent the Job from completing.
Note: the official nginx image symlinks `access.log` to stdout; with an emptyDir mounted at
`/var/log/nginx`, nginx writes a real file instead.

## 2.12 – PriorityClass & preemption
```bash
kubectl create priorityclass low --value=100
kubectl create priorityclass high --value=10000 --preemption-policy=PreemptLowerPriority
kubectl get node cka-worker -o jsonpath='{.status.allocatable.cpu}'; echo
```
```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: filler, namespace: apps}
spec:
  replicas: 3
  selector: {matchLabels: {app: filler}}
  template:
    metadata: {labels: {app: filler}}
    spec:
      priorityClassName: low
      nodeSelector: {kubernetes.io/hostname: cka-worker}
      containers:
        - name: c
          image: registry.k8s.io/pause:3.10
          resources: {requests: {cpu: "1"}}     # adjust so that the node is almost full
---
apiVersion: v1
kind: Pod
metadata: {name: important, namespace: apps}
spec:
  priorityClassName: high
  nodeSelector: {kubernetes.io/hostname: cka-worker}
  containers:
    - name: c
      image: registry.k8s.io/pause:3.10
      resources: {requests: {cpu: "1"}}
```
```bash
kubectl -n apps get events --sort-by=.lastTimestamp | grep -i preempt
```
The scheduler evicts one `low` pod so that `important` fits; the evicted pod stays `Pending`.
