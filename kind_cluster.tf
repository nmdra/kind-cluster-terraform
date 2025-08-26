provider "kind" {}

resource "kind_cluster" "default" {
  name            = var.kind_cluster_name
  node_image      = var.kind_cluster_node_image
  kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      kubeadm_config_patches = [
        "kind: InitConfiguration\nnodeRegistration:\n  kubeletExtraArgs:\n    node-labels: \"ingress-ready=true\"\n"
      ]

      extra_port_mappings {
        container_port = 80
        host_port      = 80
      }

      extra_port_mappings {
        container_port = 443
        host_port      = 443
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