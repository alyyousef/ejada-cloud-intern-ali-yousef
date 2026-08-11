variable "tenancy_ocid" {
  description = "OCI tenancy OCID"
  type        = string
  sensitive   = true
}

variable "user_ocid" {
  description = "OCI user OCID"
  type        = string
  sensitive   = true
}

variable "fingerprint" {
  description = "OCI API key fingerprint"
  type        = string
  sensitive   = true
}

variable "private_key_path" {
  description = "Path to the OCI API private key"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "OCI region"
  type        = string
  default     = "me-jeddah-1"
}

variable "compartment_ocid" {
  description = "OCID of the compartment where resources will be created"
  type        = string
}

variable "instance_shape" {
  description = "OCI Compute shape for the Linux instance"
  type        = string
  default     = "VM.Standard.E2.1.Micro"
}

variable "ssh_public_key_path" {
  description = "Local path to the SSH public key uploaded to the instance"
  type        = string
  default     = "C:/Users/yinya/.ssh/oci_vm.pub"
}

variable "block_volume_size_in_gbs" {
  description = "Size in GB of the extra block volume attached to the instance"
  type        = number
  default     = 50
}
