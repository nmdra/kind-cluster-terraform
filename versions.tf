terraform {
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.4"
    }

    random = {
      source = "hashicorp/random"
      version = "~> 3.7.2"
    }
  }

  required_version = "~> 1.12.1"
}

