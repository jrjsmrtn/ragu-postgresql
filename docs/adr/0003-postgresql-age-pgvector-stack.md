# 3. Use PostgreSQL 18 + Apache AGE + pgvector as the RAG database stack

Date: 2026-06-13

## Status

Accepted

## Context

Ragù PostgreSQL provides a database backend for Retrieval-Augmented Generation
(RAG). RAG retrieval benefits from three complementary access patterns:

- **Graph** traversal over entities/relations ("GraphRAG").
- **Vector** similarity over embeddings.
- **Lexical** / fuzzy text matching (hybrid retrieval).

Key requirements:
- One database that can serve all three, ideally joinable in a single query.
- PostgreSQL 18 (current major) as the foundation.
- Builds and runs on Apple Silicon (arm64) under Podman and Apple `container`.

## Decision

We will ship a single container image based on
**`apache/age:release_PG18_1.7.0`** (official `postgres:18` + Apache AGE 1.7.0),
extended with **pgvector** (built from source, pinned) and **`pg_trgm`**
(bundled contrib).

**Core components**:
- **Database**: PostgreSQL 18 (Debian-based official image).
- **Graph**: Apache AGE 1.7.0 (openCypher) — from the base image.
- **Vector**: pgvector 0.8.2 — built from source against PG18.
- **Lexical**: `pg_trgm` — enabled via init script.

**Rationale**:
- `apache/age:release_PG18_1.7.0` is an official, multi-arch (amd64/arm64)
  image that already pairs PG18 with AGE 1.7.0 and sets
  `shared_preload_libraries=age` — no need to compile AGE ourselves.
- pgvector is the de-facto Postgres vector extension; 0.8.2 supports PG18 and
  carries the CVE-2026-3172 fix. Built from source with `OPTFLAGS=""` for a
  portable binary.
- All components live in one PostgreSQL instance, enabling hybrid retrieval in
  a single SQL statement (the core value of this image).

**Alternatives Considered**:

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| `apache/age:release_PG18_1.7.0` base + pgvector from source | Official PG18+AGE base, multi-arch, minimal custom build | Must compile pgvector | **Selected** |
| Build AGE from source on `postgres:18` | Full control of versions | Slow build, redundant — official image exists | Rejected |
| Separate Neo4j (graph) + Postgres/pgvector (vector) | Mature graph engine | Two services, no single-query hybrid joins | Rejected |
| External vector DB (Qdrant/Milvus) + Postgres | Specialised vector perf | Extra service, data sync, no in-DB joins | Rejected |
| pgvector packaged (apt) instead of source | No compile step | Base image lacks it; source pin gives control | Rejected (for now) |

## Consequences

**Positive**:
- One image, one connection, hybrid graph + vector + lexical retrieval.
- Native arm64 support for local dev on Apple Silicon.
- Minimal custom build surface (only pgvector compiled).

**Negative**:
- All extensions must align on one PostgreSQL major version; a lagging upstream
  pins the whole image.
- Compiling pgvector adds build time and toolchain management.

**Risks**:
- Upstream version skew (AGE / pgvector / future VectorChord / ParadeDB
  `pg_search`) on new PG majors. *Mitigation*: pin versions; bump deliberately;
  the multi-extension **topology** decision (single instance vs. multiple
  containers, and the exact extension set) is deferred to its own ADR.

## References

- [Apache AGE](https://age.apache.org/) · [apache/age PG18 1.7.0](https://hub.docker.com/r/apache/age/tags)
- [pgvector](https://github.com/pgvector/pgvector) · [pgvector 0.8.2 release](https://www.postgresql.org/about/news/pgvector-082-released-3245/)
- [PostgreSQL 18 image PGDATA/VOLUME change](https://github.com/docker-library/postgres/pull/1259)
