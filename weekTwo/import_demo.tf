resource "oci_core_network_security_group" "imported_nsg" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id
  display_name   = "tf-lab-imported-nsg-AliYousef"
}
