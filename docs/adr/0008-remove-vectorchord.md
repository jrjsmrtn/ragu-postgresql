# 8. Remove VectorChord; pgvector-only vector indexing

Date: 2026-07-09

## Status

Accepted

Amends [ADR-0004](0004-extension-topology-and-licensing.md) (extension topology +
licensing posture) by exercising the permissive-only fallback it reserved.

## Context

[ADR-0004](0004-extension-topology-and-licensing.md) adopted a single
multi-extension instance and added **VectorChord (`vchord`)** for scalable,
disk-friendly vector indexing (RaBitQ) layered on pgvector's `vector` type. It
explicitly kept a **permissive-only fallback** ("drop VectorChord; pgvector
indexing only") as the escape hatch "if a permissive-only image is later
required."

Since then two things changed the balance:

1. **Licensing.** With ParadeDB `pg_search` replaced by permissive
   `pg_textsearch` ([ADR-0007](0007-replace-pg-search-with-pg-textsearch.md)),
   VectorChord became the **sole** copyleft / source-available component — the
   only thing setting the image's copyleft floor at `AGPL-3.0 OR ELv2`. Every
   other component is permissive (PostgreSQL / Apache-2.0 / MIT). One extension
   is the entire reason the image is not a clean permissive aggregate.
2. **Supply chain + portability.** VectorChord is the only extension installed
   from a **prebuilt per-arch upstream `.deb`** (arm64/amd64 checksums pinned by
   hand), rather than built from source by PGXS like pgvector, pg_textsearch, and
   libversion. It also requires `shared_preload_libraries` and does not run in
   constrained Postgres runtimes (e.g. the PGlite/WASM sibling `ragu-pglite`).

For the image's current scale (self-hosted / dogfooding RAG backends),
**pgvector's own HNSW and IVFFlat indexing is sufficient** for vector similarity
search. VectorChord's advantage is at larger scale (disk-friendly RaBitQ
quantization, very large indexes) — capability we are not exercising today.

## Decision

**Remove VectorChord (`vchord`) from the image.** Vector similarity search is
provided by **pgvector alone** (the `vector` type plus HNSW / IVFFlat indexes).

- Drop the `vchord` `.deb` install layer and its per-arch checksum block from the
  `Dockerfile`.
- Drop `CREATE EXTENSION vchord CASCADE` from
  `01-create-extensions-rag.sql`; pgvector's `vector` is now created directly
  (no CASCADE needed).
- Preload drops to `shared_preload_libraries=age,pg_textsearch` (baked
  `postgresql.conf.sample` + `CMD`). AGE and pg_textsearch still require it;
  pgvector and libversion do not.
- The post-init verify script and smoke test now expect **five** extensions:
  `age`, `vector`, `pg_textsearch`, `pg_trgm`, `libversion`.

### Resulting extension set

| Extension           | Purpose                      | License            |
| ------------------- | ---------------------------- | ------------------ |
| Apache AGE 1.7.0    | graph (openCypher)           | Apache-2.0         |
| pgvector 0.8.2      | vector type + HNSW / IVFFlat | PostgreSQL License |
| pg_textsearch 1.3.1 | BM25 full-text               | PostgreSQL License |
| pg_trgm             | trigram / fuzzy              | PostgreSQL License |
| libversion          | version-string comparison    | MIT                |

## Consequences

**Positive**:

- **The image becomes a fully permissive aggregate** —
  `Apache-2.0 AND PostgreSQL AND MIT`, **no copyleft floor**. No AGPL §13
  source-offer and no Elastic License managed-service prohibition apply to any
  component. Public redistribution and managed-service (SaaS) hosting are no
  longer constrained by a bundled licence. `LICENSING.md` and the OCI `licenses`
  label are updated.
- **Simpler, more uniform supply chain.** No per-arch binary `.deb` to checksum;
  all non-base extensions are now built from pinned source (pgvector,
  pg_textsearch, libversion). One fewer upstream to track for security bumps
  (ADR-0006).
- **Lighter image** and one fewer preloaded library.
- Hybrid retrieval is preserved — graph (AGE) + vector (pgvector) + BM25
  (pg_textsearch) + trigram (pg_trgm), joinable in one SQL query.

**Negative**:

- **Loss of VectorChord's scalable / disk-friendly indexing** (RaBitQ
  quantization, external index build). At large corpus sizes pgvector's HNSW is
  more memory-hungry and IVFFlat less accurate; this is a real capability ceiling
  for very large vector workloads. Revisit if the dogfooding corpus outgrows
  pgvector — re-adding VectorChord would reintroduce the `AGPL-3.0 OR ELv2` floor.
- Breaking change for any consumer that created `vchord` indexes; they fall back
  to pgvector index types.

**Risks**:

- Under-provisioning at scale. _Mitigation_: pgvector HNSW/IVFFlat covers the
  current self-hosted scale; the door to re-adding VectorChord (ADR-0004's
  topology is unchanged) stays open if a concrete scale need appears.

## References

- [`LICENSING.md`](../../LICENSING.md)
- [ADR-0004](0004-extension-topology-and-licensing.md) — topology + licensing (reserved this fallback)
- [ADR-0007](0007-replace-pg-search-with-pg-textsearch.md) — pg_textsearch (made VectorChord the sole copyleft component)
- [pgvector indexing](https://github.com/pgvector/pgvector#indexing) · [VectorChord](https://github.com/tensorchord/VectorChord)
