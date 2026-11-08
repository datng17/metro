#!/usr/bin/env bash
# Builds the Docker images of all 9 metro-be services from the repo root.
# Usage (Git Bash / WSL):
#   ./scripts/build-all.sh                          # metro/<svc>:local
#   TAG=dev ./scripts/build-all.sh gateway-service cronjob-service
#   PLATFORM=linux/amd64 ./scripts/build-all.sh     # match ECS Fargate (x86_64)
set -euo pipefail

TAG="${TAG:-local}"
PREFIX="${PREFIX:-metro}"
PLATFORM="${PLATFORM:-}"

if [ "$#" -gt 0 ]; then
  SERVICES=("$@")
else
  SERVICES=(eureka-service gateway-service auth-service user-service station-service
    ticket-service order-service notification-service cronjob-service)
fi

cd "$(dirname "$0")/.."

failed=()
for svc in "${SERVICES[@]}"; do
  dockerfile="services/${svc}/Dockerfile"
  [ -f "$dockerfile" ] || { echo "Missing $dockerfile" >&2; exit 1; }
  image="${PREFIX}/${svc}:${TAG}"
  echo "==> Building ${image}"
  args=(build -f "$dockerfile" -t "$image")
  [ -n "$PLATFORM" ] && args+=(--platform "$PLATFORM")
  if ! docker "${args[@]}" .; then
    failed+=("$svc")
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  echo "FAILED: ${failed[*]}" >&2
  exit 1
fi
echo "All ${#SERVICES[@]} images built with tag '${TAG}'."
