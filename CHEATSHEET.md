# CKA Cheatsheet

## Setup in the exam terminal
```bash
alias k=kubectl
export do="--dry-run=client -o yaml"      # k create deploy x --image=nginx $do > x.yaml
export now="--force --grace-period=0"     # k delete pod x $now
source <(kubectl completion bash); complete -o default -F __start_kubectl k
k config use-context <ctx>                # ALWAYS first!
```

## Imperative commands
```bash
k run pod1 --image=nginx:1.27 --labels=app=web --port=80 $do
k create deploy web --image=nginx:1.27 --replicas=3 $do
k expose deploy web --port=80 --target-port=8080 --type=NodePort
k create svc clusterip db --tcp=5432:5432
k create cm cfg --from-literal=k=v --from-file=app.conf
k create secret generic s --from-literal=pw=x
k create secret tls t --cert=tls.crt --key=tls.key
k create job j --image=busybox -- echo hi
k create cronjob c --image=busybox --schedule="*/5 * * * *" -- date
k create job manual --from=cronjob/c
k create ingress web --class=traefik --rule="host/path*=svc:80,tls=secret"
k create role r --verb=get,list --resource=pods --resource-name=x
k create rolebinding rb --role=r --user=u --group=g --serviceaccount=ns:sa
k create clusterrole cr --verb=get --resource=nodes
k create token sa-name --duration=1h
k create pdb p --selector=app=web --min-available=1
k create priorityclass high --value=1000
k create quota q --hard=pods=5,requests.cpu=2
k autoscale deploy web --min=2 --max=5 --cpu-percent=60
k set image deploy/web nginx=nginx:1.27
k set resources deploy/web --requests=cpu=100m,memory=64Mi --limits=memory=128Mi
k set env deploy/web KEY=value
k set selector svc web app=web
k label / annotate / taint node n key=value:NoSchedule  (key- to remove)
```

## Rollouts
```bash
k rollout status|history|undo|restart|pause|resume deploy/web
k rollout history deploy/web --revision=2
k rollout undo deploy/web --to-revision=2
```

## RBAC & auth
```bash
k auth can-i <verb> <resource> -n <ns> --as=<user> [--as-group=g]
k auth can-i --list --as=system:serviceaccount:<ns>:<sa>
k certificate approve <csr>
k config set-credentials u --client-key=u.key --client-certificate=u.crt --embed-certs
k config set-context u@c --cluster=c --user=u
```

## etcd
```bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key snapshot save /opt/backup.db
etcdutl snapshot status /opt/backup.db -w table
etcdutl snapshot restore /opt/backup.db --data-dir /var/lib/etcd-new
# then point the etcd-data hostPath in /etc/kubernetes/manifests/etcd.yaml to the new dir
```

## kubeadm
```bash
kubeadm init --pod-network-cidr=10.244.0.0/16 [--control-plane-endpoint lb:6443 --upload-certs]
kubeadm token create --print-join-command [--ttl 2h]
kubeadm upgrade plan | apply v1.x.y      # first control plane
kubeadm upgrade node                     # other nodes
kubeadm certs check-expiration | renew all
k drain <node> --ignore-daemonsets --delete-emptydir-data ; k uncordon <node>
```

## Node troubleshooting
```bash
systemctl status kubelet | containerd ; systemctl enable --now kubelet
journalctl -u kubelet -n 50 --no-pager
crictl ps -a ; crictl logs <id> ; crictl pods ; crictl images
/var/lib/kubelet/config.yaml             # kubelet config (staticPodPath, clientCAFile, ...)
/var/lib/kubelet/kubeadm-flags.env       # extra kubelet flags
/etc/kubernetes/manifests/               # static pods: apiserver, scheduler, controller-manager, etcd
/etc/kubernetes/*.conf                   # kubeconfigs (admin, kubelet, scheduler, controller-manager)
/etc/kubernetes/pki/                     # certificates
/var/log/pods/ , /var/log/containers/    # container logs on the node
/etc/cni/net.d/ , /opt/cni/bin/          # CNI config & binaries
```

## Inspection
```bash
k get events -A --sort-by=.lastTimestamp
k get pods -A -o wide --field-selector status.phase!=Running
k top nodes ; k top pods -A --sort-by=cpu|memory ; k top pod p --containers
k logs p -c c --previous --since=1h --tail=50 -f ; k logs -l app=web --all-containers --prefix
k get endpointslices -l kubernetes.io/service-name=<svc>
k explain pod.spec.affinity --recursive
k get pod p -o jsonpath='{.status.podIP}' ; -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeName
k debug node/<node> -it --image=busybox     # shell on a node (host fs under /host)
k run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- -T 3 svc.ns
```

## Troubleshooting map
| Symptom | Look at |
|---------|---------|
| Pod `Pending`, no events | kube-scheduler |
| Pod `Pending`, `FailedScheduling` | resources, taints, affinity, PVC |
| No ReplicaSet/pods for a Deployment | kube-controller-manager |
| `kubectl`: connection refused | kube-apiserver → `crictl`, manifest |
| Node `NotReady` | kubelet, containerd, CNI |
| `ImagePullBackOff` | image name/tag, registry, pull secret |
| `CrashLoopBackOff` | `logs --previous`, command, config |
| `CreateContainerConfigError` | missing ConfigMap/Secret/key |
| Service: connection refused | targetPort |
| Service: timeout | endpoints (selector, readiness), NetworkPolicy |
| Service: bad address | DNS (CoreDNS, kube-dns svc, Corefile) |
