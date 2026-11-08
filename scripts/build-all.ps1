<#
.SYNOPSIS
  Builds the Docker images of all 9 metro-be services from the repo root.

.EXAMPLE
  ./scripts/build-all.ps1                         # metro/<svc>:local
  ./scripts/build-all.ps1 -Tag dev -Services gateway-service,cronjob-service
  ./scripts/build-all.ps1 -Platform linux/amd64   # match ECS Fargate (x86_64)
#>
[CmdletBinding()]
param(
  [string]$Tag = 'local',
  [string]$Prefix = 'metro',
  [string]$Platform = '',
  [string[]]$Services = @(
    'eureka-service', 'gateway-service', 'auth-service', 'user-service', 'station-service',
    'ticket-service', 'order-service', 'notification-service', 'cronjob-service'
  )
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$failed = @()

Push-Location $repoRoot
try {
  foreach ($svc in $Services) {
    $dockerfile = "services/$svc/Dockerfile"
    if (-not (Test-Path $dockerfile)) { throw "Missing $dockerfile" }
    $image = "$Prefix/${svc}:$Tag"
    Write-Host "==> Building $image" -ForegroundColor Cyan
    $buildArgs = @('build', '-f', $dockerfile, '-t', $image)
    if ($Platform) { $buildArgs += @('--platform', $Platform) }
    $buildArgs += '.'
    & docker @buildArgs
    if ($LASTEXITCODE -ne 0) { $failed += $svc }
  }
}
finally {
  Pop-Location
}

if ($failed.Count -gt 0) {
  Write-Host "FAILED: $($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "All $($Services.Count) images built with tag '$Tag'." -ForegroundColor Green
