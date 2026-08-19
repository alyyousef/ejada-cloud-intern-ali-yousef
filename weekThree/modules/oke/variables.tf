variable "compartment_id" {
  description = "OCID of the compartment where the cluster and node pool will be created."
  type        = string
}

variable "vcn_id" {
  description = "OCID of the VCN the cluster runs in."
  type        = string
}

variable "cluster_name" {
  description = "Display name for the OKE cluster."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for both the control plane and the node pool, e.g. \"v1.30.1\". Use the oci_containerengine_cluster_option data source from the root config to look up currently supported versions instead of hardcoding one here."
  type        = string
}

variable "cluster_type" {
  description = "\"BASIC_CLUSTER\" or \"ENHANCED_CLUSTER\". Enhanced is required for features such as customer-managed control plane encryption or advanced add-ons."
  type        = string
  default     = "BASIC_CLUSTER"

  validation {
    condition     = contains(["BASIC_CLUSTER", "ENHANCED_CLUSTER"], var.cluster_type)
    error_message = "cluster_type must be \"BASIC_CLUSTER\" or \"ENHANCED_CLUSTER\"."
  }
}

variable "endpoint_subnet_id" {
  description = "OCID of the (regional) subnet the Kubernetes API endpoint is placed in."
  type        = string
}

variable "is_endpoint_public" {
  description = "Whether the Kubernetes API endpoint gets a public IP. false keeps the control plane reachable only from inside the VCN (e.g. via a bastion or VPN)."
  type        = bool
  default     = false
}

variable "endpoint_nsg_ids" {
  description = "NSG OCIDs applied to the API endpoint VNIC. Empty list = rely on the endpoint subnet's security list only."
  type        = list(string)
  default     = []
}

variable "pod_network_type" {
  description = "\"VCN_NATIVE\" (recommended - pods get real VCN IPs from pod_subnet_ids) or \"FLANNEL_OVERLAY\" (legacy overlay network)."
  type        = string
  default     = "VCN_NATIVE"

  validation {
    condition     = contains(["VCN_NATIVE", "FLANNEL_OVERLAY"], var.pod_network_type)
    error_message = "pod_network_type must be \"VCN_NATIVE\" or \"FLANNEL_OVERLAY\"."
  }
}

variable "pod_subnet_ids" {
  description = "Subnet OCID(s) pods draw IPs from. Required when pod_network_type = \"VCN_NATIVE\", ignored otherwise."
  type        = list(string)
  default     = []
}

variable "pod_nsg_ids" {
  description = "NSG OCIDs applied to pod VNICs. Only used when pod_network_type = \"VCN_NATIVE\"."
  type        = list(string)
  default     = []
}

variable "max_pods_per_node" {
  description = "Maximum pods per worker node. Only used when pod_network_type = \"VCN_NATIVE\"."
  type        = number
  default     = 31
}

variable "pods_cidr" {
  description = "CIDR block for the Kubernetes pod overlay network. Only meaningful when pod_network_type = \"FLANNEL_OVERLAY\"."
  type        = string
  default     = "10.244.0.0/16"
}

variable "services_cidr" {
  description = "CIDR block for Kubernetes ClusterIP services."
  type        = string
  default     = "10.96.0.0/16"
}

variable "service_lb_subnet_ids" {
  description = "Subnet OCID(s) OKE is allowed to provision LoadBalancer-type Service load balancers into."
  type        = list(string)
}

variable "enable_kubernetes_dashboard" {
  description = "Whether to enable the Kubernetes dashboard add-on."
  type        = bool
  default     = false
}

variable "enable_pod_security_policy" {
  description = "Whether to enable the pod security policy admission controller."
  type        = bool
  default     = false
}

variable "node_pool_name" {
  description = "Display name for the managed node pool."
  type        = string
}

variable "node_shape" {
  description = "Compute shape for worker nodes, e.g. \"VM.Standard.E4.Flex\"."
  type        = string
}

variable "node_shape_config" {
  description = "Only required for flex shapes. { ocpus = number, memory_in_gbs = number }. Leave null for fixed shapes."
  type = object({
    ocpus         = number
    memory_in_gbs = number
  })
  default = null
}

variable "node_image_id" {
  description = "OCID of the worker node image (an OKE-compatible platform image, looked up in the root config via a data source - do not hardcode)."
  type        = string
}

variable "boot_volume_size_in_gbs" {
  description = "Boot volume size, in GB, for each worker node."
  type        = number
  default     = 50
}

variable "node_pool_size" {
  description = "Number of worker nodes in the pool."
  type        = number
  default     = 2
}

variable "node_placement_configs" {
  description = <<-EOT
    One entry per availability domain / subnet combination worker nodes should be
    spread across. Each object:
      availability_domain  AD name, e.g. "oXVt:ME-JEDDAH-1-AD-1"
      subnet_id             OCID of the worker node subnet in that AD
  EOT
  type = list(object({
    availability_domain = string
    subnet_id            = string
  }))
}

variable "ssh_public_key" {
  description = "SSH public key installed on worker nodes. Empty string disables SSH access."
  type        = string
  default     = ""
}

variable "node_pool_freeform_tags" {
  description = "Freeform tags applied to worker nodes themselves (separate from the pool/cluster tags, since OCI tracks them independently)."
  type        = map(string)
  default     = {}
}

variable "freeform_tags" {
  description = "Freeform tags applied to the cluster and node pool resources."
  type        = map(string)
  default     = {}
}
