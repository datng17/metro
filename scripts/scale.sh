#!/usr/bin/env bash
# Scales the whole metro-prod deployment to zero (down) or back to the
# Terraform values (up), and stops or starts RDS. `status` only reports.
#
# Reads the cluster, service start order, desired counts, RDS identifier and
# alarm names from `terraform output -json scale_config` in infra/envs/prod.
# Needs aws, terraform, jq and curl.
#
#   down: disable alarm actions -> desired_count 0 (business + gateway, then
#         eureka, rabbitmq, redis) -> wait until stable -> stop RDS.
#   up:   start RDS and wait until available -> redis, rabbitmq, eureka ->
#         business + gateway (Terraform desired counts) -> wait until stable ->
#         poll the public health URL -> enable alarm actions.
#
# Caveats:
#   - Terraform still owns desired_count. A `terraform apply` while scaled
#     down sets the counts back to the Terraform values (and needs RDS
#     running). To keep the business services and gateway at 0 through an
#     apply, pass -var business_desired_count=0 -var gateway_desired_count=0.
#   - AWS starts a stopped RDS instance automatically after 7 days.
#   - The ALB, fck-nat, Elastic IP and Cloud Map keep running (~$35/month).
#
# Usage: scripts/scale.sh up|down|status
set -euo pipefail

ACTION="${1:-}"
case "$ACTION" in
  up | down | status) ;;
  *)
    echo "Usage: $0 up|down|status" >&2
    exit 2
    ;;
esac

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
HEALTH_TIMEOUT_SECONDS="${HEALTH_TIMEOUT_SECONDS:-300}"
TF_DIR="$(cd "$(dirname "$0")/.." && pwd)/infra/envs/prod"

for tool in aws terraform jq curl; do
  command -v "$tool" >/dev/null || { echo "'$tool' is not on PATH" >&2; exit 1; }
done

cfg="$(terraform -chdir="$TF_DIR" output -json scale_config)"
cluster="$(jq -r .cluster <<<"$cfg")"
rds_id="$(jq -r .rds_identifier <<<"$cfg")"
health_url="$(jq -r .health_url <<<"$cfg")"
group_count="$(jq '.groups | length' <<<"$cfg")"
mapfile -t alarms < <(jq -r '.alarm_names[]' <<<"$cfg" | tr -d '\r')

step() { printf '\033[36m==> %s\033[0m\n' "$*"; }

# Services of group $1 (0-based), one per line.
group_services() { jq -r --argjson i "$1" '.groups[$i][]' <<<"$cfg" | tr -d '\r'; }
desired_count() { jq -r --arg s "$1" '.desired_counts[$s]' <<<"$cfg"; }
rds_status() {
  aws rds describe-db-instances --region "$REGION" --db-instance-identifier "$rds_id" \
    --query 'DBInstances[0].DBInstanceStatus' --output text
}

show_services() {
  aws ecs describe-services --region "$REGION" --cluster "$cluster" --services "$@" \
    --query 'services[].{service:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}' \
    --output table
}

# $1 = "zero" or "terraform", rest = services.
set_counts() {
  local mode="$1"
  shift
  local svc count
  for svc in "$@"; do
    count=0
    [[ "$mode" == "terraform" ]] && count="$(desired_count "$svc")"
    echo "    $svc -> desired_count $count"
    aws ecs update-service --region "$REGION" --cluster "$cluster" --service "$svc" \
      --desired-count "$count" --query 'service.serviceName' --output text >/dev/null
  done
}

# The waiter polls every 15 s for up to 10 minutes (max 10 services per call).
wait_stable() {
  echo "    waiting for: $*"
  if ! aws ecs wait services-stable --region "$REGION" --cluster "$cluster" --services "$@"; then
    show_services "$@"
    echo "Services did not become stable within 10 minutes. Check: aws ecs describe-services --cluster $cluster --services <name> --query 'services[0].events[0:5]'" >&2
    exit 1
  fi
}

set_alarm_actions() {
  [[ ${#alarms[@]} -eq 0 ]] && return 0
  aws cloudwatch "$1" --region "$REGION" --alarm-names "${alarms[@]}"
  echo "    $1 on ${#alarms[@]} alarms"
}

stop_rds() {
  local status
  status="$(rds_status)"
  case "$status" in
    available)
      aws rds stop-db-instance --region "$REGION" --db-instance-identifier "$rds_id" \
        --query 'DBInstance.DBInstanceStatus' --output text >/dev/null
      echo "    $rds_id is stopping (AWS restarts it automatically after 7 days)."
      ;;
    stopped | stopping) echo "    $rds_id is already $status." ;;
    *) echo "WARN: $rds_id is '$status'; it can only be stopped when 'available'. Run 'down' again later." >&2 ;;
  esac
}

start_rds() {
  local status deadline
  status="$(rds_status)"
  if [[ "$status" == "stopping" ]]; then
    echo "    $rds_id is stopping; waiting until it is stopped before starting it"
    deadline=$((SECONDS + 1200))
    while [[ "$status" == "stopping" ]]; do
      ((SECONDS > deadline)) && { echo "$rds_id is still stopping after 20 minutes" >&2; exit 1; }
      sleep 30
      status="$(rds_status)"
    done
  fi
  if [[ "$status" == "stopped" ]]; then
    aws rds start-db-instance --region "$REGION" --db-instance-identifier "$rds_id" \
      --query 'DBInstance.DBInstanceStatus' --output text >/dev/null
    echo "    $rds_id is starting"
  elif [[ "$status" != "available" ]]; then
    echo "    $rds_id is '$status'"
  fi
  echo "    waiting until RDS is available (about 5 minutes after a start)"
  aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$rds_id"
  echo "    $rds_id is available"
}

wait_healthy() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT_SECONDS)) code
  while true; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$health_url" || true)"
    if [[ "$code" == "200" ]]; then
      echo "    $health_url -> 200"
      return 0
    fi
    if ((SECONDS > deadline)); then
      echo "WARN: $health_url did not return 200 within ${HEALTH_TIMEOUT_SECONDS}s (last status: $code)." >&2
      return 0
    fi
    sleep 10
  done
}

case "$ACTION" in
  down)
    step "Disabling alarm actions (a stopped site would otherwise send alerts)"
    set_alarm_actions disable-alarm-actions

    # Reverse start order: business + gateway first, platform last.
    for ((i = group_count - 1; i >= 0; i--)); do
      mapfile -t svcs < <(group_services "$i")
      step "Scaling to 0: ${svcs[*]}"
      set_counts zero "${svcs[@]}"
      wait_stable "${svcs[@]}"
    done

    step "Stopping RDS $rds_id"
    stop_rds

    echo
    echo "Scaled down. Still billed: ALB, fck-nat + EIP, RDS storage, ECR, logs."
    echo "Note: a terraform apply now restores the Terraform desired counts."
    ;;

  up)
    step "Starting RDS $rds_id"
    start_rds

    for ((i = 0; i < group_count; i++)); do
      mapfile -t svcs < <(group_services "$i")
      step "Scaling up: ${svcs[*]}"
      set_counts terraform "${svcs[@]}"
      wait_stable "${svcs[@]}"
    done

    step "Checking $health_url"
    wait_healthy

    step "Enabling alarm actions"
    set_alarm_actions enable-alarm-actions

    echo
    echo "Scaled up."
    ;;

  status)
    step "ECS services in $cluster"
    for ((i = 0; i < group_count; i++)); do
      mapfile -t svcs < <(group_services "$i")
      show_services "${svcs[@]}"
    done

    step "RDS $rds_id"
    echo "    $(rds_status)"

    if [[ ${#alarms[@]} -gt 0 ]]; then
      step "Alarms"
      aws cloudwatch describe-alarms --region "$REGION" --alarm-names "${alarms[@]}" \
        --query 'MetricAlarms[].{alarm:AlarmName,state:StateValue,actions:ActionsEnabled}' --output table
    fi
    ;;
esac
