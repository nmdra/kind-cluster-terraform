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

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
  }
}