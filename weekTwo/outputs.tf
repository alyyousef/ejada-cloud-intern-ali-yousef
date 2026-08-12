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

output "subnet_ids_by_tier" {
  description = "Map of tier name to subnet OCID"
  value       = { for tier, subnet in oci_core_subnet.tier : tier => subnet.id }
}

output "terraform_internet_gateway_id" {
  description = "OCID of the Terraform-created Internet Gateway"
  value       = oci_core_internet_gateway.terraform_igw.id
}

output "instance_id" {
  description = "OCID of the Terraform-created Linux instance (private, no public IP)"
  value       = oci_core_instance.linux_instance.id
}

output "instance_private_ip" {
  description = "Private IPv4 address of the instance. Not reachable directly from the internet — use the load balancer for app traffic, Bastion for SSH."
  value       = oci_core_instance.linux_instance.private_ip
}

output "load_balancer_public_ip" {
  description = "Public IP of the Application Load Balancer — this is the actual entry point for the app, not the instance."
  value = [
    for ip in oci_load_balancer_load_balancer.app_lb.ip_address_details :
    ip.ip_address if ip.is_public
  ][0]
}

output "load_balancer_id" {
  description = "OCID of the load balancer"
  value       = oci_load_balancer_load_balancer.app_lb.id
}

output "bastion_id" {
  description = "OCID of the Bastion — use this to create a Managed SSH Session (console or CLI) when you need to reach the private instance."
  value       = oci_bastion_bastion.tf_lab_bastion.id
}

output "file_system_export_path" {
  description = "NFS export path for the file system (app files live here)"
  value       = oci_file_storage_export.shared_export.path
}

output "mount_target_ip_address" {
  description = "Private IP of the File Storage mount target, for manual mount/troubleshooting"
  value       = oci_file_storage_mount_target.shared_mount_target.ip_address
}
