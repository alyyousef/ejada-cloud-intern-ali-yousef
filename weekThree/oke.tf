data "oci_containerengine_cluster_option" "this" {
  cluster_option_id = "all"
  compartment_id     = local.my_compartment_id
}

locals {
  kubernetes_version = data.oci_containerengine_cluster_option.this.kubernetes_versions[
    length(data.oci_containerengine_cluster_option.this.kubernetes_versions) - 1
  ]
}

data "oci_containerengine_node_pool_option" "this" {
  node_pool_option_id = "all"
  compartment_id       = local.my_compartment_id
}

locals {
  oke_worker_candidates = {
    for s in data.oci_containerengine_node_pool_option.this.sources :
    s.source_name => s.image_id
    if can(regex("^Oracle-Linux-8", s.source_name))
      && !can(regex("aarch64", s.source_name))
      && !can(regex("GPU", s.source_name))
  }

  oke_version_tagged_images = {
    for name, id in local.oke_worker_candidates : name => id
    if can(regex("-OKE-${trimprefix(local.kubernetes_version, "v")}-", name))
  }

  oke_worker_images = length(local.oke_version_tagged_images) > 0 ? local.oke_version_tagged_images : local.oke_worker_candidates

  node_image_id = local.oke_worker_images[
    sort(keys(local.oke_worker_images))[length(local.oke_worker_images) - 1]
  ]
}

module "oke" {
  source = "./modules/oke"

  compartment_id = local.my_compartment_id
  vcn_id          = oci_core_vcn.this.id

  cluster_name        = var.cluster_name
  kubernetes_version  = local.kubernetes_version
  cluster_type         = "BASIC_CLUSTER"

  endpoint_subnet_id = module.endpoint_subnet.subnet_id
  is_endpoint_public  = var.is_endpoint_public

  pod_network_type  = "VCN_NATIVE"
  pod_subnet_ids    = [module.pods_subnet.subnet_id]
  max_pods_per_node = var.max_pods_per_node

  service_lb_subnet_ids = [module.lb_subnet.subnet_id]

  node_pool_name = "${var.cluster_name}-workers"
  node_shape      = var.node_shape
  node_shape_config = {
    ocpus         = var.node_ocpus
    memory_in_gbs = var.node_memory_in_gbs
  }
  node_image_id            = local.node_image_id
  boot_volume_size_in_gbs = var.node_boot_volume_size_in_gbs
  node_pool_size           = var.node_pool_size

  node_placement_configs = [
    {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id             = module.workers_subnet.subnet_id
    }
  ]

  ssh_public_key = file(var.ssh_public_key_path)
  freeform_tags  = var.freeform_tags
}
