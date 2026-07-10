# 9. Testing Strategy: Smoke + Scan + a Shared pgTAP Suite

Date: 2026-07-10

## Status

Accepted

## Context

This project is a **packaging** artifact — a RAG-ready PostgreSQL image — so its
tests to date were image-shaped: `test/smoke-test.sh` (extension round-trips over
`psql` inside a throwaway container) and `test/scan.sh` (syft SBOM + grype CVE gate,
ADR-0006). Two gaps remained:

1. **Correctness contracts** — that the shipped extensions can actually build the
   full RAG schema (a `chunk` table with an index per modality: HNSW, GIN full-text,
   GIN trigram, and BM25) — were only spot-checked by the smoke script's ad-hoc SQL.
2. **Cross-sibling comparability** — the sibling `ragu-pglite` evaluates the same
   trio on a WASM build; a rigorous "server vs embedded" story wants the _same_
   assertions to pass on both, not two drifting hand-written checks.

## Decision

Adopt a **layered** test strategy and make the SQL correctness layer a **shared**
artifact with the sibling.

1. **CVE gate — `test/scan.sh`** (syft + grype, ADR-0006). Unchanged.
2. **Smoke — `test/smoke-test.sh`.** Boots the image and round-trips each extension
   over in-container `psql`. Unchanged.
3. **SQL correctness — shared pgTAP** (`test/sql/rag_trio.pgtap.sql`), run by
   `test/pgtap.sh`. Because the image ships extensions but **no application schema**,
   the runner first builds `test/sql/rag_trio.fixture.sql` (the RAG-trio schema +
   indexes) in a throwaway container, then asserts it with pgTAP. Like the smoke
   test it is runtime-agnostic (`podman | container | docker`) and scans the TAP
   stream for `not ok` via in-container `psql` — **no host `psql`/`pg_prove`**.
4. **pgTAP is a test-only dependency, not shipped in the image** (approach A). It is
   installed from PGDG (`postgresql-<major>-pgtap`) into the throwaway container at
   test time. The production image stays exactly as built — no test framework, no
   extra attack surface.
5. **The pgTAP suite is byte-identical with `ragu-pglite`'s** (`rag_trio.pgtap.sql`,
   same `sha256`), kept in sync by hand for now; a shared `ragu-corpus`-style repo is
   the eventual home (see the sibling's ADR-0008 / ADR-0007).

### Alternatives considered

- **`pg_regress`**: server-native but expected-output diffing is brittle and yields
  no JUnit; pgTAP's declarative assertions port cleanly to the WASM sibling.
- **Approach B — bake pgTAP into a test image** (`FROM base + postgresql-N-pgtap`):
  hermetic (no test-time network) but a second image artifact to build/scan/pin.
  Rejected for now in favour of the simpler at-test-time install (A); revisit if CI
  network flakiness or reproducibility demands it.
- **Shipping pgTAP in the production image**: rejected — it is test-only and would
  add unpatched surface to a deliberately minimal image.

## Consequences

**Positive**: the image's core promise — the trio extensions build every RAG index
type on native PostgreSQL 18 — is now asserted, not assumed; the identical suite
passing here and on PGlite (sibling ADR-0008) makes the comparative verdict rigorous;
the production image is untouched.

**Negative**: approach A needs **network at test time** (the PGDG apt install), so
`pgtap.sh` is not hermetic; `test/pgtap.sh` is **not yet wired into CI** (it is a
local/manual gate today); the byte-identical suite is hand-synced with the sibling
until a shared repo exists; and the assertions run against a **fixture** schema this
repo builds, not an application schema it ships (an honest asymmetry vs the sibling,
whose `createDb` provides the real schema).

## References

- `test/pgtap.sh`, `test/sql/` — the runner, the shared suite, the fixture
- [ADR-0006](0006-container-security-checks.md) — the scan gate + hardened-image posture the test tooling stays out of
- Sibling `ragu-pglite` **ADR-0008** (testing strategy) and **ADR-0007** (shared-artifact extraction pattern)
