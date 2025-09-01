variable "kind_cluster_name" {
  type        = string
  description = "The name of the cluster."
  default     = ""
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

variable "kind_cluster_ingress" {
  type        = bool
  description = "Enable ingress controller"
  default     = false
}
