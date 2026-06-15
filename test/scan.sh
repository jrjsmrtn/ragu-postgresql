#!/usr/bin/env bash
# Container security scan: SBOM (syft) + vulnerability scan (grype).
#
# Usage:
#   test/scan.sh [image] [runtime]
#
#   image    image ref (default: local/ragu-postgresql:latest)
#   runtime  podman (default) | docker  — used to export the image
#
# The image is exported to an archive and scanned from disk, so no container
# daemon socket is needed (works on macOS with a podman machine). Apple
# `container` images are byte-identical to the podman build (same Dockerfile),
# so scan the podman image.
#
# Writes sbom.spdx.json + sbom.cdx.json, prints a license summary, then runs
# grype (fail threshold + ignores come from .grype.yaml in the repo root).
set -euo pipefail

IMAGE="${1:-local/ragu-postgresql:latest}"
RUNTIME="${2:-podman}"
OUT="${OUT_DIR:-.}"

for tool in syft grype "$RUNTIME"; do
  command -v "$tool" >/dev/null || {
    echo "$tool not installed" >&2
    exit 127
  }
done

workdir="$(mktemp -d)"
tar="$workdir/image.tar"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

echo ">> exporting $IMAGE via $RUNTIME"
case "$RUNTIME" in
podman)
  podman save --format oci-archive -o "$tar" "$IMAGE"
  src="oci-archive:$tar"
  ;;
docker)
  docker save -o "$tar" "$IMAGE"
  src="docker-archive:$tar"
  ;;
*)
  echo "unsupported runtime: $RUNTIME (use podman|docker)" >&2
  exit 2
  ;;
esac

echo ">> SBOM (syft)"
syft scan "$src" -q \
  -o "spdx-json=$OUT/sbom.spdx.json" \
  -o "cyclonedx-json=$OUT/sbom.cdx.json"

echo ">> component licenses (best-effort, from SBOM)"
python3 - "$OUT/sbom.cdx.json" <<'PY'
import json, sys, collections
data = json.load(open(sys.argv[1]))
counter = collections.Counter()
for comp in data.get("components", []):
    names = []
    for entry in comp.get("licenses", []):
        lic = entry.get("license", {}) or {}
        names.append(lic.get("id") or lic.get("name") or entry.get("expression"))
    names = [n for n in names if n] or ["UNKNOWN"]
    for n in names:
        counter[n] += 1
for lic, n in counter.most_common():
    print(f"  {n:4d}  {lic}")
PY

echo ">> vulnerability scan (grype) — threshold/ignores from .grype.yaml"
grype "$src" -o table
echo ">> scan OK"
