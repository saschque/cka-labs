#!/usr/bin/env bash
source "$(dirname "$0")/../setup/lib.sh"
k() { kubectl "$@"; }
NS=apps

section "2.1 Rolling update & rollback"
eq "web runs nginx:1.27" "nginx:1.27" k -n $NS get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'
eq "maxUnavailable=0" "0" k -n $NS get deploy web -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}'
eq "4 replicas ready" "4" k -n $NS get deploy web -o jsonpath='{.status.readyReplicas}'

section "2.2 ConfigMaps"
eq "APP_PORT in ConfigMap" "8080" k -n $NS get cm app-config -o jsonpath='{.data.APP_PORT}'
eq "config-demo uses subPath" "nginx.conf" k -n $NS get pod config-demo -o jsonpath='{.spec.containers[0].volumeMounts[0].subPath}'

section "2.3 Secrets"
eq "Secret immutable" "true" k -n $NS get secret db-credentials -o jsonpath='{.immutable}'
eq "Secret mounted with mode 0400 (256)" "256" k -n $NS get pod secret-demo -o jsonpath='{.spec.volumes[?(@.name=="db")].secret.defaultMode}'

section "2.4 HPA"
eq "HPA max 5" "5" k -n $NS get hpa php -o jsonpath='{.spec.maxReplicas}'
eq "Scale-down window 60s" "60" k -n $NS get hpa php -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}'

section "2.5 Probes"
check "startup, readiness and liveness probes set" bash -c \
  "kubectl -n $NS get deploy healthy -o json | jq -e '.spec.template.spec.containers[0] | .startupProbe and .readinessProbe and .livenessProbe'"

section "2.6 DaemonSet"
check "node-agent runs on all nodes" bash -c \
  "[[ \$(kubectl -n kube-system get ds node-agent -o jsonpath='{.status.numberReady}') -eq \$(kubectl get nodes --no-headers | wc -l) ]]"

section "2.7 Affinity"
check "All fast pods on cka-worker" bash -c \
  "[[ \$(kubectl -n $NS get pods -l app=fast -o jsonpath='{.items[*].spec.nodeName}' | tr ' ' '\n' | sort -u) == cka-worker ]]"
eq "flexible prefers hdd with weight 80" "80" k -n $NS get deploy flexible -o jsonpath='{.spec.template.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight}'
check "Taint removed from cka-worker2" bash -c "! kubectl get node cka-worker2 -o jsonpath='{.spec.taints[*].key}' | grep -q maintenance"

section "2.8 LimitRange & ResourceQuota"
eq "LimitRange max memory 256Mi" "256Mi" k -n limited get limitrange defaults -o jsonpath='{.spec.limits[0].max.memory}'
eq "Quota pods=4" "4" k -n limited get quota quota -o jsonpath='{.spec.hard.pods}'

section "2.9 Static pod"
check "Manifest on cka-worker" docker exec cka-worker test -f /etc/kubernetes/manifests/static-web.yaml
check "Mirror pod static-web-cka-worker" bash -c "kubectl get pods -A --no-headers | grep -q static-web-cka-worker"

section "2.10 Jobs & CronJobs"
eq "Job pi: completions=5" "5" k -n $NS get job pi -o jsonpath='{.spec.completions}'
eq "CronJob cleanup: Forbid" "Forbid" k -n $NS get cronjob cleanup -o jsonpath='{.spec.concurrencyPolicy}'
check "Manual job from the CronJob" bash -c "kubectl -n $NS get jobs -o json | jq -e '[.items[] | select(.metadata.annotations[\"cronjob.kubernetes.io/instantiate\"]==\"manual\")] | length > 0'"

section "2.11 Sidecars"
eq "log-shipper is a native sidecar" "Always" k -n $NS get pod sidecar-demo -o jsonpath='{.spec.initContainers[?(@.name=="log-shipper")].restartPolicy}'
eq "sidecar-demo running" "Running" k -n $NS get pod sidecar-demo -o jsonpath='{.status.phase}'

section "2.12 PriorityClass"
eq "PriorityClass high = 10000" "10000" k get priorityclass high -o jsonpath='{.value}'
eq "Pod important running" "Running" k -n $NS get pod important -o jsonpath='{.status.phase}'

summary
