# 4. Single multi-extension PostgreSQL instance and licensing posture

Date: 2026-06-13

## Status

Accepted

> **Update:** the deferral of `pg_search` (below) was superseded by
> [ADR-0005](0005-adopt-pg-search-bm25.md), which adopted it — and ADR-0005 was
> in turn superseded by [ADR-0007](0007-replace-pg-search-with-pg-textsearch.md),
> which replaces `pg_search` with permissive `pg_textsearch`. The net effect on
> this ADR's licensing posture: the copyleft floor is back to VectorChord's
> `AGPL-3.0 OR ELv2` (no AGPL-only component). The topology decision stands.

## Context

Ragù PostgreSQL serves RAG retrieval across three access patterns — graph
(Apache AGE), vector (pgvector, with VectorChord indexing), and lexical
(pg_trgm). Two coupled questions arise:

1. **Topology** — one PostgreSQL instance hosting all extensions, or several
   containers (one per engine)?
2. **Licensing** — adding VectorChord introduced the first non-permissive
   component (AGPL-3.0 / Elastic License 2.0) into an otherwise permissively
   licensed, Apache-2.0 project. ParadeDB `pg_search` (a candidate) would add a
   second, AGPL-only, component.

[ADR-0003](0003-technology-stack.md) chose the PG18 + AGE +
pgvector stack. This ADR records the topology and the licensing posture that
follows from the extension set.

## Decision

### Topology: a single multi-extension PostgreSQL instance

We run **one** PostgreSQL instance with all retrieval extensions installed,
rather than a container per engine.

- AGE, pgvector, VectorChord, and pg_trgm coexist in one cluster.
- AGE and VectorChord are preloaded via `shared_preload_libraries=age,vchord`.
- This enables **hybrid retrieval in a single SQL query/transaction** (graph +
  vector + lexical joined together) over one connection — the core value of the
  image — and keeps self-hosted operation simple (one container, one volume).

### Current extension set

| Extension         | Purpose                  | License            |
| ----------------- | ------------------------ | ------------------ |
| Apache AGE 1.7.0  | graph (openCypher)       | Apache-2.0         |
| pgvector 0.8.2    | vector type + HNSW/IVF   | PostgreSQL License |
| VectorChord 1.1.1 | scalable vector indexing | AGPL-3.0 / ELv2    |
| pg_trgm           | lexical / fuzzy          | PostgreSQL License |

`pg_search` (ParadeDB, BM25 full-text) is **deferred**, not adopted — see
Consequences.

### Licensing posture

- This repository's own files remain **Apache-2.0**.
- The **built image is a mixed-license aggregate** (mere aggregation; it does
  not relicense our code or the permissive components). It is **not** uniformly
  Apache-2.0. Per-component licensing is documented in
  [`LICENSING.md`](../../LICENSING.md).
- All bundled components are shipped **unmodified** upstream.
- **Intended distribution model: self-hosted / dogfooding.** Under this model,
  neither AGPL §13 (network source offer) nor the ELv2 managed-service
  prohibition is triggered. A change to public image distribution or to
  offering the database as a service **requires revisiting this ADR**.

## Alternatives Considered

| Option                                                         | Pros                                                            | Cons                                                        | Decision                                                                     |
| -------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Single multi-extension instance                                | Single-query hybrid retrieval, one connection, simple self-host | All extensions must track one PG major; mixed-license image | **Selected**                                                                 |
| Container per engine                                           | License isolation; independent scaling                          | No single-query hybrid joins (FDW/app-side); more ops       | Rejected                                                                     |
| Permissive-only set (drop VectorChord; pgvector indexing only) | Image stays fully permissive                                    | Lose VectorChord's scalable/disk-friendly indexing          | Rejected (kept as the fallback if a permissive-only image is later required) |

## Consequences

**Positive**:

- Hybrid graph + vector + lexical retrieval in one query, one connection.
- Simple self-hosted operation (one container/volume), native arm64.

**Negative / obligations**:

- The image carries **VectorChord's AGPL-3.0 / ELv2 obligations** on
  redistribution or SaaS (see `LICENSING.md`). Shipping it unmodified keeps the
  source-offer burden trivial, but the obligation is real.
- The image is **not uniformly Apache-2.0**; messaging and any `NOTICE` must
  reflect the aggregate.
- All extensions must align on **one PostgreSQL major**; a lagging upstream
  pins the whole image.

**Risks**:

- **`pg_search` adoption** would add a second AGPL component with **no ELv2
  fallback**, hardening the copyleft surface. Defer until there is a concrete
  full-text need _and_ a deliberate decision in light of this ADR.
- **Distribution pivot**: moving to public distribution or managed-service
  hosting changes which obligations bite. Mitigation: if that happens, either
  obtain commercial licenses (VectorChord ELv2-incompatible SaaS, pg_search) or
  fall back to the permissive-only extension set.

## References

- [`LICENSING.md`](../../LICENSING.md) — per-component licenses and obligations
- [ADR-0003](0003-technology-stack.md) — the stack decision
- [VectorChord LICENSE](https://github.com/tensorchord/VectorChord/blob/main/LICENSE) · [ParadeDB: Why We Picked AGPL](https://www.paradedb.com/blog/agpl)
