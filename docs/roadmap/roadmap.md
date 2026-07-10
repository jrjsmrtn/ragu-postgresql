# Ragù PostgreSQL — Roadmap

## Vision

A single, reproducible PostgreSQL 18 container image for RAG backends — graph
(Apache AGE), vector (pgvector), full-text/BM25 (Tiger Data `pg_textsearch`), and
lexical (pg_trgm) retrieval in one database — built and tested on Podman and
Apple `container`, supply-chain pinned, scanned, and signed. Every bundled
component is permissively licensed (fully permissive aggregate).

## Status

Released through **v0.3.1** (see [CHANGELOG](../../CHANGELOG.md)): **five**
extensions (VectorChord removed — ADR-0008), multi-arch
(amd64 + arm64) image published to GHCR and cosign-signed, two-stage local
quality gates + GitHub Actions CI (build + scan + publish), Dependabot for
actions and the base image, plus a **shared pgTAP test suite** (`test/pgtap.sh`)
cross-checked with the sibling `ragu-pglite` (ADR-0009). Tier **t1**
(decision-tracked; ADRs `0001`–`0009`).
With VectorChord gone, the image is a **fully permissive aggregate**
(`Apache-2.0 AND PostgreSQL AND MIT`) — no copyleft floor. The BM25 engine is
`pg_textsearch` (permissive) as of v0.2.0 (ADR-0007).

## Done

### Remove VectorChord — pgvector-only vector indexing (v0.3.0)

Removed VectorChord (`vchord`), the image's sole copyleft / source-available
component (AGPL-3.0 or ELv2). Vector search is now pgvector-only (HNSW /
IVFFlat). The image becomes a **fully permissive aggregate**
(`Apache-2.0 AND PostgreSQL AND MIT`) with no copyleft floor, no per-arch `.deb`
to checksum (all non-base extensions are now source-built), and one fewer
preloaded library. Trade-off: loss of VectorChord's disk-friendly RaBitQ
indexing at large scale — revisit if the corpus outgrows pgvector. Rationale and
consequences in [ADR-0008](../adr/0008-remove-vectorchord.md).

### BM25 engine swap — `pg_search` → `pg_textsearch` (v0.2.0)

Replaced ParadeDB `pg_search` (AGPL-only, Rust/Tantivy) with Tiger Data
`pg_textsearch` (permissive PostgreSQL license, pure C on native PG pages),
built from source via PGXS. Motivation and trade-offs (breaking `@@@` → `<@>`
query API; loss of phrase queries, unused by consumers; restored whole-image
ELv2 path) in [ADR-0007](../adr/0007-replace-pg-search-with-pg-textsearch.md).

### Reliability — `pg_search` first-init hardening

The v0.1.8 CI run hit an intermittent partial first-init (built correctly, but
the init session left `pg_search`/`pg_trgm`/`libversion` uncreated; smoke caught
it, a re-run passed). Hardened (see ADR-0005):

- `shared_preload_libraries` (incl. the **required** `pg_search`) is baked into
  `postgresql.conf.sample`, so the preload no longer depends solely on the
  entrypoint passing CMD `-c` args to its temporary init server;
- `02-verify-extensions.sql` asserts all six extensions post-init and **fails
  loudly** if any are missing — a partial init can never produce a
  running-but-incomplete image;
- the smoke test now exercises a real BM25 index + `@@@` search.

Residual: the exact intermittent cause wasn't reproducible, so this is a
fail-safe + reliability mitigation rather than a proven root-cause elimination;
the smoke gate + CI re-run remain the backstop.

## Planned / backlog

### Possible future work (unscheduled)

- Native arm64 CI runners for the publish job (drop QEMU; faster releases).
- Optional `docker` Dependabot already covers the base image; revisit when a
  newer `apache/age` PG18 tag/digest lands.
- Tier promotion to **t2** (Diátaxis docs tree, C4 model, sprint cadence) if the
  project's scope grows.

## Release history

See [CHANGELOG.md](../../CHANGELOG.md) for the authoritative per-version detail.

| Version | Summary                                                                                                                                                                    |
| ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| v0.1.0  | Initial release — PG18 + AGE + pgvector + VectorChord + pg_search + pg_trgm; t1 orchestration (ADRs, hooks); container security checks (digest/`.deb` pinning, grype/syft) |
| v0.1.1  | Pre-push hook robustness fix                                                                                                                                               |
| v0.1.2  | Persistence docs (verified Apple `container` volume behaviour)                                                                                                             |
| v0.1.3  | Add repology `libversion` (6th extension)                                                                                                                                  |
| v0.1.4  | OCI image labels + `build.sh`                                                                                                                                              |
| v0.1.5  | GitHub Actions CI (build + scan)                                                                                                                                           |
| v0.1.6  | Dependabot (actions + docker ecosystems)                                                                                                                                   |
| v0.1.7  | First GHCR publish (multi-arch, cosign-signed)                                                                                                                             |
| v0.1.8  | CI GitHub Actions version bumps                                                                                                                                            |
| v0.1.9  | Roadmap added                                                                                                                                                              |
| v0.1.10 | `pg_search` first-init hardening (baked preload + verify script)                                                                                                           |
| v0.2.0  | Replace `pg_search` (AGPL) with `pg_textsearch` (permissive) as the BM25 engine (ADR-0007)                                                                                 |
| v0.3.0  | Remove VectorChord (ADR-0008) → fully permissive image; pgvector-only vector indexing; base-CVE patches                                                                    |
| v0.3.1  | Shared pgTAP test suite (`test/pgtap.sh`) + ADR-0009 testing strategy — cross-sibling correctness with `ragu-pglite`                                                       |
