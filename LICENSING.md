# Licensing

This repository's own files (Dockerfile, init scripts, `test/`, docs) are
licensed **Apache-2.0** (see [`LICENSE`](LICENSE)).

The **built container image is a mixed-license aggregate**: it bundles several
independently-licensed PostgreSQL extensions, loaded at runtime by PostgreSQL.
Aggregating them in one image is "mere aggregation" — it does **not** relicense
this repo's Apache-2.0 code or the permissive components. But the image as a
whole is **not** uniformly Apache-2.0, and one bundled component (VectorChord)
is copyleft / source-available. Read this before redistributing the image or
offering it as a network service.

## Bundled components

| Component                  | Version | License                                      | SPDX                           | Type                            |
| -------------------------- | ------- | -------------------------------------------- | ------------------------------ | ------------------------------- |
| PostgreSQL (base)          | 18      | PostgreSQL License                           | `PostgreSQL`                   | Permissive                      |
| Apache AGE                 | 1.7.0   | Apache License 2.0                           | `Apache-2.0`                   | Permissive                      |
| pgvector                   | 0.8.2   | PostgreSQL License                           | `PostgreSQL`                   | Permissive                      |
| pg_trgm (contrib)          | bundled | PostgreSQL License                           | `PostgreSQL`                   | Permissive                      |
| **VectorChord** (`vchord`) | 1.1.1   | **AGPL-3.0 _or_ Elastic License 2.0** (dual) | `AGPL-3.0-only OR Elastic-2.0` | **Copyleft / source-available** |

Candidate, **not currently bundled**:

| Component            | License                          | Type                                  |
| -------------------- | -------------------------------- | ------------------------------------- |
| ParadeDB `pg_search` | **AGPL-3.0** (+ paid commercial) | Copyleft (AGPL-only on the open side) |

All bundled components are shipped **unmodified** from their upstream releases.

## What this means

- **Among the permissive parts** (PostgreSQL, AGE, pgvector, pg_trgm) and this
  repo's Apache-2.0 files: fully compatible, no obligations beyond attribution.
  All copyleft here is **v3** (AGPLv3), which is compatible with Apache-2.0
  aggregation — the classic "Apache vs. GPL" conflict is GPL**v2**, not v3.
- **VectorChord is the inflection point.** You pick one of its two licenses:
  - **AGPL-3.0** — copyleft. Conveying the image (e.g. pushing to a public
    registry) means you must offer VectorChord's _Complete Corresponding
    Source_; because we ship it unmodified, pointing at the upstream tagged
    release satisfies this. **AGPL §13 (network clause)**: if you offer this
    database **as a service to third parties**, you must offer those users the
    source of the AGPL component(s).
  - **Elastic License 2.0 (ELv2)** — source-available, **not** OSI-open-source.
    Removes the copyleft/source-disclosure duty but **prohibits providing the
    software to third parties as a hosted/managed service** and bans
    circumventing license keys.
- `vchord` depends on `pgvector`'s `vector` type, but that dependency is
  permissive → AGPL-consumer; **pgvector keeps its permissive license**.

## Obligations by how you use the image

| Use                                                                   | AGPL-3.0 arm                                                                                    | ELv2 arm                                 |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------- |
| **Self-hosted / homelab / dogfooding** (no third-party network users) | No source-offer triggered; just attribute                                                       | No managed-service restriction triggered |
| **Redistribute the image** (public registry, etc.)                    | Offer VectorChord source (unmodified → link upstream); pass along AGPL terms for that component | Comply with ELv2 redistribution terms    |
| **Offer as a managed service to third parties (SaaS)**                | Must offer AGPL component source to users (§13)                                                 | **Prohibited** by ELv2                   |

This project's intended model is **self-hosted / dogfooding** (see
[ADR-0004](docs/adr/0004-extension-topology-and-licensing.md)), where neither
§13 nor the ELv2 managed-service clause is triggered. A pivot to public
redistribution or SaaS requires revisiting that ADR.

## If `pg_search` is added later

ParadeDB `pg_search` is **AGPL-3.0** with no ELv2 fallback (the alternative is a
paid commercial license). Adding it means **two** AGPL components and removes
the ELv2 escape hatch for the image's copyleft surface. Decide deliberately —
ParadeDB notes it issues commercial licenses specifically to Apache-licensed
projects wary of AGPL.

## Attribution / source

Each component's source and license are at its upstream project:

- PostgreSQL — <https://www.postgresql.org/> (PostgreSQL License)
- Apache AGE — <https://github.com/apache/age> (Apache-2.0)
- pgvector — <https://github.com/pgvector/pgvector> (PostgreSQL License)
- VectorChord — <https://github.com/tensorchord/VectorChord> (AGPL-3.0 / ELv2)

---

_This is license identification and how the licenses interact — not legal
advice. A concrete public-distribution or SaaS plan deserves review by counsel._
