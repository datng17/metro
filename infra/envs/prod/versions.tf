terraform {
  required_version = "~> 1.16.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }

  # Partial backend configuration. The bucket name is supplied at init time:
  #   terraform init -backend-config=backend.hcl
  # (copy backend.hcl.example -> backend.hcl). Locking uses an S3 lock file
  # (use_lockfile), so no DynamoDB table is needed.
  backend "s3" {
    key          = "prod/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
