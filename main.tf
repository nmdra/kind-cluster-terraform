resource "random_pet" "cluster" {
  length    = 2
  separator = "-"
}

locals {
  base_cluster_name = var.kind_cluster_name != "" ? var.kind_cluster_name : random_pet.cluster.id
  cluster_name      = var.enable_ingress_lb ? "${local.base_cluster_name}-ing" : local.base_cluster_name

  feature_gates  = var.enable_feature_gates ? var.feature_gates : {}
  runtime_config = var.enable_runtime_config ? var.runtime_config : {}
}

resource "kind_cluster" "default" {
  name            = local.cluster_name
  node_image      = var.kind_cluster_node_image
  kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    runtime_config = local.runtime_config
    feature_gates  = local.feature_gates

    dynamic "node" {
      for_each = range(var.control_plane_node_count)
      content {
        role                   = "control-plane"
        kubeadm_config_patches = var.kubeadm_config_patches

        dynamic "extra_port_mappings" {
          for_each = node.value == 0 ? var.ingress_port_mappings : []
          content {
            container_port = extra_port_mappings.value.container_port
            host_port      = extra_port_mappings.value.host_port
            protocol       = extra_port_mappings.value.protocol
          }
        }

        dynamic "extra_mounts" {
          for_each = var.extra_mounts
          content {
            host_path       = extra_mounts.value.host_path
            container_path  = extra_mounts.value.container_path
            read_only       = extra_mounts.value.read_only
            propagation     = extra_mounts.value.propagation
            selinux_relabel = extra_mounts.value.selinux_relabel
          }
        }
      }
    }

    dynamic "node" {
      for_each = range(var.worker_node_count)
      content {
        role                   = "worker"
        kubeadm_config_patches = var.kubeadm_config_patches

        dynamic "extra_mounts" {
          for_each = var.extra_mounts
          content {
            host_path       = extra_mounts.value.host_path
            container_path  = extra_mounts.value.container_path
            read_only       = extra_mounts.value.read_only
            propagation     = extra_mounts.value.propagation
            selinux_relabel = extra_mounts.value.selinux_relabel
          }
        }
      }
    }
  }
}

resource "terraform_data" "set_kubectl_context" {
  input = {
    cluster_name    = kind_cluster.default.name
    kubeconfig_path = pathexpand(var.kind_cluster_config_path)
  }

  triggers_replace = [
    kind_cluster.default.name,
    kind_cluster.default.kubeconfig_path
  ]

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

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      CLUSTER_NAME="${self.output.cluster_name}"
      KUBECONFIG_PATH="${self.output.kubeconfig_path}"

      echo "Cleaning up kubectl context for cluster: $CLUSTER_NAME"

      # Delete the custom short-name context (e.g., "driving-yak")
      kubectl config delete-context "$CLUSTER_NAME" \
        --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null && \
        echo "Deleted context: $CLUSTER_NAME" || \
        echo "Context $CLUSTER_NAME not found (already removed)"

      # Delete the Kind-prefixed context if still present (e.g., "kind-driving-yak")
      kubectl config delete-context "kind-$CLUSTER_NAME" \
        --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null && \
        echo "Deleted context: kind-$CLUSTER_NAME" || \
        echo "Context kind-$CLUSTER_NAME not found (already removed)"

      # Clean up orphaned cluster entry
      kubectl config delete-cluster "kind-$CLUSTER_NAME" \
        --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null && \
        echo "Deleted cluster: kind-$CLUSTER_NAME" || \
        echo "Cluster kind-$CLUSTER_NAME not found (already removed)"

      # Clean up orphaned user entry
      kubectl config delete-user "kind-$CLUSTER_NAME" \
        --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null && \
        echo "Deleted user: kind-$CLUSTER_NAME" || \
        echo "User kind-$CLUSTER_NAME not found (already removed)"

      # If the current-context pointed to the deleted cluster, unset it
      CURRENT_CTX=$(kubectl config current-context --kubeconfig="$KUBECONFIG_PATH" 2>/dev/null || echo "")
      if [ "$CURRENT_CTX" = "$CLUSTER_NAME" ] || [ "$CURRENT_CTX" = "kind-$CLUSTER_NAME" ]; then
        kubectl config unset current-context --kubeconfig="$KUBECONFIG_PATH"
        echo "Unset current-context (was: $CURRENT_CTX)"
      fi

      echo "Kubeconfig cleanup complete."
    EOT
  }
}

resource "docker_image" "cloud_provider" {
  count        = var.enable_ingress_lb ? 1 : 0
  name         = "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.10.0"
  keep_locally = true
}

resource "docker_container" "cloud_provider" {
  count      = var.enable_ingress_lb ? 1 : 0
  depends_on = [docker_image.cloud_provider, kind_cluster.default]

  image = docker_image.cloud_provider[count.index].image_id
  name  = "cloud-provider-kind"

  network_mode = "kind"
  restart      = "on-failure"

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
}
