variable "kind_cluster_name" {
  type        = string
  description = "The name of the cluster. If empty, a random name is generated."
  default     = ""
}

variable "kind_cluster_node_image" {
  type        = string
  description = "The node image/version to use."
  default     = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"

  validation {
    condition     = can(regex("^([a-zA-Z0-9.-]+:[0-9]+/)?[a-zA-Z0-9._-]+(/[a-zA-Z0-9._-]+)*:[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}(@sha256:[a-fA-F0-9]{64})?$", var.kind_cluster_node_image))
    error_message = "Use a tagged image reference, optionally pinned with @sha256:<64 hex digits> (e.g., kindest/node:custom or localhost:5000/node:dev)."
  }
}

variable "local_images" {
  type        = set(string)
  description = "Images already in local Docker to load into every cluster node. Use versioned tags; rebuilt tags require explicit replacement."
  default     = []

  validation {
    condition     = alltrue([for image in var.local_images : trimspace(image) != ""])
    error_message = "Each local image must be a nonempty image reference."
  }
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

  validation {
    condition     = var.worker_node_count >= 0
    error_message = "The worker_node_count must be 0 or greater."
  }
}

variable "control_plane_node_count" {
  type        = number
  description = "The number of control-plane nodes to create in the cluster. Use 1 for a standard setup or 3+ for HA (high availability)."
  default     = 1

  validation {
    condition     = var.control_plane_node_count >= 1
    error_message = "The control_plane_node_count must be 1 or greater. A cluster requires at least one control-plane node."
  }
}

variable "enable_feature_gates" {
  type        = bool
  description = "Flag to enable custom Kubernetes feature gates configured in var.feature_gates."
  default     = false
}

variable "feature_gates" {
  type        = map(bool)
  description = "Map of Kubernetes feature gates to enable/disable. Only applied if var.enable_feature_gates is true."
  default     = {}
}

variable "enable_runtime_config" {
  type        = bool
  description = "Flag to enable custom Kubernetes runtime configurations configured in var.runtime_config."
  default     = false
}

variable "runtime_config" {
  type        = map(string)
  description = "Kubernetes runtime configuration to enable/disable specific API groups. Only applied if var.enable_runtime_config is true."
  default     = {}
}

variable "enable_ingress_lb" {
  type        = bool
  description = "Enable ingress and load balancer support."
  default     = false
}

variable "cloud_provider_kind_image" {
  type        = string
  description = "Versioned cloud-provider-kind controller image. Used only when enable_ingress_lb is true."
  default     = "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0"

  validation {
    condition     = trimspace(var.cloud_provider_kind_image) != ""
    error_message = "The cloud-provider-kind image must not be empty."
  }
}

variable "cloud_provider_kind_gateway_channel" {
  type        = string
  description = "Gateway API channel: standard, experimental, or disabled. Disabling Gateway also disables bundled Ingress translation."
  default     = "standard"

  validation {
    condition     = contains(["standard", "experimental", "disabled"], var.cloud_provider_kind_gateway_channel)
    error_message = "Gateway channel must be standard, experimental, or disabled."
  }
}

variable "ingress_port_mappings" {
  type = list(object({
    container_port = number
    host_port      = number
    protocol       = string
  }))
  description = "List of port mappings to expose on the control-plane node."
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

  validation {
    condition = alltrue([
      for mapping in var.ingress_port_mappings : (
        mapping.container_port > 0 && mapping.container_port <= 65535 &&
        mapping.host_port > 0 && mapping.host_port <= 65535 &&
        contains(["TCP", "UDP"], upper(mapping.protocol))
      )
    ])
    error_message = "All port mappings must have ports between 1 and 65535, and the protocol must be either 'TCP' or 'UDP'."
  }
}

variable "docker_host" {
  type        = string
  description = "The Docker daemon socket or TCP host URI. Used by the Docker provider."
  default     = "unix:///var/run/docker.sock"
}

variable "kubeadm_config_patches" {
  type        = list(string)
  description = "A list of kubeadm config patches to apply to all nodes in the cluster."
  default     = []
}

variable "extra_mounts" {
  type = list(object({
    host_path       = string
    container_path  = string
    read_only       = optional(bool, false)
    propagation     = optional(string)
    selinux_relabel = optional(bool)
  }))
  description = "A list of extra mounts to apply to the nodes."
  default     = []
}

