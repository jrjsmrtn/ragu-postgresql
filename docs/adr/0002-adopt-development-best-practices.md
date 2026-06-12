# 2. Adopt Development Best Practices

Date: 2026-06-13

## Status

Accepted

## Context

Ragù PostgreSQL is a **container image** project (a PostgreSQL distribution),
not an application or library. The "code" is a Dockerfile, init SQL, and shell
tests. We need consistent practices that fit this shape and support
AI-assisted workflows, scaled to a single-deliverable project at tier **t1**.

This project follows [AI-Assisted Project Orchestration patterns](https://github.com/jrjsmrtn/ai-assisted-project-orchestration).

## Decision

### 1. Testing Strategy

There is no application runtime to unit-test. The deliverable is the image, so
testing is **build + smoke test**:

- `test/smoke-test.sh` is runtime-agnostic (`podman | container | docker`).
- It verifies extension versions and exercises each extension (AGE Cypher
  round-trip, pgvector distance, pg_trgm similarity).
- A change is "tested" when the image builds and the smoke test passes under
  **both Podman and Apple `container`** (the two target runtimes).

### 2. Semantic Versioning

- Follow [SemVer 2.0.0](https://semver.org/). During development: `0.x.x`,
  patch-level bumps unless major changes land.
- No `1.0.0` until the extension topology is settled and the image is hardened.

### 3. Git Workflow

- **Gitflow**: `main` (releases), `develop` (integration), `feature/*`,
  `release/*`, `hotfix/*`.
- **Conventional Commits**: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`,
  `chore:`.

### 4. Change Documentation

- **Keep a Changelog** format in `CHANGELOG.md`
  (Added, Changed, Deprecated, Removed, Fixed, Security).

### 5. Formatting and Editor Configuration

- `.editorconfig` for consistent whitespace.
- Markdown formatting via dprint.
- Dockerfile linting via hadolint; shell via shellcheck + shfmt.

### 6. Quality Automation

Two-stage git hooks (see [setup-pre-commit]; ADR-implemented separately):

- **Pre-commit** (fast): formatting checks, secret scanning (gitleaks).
- **Pre-push** (thorough): hadolint (Dockerfile), shellcheck (shell), and a
  build/smoke-test gate where practical.

### 7. Image Conventions

- **Podman-first, Docker-compatible**; must also build/run under Apple
  `container`.
- **Pin upstream versions** (base image tag, pgvector release); bump
  deliberately and record notable bumps in the changelog.
- **Do not override** the base image's `ENTRYPOINT`/`CMD` (it provides the
  postgres entrypoint and `shared_preload_libraries=age`).
- Keep the image slim: strip build toolchains after compiling extensions.

### Deferred to t2 (promotion triggers)

These orchestration practices are intentionally **not** adopted at t1 and are
the t1→t2 promotion triggers:

- Diátaxis `docs/` tree (tutorials/howto/reference/explanation).
- C4 architecture-as-code model.
- Sprint cadence and roadmap-driven planning.
- REUSE/SPDX licensing headers (LICENSE file is present; per-file SPDX is t2).

## Consequences

**Positive**:
- Practices match the artifact (an image), avoiding ceremony that doesn't fit.
- Clear, automatable quality gates (lint + secret scan + smoke test).
- Explicit, lightweight promotion path to t2.

**Negative**:
- Smoke-test-only coverage; regressions in untested extension behaviour can
  slip through until exercised.
- Manual discipline needed to keep pinned versions current.

## References

- [AI-Assisted Project Orchestration](https://github.com/jrjsmrtn/ai-assisted-project-orchestration)
- [hadolint](https://github.com/hadolint/hadolint), [shellcheck](https://www.shellcheck.net/)
