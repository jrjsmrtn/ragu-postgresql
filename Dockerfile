# Ragù PostgreSQL — a RAG-ready PostgreSQL 18 image.
#
# Base: apache/age:release_PG18_1.7.0
#   = official postgres:18 (Debian) + Apache AGE 1.7.0 (graph extension),
#     with `shared_preload_libraries=age` (inherited CMD) and a base init
#     script that runs `CREATE EXTENSION age` in the default database.
#
# Added on top for Retrieval-Augmented Generation workloads:
#   - pgvector  : vector similarity search over embeddings
#   - vchord    : VectorChord — scalable, disk-friendly vector indexing on top
#                 of pgvector (RaBitQ); requires preloading [AGPL-3.0 / ELv2]
#   - pg_textsearch : Tiger Data BM25 full-text search; pure C on native
#                 Postgres pages (no Tantivy/Rust); requires preloading [PostgreSQL]
#   - pg_trgm   : trigram / lexical search (built-in contrib, enabled via init)
#   - libversion: repology/libversion — version-string comparison functions and
#                 a `versiontext` type [MIT]
#
# The result is a single PostgreSQL that can back graph ("GraphRAG"), vector,
# BM25 full-text, and hybrid retrieval in one database. The image is a
# mixed-license aggregate — see LICENSING.md.
# Pinned by digest (the multi-arch OCI index) so the tag can't be remutated
# under us and builds stay reproducible. The tag is kept for readability.
# To bump: skopeo inspect --raw docker://docker.io/apache/age:<tag> | sha256sum
FROM apache/age:release_PG18_1.7.0@sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00

# Security: patch base-image packages with fixable High/Critical CVEs surfaced
# by the grype scan (ADR-0006):
#   - libgnutls30t64 → deb13u4: CVE-2026-42010, CVE-2026-33845 (Critical),
#     CVE-2026-42009/5260/3833/33846 (High)
#   - libcap2 → deb13u1+b1: CVE-2026-4878 (High)
# Version-pinned so a bump is deliberate (build fails if a pin is no longer
# available, the same model as the .deb checksums).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends --only-upgrade \
        libgnutls30t64=3.8.9-3+deb13u4 \
        libcap2=1:2.75-10+deb13u1+b1; \
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

# VectorChord (vchord): scalable, disk-friendly vector indexing layered on top
# of pgvector's `vector` type. Installed from the upstream Debian package
# (per-arch, arm64/amd64) pinned to a release. It requires preloading (see CMD
# override below) and pgvector >= 0.7, < 0.9 (satisfied by PGVECTOR_VERSION).
ARG VCHORD_VERSION=1.1.1
# DL3008 (pin apt versions): ca-certificates/curl are transient build-only deps
#   (curl is purged below); the vchord package itself is pinned via the .deb URL.
# DL4006 (pipefail): the checksum pipe's last command (sha256sum -c) is what we
#   gate on, and `set -e` already fails the build on mismatch; /bin/sh is dash
#   (no `set -o pipefail`), so we do not switch SHELL just for this.
# hadolint ignore=DL3008,DL4006
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      arm64) sha256=59dbe75a398c2df2849631de054d80e60a6c04499fa2d29eebdb04e40f28501c ;; \
      amd64) sha256=7637a18a97157db8d904bb7093e5ce33b6a395c0acac9ae6b660032f3d57a33e ;; \
      *) echo "no pinned vchord checksum for arch: $arch" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/vchord.deb \
        "https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_VERSION}/postgresql-${PG_MAJOR}-vchord_${VCHORD_VERSION}-1_${arch}.deb"; \
    echo "${sha256}  /tmp/vchord.deb" | sha256sum -c -; \
    apt-get install -y --no-install-recommends /tmp/vchord.deb; \
    rm -f /tmp/vchord.deb; \
    apt-get purge -y --auto-remove curl; \
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

# AGE, VectorChord, and pg_textsearch all REQUIRE shared_preload_libraries
# (pg_textsearch registers its bm25 access method at load time). Bake it into
# postgresql.conf.sample so EVERY initialized cluster — including the entrypoint's
# temporary first-init server — loads them from the config file, not solely from
# the CMD -c args. This makes the first-init CREATE EXTENSION reliable (hardening
# against the intermittent init flake; see docs/roadmap and ADR-0005/ADR-0007).
RUN printf "\nshared_preload_libraries = 'age,vchord,pg_textsearch'\n" \
    >> /usr/share/postgresql/postgresql.conf.sample

# Create the RAG extensions on first init, then verify all six exist.
# 00-create-extension-age.sql (base) creates AGE; 01 adds vector, vchord,
# pg_textsearch, pg_trgm, libversion; 02 fails the init loudly if any are missing.
COPY docker-entrypoint-initdb.d/01-create-extensions-rag.sql \
     /docker-entrypoint-initdb.d/01-create-extensions-rag.sql
COPY docker-entrypoint-initdb.d/02-verify-extensions.sql \
     /docker-entrypoint-initdb.d/02-verify-extensions.sql

# Keep the CMD override too (same value): it sets the preload for the final
# server and is belt-and-suspenders with the baked config. ENTRYPOINT (the
# postgres docker-entrypoint) is inherited.
CMD ["postgres", "-c", "shared_preload_libraries=age,vchord,pg_textsearch"]

# OCI image labels. Static metadata + build-arg-driven version/revision/created
# (pass via --build-arg, e.g. ./build.sh; empty if omitted). Declared last so
# changing the dynamic args doesn't invalidate the cache for the heavy layers.
# The licenses expression reflects the mixed-license aggregate. With pg_search
# (AGPL-only) replaced by pg_textsearch (PostgreSQL), the copyleft floor is set
# by VectorChord's dual AGPL-3.0-or-ELv2 license — so the whole image can once
# again take the ELv2 path. See LICENSING.md for the per-component breakdown.
ARG VERSION
ARG REVISION
ARG CREATED
LABEL org.opencontainers.image.title="Ragù PostgreSQL" \
      org.opencontainers.image.description="RAG-ready PostgreSQL 18: Apache AGE + pgvector + VectorChord + Tiger Data pg_textsearch + pg_trgm + repology libversion" \
      org.opencontainers.image.licenses="Apache-2.0 AND PostgreSQL AND MIT AND (AGPL-3.0-only OR Elastic-2.0)" \
      org.opencontainers.image.source="https://github.com/jrjsmrtn/ragu-postgresql" \
      org.opencontainers.image.base.name="docker.io/apache/age:release_PG18_1.7.0" \
      org.opencontainers.image.base.digest="sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
