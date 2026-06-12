#!/usr/bin/env bash
# Smoke-test the Ragù PostgreSQL image under a Docker-compatible runtime.
#
# Usage:
#   test/smoke-test.sh [runtime]
#
#   runtime  podman (default) | container | docker
#
# Assumes the image is already built and tagged (see IMAGE below).
set -euo pipefail

RUNTIME="${1:-podman}"
IMAGE="${IMAGE:-local/ragu-postgresql:latest}"
NAME="ragu-smoke-$$"
# Ephemeral password for a throwaway container — not a real secret.
PASS="smoke-$$"

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

echo ">> running extension + round-trip checks"
"$RUNTIME" exec -i -e PGPASSWORD="$PASS" "$NAME" \
  psql -U postgres -v ON_ERROR_STOP=1 -tAX <<'SQL'
\echo -- extension versions --
SELECT extname || ' ' || extversion
FROM pg_extension
WHERE extname IN ('age', 'vector', 'vchord', 'pg_trgm')
ORDER BY extname;

\echo -- AGE: graph + cypher round-trip --
LOAD 'age';
SET search_path = ag_catalog, public;
SELECT create_graph('smoke');
SELECT * FROM cypher('smoke', $$ CREATE (n:Doc {title: 'hello'}) RETURN n.title $$) AS (title agtype);

\echo -- pgvector: L2 distance --
SET search_path = public;
SELECT '[1,2,3]'::vector <-> '[1,2,4]'::vector AS l2_distance;

\echo -- pg_trgm: similarity --
SELECT similarity('retrieval', 'retriever') AS trgm_similarity;
SQL

echo ">> OK ($RUNTIME)"
