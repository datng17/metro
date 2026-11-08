#!/usr/bin/env bash
# Builds the metro-be service images for linux/amd64 and pushes them to ECR,
# tagged with the git short SHA.
#
# - Gets the account ID with `aws sts get-caller-identity` and logs Docker in to
#   <account>.dkr.ecr.<region>.amazonaws.com.
# - Checks that every target repository metro/<svc> exists (created by Terraform).
# - Refuses to push a service whose directory (services/<svc>) has uncommitted or
#   untracked changes. With ALLOW_DIRTY=1 it pushes anyway, using the tag
#   <sha>-dirty-<utc timestamp>.
# - The repositories are IMMUTABLE, so no `latest` tag is pushed. If the SHA tag
#   already exists in a repository, that service is skipped.
# - Builds from the repo root (the Dockerfiles COPY services/<svc>/...).
# - Stops at the first error.
#
# Usage (Linux / WSL / Git Bash / CI):
#   ./scripts/push-ecr.sh                                  # all 9 services
#   ./scripts/push-ecr.sh gateway-service eureka-service   # subset
#   AWS_REGION=us-east-1 ALLOW_DIRTY=1 ./scripts/push-ecr.sh user-service
set -euo pipefail

REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"
PREFIX="${PREFIX:-metro}"
ALLOW_DIRTY="${ALLOW_DIRTY:-0}"

ALL_SERVICES=(auth-service cronjob-service eureka-service gateway-service notification-service
  order-service station-service ticket-service user-service)

if [ "$#" -gt 0 ]; then
  SERVICES=("$@")
else
  SERVICES=("${ALL_SERVICES[@]}")
fi

for svc in "${SERVICES[@]}"; do
  case " ${ALL_SERVICES[*]} " in
    *" ${svc} "*) ;;
    *) echo "Unknown service: ${svc}. Valid: ${ALL_SERVICES[*]}" >&2; exit 1 ;;
  esac
done

for tool in aws docker git; do
  command -v "$tool" >/dev/null 2>&1 || { echo "'$tool' is not on PATH." >&2; exit 1; }
done

cd "$(dirname "$0")/.."

# --- Tag and working-tree checks (before touching AWS) -------------------------
SHA="$(git rev-parse --short=7 HEAD)"
TAG="$SHA"
dirty=()
for svc in "${SERVICES[@]}"; do
  [ -f "services/${svc}/Dockerfile" ] || { echo "Missing services/${svc}/Dockerfile" >&2; exit 1; }
  if [ -n "$(git status --porcelain -- "services/${svc}")" ]; then
    dirty+=("$svc")
  fi
done
if [ "${#dirty[@]}" -gt 0 ]; then
  if [ "$ALLOW_DIRTY" != "1" ]; then
    echo "Uncommitted changes in: ${dirty[*]}. Commit them, or rerun with ALLOW_DIRTY=1" \
      "(the images are then tagged <sha>-dirty-<timestamp>)." >&2
    exit 1
  fi
  TAG="${SHA}-dirty-$(date -u +%Y%m%d%H%M%S)"
  echo "WARNING: pushing uncommitted changes for ${dirty[*]}. Tag: ${TAG}" >&2
fi

# --- AWS identity, repositories and login --------------------------------------
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
echo "==> Account ${ACCOUNT}, registry ${REGISTRY}, commit ${SHA}"

repo_names=()
for svc in "${SERVICES[@]}"; do repo_names+=("${PREFIX}/${svc}"); done
if ! aws ecr describe-repositories --region "$REGION" --repository-names "${repo_names[@]}" \
  --query 'repositories[].repositoryName' --output text >/dev/null; then
  echo "Cannot describe ECR repositories (${repo_names[*]}); see the AWS error above." \
    "If they are missing, run terraform apply in infra/envs/prod first." >&2
  exit 1
fi

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

# --- Build and push -------------------------------------------------------------
pushed=()
skipped=()
for svc in "${SERVICES[@]}"; do
  repo="${PREFIX}/${svc}"
  image="${REGISTRY}/${repo}:${TAG}"

  # batch-get-image exits 0 even when the tag is missing (it is reported under "failures").
  found="$(aws ecr batch-get-image --region "$REGION" --repository-name "$repo" \
    --image-ids "imageTag=${TAG}" --query 'length(images)' --output text)"
  if [ "$found" != "0" ]; then
    echo "==> ${image} already exists (tags are immutable), skipping"
    skipped+=("$svc")
    continue
  fi

  echo "==> Building and pushing ${image}"
  # --provenance/--sbom=false: push a plain single-platform image manifest instead of an
  # index with attestation artifacts, so ECR basic scanning and the "last 10 images"
  # lifecycle rule count only real images.
  docker buildx build \
    --platform linux/amd64 \
    --provenance=false \
    --sbom=false \
    --file "services/${svc}/Dockerfile" \
    --tag "$image" \
    --label "org.opencontainers.image.revision=${SHA}" \
    --label "org.opencontainers.image.source=metro-be/services/${svc}" \
    --push \
    .
  pushed+=("$svc")
done

echo
echo "Tag: ${TAG}"
[ "${#pushed[@]}" -gt 0 ] && echo "Pushed:  ${pushed[*]}"
[ "${#skipped[@]}" -gt 0 ] && echo "Skipped: ${skipped[*]}"
exit 0
