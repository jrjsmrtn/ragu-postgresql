# 7. Replace ParadeDB pg_search with Tiger Data pg_textsearch for BM25

Date: 2026-07-07

## Status

Accepted

Supersedes [ADR-0005](0005-adopt-pg-search-bm25.md) (adopt ParadeDB `pg_search`).

## Context

[ADR-0005](0005-adopt-pg-search-bm25.md) adopted ParadeDB `pg_search` 0.24.0 to
get BM25 lexical relevance for hybrid retrieval. It works, but it carries two
costs that have become more visible in use:

1. **License.** `pg_search` is **AGPL-3.0 with no permissive/ELv2 option** (the
   only alternative is a paid ParadeDB commercial licence). It is the sole
   _AGPL-only_ component in the image, and it single-handedly forces the whole
   image's copyleft floor to hard AGPL-3.0 — removing the ELv2 escape hatch that
   VectorChord's dual licence would otherwise leave open (see ADR-0004,
   `LICENSING.md`).
2. **Architecture.** `pg_search` is a Rust/`pgrx` extension wrapping Tantivy,
   storing its index as an on-disk LSM tree of separate files, and it **requires**
   `shared_preload_libraries` (0.24.0 errors without it). That heaviness is why
   its first-init needed hardening (ADR-0005 update) — and why it cannot run in
   constrained Postgres runtimes (e.g. PGlite/WASM). Serverless hosts have hit
   the same wall: **Neon dropped `pg_search` for new projects (2026-03-19)**,
   replacing it with an in-house BM25 index tuned to their storage engine.

Tiger Data (ex-Timescale) open-sourced **`pg_textsearch`** — a BM25 engine
written **in pure C directly on native Postgres pages** (buffer cache, WAL,
`pg_dump`, streaming replication), under the **PostgreSQL Licence** (permissive).
It supports PostgreSQL 17/18, builds via PGXS with no external dependencies, and
reached v1.0 GA on 2026-03-31 (v1.3.1 current).

Crucially for us: our reference consumers (`ragu-ansible` and its Python port)
use BM25 as **bag-of-tokens matching fused by Reciprocal Rank Fusion** — neither
issues phrase or proximity queries. `pg_textsearch`'s one functional gap versus
`pg_search` (no term positions → **no phrase queries**) therefore costs us
nothing we actually use today.

## Decision

Replace `pg_search` with **Tiger Data `pg_textsearch` v1.3.1** as the image's
BM25 extension.

- **Built from source via PGXS** against the base image's PostgreSQL 18 (pinned by
  git tag `v1.3.1`), with the build toolchain stripped in the same layer — the
  same pattern already used for pgvector and libversion. No `.deb` exists
  upstream, and a source build avoids maintaining per-arch binary checksums.
- Preload is updated to `shared_preload_libraries=age,vchord,pg_textsearch`
  (baked into `postgresql.conf.sample` and the `CMD`, as before).
- Created on first init via `CREATE EXTENSION pg_textsearch`; the post-init
  verify script now expects `pg_textsearch` in place of `pg_search`.
- The query surface changes: BM25 indexes are `USING bm25(col) WITH
  (text_config='english')` and ranked with the `<@>` operator in `ORDER BY`
  (returns a negative BM25 score; lower ranks better) — pgvector-style — rather
  than `pg_search`'s `@@@` predicate with `WITH (key_field=...)`. Consumers of
  the image adapt their lexical query accordingly; the image's own smoke test is
  updated to the new syntax.

### Resulting extension set

| Extension               | Purpose                  | License            |
| ----------------------- | ------------------------ | ------------------ |
| Apache AGE 1.7.0        | graph (openCypher)       | Apache-2.0         |
| pgvector 0.8.2          | vector type              | PostgreSQL License |
| VectorChord 1.1.1       | scalable vector indexing | AGPL-3.0 / ELv2    |
| **pg_textsearch 1.3.1** | **BM25 full-text**       | **PostgreSQL**     |
| pg_trgm                 | trigram / fuzzy          | PostgreSQL License |

## Consequences

**Positive**:

- **License floor drops** from hard `AGPL-3.0-only` back to
  `AGPL-3.0-only OR Elastic-2.0` — set by VectorChord's dual licence, so the
  whole image can once again take the ELv2 path (no more AGPL-only component).
  `LICENSING.md` and the OCI `licenses` label are updated.
- Lighter, WASM-friendlier architecture (pure C on PG pages); no separate Tantivy
  index files; native `pg_dump`/replication of the BM25 index.
- Keeps true hybrid retrieval — BM25 + vector + graph + trigram in one SQL query.

**Negative / obligations**:

- **No phrase or proximity queries** (pg_textsearch stores no term positions). Not
  used by our current consumers, but a genuine capability loss versus `pg_search`;
  revisit if exact multi-word matching becomes a requirement.
- **Breaking query-API change** for consumers (`@@@`/`paradedb.score` →
  `<@>`/`ORDER BY`). Downstream `ragu-*` retrieval code must be migrated.
- BM25 index build is source-compiled — adds a build stage (toolchain purged, so
  no runtime footprint), consistent with pgvector/libversion.

**Risks**:

- pg_textsearch is younger (v1.x, 2026) than Tantivy-based search. _Mitigation_:
  it is v1.0 GA, PostgreSQL-licensed, and pinned by tag; bumps are deliberate.

VectorChord remains the sole copyleft component; ADR-0004's self-hosted /
dogfooding distribution posture is unchanged (and now has an ELv2 option again).

## References

- [`LICENSING.md`](../../LICENSING.md)
- [ADR-0004](0004-extension-topology-and-licensing.md) — topology + licensing posture
- [ADR-0005](0005-adopt-pg-search-bm25.md) — superseded (adopted pg_search)
- [Tiger Data pg_textsearch](https://github.com/timescale/pg_textsearch) · [v1.0 announcement](https://www.postgresql.org/about/news/pg_textsearch-v10-3264/)
- [Neon: pg_search deprecation](https://neon.com/docs/extensions/pg_search)
