#!/usr/bin/env bash
set -euo pipefail

image="${1:?Image reference is required}"
commit="${2:?Commit SHA is required}"
: "${REGISTRY_USERNAME:?Registry username is required}"
: "${REGISTRY_PASSWORD:?Registry password is required}"

mkdir -p evidence
registry="${image%%/*}"

docker image inspect "$image" >/dev/null 2>&1 || {
  echo "Image $image is missing; refusing to rebuild after certification" >&2
  exit 1
}

actual_commit="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
[[ "$actual_commit" == "$commit" ]] || {
  echo "Image revision label $actual_commit does not match Git commit $commit" >&2
  exit 1
}

printf '%s' "$REGISTRY_PASSWORD" | docker login "$registry" --username "$REGISTRY_USERNAME" --password-stdin
trap 'docker logout "$registry" >/dev/null 2>&1 || true' EXIT

docker push "$image" 2>&1 | tee evidence/docker-push.log
digest="$(sed -nE 's/.*digest: (sha256:[0-9a-f]{64}).*/\1/p' evidence/docker-push.log | tail -n 1)"
[[ -n "$digest" ]] || {
  echo "Registry push completed without returning an immutable digest" >&2
  exit 1
}

repository="${image%:*}"
published_image="${repository}@${digest}"
printf '%s\n' "$published_image" > evidence/published-image.txt
printf 'tagged_image=%s\npublished_image=%s\ncommit=%s\n' "$image" "$published_image" "$commit" > evidence/publish-identity.txt
