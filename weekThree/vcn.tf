data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_compartments" "mine" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  name                      = "intern-02-ali-youssef-cmp"
  state                     = "ACTIVE"
}

locals {
  my_compartment_id = data.oci_identity_compartments.mine.compartments[0].id
}

resource "oci_core_vcn" "this" {
  compartment_id = local.my_compartment_id
  cidr_blocks    = [var.vcn_cidr_block]
  display_name   = "tf-lab-oke-vcn-AliYousef"
  dns_label      = var.vcn_dns_label
  freeform_tags  = var.freeform_tags
}

resource "oci_core_internet_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-igw-AliYousef"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

resource "oci_core_nat_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-nat-AliYousef"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_service_gateway" "this" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.this.id
  display_name   = "tf-lab-oke-sgw-AliYousef"
  freeform_tags  = var.freeform_tags

  services {
    service_id = data.oci_core_services.all_oci_services.services[0].id
  }
}

data "oci_core_services" "all_oci_services" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}

resource "oci_logging_log_group" "this" {
  count = var.enable_flow_logs ? 1 : 0

  compartment_id = local.my_compartment_id
  display_name   = "tf-lab-oke-log-group-AliYousef"
  freeform_tags  = var.freeform_tags
}
