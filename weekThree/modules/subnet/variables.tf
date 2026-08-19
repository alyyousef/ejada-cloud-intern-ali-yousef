variable "compartment_id" {
  description = "OCID of the compartment where the subnet and its related resources will be created."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN the subnet belongs to."
  type        = string
}

variable "subnet_display_name" {
  description = "Display name for the subnet."
  type        = string
}

variable "subnet_cidr_block" {
  description = "CIDR block for the subnet, e.g. \"10.0.1.0/24\"."
  type        = string
}

variable "dns_label" {
  description = "DNS label for the subnet. Set to null to skip DNS resolution for this subnet."
  type        = string
  default     = null
}

variable "is_public" {
  description = "Whether VNICs in this subnet are allowed a public IP. false creates a private subnet (prohibit_public_ip_on_vnic = true)."
  type        = bool
  default     = false
}

variable "route_table_display_name" {
  description = "Display name for the route table created for this subnet."
  type        = string
}

variable "security_list_display_name" {
  description = "Display name for the security list created for this subnet."
  type        = string
}

variable "route_rules" {
  description = <<-EOT
    Route rules attached to this subnet's route table. One object per rule:
      destination        CIDR block (or service CIDR label) the rule matches
      destination_type   "CIDR_BLOCK" or "SERVICE_CIDR_BLOCK" (default "CIDR_BLOCK")
      network_entity_id  OCID of the target: internet gateway, NAT gateway, service gateway, DRG, etc.
  EOT
  type = list(object({
    destination       = string
    destination_type  = optional(string, "CIDR_BLOCK")
    network_entity_id = string
  }))
  default = []
}

variable "ingress_rules" {
  description = <<-EOT
    Ingress security rules for this subnet's security list. One object per rule:
      source        CIDR block, service label, or NSG OCID traffic is allowed from
      source_type   "CIDR_BLOCK", "SERVICE_CIDR_BLOCK", or "NETWORK_SECURITY_GROUP" (default "CIDR_BLOCK")
      protocol      protocol number as a string: "6" = TCP, "17" = UDP, "1" = ICMP, "all" = all protocols
      description   human-readable description shown in the console
      stateless     whether the rule is stateless (default false)
      tcp_options   optional { min = number, max = number } port range, only relevant when protocol = "6"
      udp_options   optional { min = number, max = number } port range, only relevant when protocol = "17"
      icmp_options  optional { type = number, code = optional(number) }, only relevant when protocol = "1"
  EOT
  type = list(object({
    source      = string
    source_type = optional(string, "CIDR_BLOCK")
    protocol    = string
    description = optional(string, "")
    stateless   = optional(bool, false)
    tcp_options = optional(object({
      min = number
      max = number
    }))
    udp_options = optional(object({
      min = number
      max = number
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []
}

variable "egress_rules" {
  description = "Egress security rules for this subnet's security list. Same shape as ingress_rules, but source/source_type become destination/destination_type."
  type = list(object({
    destination      = string
    destination_type = optional(string, "CIDR_BLOCK")
    protocol         = string
    description      = optional(string, "")
    stateless        = optional(bool, false)
    tcp_options = optional(object({
      min = number
      max = number
    }))
    udp_options = optional(object({
      min = number
      max = number
    }))
    icmp_options = optional(object({
      type = number
      code = optional(number)
    }))
  }))
  default = []
}

variable "enable_logs" {
  description = "Whether to create a VCN flow log ('Enable Logs') for this subnet."
  type        = bool
  default     = false
}

variable "log_group_id" {
  description = "OCID of the OCI Logging log group to place the flow log in. Required when enable_logs = true. Enforced with a lifecycle precondition on oci_logging_log.flow_log in main.tf, since a variable validation block can only reference itself, not enable_logs."
  type        = string
  default     = null
}

variable "log_retention_duration" {
  description = "Retention period, in days, for the subnet's flow log. Only used when enable_logs = true."
  type        = number
  default     = 30
}

variable "freeform_tags" {
  description = "Freeform tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
