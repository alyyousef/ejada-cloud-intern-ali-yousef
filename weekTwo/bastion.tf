resource "oci_bastion_bastion" "tf_lab_bastion" {
  compartment_id               = local.my_compartment_id
  bastion_type                 = "STANDARD"
  target_subnet_id             = oci_core_subnet.tier["private"].id
  name                         = "${local.name_prefix}-bastion-${local.owner}"
  client_cidr_block_allow_list = var.bastion_client_cidr_allow_list
  max_session_ttl_in_seconds   = var.bastion_max_session_ttl_in_seconds
}
