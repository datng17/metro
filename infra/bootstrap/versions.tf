terraform {
  required_version = "~> 1.16.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Intentionally no backend block: the bootstrap stack keeps LOCAL state
  # (terraform.tfstate in this folder). It is applied once to create the
  # bucket that every other stack uses as its remote backend.
}
