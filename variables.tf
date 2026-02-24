variable "kind_cluster_name" {
  type        = string
  description = "The name of the cluster."
  default     = ""
}

variable "kind_cluster_node_image" {
  type        = string
  description = "The node image/version to use"
  default     = "kindest/node:v1.35.0"
}

variable "kind_cluster_config_path" {
  type        = string
  description = "The location where this cluster's kubeconfig will be saved to."
  default     = "~/.kube/config"
}

variable "worker_node_count" {
  type        = number
  description = "The number of worker nodes to create in the cluster."
  default     = 1
}

variable "runtime_config" {
  type        = map(string)
  description = "Kubernetes runtime configuration to enable/disable specific API groups."
}

variable "feature_gates" {
  type        = map(bool)
  description = "Map of Kubernetes feature gates to enable/disable."
}

variable "enable_ingress_lb" {
  type        = bool
  description = "Enable ingress and load balancer support."
  default     = false
}

variable "ingress_port_mappings" {
  type = list(object({
    container_port = number
    host_port      = number
    protocol       = string
  }))
  description = "List of port mappings to expose on the control-plane node"
  default = [
    {
      container_port = 80
      host_port      = 30082
      protocol       = "TCP"
    },
    {
      container_port = 443
      host_port      = 30443
      protocol       = "TCP"
    }
  ]
}