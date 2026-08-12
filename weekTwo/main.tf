data "oci_identity_availability_domains" "ads" {
  compartment_id = var.tenancy_ocid
}

data "oci_identity_compartments" "mine" {
  compartment_id            = var.tenancy_ocid
  compartment_id_in_subtree = true
  name                      = "intern-02-ali-youssef-cmp"
  state                     = "ACTIVE"
}

resource "oci_core_vcn" "terraform_vcn" {
  compartment_id = local.my_compartment_id
  display_name   = "${local.name_prefix}-vcn-${local.owner}"
  cidr_blocks    = ["10.1.0.0/16"]
  dns_label      = "tflabvcn"
  freeform_tags  = local.common_freeform_tags
}

resource "oci_core_internet_gateway" "terraform_igw" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-igw-${local.owner}"
  enabled        = true
}

resource "oci_core_nat_gateway" "terraform_nat" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-nat-${local.owner}"
}

resource "oci_core_route_table" "public_route_table" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-public-route-table-${local.owner}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.terraform_igw.id
  }
}

resource "oci_core_route_table" "private_route_table" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-private-route-table-${local.owner}"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.terraform_nat.id
  }
}

resource "oci_core_security_list" "web_tier_security_list" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-public-security-list-${local.owner}"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  dynamic "ingress_security_rules" {
    for_each = var.public_ingress_rules
    content {
      source      = ingress_security_rules.value.source
      source_type = "CIDR_BLOCK"
      protocol    = ingress_security_rules.value.protocol
      stateless   = false
      description = ingress_security_rules.value.description

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.protocol == "6" ? [1] : []
        content {
          min = ingress_security_rules.value.port_min
          max = ingress_security_rules.value.port_max
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.protocol == "17" ? [1] : []
        content {
          min = ingress_security_rules.value.port_min
          max = ingress_security_rules.value.port_max
        }
      }
    }
  }
}

resource "oci_core_security_list" "private_tier_security_list" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "${local.name_prefix}-private-security-list-${local.owner}"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  dynamic "ingress_security_rules" {
    for_each = var.private_ingress_rules
    content {
      source      = ingress_security_rules.value.source
      source_type = "CIDR_BLOCK"
      protocol    = ingress_security_rules.value.protocol
      stateless   = false
      description = ingress_security_rules.value.description

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.protocol == "6" ? [1] : []
        content {
          min = ingress_security_rules.value.port_min
          max = ingress_security_rules.value.port_max
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.protocol == "17" ? [1] : []
        content {
          min = ingress_security_rules.value.port_min
          max = ingress_security_rules.value.port_max
        }
      }
    }
  }
}

resource "oci_core_subnet" "tier" {
  for_each = var.subnet_tiers

  compartment_id             = local.my_compartment_id
  vcn_id                     = oci_core_vcn.terraform_vcn.id
  display_name               = "${local.name_prefix}-${each.key}-subnet-${local.owner}"
  cidr_block                 = each.value.cidr_block
  dns_label                  = each.value.dns_label
  route_table_id             = each.value.is_public ? oci_core_route_table.public_route_table.id : oci_core_route_table.private_route_table.id
  security_list_ids          = each.value.is_public ? [oci_core_security_list.web_tier_security_list.id] : [oci_core_security_list.private_tier_security_list.id]
  prohibit_public_ip_on_vnic = !each.value.is_public
}

data "oci_core_images" "oracle_linux" {
  compartment_id           = local.my_compartment_id
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "oci_core_instance" "linux_instance" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${local.name_prefix}-linux-${local.owner}"
  shape               = var.instance_shape
  freeform_tags       = local.common_freeform_tags

  create_vnic_details {
    subnet_id        = oci_core_subnet.tier["private"].id
    assign_public_ip = false
    display_name     = "${local.name_prefix}-linux-vnic-${local.owner}"
    hostname_label   = "tflablinux"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)

    user_data = base64encode(templatefile("${path.module}/templates/app_userdata.sh.tftpl", {
      mount_target_ip = oci_file_storage_mount_target.shared_mount_target.ip_address
      export_path     = oci_file_storage_export.shared_export.path
      app_port        = var.app_port
    }))
  }

  preserve_boot_volume = false

  lifecycle {
    ignore_changes = [freeform_tags]
  }
}

resource "oci_file_storage_file_system" "shared_fs" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  display_name        = "${local.name_prefix}-fs-${local.owner}"
  freeform_tags       = local.common_freeform_tags
}

resource "oci_file_storage_mount_target" "shared_mount_target" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  subnet_id           = oci_core_subnet.tier["private"].id
  display_name        = "${local.name_prefix}-mount-target-${local.owner}"
}

resource "oci_file_storage_export" "shared_export" {
  export_set_id  = oci_file_storage_mount_target.shared_mount_target.export_set_id
  file_system_id = oci_file_storage_file_system.shared_fs.id
  path           = "/tf-lab-export-aliyousef"
}
