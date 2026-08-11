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

resource "oci_core_vcn" "terraform_vcn" {
  compartment_id = local.my_compartment_id

  display_name = "tf-lab-vcn-AliYousef"
  cidr_blocks  = ["10.1.0.0/16"]
  dns_label    = "tflabvcn"
}

resource "oci_core_internet_gateway" "terraform_igw" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id

  display_name = "tf-lab-igw-AliYousef"
  enabled      = true
}

resource "oci_core_route_table" "public_route_table" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id

  display_name = "tf-lab-public-route-table-AliYousef"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.terraform_igw.id
  }
}

resource "oci_core_security_list" "public_security_list" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id

  display_name = "tf-lab-public-security-list-AliYousef"

  egress_security_rules {
    destination      = "0.0.0.0/0"
    destination_type = "CIDR_BLOCK"
    protocol         = "all"
    stateless        = false
  }

  ingress_security_rules {
    source      = "0.0.0.0/0"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
    description = "Allow SSH"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    source      = "10.1.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
    description = "NFS TCP from within the VCN"

    tcp_options {
      min = 111
      max = 111
    }
  }

  ingress_security_rules {
    source      = "10.1.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "17"
    stateless   = false
    description = "NFS UDP from within the VCN"

    udp_options {
      min = 111
      max = 111
    }
  }

  ingress_security_rules {
    source      = "10.1.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "6"
    stateless   = false
    description = "NFS/mount TCP from within the VCN"

    tcp_options {
      min = 2048
      max = 2050
    }
  }

  ingress_security_rules {
    source      = "10.1.0.0/16"
    source_type = "CIDR_BLOCK"
    protocol    = "17"
    stateless   = false
    description = "NFS/mount UDP from within the VCN"

    udp_options {
      min = 2048
      max = 2050
    }
  }
}

resource "oci_core_subnet" "public_subnet" {
  compartment_id = local.my_compartment_id
  vcn_id         = oci_core_vcn.terraform_vcn.id

  display_name = "tf-lab-public-subnet-AliYousef"
  cidr_block   = "10.1.1.0/24"
  dns_label    = "public"

  route_table_id    = oci_core_route_table.public_route_table.id
  security_list_ids = [oci_core_security_list.public_security_list.id]

  prohibit_public_ip_on_vnic = false
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

  display_name = "tf-lab-linux-AliYousef"
  shape        = var.instance_shape

  create_vnic_details {
    subnet_id        = oci_core_subnet.public_subnet.id
    assign_public_ip = true
    display_name     = "tf-lab-linux-vnic-AliYousef"
    hostname_label   = "tflablinux"
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.oracle_linux.images[0].id
  }

  metadata = {
    ssh_authorized_keys = file(var.ssh_public_key_path)
  }

  preserve_boot_volume = false
}

resource "oci_core_volume" "data_volume" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

  display_name = "tf-lab-block-volume-AliYousef"
  size_in_gbs  = var.block_volume_size_in_gbs
}

resource "oci_core_volume_attachment" "data_volume_attachment" {
  attachment_type = "paravirtualized"
  instance_id     = oci_core_instance.linux_instance.id
  volume_id       = oci_core_volume.data_volume.id
  display_name    = "tf-lab-block-volume-attachment-AliYousef"
}

resource "oci_file_storage_file_system" "shared_fs" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name

  display_name = "tf-lab-fs-AliYousef"
}

resource "oci_file_storage_mount_target" "shared_mount_target" {
  compartment_id      = local.my_compartment_id
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  subnet_id           = oci_core_subnet.public_subnet.id

  display_name = "tf-lab-mount-target-AliYousef"
}

resource "oci_file_storage_export" "shared_export" {
  export_set_id  = oci_file_storage_mount_target.shared_mount_target.export_set_id
  file_system_id = oci_file_storage_file_system.shared_fs.id
  path           = "/tf-lab-export-aliyousef"
}

data "oci_core_vnic_attachments" "linux_instance" {
  compartment_id = local.my_compartment_id
  instance_id    = oci_core_instance.linux_instance.id
}

data "oci_core_vnic" "linux_instance" {
  vnic_id = data.oci_core_vnic_attachments.linux_instance.vnic_attachments[0].vnic_id
}
