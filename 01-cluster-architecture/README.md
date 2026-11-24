# Domain 1 – Cluster Architecture, Installation & Configuration (25 %)

Competencies from the curriculum:
- Manage role based access control (RBAC)
- Prepare underlying infrastructure for installing a Kubernetes cluster
- Create and manage Kubernetes clusters using kubeadm
- Manage the lifecycle of Kubernetes clusters
- Implement and configure a highly-available control plane
- Use Helm and Kustomize to install cluster components
- Understand extension interfaces (CNI, CSI, CRI, etc.)
- Understand CRDs, install and configure operators

Add-ons needed: `./setup/install.sh cert-manager` (only for 1.8)

> **kind vs. real VMs:** kubeadm installation, upgrades and HA joins need real machines. Tasks
> marked **🖥 VM lab** are best done on 2–3 VMs (e.g. Multipass, Vagrant, cloud VMs). Their
> solutions contain the full command sequence; `verify.sh` skips them.

---

## Task 1.1 – Role & RoleBinding ⏱ 4 min

1. Create the namespace `dev`.
2. Create a Role `pod-reader` in `dev` that allows `get`, `list`, `watch` on pods and `get` on
   `pods/log`.
3. Bind it to the user `jane` (RoleBinding `jane-pod-reader`).
4. Check: `jane` can list pods in `dev`, but not delete them and not list pods in `default`.

---

## Task 1.2 – ServiceAccount with a ClusterRole ⏱ 4 min

1. Create the ServiceAccount `node-viewer` in namespace `ops`.
2. Create a ClusterRole `node-reader` (`get`, `list`, `watch` on `nodes`) and bind it cluster-wide
   to the ServiceAccount.
3. Check with `kubectl auth can-i list nodes --as=system:serviceaccount:ops:node-viewer`.
4. Create a token for the ServiceAccount (valid for 1 hour) and use it with `curl` or
   `kubectl --token` to list the nodes.

---

## Task 1.3 – A new user with a client certificate ⏱ 8 min

1. Create a private key and a CSR for the user `bob` (group `developers`) with `openssl`.
2. Create a Kubernetes `CertificateSigningRequest` `bob` (signer `kubernetes.io/kube-apiserver-client`,
   expiry 1 day), approve it and extract the certificate to `/tmp/bob.crt`.
3. Add `bob` as a user and a context `bob@kind-cka` to your kubeconfig.
4. Give the group `developers` the ClusterRole `view` in namespace `dev` and verify with the new
   context that `bob` can list pods there.

---

## Task 1.4 – etcd backup ⏱ 6 min

1. Find out from the etcd static pod manifest where the certificates are and which endpoint etcd
   listens on.
2. Create a snapshot at `/var/lib/etcd/backup-1.4.db` **on the control-plane node**
   (tip: in kind, run `etcdctl` inside the etcd pod – its `/var/lib/etcd` is a hostPath).
3. Check the snapshot status (`etcdutl snapshot status` or `etcdctl snapshot status`) and write the
   number of keys to `/tmp/etcd-keys.txt`.
4. 🖥 VM lab: restore the snapshot into a new data directory and point the etcd manifest to it.

---

## Task 1.5 – Prepare a node for kubeadm 🖥 VM lab ⏱ 10 min

On a fresh Ubuntu VM, prepare everything that `kubeadm init` needs:
- swap off (permanently), kernel modules `overlay` and `br_netfilter`,
- sysctls `net.bridge.bridge-nf-call-iptables`, `net.ipv4.ip_forward`,
- containerd with `SystemdCgroup = true`,
- `kubeadm`, `kubelet`, `kubectl` in the target version, held at that version.

Then initialize a control plane with pod CIDR `10.244.0.0/16`, install a CNI and join a worker.

---

## Task 1.6 – Cluster upgrade 🖥 VM lab ⏱ 12 min

Upgrade the control plane and one worker of your kubeadm cluster by one minor version:
`kubeadm upgrade plan/apply`, drain/uncordon, upgrade kubelet and kubectl. Write down the exact
order of the steps.

---

## Task 1.7 – Helm ⏱ 6 min

1. Add the Helm repo `podinfo` (`https://stefanprodan.github.io/podinfo`).
2. Install the chart `podinfo/podinfo` as release `web` in namespace `helm-demo` with
   `replicaCount=2` and `ui.message="Hello CKA"`.
3. Upgrade the release to `replicaCount=3`, then roll back to revision 1.
4. Write all values that differ from the defaults (`helm get values`) to `/tmp/web-values.yaml`.

---

## Task 1.8 – CRDs & operators (cert-manager) ⏱ 8 min

1. Install cert-manager with Helm including its CRDs (`./setup/install.sh cert-manager` or by hand).
2. List all CRDs that belong to cert-manager and use `kubectl explain` to find the fields of
   `Certificate.spec`.
3. Create a self-signed `ClusterIssuer` `selfsigned` and a `Certificate` `demo-cert` in namespace
   `certs` for `demo.example.com` that stores its key pair in the secret `demo-tls`.
4. Check that the secret `demo-tls` of type `kubernetes.io/tls` was created by the operator.

---

## Task 1.9 – Extension interfaces ⏱ 5 min

Answer with commands and write the answers to `/tmp/interfaces.txt` (one per line, `key=value`):
- `cri=` the container runtime and version of node `cka-worker`
- `cri_socket=` the CRI socket the kubelet uses
- `cni=` the CNI plugin running in the cluster
- `csi=` the names of all installed CSI drivers (or `none`)
- `pod_cidr=` the pod CIDR of node `cka-worker`

---

## Task 1.10 – Highly available control plane ⏱ 8 min

1. Create a **second** kind cluster `cka-ha` with 3 control-plane nodes and 1 worker.
2. List the etcd members and find out how kind load-balances the API server.
3. Stop one control-plane container (`docker stop cka-ha-control-plane2`). Does the API still work?
   How many control-plane nodes may fail with 3 etcd members?
4. 🖥 VM lab: describe how you would build the same with kubeadm
   (`--control-plane-endpoint`, `--upload-certs`, `join --control-plane`).
5. Delete the cluster afterwards: `kind delete cluster --name cka-ha`.

---

## Task 1.11 – Kustomize ⏱ 6 min

Create under `/tmp/kustomize/` a base (Deployment `api`, image `nginx:1.27`, Service `api`) and an
overlay `prod` that
- sets the namespace `prod` and the name prefix `prod-`,
- sets 3 replicas and the image tag `1.27-alpine`,
- generates a ConfigMap `api-config` with `LOG_LEVEL=warn` (with a hash suffix) and mounts it as env.

Apply it with `kubectl apply -k` and explain what happens to the pods when you change `LOG_LEVEL`.

---

✅ Check: `./01-cluster-architecture/verify.sh`
📖 Solutions: [`SOLUTIONS.md`](SOLUTIONS.md)
