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

    runtime_config = var.runtime_config
    feature_gates  = var.feature_gates

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = var.ingress_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          protocol       = extra_port_mappings.value.protocol
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role = "worker"
      }
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
