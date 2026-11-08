# ---------------------------------------------------------------------------
# GitHub Actions -> AWS without stored keys.
#
# A workflow with `permissions: id-token: write` asks GitHub for a signed OIDC
# token (aud = sts.amazonaws.com, sub = repo:<owner>/<repo>:ref:refs/heads/<branch>).
# aws-actions/configure-aws-credentials exchanges it with
# sts:AssumeRoleWithWebIdentity for short-lived credentials of a role below.
#
#   deploy role: trusted only for pushes/dispatches on the deploy branch.
#                ECR push on the given repositories, register task definitions,
#                update the given ECS services, pass only the task roles.
#   plan role:   trusted only for pull_request runs. AWS ReadOnlyAccess, used
#                by infra-ci.yml for `terraform plan -lock=false`.
# ---------------------------------------------------------------------------
locals {
  oidc_host   = "token.actions.githubusercontent.com"
  deploy_sub  = "repo:${var.github_repository}:ref:refs/heads/${var.deploy_branch}"
  plan_sub    = "repo:${var.github_repository}:pull_request"
  oidc_arn    = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  oidc_issuer = "https://${local.oidc_host}"
}

# ---------------------------------------------------------------------------
# OIDC provider (one per account). AWS validates GitHub's certificate through
# its own trust store, so no thumbprint is pinned.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = local.oidc_issuer
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 0 : 1

  url = local.oidc_issuer
}

# ---------------------------------------------------------------------------
# Deploy role
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "deploy_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Exact match: other branches, tags, PRs, environments and forks are rejected.
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.deploy_sub]
    }
  }
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.name}-github-deploy"
  description          = "GitHub Actions deploy role for ${local.deploy_sub}"
  assume_role_policy   = data.aws_iam_policy_document.deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # this action does not support resource-level permissions
  }

  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImages",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = var.ecr_repository_arns
  }

  statement {
    sid = "TaskDefinitions"
    actions = [
      "ecs:DescribeTaskDefinition",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # these actions do not support resource-level permissions
  }

  statement {
    sid = "Services"
    actions = [
      "ecs:DescribeServices",
      "ecs:UpdateService",
    ]
    resources = var.ecs_service_arns
  }

  statement {
    sid       = "PassTaskRoles"
    actions   = ["iam:PassRole"]
    resources = var.pass_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "deploy" {
  name   = "deploy"
  role   = aws_iam_role.deploy.id
  policy = data.aws_iam_policy_document.deploy.json
}

# ---------------------------------------------------------------------------
# Plan role (pull requests). GitHub issues no OIDC token to workflows from
# fork PRs, so only branches of this repository can use it.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = [local.plan_sub]
    }
  }
}

resource "aws_iam_role" "plan" {
  count = var.enable_plan_role ? 1 : 0

  name                 = "${var.name}-github-plan"
  description          = "GitHub Actions read-only terraform plan role for ${local.plan_sub}"
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

resource "aws_iam_role_policy_attachment" "plan_readonly" {
  count = var.enable_plan_role ? 1 : 0

  role       = aws_iam_role.plan[0].name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}
