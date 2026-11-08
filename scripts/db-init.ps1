<#
.SYNOPSIS
  Runs the one-off db-init ECS task, waits for it to stop, prints its CloudWatch
  logs and exits with the container's exit code.
.DESCRIPTION
  Reads cluster, subnets, security group, task definition and log group from
  `terraform output` in infra/envs/prod (run terraform apply first).
  db-init is idempotent: it creates the app role and the service databases if
  missing and re-syncs the app role password from /metro/DB_PASSWORD.
  Compatible with Windows PowerShell 5.1 and PowerShell 7.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\db-init.ps1
#>
[CmdletBinding()]
param(
  [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { 'us-east-1' })
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Runs a native command and throws if it exits non-zero. Returns its stdout.
function Invoke-Native {
  $exe = $args[0]
  $rest = @()
  if ($args.Count -gt 1) { $rest = $args[1..($args.Count - 1)] }
  $out = & $exe @rest
  if ($LASTEXITCODE -ne 0) {
    throw "'$exe $($rest -join ' ')' failed with exit code $LASTEXITCODE"
  }
  return $out
}

$tfDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'infra/envs/prod'
$tf = (Invoke-Native terraform "-chdir=$tfDir" output -json | Out-String) | ConvertFrom-Json

$cluster = $tf.ecs_cluster_name.value
$taskDef = $tf.db_init_task_definition_arn.value
$logGroup = $tf.db_init_log_group.value
$subnets = ($tf.private_app_subnet_ids.value -join ',')
$sg = $tf.ecs_tasks_security_group_id.value
$network = "awsvpcConfiguration={subnets=[$subnets],securityGroups=[$sg],assignPublicIp=DISABLED}"

Write-Host "==> Starting $taskDef on cluster $cluster" -ForegroundColor Cyan
$taskArn = (Invoke-Native aws ecs run-task --region $Region --cluster $cluster --task-definition $taskDef `
    --launch-type FARGATE --network-configuration $network `
    --query 'tasks[0].taskArn' --output text | Out-String).Trim()
if (-not $taskArn -or $taskArn -eq 'None') { throw 'run-task did not return a task ARN (see the failures above).' }
$taskId = $taskArn.Split('/')[-1]
Write-Host "==> Task $taskId started, waiting for it to stop (pull + run takes 1-2 minutes)" -ForegroundColor Cyan

Invoke-Native aws ecs wait tasks-stopped --region $Region --cluster $cluster --tasks $taskArn | Out-Null

$task = (Invoke-Native aws ecs describe-tasks --region $Region --cluster $cluster --tasks $taskArn `
    --query 'tasks[0].{reason:stoppedReason,exit:containers[0].exitCode,containerReason:containers[0].reason}' `
    --output json | Out-String) | ConvertFrom-Json

Write-Host "==> Logs ($logGroup, stream db-init/db-init/$taskId)" -ForegroundColor Cyan
& aws logs tail $logGroup --region $Region --log-stream-names "db-init/db-init/$taskId" --since 1h --format short
if ($LASTEXITCODE -ne 0) { Write-Warning 'Could not read the logs (the task may have failed before starting).' }

Write-Host ''
Write-Host "Stopped reason: $($task.reason)"
if ($task.containerReason) { Write-Host "Container reason: $($task.containerReason)" }
if ($null -eq $task.exit) {
  Write-Host 'Exit code: none (the container never ran)' -ForegroundColor Red
  exit 1
}
$color = 'Red'
if ($task.exit -eq 0) { $color = 'Green' }
Write-Host "Exit code: $($task.exit)" -ForegroundColor $color
exit [int]$task.exit
