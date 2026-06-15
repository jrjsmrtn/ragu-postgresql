# 5. Adopt ParadeDB pg_search for BM25 full-text

Date: 2026-06-13

## Status

Accepted

Supersedes the deferral of `pg_search` in
[ADR-0004](0004-extension-topology-and-licensing.md).

## Context

[ADR-0004](0004-extension-topology-and-licensing.md) adopted a single
multi-extension instance (AGE + pgvector + VectorChord + pg_trgm) and
**deferred** ParadeDB `pg_search`, conditioned on "a concrete full-text need
_and_ a deliberate decision in light of this ADR" — the concern being that
`pg_search` is **AGPL-3.0 with no ELv2 fallback**.

We now want true hybrid retrieval: BM25 lexical relevance scored and combined
with vector similarity in one query. `pg_trgm` gives trigram/fuzzy matching but
not BM25 ranking. This is the concrete need, so we make the deliberate decision.

## Decision

Adopt **ParadeDB `pg_search` 0.24.0** as a bundled extension.

- Installed from ParadeDB's per-distro, per-arch Debian package; the distro
  codename is derived from the base image (Debian 13 _trixie_) so the `.deb`
  matches the runtime's libc/ABI.
- `pg_search` requires preloading, so the image's `CMD` now sets
  `shared_preload_libraries=age,vchord,pg_search`.
- Created on first init via `CREATE EXTENSION pg_search`.

### Resulting extension set

| Extension            | Purpose                     | License            |
| -------------------- | --------------------------- | ------------------ |
| Apache AGE 1.7.0     | graph (openCypher)          | Apache-2.0         |
| pgvector 0.8.2       | vector type                 | PostgreSQL License |
| VectorChord 1.1.1    | scalable vector indexing    | AGPL-3.0 / ELv2    |
| **pg_search 0.24.0** | **BM25 full-text / hybrid** | **AGPL-3.0**       |
| pg_trgm              | trigram / fuzzy             | PostgreSQL License |

## Consequences

**Positive**:

- True hybrid retrieval — BM25 + vector + graph + trigram — joinable in one SQL
  query/transaction over one connection.

**Negative / obligations**:

- The image now bundles **two** AGPL components, one of which (`pg_search`) is
  **AGPL-only**. The practical effect: the image's copyleft floor is now
  **AGPL-3.0** — there is no whole-image "choose ELv2 to avoid copyleft" path
  anymore, because `pg_search` offers no ELv2/permissive option (only a paid
  commercial license). `LICENSING.md` is updated accordingly.
- Image size grows materially (Tantivy/BM25 engine).

**Risks**:

- **Distribution pivot** (public image or managed-service SaaS) now
  unavoidably triggers AGPL obligations for `pg_search` (and AGPL or commercial
  for VectorChord). _Mitigation_: stay on the self-hosted/dogfooding model of
  ADR-0004; if that changes, obtain ParadeDB/VectorChord commercial licenses or
  drop to the permissive-only fallback set (which loses BM25 and VectorChord).

This decision keeps the **self-hosted / dogfooding** distribution model of
ADR-0004, under which AGPL §13 (network source offer) is not triggered.

## References

- [`LICENSING.md`](../../LICENSING.md)
- [ADR-0004](0004-extension-topology-and-licensing.md) — topology + licensing posture
- [ParadeDB pg_search](https://github.com/paradedb/paradedb) · [Why We Picked AGPL](https://www.paradedb.com/blog/agpl)
