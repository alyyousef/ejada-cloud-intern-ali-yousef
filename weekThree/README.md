# Week 3 — DevOps / Kubernetes: OKE via reusable Terraform modules

## Layout

```
weekThree/
  modules/
    subnet/   subnet + route table + security list + optional flow log
    oke/      OKE cluster + managed node pool (VCN-native pod networking)
  provider.tf
  variables.tf       root-level inputs (auth, CIDRs, cluster sizing)
  vcn.tf             VCN, IGW, NAT gateway, service gateway, log group
  subnets.tf         4 calls to modules/subnet (endpoint, workers, pods, lb)
  oke.tf             lookups (k8s version, worker image) + call to modules/oke
  outputs.tf
  terraform.tfvars.example
  k8s/               Kubernetes manifests for the lab - written and schema-validated, not yet applied (no cluster exists yet)
```

## What each module demonstrates

**`modules/subnet`** — the 4 resources the assignment asked for (Subnet, Route
Table, Security List, "Enable Logs"), fully generic: route rules and
security rules are passed in as lists of objects and rendered with
`dynamic` blocks, including nested `dynamic "tcp_options"` /
`"udp_options"` / `"icmp_options"` that only appear when that particular
rule actually needs them. The flow log resource is gated with
`count = var.enable_logs ? 1 : 0` — a conditional expression deciding
whether a whole resource exists, not just a value inside one.

**`modules/oke`** — cluster + managed node pool. The interesting part is
`pod_network_type`: two mutually exclusive `dynamic` blocks (one per CNI
type) so switching from `"VCN_NATIVE"` to `"FLANNEL_OVERLAY"` changes which
block actually renders, in both the cluster resource and the node pool.
Node placement uses a `dynamic "placement_configs"` block so the same module
works whether you're spreading nodes across one AD (Jeddah, single-AD) or
three.

## Network layout (matches OCI's standard "quick create OKE with custom VCN" shape)

| Subnet | CIDR (default) | Public? | Purpose |
|---|---|---|---|
| endpoint | 10.0.0.0/28 | private by default | Kubernetes API endpoint |
| workers | 10.0.16.0/20 | private | Managed node pool VNICs |
| pods | 10.0.32.0/19 | private | Pod IPs (VCN-native networking) |
| lb | 10.0.8.0/24 | public | Load balancer created by `Service type: LoadBalancer` |

## Root config is a consumer, not a copy

Every value in `subnets.tf` / `oke.tf` comes from a root variable or a data
source lookup (Kubernetes version, worker image, availability domain) —
nothing is hardcoded inside the modules themselves, per the assignment's
explicit instruction. `variables.tf` documents every override point.

## Before running `terraform apply`

1. `terraform init` (pulls the `oracle/oci` provider, same as Week 1/2).
2. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in real
   values — reuses the same tenancy/user/fingerprint/key from Week 1 & 2.
3. **IAM policies are not created by this code.** OKE needs a dynamic group
   for the node pool (matching instances in this compartment) plus policy
   statements letting the OKE service and that dynamic group manage
   networking, block volumes, and load balancers in
   `intern-02-ali-youssef-cmp`. **Checked live on 2026-08-17: the account
   still gets `Authorization failed or requested resource not found` just
   listing Identity & Security → Policies in this compartment** — the same
   error class as the Week 2 Bastion gap, and it has not been resolved.
   `apply` will very likely fail on the cluster/node pool step for the same
   reason. Get this fixed by a tenancy admin before running `apply`.
4. `terraform plan` first, review it, then `apply`.

## Validation status (as of this session)

- All 12 `.tf` files parse as syntactically valid HCL (checked with
  `python-hcl2`).
- Ran `tofu init` (OpenTofu, Terraform-compatible) against the actual module
  graph. It caught one real bug, now fixed: a `variable "log_group_id"`
  validation block referenced `var.enable_logs`, which Terraform/OpenTofu
  disallows (a variable's own `validation` block may only reference itself).
  Moved that check into a `lifecycle { precondition {} }` on the
  `oci_logging_log.flow_log` resource in `modules/subnet/main.tf` instead,
  which is where cross-variable checks belong.
- Could not complete `tofu init`/`validate` end-to-end: this sandbox's
  network egress blocks `registry.terraform.io`, `registry.opentofu.org`,
  and `releases.hashicorp.com` (403 on all three), so the `oracle/oci`
  provider plugin itself can't be downloaded here. `provider.tf` was updated
  to pin the fully-qualified `registry.terraform.io/oracle/oci` source
  either way (works with both Terraform and OpenTofu, avoids ambiguity).
  **Please run `terraform init && terraform validate` yourself as the first
  step** — real provider-schema validation (attribute names, block shapes)
  hasn't happened yet, only structural/HCL-syntax checks have.

## Lab steps

- Application manifests are written and ready in `k8s/` (see `k8s/README.md`):
  a namespace, an explicit block-volume `StorageClass`, a `PersistentVolumeClaim`,
  an nginx `Deployment` (single replica — the PVC is ReadWriteOnce) whose
  `initContainer` writes a status page onto the mounted volume, and a
  `type: LoadBalancer` `Service`.
- These are schema-validated (against the Kubernetes 1.30 API) but **not yet
  applied** — there's no cluster to apply them against until `terraform apply`
  succeeds, which is blocked on the IAM policy gap above.
