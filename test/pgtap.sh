#!/usr/bin/env bash
# Run the shared pgTAP suite against the Ragù PostgreSQL image.
#
# The same test/sql/rag_trio.pgtap.sql assertions run here (server image) and in
# the sibling ragu-pglite (in-process PGlite). Since the image ships the RAG
# extensions but no application schema, this builds test/sql/rag_trio.fixture.sql
# in a throwaway session first, then asserts it with pgTAP.
#
# pgTAP is not in the image (it is a test-only dependency); it is installed into
# the running container from PGDG at test time (postgresql-<major>-pgtap). The
# TAP stream is run through psql inside the container and scanned for "not ok" —
# no host psql / pg_prove required (mirrors smoke-test.sh).
#
# Usage:
#   test/pgtap.sh [runtime]
#
#   runtime  podman (default) | container | docker
#
# Assumes the image is already built and tagged (see IMAGE below).
set -euo pipefail

RUNTIME="${1:-podman}"
IMAGE="${IMAGE:-local/ragu-postgresql:latest}"
NAME="ragu-pgtap-$$"
# Ephemeral password for a throwaway container — not a real secret.
PASS="pgtap-$$"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() { "$RUNTIME" rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo ">> [$RUNTIME] starting $IMAGE as $NAME"
"$RUNTIME" run -d --name "$NAME" -e POSTGRES_PASSWORD="$PASS" "$IMAGE" >/dev/null

echo ">> waiting for postgres to accept connections"
ready=""
for _ in $(seq 1 90); do
  if "$RUNTIME" exec "$NAME" pg_isready -U postgres >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
[ -n "$ready" ] || {
  echo "!! postgres did not become ready"
  "$RUNTIME" logs "$NAME" | tail -30
  exit 1
}

psql_c() { "$RUNTIME" exec -e PGPASSWORD="$PASS" "$NAME" psql -U postgres -tAX "$@"; }

# The Debian package is versioned by PG major (e.g. postgresql-18-pgtap).
PGMAJOR="$(psql_c -c "SELECT current_setting('server_version_num')::int / 10000")"
echo ">> installing pgTAP (postgresql-${PGMAJOR}-pgtap) from PGDG into $NAME"
"$RUNTIME" exec -e DEBIAN_FRONTEND=noninteractive "$NAME" bash -lc \
  "apt-get update -qq && apt-get install -y -qq postgresql-${PGMAJOR}-pgtap" >/dev/null 2>&1

echo ">> building RAG-trio fixture + running the shared pgTAP suite"
out="$(
  {
    cat "$HERE/sql/rag_trio.fixture.sql"
    cat "$HERE/sql/rag_trio.pgtap.sql"
  } | "$RUNTIME" exec -i -e PGPASSWORD="$PASS" "$NAME" \
    psql -U postgres -tAX -v ON_ERROR_STOP=1 2>&1
)"

echo "$out" | grep -E '^(ok|not ok|[0-9]+\.\.[0-9]+)' || true

if echo "$out" | grep -q '^not ok'; then
  echo "!! pgTAP FAILED"
  echo "$out"
  exit 1
fi

plan="$(echo "$out" | grep -oE '^[0-9]+\.\.[0-9]+' | head -1)"
oks="$(echo "$out" | grep -c '^ok' || true)"
echo ">> OK ($RUNTIME) — pgTAP plan ${plan}, ${oks} passed, 0 failed"
