# These tests only plan with mocked providers. They never create a cluster.
mock_provider "kind" {
  override_during = plan
  mock_resource "kind_cluster" {
    defaults = {
      context_name = "kind-upgrade-test"
    }
  }
}
mock_provider "docker" {}
mock_provider "random" {}

variables {
  kind_cluster_name = "upgrade-test"
}

run "published_kubernetes_default" {
  command = plan

  assert {
    condition     = kind_cluster.default.node_image == "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"
    error_message = "Use the Kubernetes 1.37.0 image published for Kind 0.33.0."
  }
}

run "no_local_images_by_default" {
  command = plan
  assert {
    condition     = length(kind_load.local_images) == 0
    error_message = "Image loading must be opt-in."
  }
}

run "two_local_images" {
  command = plan
  variables {
    local_images = ["frontend:dev-1", "backend:dev-1"]
  }
  assert {
    condition = (
      length(kind_load.local_images) == 2 &&
      kind_load.local_images["frontend:dev-1"].image == "frontend:dev-1" &&
      kind_load.local_images["backend:dev-1"].image == "backend:dev-1" &&
      alltrue([for load in kind_load.local_images : load.cluster_name == "upgrade-test"])
    )
    error_message = "Load each requested local image into the selected cluster."
  }
}

run "networking_disabled_by_default" {
  command = plan
  assert {
    condition     = length(docker_image.cloud_provider) == 0 && length(docker_container.cloud_provider) == 0
    error_message = "The controller must remain opt-in."
  }
}

run "standard_controller" {
  command = plan
  variables {
    enable_ingress_lb = true
  }
  assert {
    condition     = docker_image.cloud_provider[0].name == "registry.k8s.io/cloud-provider-kind/cloud-controller-manager:v0.12.0"
    error_message = "Use the approved controller release."
  }
  assert {
    condition     = docker_container.cloud_provider[0].command == tolist(["--gateway-channel=standard"])
    error_message = "Use the standard channel without connectivity override flags."
  }
}

run "canonical_context" {
  command = plan

  assert {
    condition     = output.cluster_context == "kind-upgrade-test"
    error_message = "Expose the provider-reported canonical context."
  }
}

run "custom_tag" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:custom"
  }
  assert {
    condition     = kind_cluster.default.node_image == "kindest/node:custom"
    error_message = "Preserve the supplied custom image reference."
  }
}

run "registry_port" {
  command = plan
  variables {
    kind_cluster_node_image = "localhost:5000/node:dev"
  }
  assert {
    condition     = kind_cluster.default.node_image == "localhost:5000/node:dev"
    error_message = "Preserve the supplied custom image reference."
  }
}

run "registry_host" {
  command = plan
  variables {
    kind_cluster_node_image = "registry.example.com/team/node:dev"
  }
  assert {
    condition     = kind_cluster.default.node_image == "registry.example.com/team/node:dev"
    error_message = "Preserve the supplied custom image reference."
  }
}

run "pinned_custom_image" {
  command = plan
  variables {
    kind_cluster_node_image = "localhost:5000/node:dev@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  assert {
    condition     = kind_cluster.default.node_image == "localhost:5000/node:dev@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "Preserve the supplied custom image reference."
  }
}

run "empty_image" {
  command = plan
  variables {
    kind_cluster_node_image = ""
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "missing_tag" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "empty_tag" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "image_whitespace" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:dev latest"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "short_digest" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:dev@sha256:abc"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "invalid_digest" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:dev@sha256:zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "unsupported_digest" {
  command = plan
  variables {
    kind_cluster_node_image = "kindest/node:dev@sha512:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }
  expect_failures = [var.kind_cluster_node_image]
}

run "experimental_gateway_channel" {
  command = plan
  variables {
    enable_ingress_lb                   = true
    cloud_provider_kind_gateway_channel = "experimental"
  }
  assert {
    condition     = docker_container.cloud_provider[0].command == tolist(["--gateway-channel=experimental"])
    error_message = "Forward the selected Gateway channel."
  }
}

run "disabled_gateway_channel" {
  command = plan
  variables {
    enable_ingress_lb                   = true
    cloud_provider_kind_gateway_channel = "disabled"
  }
  assert {
    condition     = docker_container.cloud_provider[0].command == tolist(["--gateway-channel=disabled"])
    error_message = "Forward the selected Gateway channel."
  }
}

run "blank_local_image" {
  command = plan
  variables {
    local_images = ["   "]
  }
  expect_failures = [var.local_images]
}
run "blank_controller_image" {
  command = plan
  variables {
    cloud_provider_kind_image = "  "
  }
  expect_failures = [var.cloud_provider_kind_image]
}
run "invalid_gateway_channel" {
  command = plan
  variables {
    cloud_provider_kind_gateway_channel = "latest"
  }
  expect_failures = [var.cloud_provider_kind_gateway_channel]
}
