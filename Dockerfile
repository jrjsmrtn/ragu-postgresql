# Ragù PostgreSQL — a RAG-ready PostgreSQL 18 image.
#
# Base: apache/age:release_PG18_1.7.0
#   = official postgres:18 (Debian) + Apache AGE 1.7.0 (graph extension),
#     with `shared_preload_libraries=age` (inherited CMD) and a base init
#     script that runs `CREATE EXTENSION age` in the default database.
#
# Added on top for Retrieval-Augmented Generation workloads:
#   - pgvector  : vector similarity search over embeddings (HNSW / IVFFlat)
#   - pg_textsearch : Tiger Data BM25 full-text search; pure C on native
#                 Postgres pages (no Tantivy/Rust); requires preloading [PostgreSQL]
#   - pg_trgm   : trigram / lexical search (built-in contrib, enabled via init)
#   - libversion: repology/libversion — version-string comparison functions and
#                 a `versiontext` type [MIT]
#
# The result is a single PostgreSQL that can back graph ("GraphRAG"), vector,
# BM25 full-text, and hybrid retrieval in one database. Every bundled component
# is permissively licensed, so the image is a fully permissive aggregate
# (Apache-2.0 AND PostgreSQL AND MIT) — see LICENSING.md.
# Pinned by digest (the multi-arch OCI index) so the tag can't be remutated
# under us and builds stay reproducible. The tag is kept for readability.
# To bump: skopeo inspect --raw docker://docker.io/apache/age:<tag> | sha256sum
FROM apache/age:release_PG18_1.7.0@sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00

# Security: patch base-image packages with fixable CVEs surfaced by the grype
# scan (ADR-0006). Version-pinned so a bump is deliberate (build fails if a pin
# is no longer available, the same model as the source-build git tags).
#   - libgnutls30t64 → deb13u4: CVE-2026-42010, CVE-2026-33845 (Critical),
#     CVE-2026-42009/5260/3833/33846 (High)
#   - libcap2 → deb13u1+b1: CVE-2026-4878 (High)
#   - glibc set (libc6/libc-bin/libc-l10n/locales) → deb13u3: CVE-2026-0915,
#     CVE-2026-0861, CVE-2026-4046, CVE-2026-4437, CVE-2025-15281 (High),
#     CVE-2026-4438 (Medium). Co-versioned, so all four move together.
#   - krb5 runtime (libgssapi-krb5-2/libk5crypto3/libkrb5-3/libkrb5support0)
#     → deb13u1: CVE-2026-40355, CVE-2026-40356 (High)
#   - libsystemd0/libudev1 → 257.13-1~deb13u1: CVE-2026-4105, CVE-2026-40225,
#     CVE-2026-29111, CVE-2026-40226 (Medium)
#   - libgcrypt20 → deb13u1: CVE-2026-41989 (Medium)
#   - libsqlite3-0 → deb13u1: CVE-2025-7709 (Medium)
#   - sed → deb13u1: CVE-2026-5958 (Low)
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends --only-upgrade \
        libgnutls30t64=3.8.9-3+deb13u4 \
        libcap2=1:2.75-10+deb13u1+b1 \
        libc6=2.41-12+deb13u3 \
        libc-bin=2.41-12+deb13u3 \
        libc-l10n=2.41-12+deb13u3 \
        locales=2.41-12+deb13u3 \
        libgssapi-krb5-2=1.21.3-5+deb13u1 \
        libk5crypto3=1.21.3-5+deb13u1 \
        libkrb5-3=1.21.3-5+deb13u1 \
        libkrb5support0=1.21.3-5+deb13u1 \
        libsystemd0=257.13-1~deb13u1 \
        libudev1=257.13-1~deb13u1 \
        libgcrypt20=1.11.0-7+deb13u1 \
        libsqlite3-0=3.46.1-7+deb13u1 \
        sed=4.9-2+deb13u1; \
    rm -rf /var/lib/apt/lists/*

# Pin pgvector to a release that supports PG18 and includes the
# CVE-2026-3172 fix (parallel HNSW build buffer overflow).
ARG PGVECTOR_VERSION=v0.8.2
ARG PG_MAJOR=18

# Build pgvector from source against the base image's PostgreSQL 18, then strip
# the build toolchain so it does not ship in the final image.
#   - `apt-mark hold locales` keeps --auto-remove from pulling locales (which
#     the postgres runtime depends on) out with the build deps.
#   - OPTFLAGS="" disables -march=native so the binary stays portable across
#     CPUs (matters for sharing one image across machines / arches).
# DL3008 (pin apt versions): build-only deps purged in this same layer — pinning
#   adds brittleness, not reproducibility, to the final image.
# DL3003 (use WORKDIR): a `cd` inside this single build+cleanup RUN is clearer
#   than a WORKDIR we would immediately tear down.
# hadolint ignore=DL3003,DL3008
RUN set -eux; \
    apt-get update; \
    apt-mark hold locales; \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        "postgresql-server-dev-${PG_MAJOR}"; \
    git clone --branch "${PGVECTOR_VERSION}" --depth 1 \
        https://github.com/pgvector/pgvector.git /tmp/pgvector; \
    cd /tmp/pgvector; \
    make OPTFLAGS=""; \
    make install; \
    mkdir -p /usr/share/doc/pgvector; \
    cp LICENSE README.md /usr/share/doc/pgvector; \
    cd /; \
    rm -rf /tmp/pgvector; \
    apt-get purge -y --auto-remove \
        build-essential git "postgresql-server-dev-${PG_MAJOR}"; \
    apt-mark unhold locales; \
    rm -rf /var/lib/apt/lists/*

# Tiger Data pg_textsearch: BM25 full-text search implemented in pure C directly
# on native Postgres pages (buffer cache, WAL, pg_dump, replication) — no Tantivy,
# no Rust, no external index files. Built from source via PGXS against the base
# image's PostgreSQL 18, then the build toolchain is stripped (same pattern as the
# pgvector and libversion builds below/above), so it does not ship in the final
# image. Pinned by git tag for deliberate bumps.
#   - OPTFLAGS/-march=native is not set by the Makefile (it uses PGXS's -O2), so
#     the binary stays portable across CPUs.
#   - `apt-mark hold locales` keeps --auto-remove from pulling locales (a postgres
#     runtime dep) out with the build deps.
# NOTE: pg_textsearch is PostgreSQL-licensed (permissive) — see LICENSING.md and
# docs/adr/0007-replace-pg-search-with-pg-textsearch.md. It requires preloading
# (see CMD below).
ARG PG_TEXTSEARCH_VERSION=v1.3.1
# DL3008 (pin apt versions): build-only deps purged in this same layer — pinning
#   adds brittleness, not reproducibility, to the final image.
# DL3003 (use WORKDIR): a `cd` inside this single build+cleanup RUN is clearer
#   than a WORKDIR we would immediately tear down.
# hadolint ignore=DL3003,DL3008
RUN set -eux; \
    apt-get update; \
    apt-mark hold locales; \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        ca-certificates \
        "postgresql-server-dev-${PG_MAJOR}"; \
    git clone --branch "${PG_TEXTSEARCH_VERSION}" --depth 1 \
        https://github.com/timescale/pg_textsearch.git /tmp/pg_textsearch; \
    cd /tmp/pg_textsearch; \
    make; \
    make install; \
    mkdir -p /usr/share/doc/pg_textsearch; \
    cp LICENSE README.md /usr/share/doc/pg_textsearch; \
    cd /; \
    rm -rf /tmp/pg_textsearch; \
    apt-get purge -y --auto-remove \
        build-essential git "postgresql-server-dev-${PG_MAJOR}"; \
    apt-mark unhold locales; \
    rm -rf /var/lib/apt/lists/*

# repology/libversion: advanced version-string comparison as SQL functions and
# a `versiontext` type (MIT). Two source builds: the libversion C library (CMake
# → /usr/local/lib, kept at runtime and registered with ldconfig) and the PGXS
# extension linked against it via pkg-config. No preloading required. Pinned for
# deliberate bumps.
ARG LIBVERSION_VERSION=3.0.4
ARG PG_LIBVERSION_VERSION=2.0.1
# DL3008 (pin apt versions): build-only toolchain purged in this same layer.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-mark hold locales; \
    apt-get install -y --no-install-recommends \
        build-essential cmake git ca-certificates pkgconf \
        "postgresql-server-dev-${PG_MAJOR}"; \
    git clone --branch "${LIBVERSION_VERSION}" --depth 1 \
        https://github.com/repology/libversion.git /tmp/libversion; \
    cmake -S /tmp/libversion -B /tmp/libversion/build -DCMAKE_BUILD_TYPE=Release; \
    cmake --build /tmp/libversion/build -j"$(nproc)"; \
    cmake --install /tmp/libversion/build; \
    ldconfig; \
    git clone --branch "${PG_LIBVERSION_VERSION}" --depth 1 \
        https://github.com/repology/postgresql-libversion.git /tmp/pg-libversion; \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig make -C /tmp/pg-libversion; \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig make -C /tmp/pg-libversion install; \
    rm -rf /tmp/libversion /tmp/pg-libversion; \
    apt-get purge -y --auto-remove \
        build-essential cmake git pkgconf "postgresql-server-dev-${PG_MAJOR}"; \
    apt-mark unhold locales; \
    ldconfig; \
    rm -rf /var/lib/apt/lists/*

# AGE and pg_textsearch both REQUIRE shared_preload_libraries (pg_textsearch
# registers its bm25 access method at load time). Bake it into
# postgresql.conf.sample so EVERY initialized cluster — including the entrypoint's
# temporary first-init server — loads them from the config file, not solely from
# the CMD -c args. This makes the first-init CREATE EXTENSION reliable (hardening
# against the intermittent init flake; see docs/roadmap and ADR-0005/ADR-0007).
RUN printf "\nshared_preload_libraries = 'age,pg_textsearch'\n" \
    >> /usr/share/postgresql/postgresql.conf.sample

# Create the RAG extensions on first init, then verify all five exist.
# 00-create-extension-age.sql (base) creates AGE; 01 adds vector,
# pg_textsearch, pg_trgm, libversion; 02 fails the init loudly if any are missing.
COPY docker-entrypoint-initdb.d/01-create-extensions-rag.sql \
     /docker-entrypoint-initdb.d/01-create-extensions-rag.sql
COPY docker-entrypoint-initdb.d/02-verify-extensions.sql \
     /docker-entrypoint-initdb.d/02-verify-extensions.sql

# Keep the CMD override too (same value): it sets the preload for the final
# server and is belt-and-suspenders with the baked config. ENTRYPOINT (the
# postgres docker-entrypoint) is inherited.
CMD ["postgres", "-c", "shared_preload_libraries=age,pg_textsearch"]

# OCI image labels. Static metadata + build-arg-driven version/revision/created
# (pass via --build-arg, e.g. ./build.sh; empty if omitted). Declared last so
# changing the dynamic args doesn't invalidate the cache for the heavy layers.
# The licenses expression reflects the aggregate. With VectorChord removed, every
# bundled component is permissive, so the image carries no copyleft floor — it is
# a fully permissive aggregate. See LICENSING.md for the per-component breakdown.
ARG VERSION
ARG REVISION
ARG CREATED
LABEL org.opencontainers.image.title="Ragù PostgreSQL" \
      org.opencontainers.image.description="RAG-ready PostgreSQL 18: Apache AGE + pgvector + Tiger Data pg_textsearch + pg_trgm + repology libversion" \
      org.opencontainers.image.licenses="Apache-2.0 AND PostgreSQL AND MIT" \
      org.opencontainers.image.source="https://github.com/jrjsmrtn/ragu-postgresql" \
      org.opencontainers.image.base.name="docker.io/apache/age:release_PG18_1.7.0" \
      org.opencontainers.image.base.digest="sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
