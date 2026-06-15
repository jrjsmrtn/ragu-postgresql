# Ragù PostgreSQL

A RAG-ready **PostgreSQL 18** container image: graph + vector + lexical
retrieval in a single database, for building Retrieval-Augmented Generation
backends.

It layers [pgvector](https://github.com/pgvector/pgvector),
[VectorChord](https://github.com/tensorchord/VectorChord), and
[ParadeDB pg_search](https://github.com/paradedb/paradedb) on top of the
official [Apache AGE](https://age.apache.org/) image so one PostgreSQL can back:

- **GraphRAG** — graph traversal via Apache AGE (openCypher).
- **Vector retrieval** — embeddings + similarity search via pgvector, with
  scalable, disk-friendly indexing via VectorChord (`vchord`).
- **Full-text / hybrid retrieval** — BM25 ranking via ParadeDB `pg_search`,
  plus trigram / fuzzy matching via `pg_trgm`.

## What's inside

| Layer      | Component              | Version           | Source                          |
| ---------- | ---------------------- | ----------------- | ------------------------------- |
| Base image | PostgreSQL             | 18                | `apache/age:release_PG18_1.7.0` |
| Graph      | Apache AGE             | 1.7.0             | base image                      |
| Vector     | pgvector               | 0.8.2 (`v0.8.2`)  | built from source               |
| Vector idx | VectorChord (`vchord`) | 1.1.1             | upstream `.deb`                 |
| Full-text  | ParadeDB `pg_search`   | 0.24.0            | upstream `.deb`                 |
| Lexical    | pg_trgm                | (bundled contrib) | enabled via init                |
| Versions   | `libversion`           | 2.0.0 (lib 3.0.4) | built from source               |

The base image is multi-arch (`linux/amd64`, `linux/arm64`), so it builds and
runs natively on Apple Silicon. Apache AGE, VectorChord, and pg_search all
require preloading, so this image overrides the base `CMD` to
`postgres -c shared_preload_libraries=age,vchord,pg_search`.

The extensions are created in the default database on first initialisation by
`docker-entrypoint-initdb.d/`:

- `00-create-extension-age.sql` (base image) → `age`
- `01-create-extensions-rag.sql` (this image) → `vector`, `vchord`,
  `pg_search`, `pg_trgm`, `libversion`

> Init scripts only run on **first** cluster init (empty data volume) and only
> against the default `POSTGRES_DB`. For additional databases, run
> `CREATE EXTENSION ...` yourself.

## Build

### Podman (Docker-compatible Dockerfile)

```bash
podman build -t local/ragu-postgresql:latest .
```

### Apple `container`

```bash
container build -t local/ragu-postgresql:latest .
```

## Run

```bash
# Podman
podman run -d --name ragu -e POSTGRES_PASSWORD=secret -p 5432:5432 \
  local/ragu-postgresql:latest

# Apple container
container run -d --name ragu -e POSTGRES_PASSWORD=secret -p 5432:5432 \
  local/ragu-postgresql:latest
```

Or with Compose (`compose.yaml`, Podman-first / Docker-compatible):

```bash
cp .env.example .env   # then edit POSTGRES_PASSWORD
podman compose up -d   # or: docker compose up -d
```

The Compose volume mounts `/var/lib/postgresql` — note PostgreSQL 18 changed
the image's data layout to `/var/lib/postgresql/18/docker` and the VOLUME to
`/var/lib/postgresql` (so a `postgres:17` volume is **not** reused as-is).

## Persistence

Data lives under the image's `VOLUME` at `/var/lib/postgresql` (PGDATA is
`/var/lib/postgresql/18/docker`). Whether it survives the container lifecycle
depends on what you mount there:

| How you run it                                        | Survives `stop`/`start` | Survives `rm` + recreate                             |
| ----------------------------------------------------- | ----------------------- | ---------------------------------------------------- |
| Named volume / bind mount (e.g. the Compose `pgdata`) | yes                     | **yes**                                              |
| No `-v` given                                         | yes                     | **no** — data does not carry over to a new container |
| `run --rm` with no volume                             | n/a                     | **no** — nothing is persisted                        |

For anything you want to keep, mount an explicit volume:

```bash
podman run -d --name ragu -e POSTGRES_PASSWORD=secret -p 5432:5432 \
  -v ragu-pgdata:/var/lib/postgresql \
  local/ragu-postgresql:latest
```

`compose.yaml` already does this. The bare `run` examples above and
`test/smoke-test.sh` deliberately omit a volume — they are throwaway.

> The `docker-entrypoint-initdb.d/` scripts (which `CREATE EXTENSION age,
> vector, vchord, pg_search, pg_trgm`) run **only on first init of an empty
> data directory**. On a persisted volume the extensions are already present on
> restart — they are not re-created, and a newly added one won't appear until
> you `CREATE EXTENSION` it yourself or start from a fresh volume.

> **Runtime difference with no `-v` (verified).** Docker/Podman auto-create an
> _anonymous_ volume for the `VOLUME` path, so the data survives on disk but is
> orphaned from any new container. Apple `container` creates **no** volume at
> all — bare-`VOLUME` data lives only on the container's own filesystem and is
> gone after `rm` (it does survive `stop`/`start`), with no dangling volume left
> behind. Either way, mount an explicit named volume / bind mount for real data;
> that persists across `rm` on both (confirmed on Apple `container`, where the
> volume is an ext4 image under `~/Library/Application Support/com.apple.container/volumes/`).

## Verify

A runtime-agnostic smoke test checks extension versions and runs an AGE Cypher
round-trip plus a pgvector distance query:

```bash
test/smoke-test.sh podman      # default
test/smoke-test.sh container   # Apple container
test/smoke-test.sh docker
```

## Security

Supply-chain and vulnerability hygiene (see
[ADR-0006](docs/adr/0006-container-security-checks.md)):

- **Build-time integrity** — the base image is pinned by digest, and the
  VectorChord + pg_search `.deb`s are sha256-verified (per arch) before install.
- **Image scan** — SBOM (syft) + vulnerability scan (grype), run on demand:

```bash
test/scan.sh                      # scans local/ragu-postgresql:latest via podman
test/scan.sh local/ragu-postgresql:latest docker
```

`test/scan.sh` writes `sbom.spdx.json` / `sbom.cdx.json`, prints a license
summary, and fails on High/Critical vulnerabilities (threshold and the curated
ignore-list live in `.grype.yaml`).

## Usage sketch

```sql
-- Vector column for embeddings (dimension = your embedding model's size).
CREATE TABLE chunk (
  id        bigserial PRIMARY KEY,
  content   text,
  embedding vector(1536)
);
CREATE INDEX ON chunk USING hnsw (embedding vector_cosine_ops);

-- Nearest neighbours to a query embedding.
SELECT id, content
FROM chunk
ORDER BY embedding <=> '[...]'::vector
LIMIT 5;

-- Graph side (Apache AGE / openCypher).
LOAD 'age';
SET search_path = ag_catalog, public;
SELECT create_graph('kb');
SELECT *
FROM cypher('kb', $$
  CREATE (d:Doc {title: 'intro'})-[:MENTIONS]->(e:Entity {name: 'pgvector'})
  RETURN d, e
$$) AS (d agtype, e agtype);
```

## License

This repository's own files are **Apache-2.0** ([`LICENSE`](LICENSE)).

The **built image is a mixed-license aggregate**: PostgreSQL, Apache AGE,
pgvector, and pg_trgm are permissively licensed, but **VectorChord (`vchord`)
is AGPL-3.0 / Elastic License 2.0** and **ParadeDB `pg_search` is AGPL-3.0**
(AGPL-only). The image's copyleft floor is therefore AGPL-3.0, which carries
obligations if you redistribute the image or offer it as a network service.
See [`LICENSING.md`](LICENSING.md),
[ADR-0004](docs/adr/0004-extension-topology-and-licensing.md), and
[ADR-0005](docs/adr/0005-adopt-pg-search-bm25.md) for the per-component
breakdown and the intended (self-hosted) distribution model.
