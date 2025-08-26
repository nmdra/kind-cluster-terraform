variable "kind_cluster_name" {
  type        = string
  description = "The name of the cluster."
  default     = "kind-cluster-tf"
}

variable "kind_cluster_node_image" {
  type        = string
  description = "node image/version"
  default     = "kindest/node:v1.33.1"
}

variable "kind_cluster_config_path" {
  type        = string
  description = "The location where this cluster's kubeconfig will be saved to."
  default     = "~/.kube/config"
}
