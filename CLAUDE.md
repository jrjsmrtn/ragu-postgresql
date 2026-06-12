# Ragù PostgreSQL

A RAG-ready PostgreSQL 18 container image combining graph (Apache AGE), vector
(pgvector), and lexical (pg_trgm) retrieval in a single database, for building
Retrieval-Augmented Generation backends.

## Project Context

- **Category**: Development
- **Type**: Container image (PostgreSQL distribution)
- **Stack**: Dockerfile (OCI), PostgreSQL 18, Apache AGE, pgvector,
  VectorChord (`vchord`); built and tested with Podman and Apple `container`
- **License**: Apache-2.0
- **Tier**: t1

## Project Tier

Current tier: **t1** (decision-tracked)

Tier-specific artifacts in this project:

- CLAUDE.md, conventional commits, gitflow (`main` / `develop`)
- Foundation + decision ADRs (`docs/adr/0001`–`0004`)
- CHANGELOG.md (Keep a Changelog)
- Two-stage pre-commit hooks

Promotion triggers being watched:

- **t1 → t2** when the documentation outgrows README + ADRs (e.g. usage guides
  for the hybrid-retrieval query patterns warrant a Diátaxis tree), or when the
  extension topology needs a C4 model.

## Status

Image built and smoke-tested under both Podman and Apple `container` (AGE
1.7.0, pgvector 0.8.2, vchord 1.1.1, pg_trgm 1.6). Topology + licensing posture
recorded in ADR-0004. Unreleased (pre-`v0.1.0`); `pg_search` is the one
deferred extension candidate.

## Foundational ADRs

Read these at the start of each AI session for complete context:

| ADR                                                           | Purpose              | Summary                            |
| ------------------------------------------------------------- | -------------------- | ---------------------------------- |
| [ADR-0001](docs/adr/0001-record-architecture-decisions.md)    | HOW TO DECIDE        | Decision methodology               |
| [ADR-0002](docs/adr/0002-adopt-development-best-practices.md) | HOW TO DEVELOP       | Development practices              |
| [ADR-0003](docs/adr/0003-technology-stack.md)                 | WHAT TECH            | Technology stack                   |
| [ADR-0004](docs/adr/0004-extension-topology-and-licensing.md) | TOPOLOGY + LICENSING | Single instance; AGPL/ELv2 posture |

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
# Build (pick a runtime)
podman build -t local/ragu-postgresql:latest .
container build -t local/ragu-postgresql:latest .

# Smoke test (runtime-agnostic: podman | container | docker)
test/smoke-test.sh podman
test/smoke-test.sh container
```

## AI Collaboration Notes

**Project-specific guidance:**

- Base image is `apache/age:release_PG18_1.7.0` = official `postgres:18`
  (Debian) + Apache AGE 1.7.0. The base `CMD` sets
  `shared_preload_libraries=age`; this image **overrides `CMD`** to
  `postgres -c shared_preload_libraries=age,vchord` because AGE and VectorChord
  both require preloading. ENTRYPOINT is still inherited — do not override it.
- pgvector is built from source, pinned to a PG18-compatible release with the
  CVE-2026-3172 fix. Keep it pinned; bump deliberately.
- VectorChord (`vchord`) is installed from the per-arch upstream `.deb`
  (`VCHORD_VERSION`), depends on pgvector (0.7–<0.9), and is created with
  `CREATE EXTENSION vchord CASCADE`. The vchord `.deb` does **not** pull an apt
  pgvector, so the source build remains the single `vector` provider.
- PostgreSQL 18 moved the image data dir to `/var/lib/postgresql/18/docker`
  and the VOLUME to `/var/lib/postgresql` — mount the latter.
- Init scripts in `docker-entrypoint-initdb.d/` only run on first cluster init
  and only against the default database.

**Topology/licensing settled in [ADR-0004](docs/adr/0004-extension-topology-and-licensing.md):**

- Single multi-extension instance hosts AGE, pgvector, VectorChord, pg_trgm.
  ParadeDB `pg_search` (BM25 full-text) is the one remaining candidate —
  deferred because it is AGPL-only (no ELv2 fallback); read ADR-0004 before
  adopting. The built image is a mixed-license aggregate; see `LICENSING.md`.

**AI delegation in this project:**

- **AI leads**: Dockerfile/init scripting, smoke tests, docs, version research
- **Human leads**: extension-set / topology decisions, release tagging
- **Collaborative**: ADRs, image hardening
