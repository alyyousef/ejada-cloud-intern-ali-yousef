terraform {
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 7.0"
    }
  }
}

resource "oci_core_route_table" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = var.route_table_display_name
  freeform_tags  = var.freeform_tags

  dynamic "route_rules" {
    for_each = var.route_rules
    content {
      destination       = route_rules.value.destination
      destination_type  = route_rules.value.destination_type
      network_entity_id = route_rules.value.network_entity_id
    }
  }
}

resource "oci_core_security_list" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id
  display_name   = var.security_list_display_name
  freeform_tags  = var.freeform_tags

  dynamic "ingress_security_rules" {
    for_each = var.ingress_rules
    content {
      source      = ingress_security_rules.value.source
      source_type = ingress_security_rules.value.source_type
      protocol    = ingress_security_rules.value.protocol
      description = ingress_security_rules.value.description
      stateless   = ingress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = ingress_security_rules.value.tcp_options != null ? [ingress_security_rules.value.tcp_options] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = ingress_security_rules.value.udp_options != null ? [ingress_security_rules.value.udp_options] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = ingress_security_rules.value.icmp_options != null ? [ingress_security_rules.value.icmp_options] : []
        content {
          type = icmp_options.value.type
          code = try(icmp_options.value.code, null)
        }
      }
    }
  }

  dynamic "egress_security_rules" {
    for_each = var.egress_rules
    content {
      destination      = egress_security_rules.value.destination
      destination_type = egress_security_rules.value.destination_type
      protocol         = egress_security_rules.value.protocol
      description      = egress_security_rules.value.description
      stateless        = egress_security_rules.value.stateless

      dynamic "tcp_options" {
        for_each = egress_security_rules.value.tcp_options != null ? [egress_security_rules.value.tcp_options] : []
        content {
          min = tcp_options.value.min
          max = tcp_options.value.max
        }
      }

      dynamic "udp_options" {
        for_each = egress_security_rules.value.udp_options != null ? [egress_security_rules.value.udp_options] : []
        content {
          min = udp_options.value.min
          max = udp_options.value.max
        }
      }

      dynamic "icmp_options" {
        for_each = egress_security_rules.value.icmp_options != null ? [egress_security_rules.value.icmp_options] : []
        content {
          type = icmp_options.value.type
          code = try(icmp_options.value.code, null)
        }
      }
    }
  }
}

resource "oci_core_subnet" "this" {
  compartment_id = var.compartment_id
  vcn_id         = var.vcn_id

  display_name = var.subnet_display_name
  cidr_block   = var.subnet_cidr_block
  dns_label    = var.dns_label

  route_table_id    = oci_core_route_table.this.id
  security_list_ids = [oci_core_security_list.this.id]

  prohibit_public_ip_on_vnic = var.is_public ? false : true

  freeform_tags = var.freeform_tags
}

resource "oci_logging_log" "flow_log" {
  count = var.enable_logs ? 1 : 0

  display_name = "${var.subnet_display_name}-flow-log"
  log_group_id = var.log_group_id
  log_type     = "SERVICE"

  configuration {
    compartment_id = var.compartment_id

    source {
      category    = "all"
      resource    = oci_core_subnet.this.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
  }

  retention_duration = var.log_retention_duration
  is_enabled         = true

  freeform_tags = var.freeform_tags

  lifecycle {
    precondition {
      condition     = var.log_group_id != null
      error_message = "log_group_id must be set when enable_logs = true."
    }
  }
}
