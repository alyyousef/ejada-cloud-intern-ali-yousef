Kubernetes manifests for the Week 3 lab. Ready to apply once the OKE cluster
from `../oke.tf` is up and `kubeconfig` is pulled down (see the
`kubeconfig_command` output at the root).

| File | What it does |
|---|---|
| `namespace.yaml` | `week3-demo` namespace everything else lives in |
| `storageclass.yaml` | explicit OCI block volume StorageClass (`week3-oci-bv`), Balanced tier (10 VPUs/GB), paravirtualized attachment |
| `pvc.yaml` | 50Gi `PersistentVolumeClaim` against that StorageClass - keep in sync with `var.app_block_volume_size_in_gbs` in `../variables.tf` |
| `deployment.yaml` | the demo app: an `initContainer` writes a small status page (pod name, node name, timestamp) onto the PVC, then nginx serves it read-only. `replicas: 1` - see the comment in the file for why |
| `service.yaml` | `type: LoadBalancer`, provisions a real OCI Load Balancer in the `lb` subnet |

Apply order:

```
kubectl apply -f namespace.yaml
kubectl apply -f storageclass.yaml
kubectl apply -f pvc.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
```

**Validated so far:** all five files parse as valid YAML and pass schema
validation against the Kubernetes 1.30 API (checked with the
`kubernetes-validate` Python package against every built-in kind used here:
Namespace, StorageClass, PersistentVolumeClaim, Deployment, Service).
That confirms the manifests are well-formed - it does **not** confirm the
OCI CSI driver accepts `storageclass.yaml`'s `vpusPerGB` parameter, since
that's opaque to the core Kubernetes schema and only meaningful to OCI's
driver. First real test is `kubectl apply` once the cluster exists.

**Not yet run** - there's no cluster to apply these against yet (Terraform
hasn't been applied). This is the "deploy an application to OKE / attach a
block volume / expose via load balancer" part of the lab, staged and ready
to go the moment the cluster is up.
