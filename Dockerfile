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
#   - pg_search : ParadeDB BM25 full-text / hybrid search (Tantivy); requires
#                 preloading [AGPL-3.0]
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

# ParadeDB pg_search: BM25 full-text / hybrid search (Tantivy). Installed from
# ParadeDB's per-distro, per-arch Debian package pinned to a release. The distro
# codename is derived from the base image so the .deb matches its libc/ABI.
# NOTE: pg_search is AGPL-3.0 (no permissive/ELv2 option) — see LICENSING.md and
# docs/adr/0005-adopt-pg-search-bm25.md. It requires preloading (see CMD below).
ARG PG_SEARCH_VERSION=0.24.0
# DL3008 (pin apt versions): ca-certificates/curl are transient build-only deps
#   (curl is purged below); the pg_search package itself is pinned via the URL.
# DL4006 (pipefail): see the vchord step above — sha256sum -c is the gating
#   command and `set -e` covers it; dash has no `set -o pipefail`.
# SC1091 (`. /etc/os-release`): hadolint's shellcheck can't follow the sourced
#   file in its mock FS; it exists at build time in the base image.
# hadolint ignore=DL3008,DL4006,SC1091
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    . /etc/os-release; \
    case "$arch" in \
      arm64) sha256=7363017d6024380062298562d3223d795696dfa2b3a3726687ae9b6574e2fc18 ;; \
      amd64) sha256=f99267a6533a02f077824938a29e80586415b301928d4499d01cb4a1b9c7ccca ;; \
      *) echo "no pinned pg_search checksum for arch: $arch" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/pg_search.deb \
        "https://github.com/paradedb/paradedb/releases/download/v${PG_SEARCH_VERSION}/postgresql-${PG_MAJOR}-pg-search_${PG_SEARCH_VERSION}-1PARADEDB-${VERSION_CODENAME}_${arch}.deb"; \
    echo "${sha256}  /tmp/pg_search.deb" | sha256sum -c -; \
    apt-get install -y --no-install-recommends /tmp/pg_search.deb; \
    rm -f /tmp/pg_search.deb; \
    apt-get purge -y --auto-remove curl; \
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

# AGE, VectorChord, and pg_search all REQUIRE shared_preload_libraries (verified:
# pg_search 0.24.0 errors "must be loaded via shared_preload_libraries" at
# CREATE EXTENSION otherwise). Bake it into postgresql.conf.sample so EVERY
# initialized cluster — including the entrypoint's temporary first-init server —
# loads them from the config file, not solely from the CMD -c args. This makes
# the first-init CREATE EXTENSION reliable (hardening against the intermittent
# init flake; see docs/roadmap and ADR-0005).
RUN printf "\nshared_preload_libraries = 'age,vchord,pg_search'\n" \
    >> /usr/share/postgresql/postgresql.conf.sample

# Create the RAG extensions on first init, then verify all six exist.
# 00-create-extension-age.sql (base) creates AGE; 01 adds vector, vchord,
# pg_search, pg_trgm, libversion; 02 fails the init loudly if any are missing.
COPY docker-entrypoint-initdb.d/01-create-extensions-rag.sql \
     /docker-entrypoint-initdb.d/01-create-extensions-rag.sql
COPY docker-entrypoint-initdb.d/02-verify-extensions.sql \
     /docker-entrypoint-initdb.d/02-verify-extensions.sql

# Keep the CMD override too (same value): it sets the preload for the final
# server and is belt-and-suspenders with the baked config. ENTRYPOINT (the
# postgres docker-entrypoint) is inherited.
CMD ["postgres", "-c", "shared_preload_libraries=age,vchord,pg_search"]

# OCI image labels. Static metadata + build-arg-driven version/revision/created
# (pass via --build-arg, e.g. ./build.sh; empty if omitted). Declared last so
# changing the dynamic args doesn't invalidate the cache for the heavy layers.
# The licenses expression reflects the mixed-license aggregate — AGPL-3.0 floor;
# see LICENSING.md for the full per-component breakdown (incl. VectorChord ELv2).
ARG VERSION
ARG REVISION
ARG CREATED
LABEL org.opencontainers.image.title="Ragù PostgreSQL" \
      org.opencontainers.image.description="RAG-ready PostgreSQL 18: Apache AGE + pgvector + VectorChord + ParadeDB pg_search + pg_trgm + repology libversion" \
      org.opencontainers.image.licenses="Apache-2.0 AND PostgreSQL AND MIT AND AGPL-3.0-only" \
      org.opencontainers.image.source="https://github.com/jrjsmrtn/ragu-postgresql" \
      org.opencontainers.image.base.name="docker.io/apache/age:release_PG18_1.7.0" \
      org.opencontainers.image.base.digest="sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"
