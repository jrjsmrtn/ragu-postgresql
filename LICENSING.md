# Licensing

This repository's own files (Dockerfile, init scripts, `test/`, docs) are
licensed **Apache-2.0** (see [`LICENSE`](LICENSE)).

The **built container image is a license aggregate**: it bundles several
independently-licensed PostgreSQL extensions, loaded at runtime by PostgreSQL.
Aggregating them in one image is "mere aggregation" — it does **not** relicense
this repo's Apache-2.0 code or any component. As of the VectorChord removal
([ADR-0008](docs/adr/0008-remove-vectorchord.md)), **every bundled component is
permissively licensed**, so the image is a **fully permissive aggregate** with
**no copyleft floor**: `Apache-2.0 AND PostgreSQL AND MIT`. There is nothing here
that triggers AGPL source-offer or Elastic License managed-service restrictions.

## Bundled components

| Component                           | Version       | License            | SPDX         | Type       |
| ----------------------------------- | ------------- | ------------------ | ------------ | ---------- |
| PostgreSQL (base)                   | 18            | PostgreSQL License | `PostgreSQL` | Permissive |
| Apache AGE                          | 1.7.0         | Apache License 2.0 | `Apache-2.0` | Permissive |
| pgvector                            | 0.8.2         | PostgreSQL License | `PostgreSQL` | Permissive |
| pg_trgm (contrib)                   | bundled       | PostgreSQL License | `PostgreSQL` | Permissive |
| Tiger Data `pg_textsearch`          | 1.3.1         | PostgreSQL License | `PostgreSQL` | Permissive |
| repology `libversion` (ext / C lib) | 2.0.0 / 3.0.4 | MIT                | `MIT`        | Permissive |

All bundled components are shipped **unmodified** from their upstream releases.

> **The image has no copyleft floor.** VectorChord (`vchord`) — the only
> copyleft / source-available component the image ever carried (AGPL-3.0 or
> Elastic License 2.0, dual) — was **removed** in
> [ADR-0008](docs/adr/0008-remove-vectorchord.md). Vector search is now provided
> by pgvector alone (HNSW / IVFFlat). The BM25 engine `pg_textsearch` is
> permissively (PostgreSQL) licensed and was already copyleft-free
> ([ADR-0007](docs/adr/0007-replace-pg-search-with-pg-textsearch.md)).

## What this means

- **All parts are permissive** (PostgreSQL, Apache-2.0, MIT) and mutually
  compatible with this repo's Apache-2.0 files. The only obligation is the usual
  permissive one: **preserve attribution / copyright and license notices** for
  each bundled component when you redistribute the image.
- **No source-disclosure or copyleft duty**, and **no managed-service
  restriction**: you may self-host, redistribute the image, or offer it as a
  managed service to third parties without triggering AGPL §13 or the Elastic
  License 2.0 hosting prohibition — none of those clauses apply to any bundled
  component anymore.
- `pg_trgm` and `pgvector` are the vector + lexical stack; neither imposes any
  copyleft. `pg_textsearch` (BM25) and `libversion` are likewise permissive.

## Obligations by how you use the image

Because every component is permissive, the obligations are the same across all
use cases — attribution only.

| Use                                                    | Obligation                                               |
| ------------------------------------------------------ | -------------------------------------------------------- |
| **Self-hosted / homelab / dogfooding**                 | Attribution only                                         |
| **Redistribute the image** (public registry, etc.)     | Preserve each component's copyright / license notices    |
| **Offer as a managed service to third parties (SaaS)** | Attribution only — no copyleft or managed-service clause |

This project's intended model remains **self-hosted / dogfooding** (see
[ADR-0004](docs/adr/0004-extension-topology-and-licensing.md)), but the licensing
posture no longer constrains a pivot to public redistribution or SaaS: there is
no copyleft component to comply with and no ELv2 hosting prohibition to avoid.
See [ADR-0008](docs/adr/0008-remove-vectorchord.md) for the trade-off (loss of
VectorChord's RaBitQ / disk-friendly indexing).

## Attribution / source

Each component's source and license are at its upstream project:

- PostgreSQL — <https://www.postgresql.org/> (PostgreSQL License)
- Apache AGE — <https://github.com/apache/age> (Apache-2.0)
- pgvector — <https://github.com/pgvector/pgvector> (PostgreSQL License)
- Tiger Data pg_textsearch — <https://github.com/timescale/pg_textsearch> (PostgreSQL License)
- repology libversion — <https://github.com/repology/postgresql-libversion> and <https://github.com/repology/libversion> (MIT)

---

_This is license identification and how the licenses interact — not legal
advice. A concrete public-distribution or SaaS plan deserves review by counsel._
