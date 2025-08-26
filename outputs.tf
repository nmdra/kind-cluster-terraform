output "kubeconfig_path" {
  description = "Path to the kubeconfig file for the Kind cluster"
  value       = pathexpand(var.kind_cluster_config_path)
}

output "cluster_name" {
  description = "Name of the Kind cluster"
  value       = kind_cluster.default.name
}