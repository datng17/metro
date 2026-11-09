<#
.SYNOPSIS
  Scales the whole metro-prod deployment to zero (down) or back to the
  Terraform values (up), and stops or starts RDS. `status` only reports.
.DESCRIPTION
  Reads the cluster, service start order, desired counts, RDS identifier and
  alarm names from `terraform output -json scale_config` in infra/envs/prod.

  down: disable alarm actions -> desired_count 0 (business + gateway, then
        eureka, rabbitmq, redis) -> wait until stable -> stop RDS.
  up:   start RDS and wait until available -> redis, rabbitmq, eureka ->
        business + gateway (Terraform desired counts) -> wait until stable ->
        poll the public health URL -> enable alarm actions.

  Caveats:
  - Terraform still owns desired_count. A `terraform apply` while scaled down
    sets the counts back to the Terraform values (and needs RDS running).
    To keep the business services and gateway at 0 through an apply, pass
    -var business_desired_count=0 -var gateway_desired_count=0.
  - AWS starts a stopped RDS instance automatically after 7 days. Run
    `down` again (or stop it by hand) if the pause lasts longer.
  - The ALB, fck-nat, Elastic IP and Cloud Map keep running (about $35/month).
  Compatible with Windows PowerShell 5.1 and PowerShell 7.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\scale.ps1 down
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\scale.ps1 up
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\scale.ps1 status
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet('up', 'down', 'status')]
  [string]$Action,

  [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { 'us-east-1' }),

  # How long `up` polls the public health URL after the services are stable.
  [int]$HealthTimeoutSeconds = 300
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

function Write-Step([string]$Message) {
  Write-Host "==> $Message" -ForegroundColor Cyan
}

$tfDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'infra/envs/prod'
$cfg = (Invoke-Native terraform "-chdir=$tfDir" output -json scale_config | Out-String) | ConvertFrom-Json

$cluster = $cfg.cluster
$groups = @($cfg.groups | ForEach-Object { , @($_) })
$rdsId = $cfg.rds_identifier
$alarms = @($cfg.alarm_names)
$healthUrl = $cfg.health_url

function Get-DesiredCount([string]$Service) {
  return [int]$cfg.desired_counts.$Service
}

function Get-RdsStatus {
  return (Invoke-Native aws rds describe-db-instances --region $Region --db-instance-identifier $rdsId `
      --query 'DBInstances[0].DBInstanceStatus' --output text | Out-String).Trim()
}

function Set-ServiceCounts([string[]]$Services, [switch]$Zero) {
  foreach ($svc in $Services) {
    $count = 0
    if (-not $Zero) { $count = Get-DesiredCount $svc }
    Write-Host "    $svc -> desired_count $count"
    Invoke-Native aws ecs update-service --region $Region --cluster $cluster --service $svc `
      --desired-count $count --query 'service.serviceName' --output text | Out-Null
  }
}

# The services-stable waiter polls every 15 s for up to 10 minutes and takes
# at most 10 services per call (each group is smaller than that).
function Wait-ServicesStable([string[]]$Services) {
  Write-Host "    waiting for: $($Services -join ', ')"
  & aws ecs wait services-stable --region $Region --cluster $cluster --services @Services
  if ($LASTEXITCODE -ne 0) {
    Show-Services $Services
    throw "Services did not become stable within 10 minutes. Check the events: aws ecs describe-services --cluster $cluster --services <name> --query 'services[0].events[0:5]'"
  }
}

function Show-Services([string[]]$Services) {
  & aws ecs describe-services --region $Region --cluster $cluster --services @Services `
    --query 'services[].{service:serviceName,desired:desiredCount,running:runningCount,pending:pendingCount}' `
    --output table
}

function Set-AlarmActions([bool]$Enabled) {
  if ($alarms.Count -eq 0) { return }
  $verb = 'disable-alarm-actions'
  if ($Enabled) { $verb = 'enable-alarm-actions' }
  Invoke-Native aws cloudwatch $verb --region $Region --alarm-names @alarms | Out-Null
  Write-Host "    $verb on $($alarms.Count) alarms"
}

function Stop-Rds {
  $status = Get-RdsStatus
  switch ($status) {
    'available' {
      Invoke-Native aws rds stop-db-instance --region $Region --db-instance-identifier $rdsId `
        --query 'DBInstance.DBInstanceStatus' --output text | Out-Null
      Write-Host "    $rdsId is stopping (takes a few minutes; AWS restarts it automatically after 7 days)."
    }
    { $_ -in 'stopped', 'stopping' } { Write-Host "    $rdsId is already $status." }
    default { Write-Warning "$rdsId is '$status'; it can only be stopped when 'available'. Run 'down' again later." }
  }
}

function Start-Rds {
  $status = Get-RdsStatus
  if ($status -eq 'stopping') {
    Write-Host "    $rdsId is stopping; waiting until it is stopped before starting it"
    $deadline = (Get-Date).AddMinutes(20)
    while ($status -eq 'stopping') {
      if ((Get-Date) -gt $deadline) { throw "$rdsId is still stopping after 20 minutes." }
      Start-Sleep -Seconds 30
      $status = Get-RdsStatus
    }
  }
  if ($status -eq 'stopped') {
    Invoke-Native aws rds start-db-instance --region $Region --db-instance-identifier $rdsId `
      --query 'DBInstance.DBInstanceStatus' --output text | Out-Null
    Write-Host "    $rdsId is starting"
  }
  elseif ($status -ne 'available') {
    Write-Host "    $rdsId is '$status'"
  }
  Write-Host '    waiting until RDS is available (about 5 minutes after a start)'
  Invoke-Native aws rds wait db-instance-available --region $Region --db-instance-identifier $rdsId | Out-Null
  Write-Host "    $rdsId is available"
}

function Wait-Healthy {
  $deadline = (Get-Date).AddSeconds($HealthTimeoutSeconds)
  while ($true) {
    $code = 0
    try {
      $code = (Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 10).StatusCode
    }
    catch {
      $code = 0
    }
    if ($code -eq 200) {
      Write-Host "    $healthUrl -> 200" -ForegroundColor Green
      return
    }
    if ((Get-Date) -gt $deadline) {
      Write-Warning "$healthUrl did not return 200 within $HealthTimeoutSeconds s (last status: $code). The ALB health check may still be warming up."
      return
    }
    Start-Sleep -Seconds 10
  }
}

switch ($Action) {
  'down' {
    Write-Step 'Disabling alarm actions (a stopped site would otherwise send alerts)'
    Set-AlarmActions $false

    # Reverse start order: business + gateway first, platform last.
    for ($i = $groups.Count - 1; $i -ge 0; $i--) {
      Write-Step "Scaling to 0: $($groups[$i] -join ', ')"
      Set-ServiceCounts $groups[$i] -Zero
      Wait-ServicesStable $groups[$i]
    }

    Write-Step "Stopping RDS $rdsId"
    Stop-Rds

    Write-Host ''
    Write-Host 'Scaled down. Still billed: ALB, fck-nat + EIP, RDS storage, ECR, logs.' -ForegroundColor Green
    Write-Host 'Note: a terraform apply now restores the Terraform desired counts.'
  }

  'up' {
    Write-Step "Starting RDS $rdsId"
    Start-Rds

    foreach ($group in $groups) {
      Write-Step "Scaling up: $($group -join ', ')"
      Set-ServiceCounts $group
      Wait-ServicesStable $group
    }

    Write-Step "Checking $healthUrl"
    Wait-Healthy

    Write-Step 'Enabling alarm actions'
    Set-AlarmActions $true

    Write-Host ''
    Write-Host 'Scaled up.' -ForegroundColor Green
  }

  'status' {
    Write-Step "ECS services in $cluster"
    foreach ($group in $groups) { Show-Services $group }

    Write-Step "RDS $rdsId"
    Write-Host "    $(Get-RdsStatus)"

    if ($alarms.Count -gt 0) {
      Write-Step 'Alarms'
      & aws cloudwatch describe-alarms --region $Region --alarm-names @alarms `
        --query 'MetricAlarms[].{alarm:AlarmName,state:StateValue,actions:ActionsEnabled}' --output table
    }
  }
}
