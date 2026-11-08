provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "metro"
      Env       = "prod"
      ManagedBy = "terraform"
    }
  }
}
