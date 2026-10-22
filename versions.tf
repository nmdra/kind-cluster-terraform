terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }

    docker = {
      source  = "kreuzwerker/docker",
      version = "~> 4.6.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.9.1"
    }
  }

  required_version = "~> 1.15.0"
}

