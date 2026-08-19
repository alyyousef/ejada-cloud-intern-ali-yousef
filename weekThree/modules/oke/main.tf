terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

resource "oci_containerengine_cluster" "this" {
  compartment_id     = var.compartment_id
  vcn_id             = var.vcn_id
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version
  type               = var.cluster_type

  endpoint_config {
    is_public_ip_enabled = var.is_endpoint_public
    subnet_id             = var.endpoint_subnet_id
    nsg_ids                = var.endpoint_nsg_ids
  }

  dynamic "cluster_pod_network_options" {
    for_each = var.pod_network_type == "VCN_NATIVE" ? [1] : []
    content {
      cni_type = "OCI_VCN_IP_NATIVE"
    }
  }

  dynamic "cluster_pod_network_options" {
    for_each = var.pod_network_type == "FLANNEL_OVERLAY" ? [1] : []
    content {
      cni_type = "FLANNEL_OVERLAY"
    }
  }

  options {
    service_lb_subnet_ids = var.service_lb_subnet_ids

    dynamic "add_ons" {
      for_each = [1]
      content {
        is_kubernetes_dashboard_enabled = var.enable_kubernetes_dashboard
        is_tiller_enabled               = false
      }
    }

    admission_controller_options {
      is_pod_security_policy_enabled = var.enable_pod_security_policy
    }

    kubernetes_network_config {
      pods_cidr     = var.pod_network_type == "FLANNEL_OVERLAY" ? var.pods_cidr : null
      services_cidr = var.services_cidr
    }
  }

  freeform_tags = var.freeform_tags
}

resource "oci_containerengine_node_pool" "this" {
  cluster_id         = oci_containerengine_cluster.this.id
  compartment_id     = var.compartment_id
  name               = var.node_pool_name
  kubernetes_version = var.kubernetes_version
  node_shape         = var.node_shape

  dynamic "node_shape_config" {
    for_each = var.node_shape_config != null ? [var.node_shape_config] : []
    content {
      ocpus         = node_shape_config.value.ocpus
      memory_in_gbs = node_shape_config.value.memory_in_gbs
    }
  }

  node_source_details {
    source_type             = "IMAGE"
    image_id                = var.node_image_id
    boot_volume_size_in_gbs = var.boot_volume_size_in_gbs
  }

  node_config_details {
    size = var.node_pool_size

    dynamic "placement_configs" {
      for_each = var.node_placement_configs
      content {
        availability_domain = placement_configs.value.availability_domain
        subnet_id             = placement_configs.value.subnet_id
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = var.pod_network_type == "VCN_NATIVE" ? [1] : []
      content {
        cni_type          = "OCI_VCN_IP_NATIVE"
        pod_subnet_ids    = var.pod_subnet_ids
        pod_nsg_ids       = var.pod_nsg_ids
        max_pods_per_node = var.max_pods_per_node
      }
    }

    dynamic "node_pool_pod_network_option_details" {
      for_each = var.pod_network_type == "FLANNEL_OVERLAY" ? [1] : []
      content {
        cni_type = "FLANNEL_OVERLAY"
      }
    }

    freeform_tags = var.node_pool_freeform_tags
  }

  ssh_public_key = var.ssh_public_key != "" ? var.ssh_public_key : null

  initial_node_labels {
    key   = "name"
    value = var.node_pool_name
  }

  freeform_tags = var.freeform_tags
}
