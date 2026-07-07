# Ragù PostgreSQL

A RAG-ready PostgreSQL 18 container image combining graph (Apache AGE), vector
(pgvector), and lexical (pg_trgm) retrieval in a single database, for building
Retrieval-Augmented Generation backends.

## Project Context

- **Category**: Development
- **Type**: Container image (PostgreSQL distribution)
- **Stack**: Dockerfile (OCI), PostgreSQL 18, Apache AGE, pgvector,
  VectorChord (`vchord`), Tiger Data `pg_textsearch`, repology `libversion`; built
  and tested with Podman and Apple `container`
- **License**: Apache-2.0
- **Tier**: t1

## Project Tier

Current tier: **t1** (decision-tracked)

Tier-specific artifacts in this project:

- CLAUDE.md, conventional commits, gitflow (`main` / `develop`)
- Foundation + decision ADRs (`docs/adr/0001`–`0006`)
- CHANGELOG.md (Keep a Changelog)
- Two-stage pre-commit hooks

Promotion triggers being watched:

- **t1 → t2** when the documentation outgrows README + ADRs (e.g. usage guides
  for the hybrid-retrieval query patterns warrant a Diátaxis tree), or when the
  extension topology needs a C4 model.

## Status

Single PostgreSQL 18 image with AGE 1.7.0, pgvector 0.8.2, VectorChord 1.1.1,
**pg_textsearch 1.3.1** (replaced ParadeDB pg_search as of v0.2.0, ADR-0007),
pg_trgm — built and smoke-tested under Podman and Apple `container`, with the
ADR-0006 security checks (digest pin, `.deb` sha256, grype/syft scan green).
Topology + licensing in ADR-0004; the BM25-engine swap in ADR-0007. The image's
copyleft floor is `AGPL-3.0 OR ELv2` (VectorChord's dual license — the only
copyleft component now that pg_search is gone) — see `LICENSING.md`.

## Foundational ADRs

Read these at the start of each AI session for complete context:

| ADR                                                               | Purpose              | Summary                              |
| ----------------------------------------------------------------- | -------------------- | ------------------------------------ |
| [ADR-0001](docs/adr/0001-record-architecture-decisions.md)        | HOW TO DECIDE        | Decision methodology                 |
| [ADR-0002](docs/adr/0002-adopt-development-best-practices.md)     | HOW TO DEVELOP       | Development practices                |
| [ADR-0003](docs/adr/0003-technology-stack.md)                     | WHAT TECH            | Technology stack                     |
| [ADR-0004](docs/adr/0004-extension-topology-and-licensing.md)     | TOPOLOGY + LICENSING | Single instance; AGPL/ELv2 posture   |
| [ADR-0005](docs/adr/0005-adopt-pg-search-bm25.md)                 | WHAT TECH            | Adopt pg_search — superseded by 0007 |
| [ADR-0006](docs/adr/0006-container-security-checks.md)            | SECURITY             | grype/syft scan; .deb + base pinning |
| [ADR-0007](docs/adr/0007-replace-pg-search-with-pg-textsearch.md) | WHAT TECH            | Replace pg_search with pg_textsearch |

## Development Practices

This project follows [AI-Assisted Project Orchestration patterns](https://github.com/jrjsmrtn/ai-assisted-project-orchestration):

- **Versioning**: Semantic versioning (0.x.x during development; patch-level
  bumps unless major changes land)
- **Git Workflow**: Gitflow (`main`, `develop`, `feature/*`, `release/*`)
- **Commits**: Conventional Commits
- **Containerization**: Podman-first, Docker-compatible; must also build and
  run under Apple `container`

## Quick Commands

```bash
# Build (pick a runtime); plain build leaves dynamic OCI labels empty
podman build -t local/ragu-postgresql:latest .
container build -t local/ragu-postgresql:latest .

# Build with OCI labels stamped from git (version/revision/created)
./build.sh podman      # or: container | docker

# Smoke test (runtime-agnostic: podman | container | docker)
test/smoke-test.sh podman
test/smoke-test.sh container
```

## AI Collaboration Notes

**Project-specific guidance:**

- Base image is `apache/age:release_PG18_1.7.0` (= official `postgres:18`
  Debian + Apache AGE 1.7.0), **pinned by digest** (ADR-0006). The base `CMD`
  sets `shared_preload_libraries=age`; this image **overrides `CMD`** to
  `postgres -c shared_preload_libraries=age,vchord,pg_textsearch` because AGE,
  VectorChord, and pg_textsearch all require preloading. ENTRYPOINT is still
  inherited — do not override it.
- pgvector is built from source, pinned to a PG18-compatible release with the
  CVE-2026-3172 fix. Keep it pinned; bump deliberately.
- VectorChord (`vchord`) is installed from the per-arch upstream `.deb`
  (`VCHORD_VERSION`), depends on pgvector (0.7–<0.9), and is created with
  `CREATE EXTENSION vchord CASCADE`. The vchord `.deb` does **not** pull an apt
  pgvector, so the source build remains the single `vector` provider.
- `pg_textsearch` (Tiger Data) is **built from source via PGXS** (git tag
  `PG_TEXTSEARCH_VERSION`), the same pattern as pgvector/libversion — no `.deb`
  exists upstream. Pure C on native Postgres pages (no Tantivy/Rust). It requires
  preloading. **PostgreSQL-licensed (permissive)** — it replaced the AGPL-only
  `pg_search` (ADR-0007), which is why the image's copyleft floor dropped to
  VectorChord's `AGPL-3.0 OR ELv2`. BM25 query API: `USING bm25(col) WITH
  (text_config='english')` + `<@>` in `ORDER BY` (not pg_search's `@@@`).
- PostgreSQL 18 moved the image data dir to `/var/lib/postgresql/18/docker`
  and the VOLUME to `/var/lib/postgresql` — mount the latter.
- Init scripts in `docker-entrypoint-initdb.d/` only run on first cluster init
  and only against the default database.
- `libversion` (repology) is two source builds: the `libversion` C library
  (CMake → `/usr/local/lib`, kept at runtime + `ldconfig`) and the PGXS
  extension linked against it via pkg-config (`PKG_CONFIG_PATH=/usr/local/lib/pkgconfig`).
  MIT-licensed, no preload. Pinned via `LIBVERSION_VERSION` / `PG_LIBVERSION_VERSION`.
- Security (ADR-0006): base image is digest-pinned and the vchord `.deb` is
  sha256-verified per arch; source-built extensions (pgvector, pg_textsearch,
  libversion) are pinned by git tag. **When bumping any of these, update the
  pinned digest/checksum/tag** (build fails otherwise — by design). `test/scan.sh`
  runs syft+grype; policy in `.grype.yaml`.

**Topology/licensing in [ADR-0004](docs/adr/0004-extension-topology-and-licensing.md) + [ADR-0007](docs/adr/0007-replace-pg-search-with-pg-textsearch.md):**

- Single multi-extension instance hosts AGE, pgvector, VectorChord,
  pg_textsearch, pg_trgm. The built image is a mixed-license aggregate whose
  copyleft floor is **`AGPL-3.0 OR ELv2`** — set by VectorChord, the sole
  copyleft component (pg_textsearch is permissive). This is fine for the
  self-hosted / dogfooding model; a public-distribution or SaaS pivot must
  revisit ADR-0004 / ADR-0007. See `LICENSING.md`.

**AI delegation in this project:**

- **AI leads**: Dockerfile/init scripting, smoke tests, docs, version research
- **Human leads**: extension-set / topology decisions, release tagging
- **Collaborative**: ADRs, image hardening
