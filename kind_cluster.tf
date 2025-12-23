resource "random_pet" "cluster" {
  length    = 2
  separator = "-"
}

locals {
  base_cluster_name = var.kind_cluster_name != "" ? var.kind_cluster_name : random_pet.cluster.id
  cluster_name      = var.enable_ingress_lb ? "${local.base_cluster_name}-ing" : local.base_cluster_name
}

resource "kind_cluster" "default" {
  name            = local.cluster_name
  node_image      = var.kind_cluster_node_image
  kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 80
        host_port      = 30080
        protocol = "TCP"
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 30443
        protocol = "TCP"
      }
    }

    node {
      role = "worker"
    }
  }
}

resource "null_resource" "set_kubectl_context" {
  depends_on = [kind_cluster.default]

  provisioner "local-exec" {
    command = <<EOT
      kubectl config set-context ${kind_cluster.default.name} \
        --cluster=kind-${kind_cluster.default.name} \
        --user=kind-${kind_cluster.default.name} \
        --kubeconfig=${pathexpand(var.kind_cluster_config_path)}

      kubectl config use-context ${kind_cluster.default.name} \
        --kubeconfig=${pathexpand(var.kind_cluster_config_path)}

      echo "Switched kubectl to context: ${kind_cluster.default.name}"
    EOT
  }
}
