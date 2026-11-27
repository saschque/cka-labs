# CKA Labs – Practice exercises for the Certified Kubernetes Administrator

Hands-on exercises for the **CKA** exam by the Linux Foundation / CNCF.
The exam is **performance-based**: about 15–20 tasks in 120 minutes on live clusters, using the
command line. This repo mirrors the five official domains and runs on a local
[kind](https://kind.sigs.k8s.io) cluster.

| # | Domain | Weight | Folder |
|---|--------|--------|--------|
| 1 | Cluster Architecture, Installation & Configuration | 25 % | [`01-cluster-architecture`](01-cluster-architecture/) |
| 2 | Workloads & Scheduling | 15 % | [`02-workloads-scheduling`](02-workloads-scheduling/) |
| 3 | Services & Networking | 20 % | [`03-services-networking`](03-services-networking/) |
| 4 | Storage | 10 % | [`04-storage`](04-storage/) |
| 5 | Troubleshooting | 30 % | [`05-troubleshooting`](05-troubleshooting/) |

Plus:
- [`mock-exams/`](mock-exams/) – full mock exams (120 min, 100 points, automatic scoring)
- [`CHEATSHEET.md`](CHEATSHEET.md) – the most important commands at a glance

> ⚠️ The official curriculum (github.com/cncf/curriculum) is the reference. Check before the
> exam whether the competencies or the Kubernetes version have changed.

## Quick start

```bash
# 1. Create a local cluster (kind: 1 control plane + 2 workers, metrics-server)
./setup/create-cluster.sh

# 2. Optional add-ons (Traefik for Ingress + Gateway API, cert-manager)
./setup/install.sh traefik cert-manager

# 3. Work through the tasks
cat 01-cluster-architecture/README.md

# 4. Check your result
./01-cluster-architecture/verify.sh
```

Requirements: Docker, kind, kubectl, helm, jq, openssl, curl.

## Low on RAM? (8 GB laptops)

```bash
./setup/resources.sh                    # what uses CPU/memory right now?
./setup/uninstall.sh traefik            # remove add-ons you don't need at the moment
```

- **Only install add-ons when a task needs them** (Traefik for Ingress/Gateway API, cert-manager
  for the operator tasks) and remove them afterwards.
- **Start over between domains:** `kind delete cluster --name cka && ./setup/create-cluster.sh`
  takes about a minute and frees everything.
- **Close the rest:** browser tabs and IDEs compete for the same RAM.
- **Windows/WSL2:** cap the VM in `%UserProfile%\\.wslconfig` (`[wsl2]` → `memory=5GB`, `swap=4GB`),
  otherwise Windows and Docker fight over the RAM.
- The three-node cluster itself needs roughly 1.5–2 GB; many tasks rely on the worker nodes, so
  there is no single-node mode here.

### kind vs. real machines

kind nodes are Docker containers, so `docker exec -it cka-control-plane bash` is your "SSH".
`systemctl`, `journalctl`, `crictl`, `kubeadm` and the static pod manifests work inside them just
like on a real node – that's enough for almost all troubleshooting tasks.
Installing clusters with kubeadm, upgrading them and joining HA control planes needs real VMs:
those tasks are marked **🖥 VM lab** and come with complete command sequences.

## Structure

```
0X-domain/
├── README.md        # tasks (scenario, requirements, time estimate)
├── SOLUTIONS.md     # reference solutions (only look AFTER your own attempt!)
├── verify.sh        # automatic check of your solution
└── scenarios/       # (troubleshooting) scripts and manifests that break things on purpose
```

Troubleshooting helpers:
```bash
./05-troubleshooting/scenarios/break.sh <scenario>   # node | kubelet | scheduler | controller-manager | apiserver | dns
./05-troubleshooting/scenarios/restore.sh            # emergency reset
```

## Mock exams

Each exam: `setup.sh` (prepares the scenario and breaks parts of the cluster) → 120 min timer →
`verify.sh` (point-based scoring, pass mark 66 %) → `SOLUTIONS.md`. Use a fresh cluster for
each exam (`kind delete cluster --name cka && ./setup/create-cluster.sh`).

## Study strategy

1. **Troubleshooting is 30 %** – practice breaking and fixing the control plane and nodes until
   you can do it without thinking. Know where the kubelet config, static pod manifests and logs live.
2. **Speed with imperative commands:** `kubectl create ... --dry-run=client -o yaml > x.yaml`,
   `kubectl expose`, `kubectl set image/resources/env`, `kubectl create role/rolebinding`.
3. **Know the docs:** you may use kubernetes.io during the exam. Practice finding examples
   (NetworkPolicy, PV/PVC, Gateway API, etcd backup) quickly.
4. **Always switch context first** – every exam task names the cluster to use.
5. **Time management:** skim all tasks, do quick wins first, flag long ones, come back later.

## Progress

- [ ] Domain 1 – Cluster architecture
- [ ] Domain 2 – Workloads & scheduling
- [ ] Domain 3 – Services & networking
- [ ] Domain 4 – Storage
- [ ] Domain 5 – Troubleshooting
- [ ] Mock exam 1 ≥ 66 %
- [ ] Mock exam 2 ≥ 66 %
- [ ] Mock exam 3 ≥ 66 %
- [ ] Mock exam 4 ≥ 66 % in < 120 min
