# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Ragù PostgreSQL image: `apache/age:release_PG18_1.7.0` (PostgreSQL 18 +
  Apache AGE 1.7.0) extended with pgvector 0.8.2 (built from source) and
  `pg_trgm`, for graph + vector + lexical retrieval in one database.
- Auto-created extensions on first init via `docker-entrypoint-initdb.d/`.
- Runtime-agnostic smoke test (`test/smoke-test.sh`: podman | container | docker).
- Podman-first / Docker-compatible `compose.yaml` (PG18-correct
  `/var/lib/postgresql` volume).
- Project orchestration alignment at tier **t1**: CLAUDE.md, Apache-2.0 LICENSE,
  this changelog, foundation ADRs, and pre-commit quality gates.

### Verified

- Built and smoke-tested under Podman and Apple `container` (AGE 1.7.0,
  pgvector 0.8.2, pg_trgm 1.6; AGE Cypher round-trip and pgvector distance OK).
