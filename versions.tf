terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.11.0"
    }

    docker = {
      source  = "kreuzwerker/docker",
      version = "~> 4.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.0"
    }
  }

  required_version = "~> 1.15.0"
}

