output "cluster_id" {
  description = "OCID of the OKE cluster."
  value       = oci_containerengine_cluster.this.id
}

output "cluster_kubernetes_version" {
  description = "Kubernetes version actually running on the control plane."
  value       = oci_containerengine_cluster.this.kubernetes_version
}

output "node_pool_id" {
  description = "OCID of the managed node pool."
  value       = oci_containerengine_node_pool.this.id
}

output "pod_network_type" {
  description = "The pod networking mode this cluster/node pool were created with."
  value       = var.pod_network_type
}
