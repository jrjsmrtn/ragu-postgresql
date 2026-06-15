# Ragù PostgreSQL — Roadmap

## Vision

A single, reproducible PostgreSQL 18 container image for RAG backends — graph
(Apache AGE), vector (pgvector + VectorChord), full-text/BM25 (ParadeDB
pg_search), and lexical (pg_trgm) retrieval in one database — built and tested
on Podman and Apple `container`, supply-chain pinned, scanned, and signed.

## Status

Released through **v0.1.8** (see [CHANGELOG](../../CHANGELOG.md)): six extensions,
multi-arch (amd64 + arm64) image published to GHCR and cosign-signed, two-stage
local quality gates + GitHub Actions CI (build + scan + publish), Dependabot for
actions and the base image. Tier **t1** (decision-tracked; ADRs `0001`–`0006`).

## Planned / backlog

### Reliability

- **Harden the `pg_search` first-init to prevent the v0.1.8 flake.** In the
  v0.1.8 CI run the image built correctly, but the runtime first-init session
  aborted after `vchord`, leaving `pg_search`, `pg_trgm`, and `libversion`
  uncreated (smoke test caught it; a re-run on the identical commit passed). It
  is so far a single, transient occurrence. Investigate and make init
  deterministic — options to weigh:
  - confirm `pg_search` ↔ PostgreSQL 18.4 first-init behaviour (init-time
    `CREATE EXTENSION` vs. preload ordering / any startup race);
  - split or reorder the `CREATE EXTENSION` statements, or run `pg_search`
    last so a transient failure can't mask the others;
  - make the init self-verify (assert all six extensions exist) so a partial
    init fails loudly at build/test time rather than intermittently;
  - keep the smoke-test gate as the backstop regardless.
  - **Goal:** reliable six-extension init across both runtimes, no flakes.

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
