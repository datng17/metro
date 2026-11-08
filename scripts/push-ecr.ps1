<#
.SYNOPSIS
  Builds the metro-be service images for linux/amd64 and pushes them to ECR,
  tagged with the git short SHA.

.DESCRIPTION
  - Gets the account ID with `aws sts get-caller-identity` and logs Docker in to
    <account>.dkr.ecr.<region>.amazonaws.com.
  - Checks that every target repository metro/<svc> exists (created by Terraform).
  - Refuses to push a service whose directory (services/<svc>) has uncommitted or
    untracked changes, because the tag must describe exactly what was built.
    With -AllowDirty it pushes anyway, using the tag <sha>-dirty-<utc timestamp>.
  - The repositories are IMMUTABLE, so no `latest` tag is pushed. If the SHA tag
    already exists in a repository, that service is skipped.
  - Builds from the repo root (the Dockerfiles COPY services/<svc>/...) with
    `docker buildx build --platform linux/amd64 --push`.
  - Stops at the first error.

  Compatible with Windows PowerShell 5.1 and PowerShell 7.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\push-ecr.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\push-ecr.ps1 gateway-service eureka-service
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\push-ecr.ps1 -Region us-east-1 -AllowDirty user-service
#>
# PositionalBinding = $false: bare arguments go to -Services, never to -Region/-Prefix.
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$Region = $(if ($env:AWS_REGION) { $env:AWS_REGION } elseif ($env:AWS_DEFAULT_REGION) { $env:AWS_DEFAULT_REGION } else { 'us-east-1' }),
  [string]$Prefix = 'metro',
  [switch]$AllowDirty,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Services
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$AllServices = @(
  'auth-service', 'cronjob-service', 'eureka-service', 'gateway-service', 'notification-service',
  'order-service', 'station-service', 'ticket-service', 'user-service'
)

# Runs a native command and throws if it exits non-zero. Returns its stdout.
# Deliberately a simple function (no param block): tokens such as --query are then passed
# through $args unchanged instead of being parsed as PowerShell parameter names.
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

# Accept both "a b c" and "a,b,c".
if (-not $Services -or $Services.Count -eq 0) {
  $Services = $AllServices
}
else {
  $Services = @($Services | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

$unknown = @($Services | Where-Object { $AllServices -notcontains $_ })
if ($unknown.Count -gt 0) {
  throw "Unknown service(s): $($unknown -join ', '). Valid: $($AllServices -join ', ')"
}

foreach ($tool in 'aws', 'docker', 'git') {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { throw "'$tool' is not on PATH." }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
  # --- Tag and working-tree checks (before touching AWS) ----------------------
  $sha = (Invoke-Native git rev-parse --short=7 HEAD | Out-String).Trim()
  $baseTag = $sha
  $dirtyServices = @()
  foreach ($svc in $Services) {
    if (-not (Test-Path "services/$svc/Dockerfile")) { throw "Missing services/$svc/Dockerfile" }
    # '--' is quoted so PowerShell passes it to git instead of treating it as end-of-parameters.
    $status = (Invoke-Native git status --porcelain '--' "services/$svc" | Out-String).Trim()
    if ($status) { $dirtyServices += $svc }
  }
  if ($dirtyServices.Count -gt 0) {
    if (-not $AllowDirty) {
      throw ("Uncommitted changes in: $($dirtyServices -join ', '). Commit them, or rerun with -AllowDirty " +
        "(the images are then tagged <sha>-dirty-<timestamp>).")
    }
    $baseTag = "$sha-dirty-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
    Write-Warning "Pushing uncommitted changes for $($dirtyServices -join ', '). Tag: $baseTag"
  }

  # --- AWS identity, repositories and login -----------------------------------
  $account = (Invoke-Native aws sts get-caller-identity --query Account --output text | Out-String).Trim()
  $registry = "$account.dkr.ecr.$Region.amazonaws.com"
  Write-Host "==> Account $account, registry $registry, commit $sha" -ForegroundColor Cyan

  $repoNames = @($Services | ForEach-Object { "$Prefix/$_" })
  $describeArgs = @('ecr', 'describe-repositories', '--region', $Region, '--repository-names') + $repoNames +
    @('--query', 'repositories[].repositoryName', '--output', 'text')
  try {
    Invoke-Native aws @describeArgs | Out-Null
  }
  catch {
    throw ("Cannot describe ECR repositories ($($repoNames -join ', ')); see the AWS error above. " +
      "If they are missing, run terraform apply in infra/envs/prod first.")
  }

  # The token is piped by cmd.exe, not PowerShell: Windows PowerShell 5.1 re-encodes strings
  # piped to native commands, which makes ECR reject the login with 400 Bad Request.
  # $Region/$registry are interpolated into the cmd line, so allow only [a-z0-9.-] in them.
  if ($registry -notmatch '^\d{12}\.dkr\.ecr\.[a-z0-9-]+\.amazonaws\.com$') {
    throw "Unexpected registry name '$registry' (check -Region)."
  }
  & cmd /c "aws ecr get-login-password --region $Region | docker login --username AWS --password-stdin $registry"
  if ($LASTEXITCODE -ne 0) { throw "docker login to $registry failed" }

  # --- Build and push ---------------------------------------------------------
  $pushed = @()
  $skipped = @()
  foreach ($svc in $Services) {
    $repo = "$Prefix/$svc"
    $image = "$registry/${repo}:$baseTag"

    # batch-get-image exits 0 even when the tag is missing (it is reported under "failures").
    $found = (Invoke-Native aws ecr batch-get-image --region $Region --repository-name $repo `
        --image-ids "imageTag=$baseTag" --query 'length(images)' --output text | Out-String).Trim()
    if ($found -ne '0') {
      Write-Host "==> $image already exists (tags are immutable), skipping" -ForegroundColor Yellow
      $skipped += $svc
      continue
    }

    Write-Host "==> Building and pushing $image" -ForegroundColor Cyan
    # --provenance/--sbom=false: push a plain single-platform image manifest instead of an
    # index with attestation artifacts, so ECR basic scanning and the "last 10 images"
    # lifecycle rule count only real images.
    # Called directly (not through Invoke-Native) so build output streams live.
    & docker buildx build `
      --platform linux/amd64 `
      --provenance=false `
      --sbom=false `
      --file "services/$svc/Dockerfile" `
      --tag $image `
      --label "org.opencontainers.image.revision=$sha" `
      --label "org.opencontainers.image.source=metro-be/services/$svc" `
      --push `
      .
    if ($LASTEXITCODE -ne 0) { throw "docker buildx build/push of $image failed (exit code $LASTEXITCODE)" }
    $pushed += $svc
  }
}
finally {
  Pop-Location
}

Write-Host ''
Write-Host "Tag: $baseTag" -ForegroundColor Green
if ($pushed.Count -gt 0) { Write-Host "Pushed:  $($pushed -join ', ')" -ForegroundColor Green }
if ($skipped.Count -gt 0) { Write-Host "Skipped: $($skipped -join ', ')" -ForegroundColor Yellow }
