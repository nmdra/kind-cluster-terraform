provider "kind" {}

provider "docker" {
  host = var.docker_host
}