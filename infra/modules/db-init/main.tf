data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  family    = "${var.name}-db-init"
  container = "db-init"

  # Runs inside postgres:17 as `bash -c`. Idempotent: safe to run again, e.g.
  # after rotating the app password (it re-syncs the role password).
  # Connection settings come from PG* env vars; secrets are injected by ECS.
  script = <<-EOT
    set -euo pipefail
    echo "db-init: waiting for $PGHOST:$PGPORT"
    i=0
    until pg_isready -q; do
      i=$((i + 1))
      if [ "$i" -ge 30 ]; then echo "db-init: database not reachable"; exit 1; fi
      sleep 5
    done
    echo "db-init: connected as $PGUSER, server $(psql -XAtc 'SHOW server_version')"
    psql -X -v ON_ERROR_STOP=1 \
      -v app_user="$APP_DB_USER" \
      -v app_password="$APP_DB_PASSWORD" \
      -v databases="$DATABASES" <<'SQL'
    -- Application login role (services use it instead of the rotating master user).
    SELECT format('CREATE ROLE %I LOGIN', :'app_user')
    WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user')
    \gexec
    SELECT format('ALTER ROLE %I WITH LOGIN PASSWORD %L', :'app_user', :'app_password')
    \gexec
    -- PG16+: the master user must be able to SET ROLE to the owner of a new database.
    GRANT :"app_user" TO CURRENT_USER;

    -- One database per service, owned by the app role.
    SELECT format('CREATE DATABASE %I OWNER %I', d, :'app_user')
    FROM unnest(string_to_array(:'databases', ',')) AS d
    WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = d)
    \gexec
    SELECT format('ALTER DATABASE %I OWNER TO %I', d, :'app_user')
    FROM unnest(string_to_array(:'databases', ',')) AS d
    \gexec

    \echo 'db-init: service databases'
    SELECT d.datname AS database, pg_get_userbyid(d.datdba) AS owner, pg_encoding_to_char(d.encoding) AS encoding
    FROM pg_database d
    WHERE d.datname = ANY (string_to_array(:'databases', ','))
    ORDER BY 1;
    SQL
    echo "db-init: done"
  EOT
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}/db-init"
  retention_in_days = var.log_retention_days
}

# ---------------------------------------------------------------------------
# Execution role: write logs, read the two secrets. Nothing else.
# The image is pulled anonymously from ECR Public, so no ECR permissions.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${local.family}-execution"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  statement {
    sid       = "MasterSecret"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.master_user_secret_arn]
  }

  statement {
    sid       = "AppPassword"
    actions   = ["ssm:GetParameters"]
    resources = [var.app_password_parameter_arn]
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "db-init"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}

# ---------------------------------------------------------------------------
# Task definition (one-off, no ECS service). Run with `aws ecs run-task`.
# ---------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  family                   = local.family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name       = local.container
      image      = var.image
      essential  = true
      entryPoint = ["bash", "-c"]
      command    = [local.script]

      environment = [
        { name = "PGHOST", value = var.db_host },
        { name = "PGPORT", value = tostring(var.db_port) },
        { name = "PGDATABASE", value = "postgres" },
        { name = "PGSSLMODE", value = "require" },
        { name = "PGCONNECT_TIMEOUT", value = "10" },
        { name = "APP_DB_USER", value = var.app_db_username },
        { name = "DATABASES", value = join(",", var.databases) },
      ]

      # SSM / Secrets Manager -> env vars, resolved by ECS at task start.
      secrets = [
        { name = "PGUSER", valueFrom = "${var.master_user_secret_arn}:username::" },
        { name = "PGPASSWORD", valueFrom = "${var.master_user_secret_arn}:password::" },
        { name = "APP_DB_PASSWORD", valueFrom = var.app_password_parameter_arn },
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.this.name
          awslogs-region        = data.aws_region.current.region
          awslogs-stream-prefix = "db-init"
        }
      }
    }
  ])
}
