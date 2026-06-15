#!/usr/bin/env bash
# Build the Ragù PostgreSQL image with OCI labels stamped from git.
#
# Usage:
#   build.sh [runtime] [tag]
#
#   runtime  podman (default) | container | docker
#   tag      image tag (default: local/ragu-postgresql:latest)
#
# Populates the version/revision/created build-args (org.opencontainers.image.*)
# from the current git checkout. Build plain (`podman build .`) if you don't
# need the dynamic labels.
set -euo pipefail

RUNTIME="${1:-podman}"
TAG="${2:-local/ragu-postgresql:latest}"

VERSION="$(git describe --tags --always --dirty 2>/dev/null || echo unknown)"
REVISION="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
CREATED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo ">> [$RUNTIME] building $TAG  (version=$VERSION revision=${REVISION:0:12} created=$CREATED)"
exec "$RUNTIME" build \
  --build-arg VERSION="$VERSION" \
  --build-arg REVISION="$REVISION" \
  --build-arg CREATED="$CREATED" \
  -t "$TAG" .
