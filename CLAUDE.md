# Ragù PostgreSQL

A RAG-ready PostgreSQL 18 container image combining graph (Apache AGE), vector
(pgvector), and lexical (pg_trgm) retrieval in a single database, for building
Retrieval-Augmented Generation backends.

## Project Context

- **Category**: Development
- **Type**: Container image (PostgreSQL distribution)
- **Stack**: Dockerfile (OCI), PostgreSQL 18, Apache AGE, pgvector; built and
  tested with Podman and Apple `container`
- **License**: Apache-2.0
- **Tier**: t1

## Project Tier

Current tier: **t1** (decision-tracked)

Tier-specific artifacts in this project:

- CLAUDE.md, conventional commits, gitflow (`main` / `develop`)
- Foundation ADRs (`docs/adr/0001`–`0003`)
- CHANGELOG.md (Keep a Changelog)
- Two-stage pre-commit hooks

Promotion triggers being watched:

- **t1 → t2** when the documentation outgrows README + ADRs (e.g. usage guides
  for the hybrid-retrieval query patterns warrant a Diátaxis tree), or when the
  extension topology needs a C4 model.

## Status

Foundational image is built and smoke-tested under both Podman and Apple
`container` (AGE 1.7.0, pgvector 0.8.2, pg_trgm 1.6; Cypher round-trip +
vector distance verified). Next candidate work: decide the full extension set
(see open decision below) and record the topology ADR.

## Foundational ADRs

Read these at the start of each AI session for complete context:

| ADR                                                           | Purpose        | Summary               |
| ------------------------------------------------------------- | -------------- | --------------------- |
| [ADR-0001](docs/adr/0001-record-architecture-decisions.md)    | HOW TO DECIDE  | Decision methodology  |
| [ADR-0002](docs/adr/0002-adopt-development-best-practices.md) | HOW TO DEVELOP | Development practices |
| [ADR-0003](docs/adr/0003-*.md)                                | WHAT TECH      | Technology stack      |

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
  (Debian) + Apache AGE 1.7.0; `shared_preload_libraries=age` is set by the
  inherited base `CMD` — do not override ENTRYPOINT/CMD.
- pgvector is built from source, pinned to a PG18-compatible release with the
  CVE-2026-3172 fix. Keep it pinned; bump deliberately.
- PostgreSQL 18 moved the image data dir to `/var/lib/postgresql/18/docker`
  and the VOLUME to `/var/lib/postgresql` — mount the latter.
- Init scripts in `docker-entrypoint-initdb.d/` only run on first cluster init
  and only against the default database.

**Open decision (not yet recorded as an ADR):**

- Extension topology: single multi-extension PostgreSQL instance (AGE +
  pgvector, optionally VectorChord + ParadeDB `pg_search`) vs. multiple
  containers. Leaning single-instance to enable single-query hybrid retrieval;
  exact extension set TBD. Record as a topology ADR once settled.

**AI delegation in this project:**

- **AI leads**: Dockerfile/init scripting, smoke tests, docs, version research
- **Human leads**: extension-set / topology decisions, release tagging
- **Collaborative**: ADRs, image hardening
