# Domain 1 – Solutions

> Only look after your own attempt!

## 1.1 – Role & RoleBinding
```bash
kubectl create ns dev
kubectl -n dev create role pod-reader --verb=get,list,watch --resource=pods
kubectl -n dev edit role pod-reader      # add a second rule:
#  - apiGroups: [""]
#    resources: ["pods/log"]
#    verbs: ["get"]
kubectl -n dev create rolebinding jane-pod-reader --role=pod-reader --user=jane

kubectl auth can-i list pods -n dev --as=jane         # yes
kubectl auth can-i delete pods -n dev --as=jane       # no
kubectl auth can-i list pods -n default --as=jane     # no
```
Shortcut: `kubectl create role` accepts `--resource=pods,pods/log` but applies all verbs to all
resources – fine for reading, but not when the verbs should differ per resource.

## 1.2 – ServiceAccount with a ClusterRole
```bash
kubectl create ns ops
kubectl -n ops create sa node-viewer
kubectl create clusterrole node-reader --verb=get,list,watch --resource=nodes
kubectl create clusterrolebinding node-viewer --clusterrole=node-reader --serviceaccount=ops:node-viewer
kubectl auth can-i list nodes --as=system:serviceaccount:ops:node-viewer     # yes

TOKEN=$(kubectl -n ops create token node-viewer --duration=1h)
kubectl --token="$TOKEN" get nodes
# or raw:
APISERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
curl -sk -H "Authorization: Bearer $TOKEN" "$APISERVER/api/v1/nodes" | jq -r '.items[].metadata.name'
```
Nodes are cluster-scoped → only a ClusterRole + **ClusterRoleBinding** works. A RoleBinding to a
ClusterRole only grants rights inside one namespace.

## 1.3 – A new user with a client certificate
```bash
openssl genrsa -out /tmp/bob.key 2048
openssl req -new -key /tmp/bob.key -subj "/CN=bob/O=developers" -out /tmp/bob.csr

cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: bob
spec:
  request: $(base64 -w0 < /tmp/bob.csr)
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 86400
  usages: ["client auth"]
EOF
kubectl certificate approve bob
kubectl get csr bob -o jsonpath='{.status.certificate}' | base64 -d > /tmp/bob.crt

kubectl config set-credentials bob --client-key=/tmp/bob.key --client-certificate=/tmp/bob.crt --embed-certs=true
kubectl config set-context bob@kind-cka --cluster=kind-cka --user=bob
kubectl -n dev create rolebinding developers-view --clusterrole=view --group=developers
kubectl --context=bob@kind-cka -n dev get pods        # works (maybe "No resources found")
kubectl --context=bob@kind-cka get nodes              # Forbidden
```
`CN` = username, `O` = group(s). The CSR must contain `usages: ["client auth"]`.

## 1.4 – etcd backup
```bash
kubectl -n kube-system get pod etcd-cka-control-plane -o yaml | grep -E -- '--(cert|key|trusted-ca)-file|--listen-client-urls'
# or on the node: docker exec cka-control-plane cat /etc/kubernetes/manifests/etcd.yaml

kubectl -n kube-system exec etcd-cka-control-plane -- etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /var/lib/etcd/backup-1.4.db

kubectl -n kube-system exec etcd-cka-control-plane -- etcdutl snapshot status /var/lib/etcd/backup-1.4.db -w table
kubectl -n kube-system exec etcd-cka-control-plane -- etcdutl snapshot status /var/lib/etcd/backup-1.4.db -w json \
  | jq .totalKey > /tmp/etcd-keys.txt
docker exec cka-control-plane ls -l /var/lib/etcd/backup-1.4.db    # the file is on the node
```

**🖥 Restore (VM / exam style, on the control-plane node):**
```bash
etcdutl snapshot restore /opt/backup.db --data-dir /var/lib/etcd-restore
# point the hostPath of the etcd-data volume to the new directory:
vi /etc/kubernetes/manifests/etcd.yaml     # volumes: - hostPath: {path: /var/lib/etcd-restore}
# the kubelet restarts etcd automatically; wait until the API answers again
watch crictl ps
```
`etcdctl snapshot restore` still works but is deprecated in favor of `etcdutl`.

## 1.5 – Prepare a node for kubeadm (🖥 VM)
```bash
# swap
sudo swapoff -a && sudo sed -i '/ swap / s/^/#/' /etc/fstab
# kernel modules + sysctls
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay && sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system
# containerd
sudo apt-get update && sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd && containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd
# kubeadm, kubelet, kubectl (replace v1.37 with the target minor version)
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.37/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.37/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# control plane
sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p ~/.kube && sudo cp /etc/kubernetes/admin.conf ~/.kube/config && sudo chown $(id -u):$(id -g) ~/.kube/config
kubectl apply -f <CNI manifest, e.g. Flannel or Calico>
kubeadm token create --print-join-command      # run the output on the worker
```

## 1.6 – Cluster upgrade (🖥 VM)
Order: **control plane first, then workers – one node at a time.**
```bash
# control plane
sudo apt-mark unhold kubeadm && sudo apt-get install -y kubeadm='1.37.x-*' && sudo apt-mark hold kubeadm
sudo kubeadm upgrade plan
sudo kubeadm upgrade apply v1.37.x
kubectl drain cp1 --ignore-daemonsets
sudo apt-mark unhold kubelet kubectl && sudo apt-get install -y kubelet='1.37.x-*' kubectl='1.37.x-*' && sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon cp1

# each worker
sudo apt-get install -y kubeadm='1.37.x-*'     # (with unhold/hold)
sudo kubeadm upgrade node
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data     # from the control plane
sudo apt-get install -y kubelet='1.37.x-*' kubectl='1.37.x-*' && sudo systemctl daemon-reload && sudo systemctl restart kubelet
kubectl uncordon worker1
```
Before a minor upgrade, switch the apt repo URL to the new minor version (`/v1.37/` → `/v1.38/`).
Additional control-plane nodes use `kubeadm upgrade node` instead of `apply`.

## 1.7 – Helm
```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo && helm repo update
helm install web podinfo/podinfo -n helm-demo --create-namespace \
  --set replicaCount=2 --set ui.message="Hello CKA"
helm upgrade web podinfo/podinfo -n helm-demo --reuse-values --set replicaCount=3
helm history web -n helm-demo
helm rollback web 1 -n helm-demo
helm get values web -n helm-demo -o yaml > /tmp/web-values.yaml
```
Useful: `helm show values <chart>`, `helm template` (render only), `helm list -A`,
`helm uninstall`, `--dry-run`. Without `--reuse-values`, an upgrade resets values that are not passed again.

## 1.8 – CRDs & operators (cert-manager)
```bash
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace --set crds.enabled=true
kubectl get crd | grep cert-manager.io
kubectl explain certificate.spec
kubectl create ns certs
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: demo-cert
  namespace: certs
spec:
  secretName: demo-tls
  dnsNames: ["demo.example.com"]
  issuerRef:
    name: selfsigned
    kind: ClusterIssuer
EOF
kubectl -n certs get certificate demo-cert      # READY True
kubectl -n certs get secret demo-tls -o jsonpath='{.type}'    # kubernetes.io/tls
```
Operator = CRDs + controller. Troubleshooting: `kubectl describe certificate`, then the
`CertificateRequest`/`Order` objects it created, then the controller logs.

## 1.9 – Extension interfaces
```bash
kubectl get node cka-worker -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}'; echo   # containerd://...
docker exec cka-worker cat /var/lib/kubelet/kubeadm-flags.env                                 # --container-runtime-endpoint=...
kubectl get node cka-worker -o jsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/cri-socket}'; echo
kubectl -n kube-system get ds                       # kindnet = CNI (in kind)
docker exec cka-worker ls /etc/cni/net.d/           # CNI config on the node
kubectl get csidrivers                              # kind: none (local-path is not a CSI driver)
kubectl get node cka-worker -o jsonpath='{.spec.podCIDR}'; echo

cat > /tmp/interfaces.txt <<'EOF'
cri=containerd://2.x.x
cri_socket=unix:///run/containerd/containerd.sock
cni=kindnet
csi=none
pod_cidr=10.244.1.0/24
EOF
```
- **CRI** – kubelet ↔ container runtime (containerd, CRI-O), tool: `crictl`
- **CNI** – pod networking (Calico, Cilium, Flannel, kindnet); config in `/etc/cni/net.d`, binaries in `/opt/cni/bin`
- **CSI** – storage drivers (`CSIDriver`, `CSINode`, `StorageClass.provisioner`)

## 1.10 – Highly available control plane
```bash
cat > /tmp/kind-ha.yaml <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
  - role: control-plane
  - role: control-plane
  - role: worker
EOF
kind create cluster --name cka-ha --config /tmp/kind-ha.yaml
kubectl --context kind-cka-ha -n kube-system exec etcd-cka-ha-control-plane -- etcdctl \
  --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key \
  member list -w table
docker ps --filter name=cka-ha       # cka-ha-external-load-balancer = HAProxy in front of the API servers
docker stop cka-ha-control-plane2
kubectl --context kind-cka-ha get nodes   # still works (2/3 etcd members = quorum)
kind delete cluster --name cka-ha
```
Quorum = ⌊n/2⌋+1 → with 3 members, **1** may fail; with 5 members, 2.

**🖥 kubeadm:**
```bash
sudo kubeadm init --control-plane-endpoint "lb.example.com:6443" --upload-certs --pod-network-cidr=10.244.0.0/16
# the output contains a join command with --control-plane --certificate-key <key> for more control planes
sudo kubeadm join lb.example.com:6443 --token ... --discovery-token-ca-cert-hash sha256:... \
  --control-plane --certificate-key <key>
```
Stacked etcd (etcd on the control-plane nodes) vs. external etcd (separate cluster).

## 1.11 – Kustomize
```
/tmp/kustomize/
├── base/{kustomization.yaml, deployment.yaml, service.yaml}
└── overlays/prod/kustomization.yaml
```
```bash
mkdir -p /tmp/kustomize/base /tmp/kustomize/overlays/prod && cd /tmp/kustomize
kubectl create deploy api --image=nginx:1.27 --dry-run=client -o yaml > base/deployment.yaml
kubectl create svc clusterip api --tcp=80:80 --dry-run=client -o yaml > base/service.yaml
cat > base/kustomization.yaml <<'EOF'
resources: [deployment.yaml, service.yaml]
EOF
cat > overlays/prod/kustomization.yaml <<'EOF'
resources: [../../base]
namespace: prod
namePrefix: prod-
replicas:
  - name: api
    count: 3
images:
  - name: nginx
    newTag: 1.27-alpine
configMapGenerator:
  - name: api-config
    literals: [LOG_LEVEL=warn]
patches:
  - target: {kind: Deployment, name: api}
    patch: |
      - op: add
        path: /spec/template/spec/containers/0/envFrom
        value: [{configMapRef: {name: api-config}}]
EOF
kubectl create ns prod
kubectl kustomize overlays/prod        # preview
kubectl apply -k overlays/prod
```
The generated ConfigMap gets a hash suffix (`api-config-abc123`) and Kustomize rewrites the
reference in the Deployment. Changing `LOG_LEVEL` creates a new ConfigMap name → the pod template
changes → **rolling update**. Without the hash, pods would keep the old env values.
