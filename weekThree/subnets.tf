locals {
  log_group_id = var.enable_flow_logs ? oci_logging_log_group.this[0].id : null
}

module "endpoint_subnet" {
  source = "./modules/subnet"

  compartment_id      = local.my_compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "tf-lab-oke-endpoint-subnet-AliYousef"
  subnet_cidr_block    = var.endpoint_subnet_cidr
  dns_label             = "okeendpoint"
  is_public             = var.is_endpoint_public

  route_table_display_name   = "tf-lab-oke-endpoint-rt-AliYousef"
  security_list_display_name = "tf-lab-oke-endpoint-sl-AliYousef"

  route_rules = var.is_endpoint_public ? [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_internet_gateway.this.id
    }
    ] : [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_nat_gateway.this.id
    }
  ]

  ingress_rules = concat(
    [
      {
        source      = var.workers_subnet_cidr
        protocol    = "6"
        description = "Worker nodes -> Kubernetes API"
        tcp_options = { min = 6443, max = 6443 }
      },
      {
        source      = var.workers_subnet_cidr
        protocol    = "6"
        description = "Worker nodes -> OKE control plane services"
        tcp_options = { min = 12250, max = 12250 }
      }
    ],
    var.is_endpoint_public ? [
      {
        source      = "0.0.0.0/0"
        protocol    = "6"
        description = "External kubectl access to the Kubernetes API (endpoint is public - consider narrowing this to a known IP range for anything beyond a lab)"
        tcp_options = { min = 6443, max = 6443 }
      }
    ] : []
  )

  egress_rules = [
    {
      destination = var.workers_subnet_cidr
      protocol    = "6"
      description = "Control plane -> worker nodes (kubelet)"
      tcp_options = { min = 10250, max = 10250 }
    },
    {
      destination = "0.0.0.0/0"
      protocol    = "6"
      description = "Control plane -> OCI services (path discovery)"
      tcp_options = { min = 443, max = 443 }
    }
  ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = local.log_group_id
  freeform_tags = var.freeform_tags
}

module "workers_subnet" {
  source = "./modules/subnet"

  compartment_id      = local.my_compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "tf-lab-oke-workers-subnet-AliYousef"
  subnet_cidr_block    = var.workers_subnet_cidr
  dns_label             = "okeworkers"
  is_public             = false

  route_table_display_name   = "tf-lab-oke-workers-rt-AliYousef"
  security_list_display_name = "tf-lab-oke-workers-sl-AliYousef"

  route_rules = [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_nat_gateway.this.id
    }
  ]

  ingress_rules = [
    {
      source      = var.endpoint_subnet_cidr
      protocol    = "6"
      description = "Kubernetes API -> kubelet"
      tcp_options = { min = 10250, max = 10250 }
    },
    {
      source      = var.pods_subnet_cidr
      protocol    = "all"
      description = "Pod traffic to worker nodes (VCN-native pod networking)"
    },
    {
      source      = var.workers_subnet_cidr
      protocol    = "all"
      description = "Worker-to-worker traffic"
    }
  ]

  egress_rules = [
    {
      destination = "0.0.0.0/0"
      protocol    = "all"
      description = "Allow all outbound (image pulls, OCI API calls, etc.)"
    }
  ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = local.log_group_id
  freeform_tags = var.freeform_tags
}

module "pods_subnet" {
  source = "./modules/subnet"

  compartment_id      = local.my_compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "tf-lab-oke-pods-subnet-AliYousef"
  subnet_cidr_block    = var.pods_subnet_cidr
  dns_label             = "okepods"
  is_public             = false

  route_table_display_name   = "tf-lab-oke-pods-rt-AliYousef"
  security_list_display_name = "tf-lab-oke-pods-sl-AliYousef"

  route_rules = [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_nat_gateway.this.id
    }
  ]

  ingress_rules = [
    {
      source      = var.vcn_cidr_block
      protocol    = "all"
      description = "Allow all traffic from within the VCN (pod-to-pod, worker-to-pod, LB health checks)"
    }
  ]

  egress_rules = [
    {
      destination = "0.0.0.0/0"
      protocol    = "all"
      description = "Allow all outbound"
    }
  ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = local.log_group_id
  freeform_tags = var.freeform_tags
}

module "lb_subnet" {
  source = "./modules/subnet"

  compartment_id      = local.my_compartment_id
  vcn_id                = oci_core_vcn.this.id
  subnet_display_name  = "tf-lab-oke-lb-subnet-AliYousef"
  subnet_cidr_block    = var.lb_subnet_cidr
  dns_label             = "okelb"
  is_public             = true

  route_table_display_name   = "tf-lab-oke-lb-rt-AliYousef"
  security_list_display_name = "tf-lab-oke-lb-sl-AliYousef"

  route_rules = [
    {
      destination       = "0.0.0.0/0"
      network_entity_id = oci_core_internet_gateway.this.id
    }
  ]

  ingress_rules = [
    {
      source      = "0.0.0.0/0"
      protocol    = "6"
      description = "Public HTTP to the load balancer"
      tcp_options = { min = 80, max = 80 }
    },
    {
      source      = "0.0.0.0/0"
      protocol    = "6"
      description = "Public HTTPS to the load balancer"
      tcp_options = { min = 443, max = 443 }
    }
  ]

  egress_rules = [
    {
      destination = var.workers_subnet_cidr
      protocol    = "all"
      description = "Load balancer -> worker nodes (NodePort health checks / traffic)"
    }
  ]

  enable_logs   = var.enable_flow_logs
  log_group_id  = local.log_group_id
  freeform_tags = var.freeform_tags
}
