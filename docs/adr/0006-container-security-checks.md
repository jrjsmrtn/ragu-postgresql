# 6. Container Security Checks

Date: 2026-06-13

## Status

Accepted

## Context

The deliverable is a container image bundling a PostgreSQL base plus several
extensions, two of them fetched as `.deb`s at build time. We need
proportionate security/supply-chain hygiene: know the CVEs we ship, know the
components (and their licenses), and ensure the inputs we pull haven't been
tampered with. This complements the existing gates from
[ADR-0002](0002-adopt-development-best-practices.md) (hadolint, gitleaks).

The project's posture is self-hosted / dogfooding (ADR-0004), but the licensing
ADRs contemplate possible distribution, so the checks should be publish-ready.

## Decision

Adopt four checks now:

1. **Image vulnerability scan** — `grype` over the built image, failing on
   High/Critical. Threshold and a curated ignore-list live in `.grype.yaml`
   (base images carry won't-fix CVEs; blanket-ignoring is not allowed —
   entries are justified individually).
2. **SBOM + license audit** — `syft` emits SPDX + CycloneDX SBOMs; the license
   summary cross-checks `LICENSING.md` and surfaces any license pulled in
   transitively. Feeds grype.
3. **`.deb` integrity** — the VectorChord and pg_search `.deb`s are pinned by
   **sha256 (per arch)** in the Dockerfile and verified before install, closing
   the "curl-and-install whatever arrives" gap.
4. **Base image digest pin** — `FROM apache/age:…@sha256:<index-digest>` so the
   mutable tag can't change under us and builds are reproducible. The pinned
   digest is the multi-arch OCI **index** digest, preserving arm64/amd64.

### Where they run

- **Build time** (3, 4): pinning + verification are part of `docker build`; a
  bad checksum or moved digest fails the build.
- **Pre-commit / pre-push** (unchanged): stay fast — gitleaks + dprint + shfmt
  (pre-commit), shellcheck + hadolint (pre-push). Image scanning is **not**
  added here; it needs a built image and is too slow for a hook.
- **Release / CI** (1, 2): `test/scan.sh [image] [podman|docker]` runs
  syft + grype on demand and gates a release.

## Alternatives / deferred

- **Trivy** (one tool for vuln + SBOM + license + misconfig + secret): viable,
  but `grype`/`syft`/`cosign` were already installed, so we use those. Trivy
  remains a reasonable future consolidation.
- **Image misconfig lint** (Dockle / `trivy config`): deferred. Note the
  postgres base legitimately starts as root and `gosu`-drops to `postgres`, so
  a "runs as root" finding needs context, not a blind fix.
- **Signing / provenance** (`cosign` sign + SBOM attestation): deferred until
  the image is actually distributed (ADR-0004/0005 defer distribution).
- **Runtime hardening** (cap-drop, `no-new-privileges`, read-only rootfs +
  tmpfs, secrets via `*_FILE`): deployment-time; to be documented, not a
  build-time check.

## Consequences

**Positive**:

- We ship a known CVE posture and a verifiable component/license inventory.
- Build inputs (base + `.deb`s) are integrity-pinned and reproducible.

**Negative**:

- Maintenance: bumping the base, VectorChord, or pg_search now also means
  updating the pinned digest / checksums (a deliberate, visible step — by
  design). `.grype.yaml` ignores need periodic review.
- Scanning needs a built image, so it lives outside the fast hooks.

## References

- `test/scan.sh`, `.grype.yaml`
- [grype](https://github.com/anchore/grype) · [syft](https://github.com/anchore/syft)
- [ADR-0002](0002-adopt-development-best-practices.md) · [LICENSING.md](../../LICENSING.md)
