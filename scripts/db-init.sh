#!/usr/bin/env bash
# Runs the one-off db-init ECS task, waits for it to stop, prints its CloudWatch
# logs and exits with the container's exit code.
#
# Reads cluster, subnets, security group, task definition and log group from
# `terraform output` in infra/envs/prod (run terraform apply first). Needs jq.
# db-init is idempotent: it creates the app role and the service databases if
# missing and re-syncs the app role password from /metro/DB_PASSWORD.
#
# Usage: scripts/db-init.sh
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)/infra/envs/prod"

for tool in aws terraform jq; do
  command -v "$tool" >/dev/null || { echo "'$tool' is not on PATH" >&2; exit 1; }
done

tf_json="$(terraform -chdir="$TF_DIR" output -json)"
cluster="$(jq -r .ecs_cluster_name.value <<<"$tf_json")"
task_def="$(jq -r .db_init_task_definition_arn.value <<<"$tf_json")"
log_group="$(jq -r .db_init_log_group.value <<<"$tf_json")"
subnets="$(jq -r '.private_app_subnet_ids.value | join(",")' <<<"$tf_json")"
sg="$(jq -r .ecs_tasks_security_group_id.value <<<"$tf_json")"

echo "==> Starting $task_def on cluster $cluster"
task_arn="$(aws ecs run-task --region "$REGION" --cluster "$cluster" --task-definition "$task_def" \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$sg],assignPublicIp=DISABLED}" \
  --query 'tasks[0].taskArn' --output text)"
if [[ -z "$task_arn" || "$task_arn" == "None" ]]; then
  echo "run-task did not return a task ARN" >&2
  exit 1
fi
task_id="${task_arn##*/}"
echo "==> Task $task_id started, waiting for it to stop (pull + run takes 1-2 minutes)"

aws ecs wait tasks-stopped --region "$REGION" --cluster "$cluster" --tasks "$task_arn"

echo "==> Logs ($log_group, stream db-init/db-init/$task_id)"
aws logs tail "$log_group" --region "$REGION" --log-stream-names "db-init/db-init/$task_id" \
  --since 1h --format short || echo "WARN: could not read the logs" >&2

read -r exit_code reason < <(aws ecs describe-tasks --region "$REGION" --cluster "$cluster" --tasks "$task_arn" \
  --query 'tasks[0].[containers[0].exitCode, stoppedReason]' --output text)

echo
echo "Stopped reason: $reason"
if [[ "$exit_code" == "None" ]]; then
  echo "Exit code: none (the container never ran)"
  exit 1
fi
echo "Exit code: $exit_code"
exit "$exit_code"
