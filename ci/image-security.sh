#!/usr/bin/env bash
set -euo pipefail
image="${1:?Image reference is required}"
commit="${2:?Commit SHA is required}"
mkdir -p evidence

docker image inspect "$image" >/dev/null 2>&1 || {
  echo "Image $image is missing; build it once before security scanning" >&2
  exit 1
}

actual_commit="$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$image")"
[[ "$actual_commit" == "$commit" ]] || {
  echo "Image revision label $actual_commit does not match Git commit $commit" >&2
  exit 1
}

image_id="$(docker image inspect --format '{{.Id}}' "$image")"
printf 'image=%s\ncommit=%s\nimage_id=%s\n' "$image" "$commit" "$image_id" > evidence/image-identity.txt
syft "$image" -o cyclonedx-json=evidence/sbom.cdx.json
trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed "$image" | tee evidence/trivy.log
