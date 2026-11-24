#!/usr/bin/env bash
source "$(dirname "$0")/../setup/lib.sh"
k() { kubectl "$@"; }
NS=storage

section "4.1 Dynamic provisioning"
eq "PVC data Bound" "Bound" k -n $NS get pvc data -o jsonpath='{.status.phase}'
check "hello.txt written" bash -c "kubectl -n $NS exec writer -- cat /data/hello.txt | grep -q hello"

section "4.2 StorageClass"
eq "retain-local Retain" "Retain" k get sc retain-local -o jsonpath='{.reclaimPolicy}'
eq "standard is default again" "true" k get sc standard -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}'

section "4.3 / 4.4 Static PV"
eq "pv-manual Retain" "Retain" k get pv pv-manual -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'
eq "pv-manual pinned to cka-worker" "cka-worker" k get pv pv-manual -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}'
eq "pv-manual Available again" "Available" k get pv pv-manual -o jsonpath='{.status.phase}'

section "4.5 Volume types"
eq "emptyDir medium Memory" "Memory" k -n $NS get pod volumes -o jsonpath='{.spec.volumes[?(@.name=="cache")].emptyDir.medium}'
check "Projected volume has 3 files" bash -c "[[ \$(kubectl -n $NS exec volumes -- ls /etc/info | wc -l) -ge 3 ]]"
eq "hostPath mounted read-only" "true" k -n $NS get pod volumes -o jsonpath='{.spec.containers[0].volumeMounts[?(@.name=="host-logs")].readOnly}'

section "4.6 StatefulSet"
check "PVCs data-db-0 and data-db-1" bash -c "kubectl -n $NS get pvc data-db-0 data-db-1"

section "4.7 Ephemeral volume"
check "Pod scratch has an ephemeral volume" bash -c "kubectl -n $NS get pod scratch -o jsonpath='{.spec.volumes[0].ephemeral}' | grep -q volumeClaimTemplate"
eq "PVC scratch-scratch Bound" "Bound" k -n $NS get pvc scratch-scratch -o jsonpath='{.status.phase}'

summary
