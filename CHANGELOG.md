# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.6] - 2026-06-15

### Added

- Dependabot config (`.github/dependabot.yml`): GitHub Actions ecosystem
  (weekly, grouped, `ci:` prefix) and Docker ecosystem for the base image
  FROM/digest (weekly, `build:` prefix). Both target `develop`.

## [0.1.5] - 2026-06-15

### Added

- GitHub Actions CI (`.github/workflows/ci.yml`) on push/PR to `main`/`develop`
  (and `v*` tags): a **lint** job (hadolint, shellcheck, dprint, gitleaks) and a
  **build-scan** job that builds the image, runs the smoke test, and runs the
  syft SBOM + grype scan — reusing `build.sh` / `test/smoke-test.sh` /
  `test/scan.sh` so CI matches local. Runs on amd64 (pins verified to match).

## [0.1.4] - 2026-06-15

### Added

- OCI image labels (`org.opencontainers.image.*`): static title, description,
  licenses (`Apache-2.0 AND PostgreSQL AND MIT AND AGPL-3.0-only`), source, and
  base name + digest; plus `version` / `revision` / `created` as build-args.
  `build.sh [runtime] [tag]` stamps the dynamic ones from the git checkout.

## [0.1.3] - 2026-06-15

### Added

- repology `libversion` extension (version-string comparison functions +
  `versiontext` type, MIT): built from source — the `libversion` C library
  (CMake, `lib 3.0.4`) plus the PGXS extension (`2.0.0`); created on first init,
  no preloading. Smoke test asserts `version_compare2`.

## [0.1.2] - 2026-06-15

### Added

- README "Persistence" section: how PGDATA survives the container lifecycle
  (named volume / bind mount vs. no `-v`), the first-init-only behaviour of the
  extension scripts, and the **verified** Apple `container` anonymous-volume
  behaviour (bare `VOLUME` creates no anonymous volume; named volumes persist
  across `rm`) versus Docker/Podman.

## [0.1.1] - 2026-06-15

### Fixed

- Pre-push hook: guard the hadolint container fallback on `podman info`
  (reachability) instead of `command -v podman` (installed), so a stopped
  podman machine degrades to a skip-with-warning instead of hard-blocking
  pushes.

## [0.1.0] - 2026-06-15

### Added

- Ragù PostgreSQL image: `apache/age:release_PG18_1.7.0` (PostgreSQL 18 +
  Apache AGE 1.7.0) extended with pgvector 0.8.2 (built from source),
  VectorChord (`vchord`) 1.1.1 (upstream `.deb`), and `pg_trgm`, for graph +
  vector + lexical retrieval in one database.
- VectorChord support: installed from the per-arch upstream `.deb` and enabled
  via `shared_preload_libraries=age,vchord` (overrides the base `CMD`);
  `vchord` created with `CASCADE` on top of pgvector.
- ParadeDB `pg_search` 0.24.0 (BM25 full-text / hybrid): installed from the
  per-distro/per-arch upstream `.deb` (codename derived from the base image);
  preload extended to `age,vchord,pg_search`. **Note:** `pg_search` is
  AGPL-only, making AGPL-3.0 the image's copyleft floor (see `LICENSING.md`,
  ADR-0005).
- Container security checks (ADR-0006): base image pinned by digest; VectorChord
  and pg_search `.deb`s sha256-verified per arch before install; `test/scan.sh`
  for SBOM (syft) + vulnerability scan (grype) with a `.grype.yaml` policy.
- Runtime-agnostic smoke test (`test/smoke-test.sh`: podman | container | docker).
- Podman-first / Docker-compatible `compose.yaml` (PG18-correct
  `/var/lib/postgresql` volume).
- Project orchestration alignment at tier **t1**: CLAUDE.md, Apache-2.0 LICENSE,
  this changelog, foundation ADRs, and pre-commit quality gates.

### Security

- Patched `libgnutls30t64` (deb13u1 → deb13u4) and `libcap2`
  (→ deb13u1+b1), version-pinned, to clear the fixable High/Critical CVEs
  surfaced by grype (CVE-2026-42010, CVE-2026-33845 Critical; CVE-2026-42009/
  5260/3833/33846, CVE-2026-4878 High).
- `.grype.yaml` gate policy: fail only on fixable-and-unpatched High/Critical;
  CVEs with no apt remediation and the gosu Go-stdlib are ignored by documented
  policy. The grype gate now passes (no actionable High/Critical remain).

### Verified

- Built and smoke-tested under Podman and Apple `container` (AGE 1.7.0,
  pgvector 0.8.2, vchord 1.1.1, pg_search 0.24.0, pg_trgm 1.6; AGE Cypher
  round-trip and pgvector distance OK; `vchord` and `pg_search` load,
  confirming the `age,vchord,pg_search` preload override works).
