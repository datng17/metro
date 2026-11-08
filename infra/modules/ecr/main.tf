# ---------------------------------------------------------------------------
# One private repository per service: <prefix>/<service>
# ---------------------------------------------------------------------------
resource "aws_ecr_repository" "this" {
  for_each = var.services

  name                 = "${var.repository_prefix}/${each.key}"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = var.force_delete

  # Basic scanning (free): every pushed image is scanned for OS package CVEs.
  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = {
    Name    = "${var.repository_prefix}/${each.key}"
    Service = each.key
  }
}

# ---------------------------------------------------------------------------
# Lifecycle: keep only the N most recent images (tagged or untagged)
# ---------------------------------------------------------------------------
resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep the last ${var.max_image_count} images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
