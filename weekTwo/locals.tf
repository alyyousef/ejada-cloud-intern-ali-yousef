locals {
  my_compartment_id = data.oci_identity_compartments.mine.compartments[0].id

  name_prefix = "tf-lab"
  owner       = "AliYousef"

  common_freeform_tags = {
    project     = "ejada-oci-terraform-lab"
    environment = "week2-lab"
    owner       = local.owner
    managed_by  = "terraform"
  }
}
