# Domain 4 – Storage (10 %)

Competencies from the curriculum:
- Implement storage classes and dynamic volume provisioning
- Configure volume types, access modes and reclaim policies
- Manage persistent volumes and persistent volume claims

kind ships the `local-path` provisioner (StorageClass `standard`). All tasks run in namespace
`storage`: `kubectl create ns storage`

---

## Task 4.1 – Dynamic provisioning ⏱ 5 min

1. Find the default StorageClass, its provisioner, reclaim policy and volume binding mode.
2. Create a PVC `data` (500Mi, `ReadWriteOnce`) **without** a `storageClassName`. Why is it `Pending`?
3. Create a pod `writer` (busybox) that mounts the PVC at `/data` and writes `hello` to
   `/data/hello.txt`. Which PV was created and on which node does the data live?

---

## Task 4.2 – Your own StorageClass & default class ⏱ 5 min

1. Create a StorageClass `retain-local` (provisioner `rancher.io/local-path`, `reclaimPolicy: Retain`,
   `volumeBindingMode: WaitForFirstConsumer`).
2. Make `retain-local` the **default** StorageClass and remove the default flag from `standard`.
3. Switch the default back to `standard` afterwards.

---

## Task 4.3 – Static PV & binding ⏱ 6 min

1. Create a PV `pv-manual` (1Gi, `ReadWriteOnce`, `hostPath` `/mnt/manual` on `cka-worker`,
   `storageClassName: manual`, `persistentVolumeReclaimPolicy: Retain`, label `tier=gold`).
   Pin it to `cka-worker` with `nodeAffinity`.
2. Create a PVC `claim-manual` (500Mi, class `manual`) that selects PVs with `tier=gold`.
3. Check the binding. Why does a 500Mi claim bind to a 1Gi PV?

---

## Task 4.4 – Reclaim policies in practice ⏱ 5 min

1. Delete the PVC `claim-manual`. What status does `pv-manual` have now, and why can't a new
   PVC bind to it?
2. Make `pv-manual` available again without deleting it.
3. What would have happened with `Delete` as the reclaim policy?

---

## Task 4.5 – Volume types ⏱ 6 min

Create a pod `volumes` (busybox, `sleep 3600`) with:
- `cache`: `emptyDir` with `medium: Memory` and `sizeLimit: 64Mi` at `/cache`,
- `info`: a **projected** volume at `/etc/info` that combines the pod's labels (downward API),
  the ConfigMap `app-settings` (create it: `color=blue`) and a ServiceAccount token with
  audience `vault` and 10 min expiry,
- `host-logs`: `hostPath` `/var/log` (type `Directory`), mounted **read-only** at `/host/logs`.

---

## Task 4.6 – StatefulSet storage ⏱ 5 min

Create a headless service `db` and a StatefulSet `db` (2 replicas, `busybox`, writes its hostname
to `/data/id.txt` and sleeps) with `volumeClaimTemplates` (100Mi, class `standard`).
Delete pod `db-0` – does it get its old data back? Scale to 0 and back to 2 – what about the PVCs?

---

## Task 4.7 – Access modes & generic ephemeral volumes ⏱ 4 min

1. Explain `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany` and `ReadWriteOncePod`. Which ones does
   `local-path` support?
2. Create a pod `scratch` with a **generic ephemeral volume** (200Mi, class `standard`) at `/scratch`.
   What happens to the PVC when the pod is deleted?

---

✅ Check: `./04-storage/verify.sh`
📖 Solutions: [`SOLUTIONS.md`](SOLUTIONS.md)
