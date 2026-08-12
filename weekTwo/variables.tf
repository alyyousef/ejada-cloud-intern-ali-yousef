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

variable "subnet_tiers" {
  description = "One map entry per subnet. oci_core_subnet.tier uses for_each over this — adding a tier means adding a map entry, not a new resource block."
  type = map(object({
    cidr_block = string
    dns_label  = string
    is_public  = bool
  }))
  default = {
    public = {
      cidr_block = "10.1.1.0/24"
      dns_label  = "public"
      is_public  = true
    }
    private = {
      cidr_block = "10.1.2.0/24"
      dns_label  = "private"
      is_public  = false
    }
  }
}

variable "public_ingress_rules" {
  description = "Ingress rules for the public subnet security list (the load balancer lives here). Consumed by a dynamic \"ingress_security_rules\" block."
  type = list(object({
    description = string
    protocol    = string
    source      = string
    port_min    = number
    port_max    = number
  }))
  default = [
    {
      description = "Allow HTTP to the load balancer"
      protocol    = "6"
      source      = "0.0.0.0/0"
      port_min    = 80
      port_max    = 80
    }
  ]
}

variable "private_ingress_rules" {
  description = "Ingress rules for the private subnet security list (the compute instance lives here, no public IP). App traffic only from the load balancer's subnet, SSH only from within the VCN (reached via Bastion, never from the internet), NFS only from within the VCN for the File Storage mount."
  type = list(object({
    description = string
    protocol    = string
    source      = string
    port_min    = number
    port_max    = number
  }))
  default = [
    {
      description = "App traffic from the load balancer"
      protocol    = "6"
      source      = "10.1.1.0/24"
      port_min    = 8080
      port_max    = 8080
    },
    {
      description = "SSH via OCI Bastion (never exposed to the public internet)"
      protocol    = "6"
      source      = "10.1.0.0/16"
      port_min    = 22
      port_max    = 22
    },
    {
      description = "NFS TCP from within the VCN"
      protocol    = "6"
      source      = "10.1.0.0/16"
      port_min    = 111
      port_max    = 111
    },
    {
      description = "NFS UDP from within the VCN"
      protocol    = "17"
      source      = "10.1.0.0/16"
      port_min    = 111
      port_max    = 111
    },
    {
      description = "NFS/mount TCP from within the VCN"
      protocol    = "6"
      source      = "10.1.0.0/16"
      port_min    = 2048
      port_max    = 2050
    },
    {
      description = "NFS/mount UDP from within the VCN"
      protocol    = "17"
      source      = "10.1.0.0/16"
      port_min    = 2048
      port_max    = 2050
    }
  ]
}

variable "app_port" {
  description = "Port the application listens on inside the private instance. The load balancer's backend set forwards to this port."
  type        = number
  default     = 8080
}

variable "lb_min_bandwidth_mbps" {
  description = "Minimum bandwidth for the flexible-shape load balancer"
  type        = number
  default     = 10
}

variable "lb_max_bandwidth_mbps" {
  description = "Maximum bandwidth for the flexible-shape load balancer"
  type        = number
  default     = 10
}

variable "bastion_client_cidr_allow_list" {
  description = "CIDR blocks allowed to open Bastion sessions. Defaults to open for lab convenience — narrow this to your own IP (x.x.x.x/32) for anything beyond a throwaway lab."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "bastion_max_session_ttl_in_seconds" {
  description = "Max lifetime of a Bastion session before it must be recreated. OCI's hard ceiling is 10800 (3 hours)."
  type        = number
  default     = 10800
}
