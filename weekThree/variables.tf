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
  description = "OCID of the compartment where all Week 3 resources will be created (intern-02-ali-youssef-cmp)."
  type        = string
}

variable "vcn_cidr_block" {
  description = "CIDR block for the Week 3 VCN. Sized to comfortably fit endpoint, worker, pod, and LB subnets."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vcn_dns_label" {
  description = "DNS label for the VCN."
  type        = string
  default     = "oketflab"
}

variable "endpoint_subnet_cidr" {
  description = "CIDR block for the OKE API endpoint subnet."
  type        = string
  default     = "10.0.0.0/28"
}

variable "workers_subnet_cidr" {
  description = "CIDR block for the worker node subnet."
  type        = string
  default     = "10.0.16.0/20"
}

variable "pods_subnet_cidr" {
  description = "CIDR block for the pod subnet (needs to be large - VCN-native pod networking assigns each pod a real VCN IP)."
  type        = string
  default     = "10.0.32.0/19"
}

variable "lb_subnet_cidr" {
  description = "CIDR block for the (public) load balancer subnet."
  type        = string
  default     = "10.0.8.0/24"
}

variable "enable_flow_logs" {
  description = "Whether to enable VCN flow logs ('Enable Logs') on every subnet created this week."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Display name for the OKE cluster."
  type        = string
  default     = "tf-lab-oke-AliYousef"
}

variable "is_endpoint_public" {
  description = "Whether the Kubernetes API endpoint gets a public IP. Defaulted to true so kubectl works directly from a local machine outside the VCN for this lab - flip to false and access via Cloud Shell / a bastion / VPN instead for anything beyond a lab environment."
  type        = bool
  default     = true
}

variable "node_pool_size" {
  description = "Number of worker nodes in the managed node pool."
  type        = number
  default     = 2
}

variable "node_shape" {
  description = "Compute shape for worker nodes."
  type        = string
  default     = "VM.Standard.E4.Flex"
}

variable "node_ocpus" {
  description = "OCPUs per worker node (only used when node_shape is a flex shape)."
  type        = number
  default     = 2
}

variable "node_memory_in_gbs" {
  description = "Memory (GB) per worker node (only used when node_shape is a flex shape)."
  type        = number
  default     = 16
}

variable "node_boot_volume_size_in_gbs" {
  description = "Boot volume size, in GB, for each worker node."
  type        = number
  default     = 50
}

variable "max_pods_per_node" {
  description = "Maximum pods per worker node under VCN-native pod networking."
  type        = number
  default     = 31
}

variable "ssh_public_key_path" {
  description = "Local path to the SSH public key installed on worker nodes."
  type        = string
  default     = "C:/Users/yinya/.ssh/oci_vm.pub"
}

variable "app_block_volume_size_in_gbs" {
  description = "Size, in GB, of the block volume attached to the application via a PersistentVolumeClaim."
  type        = number
  default     = 50
}

variable "freeform_tags" {
  description = "Freeform tags applied across every resource created this week."
  type        = map(string)
  default = {
    project = "ejada-internship-week3"
    owner   = "ali-yousef"
  }
}
