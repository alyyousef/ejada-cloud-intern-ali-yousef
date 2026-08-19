# oke module

Creates an OKE cluster and one managed node pool. Pod networking mode
(VCN-native vs. flannel overlay), endpoint visibility, node shape, and node
placement are all variable-driven so the same module works for a
public-endpoint demo cluster or a fully private production one.

## Resources created

- `oci_containerengine_cluster.this`
- `oci_containerengine_node_pool.this`

## Key design points

- **`pod_network_type` conditional.** Two mutually exclusive `dynamic
  "cluster_pod_network_options"` blocks (and the matching pair of
  `node_pool_pod_network_option_details` blocks in the node pool) each guard
  themselves with `var.pod_network_type == "VCN_NATIVE" ? [1] : []` /
  `"FLANNEL_OVERLAY" ? [1] : []`. Exactly one renders. This is what the Week 3
  assignment means by "conditional expressions" - the config *shape* itself
  changes based on a variable, not just a value inside it.
- **`node_placement_configs` dynamic block.** Lets the root config spread
  worker nodes across as many AD/subnet pairs as it wants (one AD in
  `me-jeddah-1`, three in a multi-AD region) without editing this module.
- **Nothing here is hardcoded**: no compartment, no VCN, no CIDR, no shape, no
  image OCID. The root config is expected to look up the worker image via a
  `data "oci_core_images"` source (filtered on the OKE-published Oracle Linux
  image) and pass the OCID in as `node_image_id`, exactly like the pattern
  already used in `weekOne/main.tf`.

## Example call

```hcl
module "oke" {
  source = "./modules/oke"

  compartment_id = var.compartment_id
  vcn_id          = oci_core_vcn.this.id
  cluster_name    = "tf-lab-oke-AliYousef"
  kubernetes_version = data.oci_containerengine_cluster_option.this.kubernetes_versions[
    length(data.oci_containerengine_cluster_option.this.kubernetes_versions) - 1
  ]

  endpoint_subnet_id = module.endpoint_subnet.subnet_id
  is_endpoint_public  = false

  pod_network_type = "VCN_NATIVE"
  pod_subnet_ids   = [module.pods_subnet.subnet_id]

  service_lb_subnet_ids = [module.lb_subnet.subnet_id]

  node_pool_name = "tf-lab-oke-workers-AliYousef"
  node_shape      = "VM.Standard.E4.Flex"
  node_shape_config = { ocpus = 2, memory_in_gbs = 16 }
  node_image_id   = data.oci_core_images.oke_worker.images[0].id
  node_pool_size  = 2

  node_placement_configs = [
    {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id             = module.workers_subnet.subnet_id
    }
  ]

  ssh_public_key = file(var.ssh_public_key_path)
  freeform_tags  = var.freeform_tags
}
```

## Not included on purpose

IAM policies (dynamic group for worker nodes + the policy statements OKE
needs to manage load balancers, block volumes, etc.) are **not** created by
this module. In Week 2 the account hit a hard wall trying to even *list*
IAM policies in `intern-02-ali-youssef-cmp` (the Bastion gap) - policy
management here needs a tenancy admin regardless of what Terraform code
exists, so it's documented as a manual prerequisite in the root README
rather than baked into a module that would just fail the same way.
