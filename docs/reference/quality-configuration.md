# Quality Configuration

Single source of truth for quality settings in Ragù PostgreSQL. Implements
[ADR-0002](../adr/0002-adopt-development-best-practices.md).

## Formatting Standards

| Setting                  | Value  | Applies To                   |
| ------------------------ | ------ | ---------------------------- |
| Indent style             | spaces | All files                    |
| Indent size              | 2      | md, yml, yaml, json, sql, sh |
| Indent size              | 4      | Dockerfile                   |
| End of line              | lf     | All files                    |
| Final newline            | yes    | All files (except LICENSE)   |
| Trim trailing whitespace | yes    | All files (except LICENSE)   |
| Charset                  | utf-8  | All files                    |

Enforced via `.editorconfig`. `shfmt` reads `.editorconfig` for shell indent.

## Quality Checks by Stage

| Check              | Pre-commit | Pre-push | CI  | Tool             | Notes                        |
| ------------------ | ---------- | -------- | --- | ---------------- | ---------------------------- |
| Secret scan        | Yes        | -        | Yes | gitleaks         | `protect --staged`           |
| Markdown format    | Yes        | -        | Yes | dprint           | `dprint check`               |
| Shell format       | Yes        | -        | Yes | shfmt            | `shfmt --diff`               |
| Shell lint         | -          | Yes      | Yes | shellcheck       |                              |
| Dockerfile lint    | -          | Yes      | Yes | hadolint         | see note below               |
| Build + smoke test | -          | -        | Yes | podman/container | run manually pre-release     |
| SBOM + vuln scan   | -          | -        | Yes | syft + grype     | `test/scan.sh`; see ADR-0006 |
| `.deb` + base pin  | build-time | -        | -   | sha256 / digest  | enforced during build        |

There is no application runtime to unit-test; the deliverable is the image, so
the functional gate is `test/smoke-test.sh` under both Podman and Apple
`container` (run manually / in CI rather than on every push — it builds and
boots a container).

## Tooling

Installed via MacPorts: `lefthook`, `dprint`, `shellcheck`, `shfmt`, `gitleaks`.
Security scanners: `syft` + `grype` (image SBOM + CVE scan, `test/scan.sh`);
`cosign` available for future image signing (see ADR-0006).

**hadolint** is not packaged for MacPorts. The pre-push Dockerfile lint uses a
local `hadolint` binary if present, else the `hadolint/hadolint` container via
Podman, else it warns without blocking. To enable it reliably, install a
hadolint binary or ensure Podman can pull the image.

## Hooks

- Framework: **lefthook** (`.lefthook.yml`), installed with `lefthook install`.
- The global git template (`~/.git-template`) installs a gitleaks-only
  `pre-commit`; lefthook overwrites `.git/hooks/`, so gitleaks is re-declared
  in `.lefthook.yml` to preserve the secret scan.

## Validation Checklist

- [ ] `.editorconfig` matches Formatting Standards
- [ ] `lefthook run pre-commit` passes
- [ ] `lefthook run pre-push` passes
- [ ] Secret scanning active on every commit
