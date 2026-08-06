output "availability_domain_names" {
  description = "Availability domains available in the tenancy"
  value = [
    for ad in data.oci_identity_availability_domains.ads.availability_domains :
    ad.name
  ]
}

output "terraform_vcn_id" {
  description = "OCID of the Terraform-created VCN"
  value       = oci_core_vcn.terraform_vcn.id
}

output "terraform_subnet_id" {
  description = "OCID of the Terraform-created public subnet"
  value       = oci_core_subnet.public_subnet.id
}

output "terraform_internet_gateway_id" {
  description = "OCID of the Terraform-created Internet Gateway"
  value       = oci_core_internet_gateway.terraform_igw.id
}

output "instance_id" {
  description = "OCID of the Terraform-created Linux instance"
  value       = oci_core_instance.linux_instance.id
}

output "instance_public_ip" {
  description = "Public IPv4 address of the Terraform-created Linux instance"
  value       = data.oci_core_vnic.linux_instance.public_ip_address
}

output "ssh_command" {
  description = "Example SSH command to reach the instance"
  value       = "ssh -i C:/Users/yinya/.ssh/oci_vm opc@${data.oci_core_vnic.linux_instance.public_ip_address}"
}

output "block_volume_id" {
  description = "OCID of the extra block volume attached to the instance"
  value       = oci_core_volume.data_volume.id
}

output "file_system_export_path" {
  description = "NFS export path for the file system"
  value       = oci_file_storage_export.shared_export.path
}

output "mount_target_private_ip_ids" {
  description = "OCID(s) of the mount target's private IP object(s). Look these up in the console (Networking > Private IPs) or via 'oci network private-ip get' to find the actual IP address to mount from."
  value       = oci_file_storage_mount_target.shared_mount_target.private_ip_ids
}
