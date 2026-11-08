# ---------------------------------------------------------------------------
# Task 9: GitHub Actions OIDC roles for CI/CD (no AWS keys in GitHub).
#
# The CD workflows deploy the 9 application services (eureka, gateway and the
# business services). redis and rabbitmq use public images and stay
# Terraform-only, so the deploy role cannot update them or pass their roles.
# ---------------------------------------------------------------------------
locals {
  deployable_services = concat([module.eureka, module.gateway], [for k in sort(keys(module.business)) : module.business[k]])
}

module "github_oidc" {
  source = "../../modules/github-oidc"

  name                  = var.name
  github_repository     = var.github_repository
  github_subject_prefix = var.github_subject_prefix
  deploy_branch         = var.github_deploy_branch
  create_oidc_provider  = var.github_create_oidc_provider
  enable_plan_role      = var.github_enable_plan_role

  ecr_repository_arns = [for svc in sort(keys(module.ecr.repository_arns)) : module.ecr.repository_arns[svc]]
  ecs_service_arns    = [for m in local.deployable_services : m.service_arn]
  pass_role_arns      = flatten([for m in local.deployable_services : [m.execution_role_arn, m.task_role_arn]])
}
