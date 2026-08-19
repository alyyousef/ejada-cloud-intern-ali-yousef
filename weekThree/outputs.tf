output "vcn_id" {
  description = "OCID of the Week 3 VCN."
  value       = oci_core_vcn.this.id
}

output "endpoint_subnet_id" {
  value = module.endpoint_subnet.subnet_id
}

output "workers_subnet_id" {
  value = module.workers_subnet.subnet_id
}

output "pods_subnet_id" {
  value = module.pods_subnet.subnet_id
}

output "lb_subnet_id" {
  value = module.lb_subnet.subnet_id
}

output "cluster_id" {
  description = "OCID of the OKE cluster - needed for `oci ce cluster create-kubeconfig`."
  value       = module.oke.cluster_id
}

output "cluster_kubernetes_version" {
  value = module.oke.cluster_kubernetes_version
}

output "node_pool_id" {
  value = module.oke.node_pool_id
}

output "kubeconfig_command" {
  description = "Command to fetch a kubeconfig for this cluster once it's up."
  value       = "oci ce cluster create-kubeconfig --cluster-id ${module.oke.cluster_id} --file $HOME/.kube/config --region ${var.region} --token-version 2.0.0"
}

output "debug_selected_node_image" {
  description = "Diagnostic only: which image name got picked for worker nodes."
  value       = sort(keys(local.oke_worker_images))[length(local.oke_worker_images) - 1]
}

output "debug_used_version_tagged_pool" {
  description = "Diagnostic only: true if a Kubernetes-version-matched image was found and used (expected), false if it fell back to newest-overall."
  value       = length(local.oke_version_tagged_images) > 0
}

output "debug_available_worker_images" {
  description = "Diagnostic only: every general-purpose x86 OL8 image name that was a candidate (GPU/aarch64 already excluded). If node pool creation still fails on image compatibility, check this list."
  value       = sort(keys(local.oke_worker_candidates))
}
