# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-07-09

### Security

- Patch newly-disclosed fixable base-image CVEs surfaced by grype (ADR-0006),
  version-pinned in the Dockerfile's security-upgrade layer:
  - glibc set (`libc6`/`libc-bin`/`libc-l10n`/`locales`) → `2.41-12+deb13u3`
    (CVE-2026-0915, CVE-2026-0861, CVE-2026-4046, CVE-2026-4437, CVE-2025-15281
    High; CVE-2026-4438 Medium);
  - krb5 runtime (`libgssapi-krb5-2`/`libk5crypto3`/`libkrb5-3`/`libkrb5support0`)
    → `1.21.3-5+deb13u1` (CVE-2026-40355, CVE-2026-40356 High);
  - `libsystemd0`/`libudev1` → `257.13-1~deb13u1`, `libgcrypt20` → `deb13u1`,
    `libsqlite3-0` → `deb13u1`, `sed` → `deb13u1` (Medium/Low).
  - Scan gate green again (only the policy-ignored gosu `golang.org/x/sys` Low
    remains, below the High threshold).

### Removed

- **Remove VectorChord (`vchord`)** — the image's sole copyleft /
  source-available component (AGPL-3.0 or Elastic License 2.0, dual) — ADR-0008,
  amends ADR-0004 by exercising its reserved permissive-only fallback:
  - **Vector search is now pgvector-only** (HNSW / IVFFlat). `01-create-extensions-rag.sql`
    creates `vector` directly (no `CASCADE`); the `vchord` `.deb` install layer and
    its per-arch sha256 block are dropped from the `Dockerfile`.
  - **The image becomes a fully permissive aggregate** —
    `Apache-2.0 AND PostgreSQL AND MIT`, **no copyleft floor**. No AGPL §13
    source-offer and no ELv2 managed-service prohibition apply to any component;
    public redistribution and SaaS are no longer license-constrained. OCI
    `licenses` label and `LICENSING.md` updated.
  - Preload drops to `shared_preload_libraries=age,pg_textsearch` (baked
    `postgresql.conf.sample` + `CMD`); the verify script and smoke test now
    expect **five** extensions (`age`, `vector`, `pg_textsearch`, `pg_trgm`,
    `libversion`).
  - **No `.deb` is fetched at build time anymore** — every non-base extension is
    source-built and git-tag-pinned (ADR-0006 check #3 dormant).
  - **Trade-off / capability loss:** VectorChord's disk-friendly RaBitQ
    quantization and scalable index build. At large corpus sizes pgvector HNSW is
    more memory-hungry and IVFFlat less accurate — revisit if the corpus outgrows
    pgvector.
  - **Breaking** for any consumer that created `vchord` indexes; fall back to
    pgvector index types.

## [0.2.0] - 2026-07-07

### Changed

- Replace ParadeDB `pg_search` (0.24.0) with **Tiger Data `pg_textsearch` 1.3.1**
  as the image's BM25 full-text engine (ADR-0007, supersedes ADR-0005):
  - `pg_textsearch` is **PostgreSQL-licensed** (permissive) and is now the only
    change to the license aggregate — the image's copyleft floor drops from hard
    **`AGPL-3.0-only`** back to VectorChord's **`AGPL-3.0-only OR Elastic-2.0`**,
    restoring a whole-image ELv2 path (no AGPL-only component remains). OCI
    `licenses` label and `LICENSING.md` updated accordingly.
  - Installed by **building from source via PGXS** (git tag `v1.3.1`) — pure C on
    native Postgres pages, no Tantivy/Rust, no upstream `.deb`; the same
    source-build pattern as pgvector and libversion.
  - Preload updated to `shared_preload_libraries=age,vchord,pg_textsearch`
    (baked into `postgresql.conf.sample` and the `CMD`); first-init
    `CREATE EXTENSION pg_textsearch`; the verify script expects it in place of
    `pg_search`.
  - **Breaking query-API change** for image consumers: BM25 indexes are now
    `USING bm25(col) WITH (text_config='english')` and ranked with the `<@>`
    operator in `ORDER BY` (pgvector-style), not `pg_search`'s `@@@` predicate /
    `paradedb.score`. Downstream `ragu-*` lexical queries must migrate.
  - **Capability loss:** no phrase/proximity queries (pg_textsearch stores no
    term positions). Not used by the current `ragu-*` consumers (bag-of-tokens
    BM25 fused by RRF), so no present functional impact.
  - Smoke test rewritten to the new BM25 index + `<@>` ranked-search syntax;
    verified end-to-end under Podman (all six extensions load; ranked query
    returns the expected row first).

## [0.1.10] - 2026-06-25

### Changed

- Harden the first-init against the intermittent `pg_search` flake:
  - bake `shared_preload_libraries = 'age,vchord,pg_search'` into
    `postgresql.conf.sample` so every initialized cluster (incl. the
    entrypoint's temporary init server) loads the preload from the config file,
    not solely from the CMD `-c` args;
  - add `02-verify-extensions.sql` to fail the init **loudly** if any of the six
    extensions is missing — a partial init can no longer produce a
    running-but-incomplete image;
  - smoke test now exercises a real `pg_search` BM25 index + `@@@` search.
  - Note: `pg_search` 0.24.0 **requires** preloading (verified) — it cannot be
    dropped from `shared_preload_libraries`.

## [0.1.9] - 2026-06-19

### Added

- Project roadmap (`docs/roadmap/roadmap.md`): vision, status, backlog, and
  release history. Top backlog item: harden the `pg_search` first-init against
  the transient v0.1.8 flake.

## [0.1.8] - 2026-06-15

### Changed

- CI: bump GitHub Actions (via Dependabot) — `actions/checkout` v6,
  `hadolint-action` v3.3.0, `gitleaks-action` v3, `upload-artifact` v7,
  `docker/setup-qemu`+`setup-buildx`+`login` v4, `build-push-action` v7.

## [0.1.7] - 2026-06-15

### Added

- CI **publish-on-tag** job: on `v*` tags (after lint + build-scan pass), build
  multi-arch (amd64 + arm64), push to `ghcr.io/jrjsmrtn/ragu-postgresql`
  (`:<version>` + `:latest`), and sign with **cosign keyless** (GitHub OIDC).
  README documents pulling and `cosign verify`.

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
