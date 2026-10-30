#!/usr/bin/env bash
# Compile-test the akmod in a Fedora container. Uses podman locally and
# docker on GitHub-hosted runners.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
image=${CI_IMAGE:-registry.fedoraproject.org/fedora:44}

if [[ -n ${CONTAINER_ENGINE:-} ]]; then
  engine=$CONTAINER_ENGINE
elif command -v podman >/dev/null 2>&1; then
  engine=podman
elif command -v docker >/dev/null 2>&1; then
  engine=docker
else
  echo "podman or docker is required" >&2
  exit 1
fi

mount=(--volume "$root:/work")
if [[ $engine == podman ]]; then
  mount=(--volume "$root:/work:Z")
fi

exec "$engine" run --rm \
  --network host \
  "${mount[@]}" \
  --workdir /work \
  --env "JOBS=${JOBS:-2}" \
  --env "KERNEL_FLAVOR=${KERNEL_FLAVOR:-mainline}" \
  "$image" \
  bash scripts/ci-build-inside.sh
