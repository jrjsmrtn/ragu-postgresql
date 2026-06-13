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
#
# The result is a single PostgreSQL that can back graph ("GraphRAG"), vector,
# BM25 full-text, and hybrid retrieval in one database. The image is a
# mixed-license aggregate — see LICENSING.md.
# Pinned by digest (the multi-arch OCI index) so the tag can't be remutated
# under us and builds stay reproducible. The tag is kept for readability.
# To bump: skopeo inspect --raw docker://docker.io/apache/age:<tag> | sha256sum
FROM apache/age:release_PG18_1.7.0@sha256:e7de1717e487dac7c1be93a1cd5360a2cf07ff4170342c2af2ac4713c21baf00

# Security: patch base-image packages with fixable High/Critical CVEs surfaced
# by the grype scan (ADR-0006). libgnutls30t64 deb13u1 → deb13u4 clears
# CVE-2026-42010 (Critical), CVE-2026-33845 (Critical), CVE-2026-42009/5260/
# 3833/33846 (High). Version-pinned so a bump is deliberate (build fails if the
# pin is no longer available, the same model as the .deb checksums).
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends --only-upgrade libgnutls30t64=3.8.9-3+deb13u4; \
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
# hadolint ignore=DL3008,DL4006
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

# Enable the RAG extensions in the default database on first init.
# The base image's 00-create-extension-age.sql creates AGE; this runs after it
# (lexicographic order) to add vector, vchord, pg_search, and pg_trgm.
COPY docker-entrypoint-initdb.d/01-create-extensions-rag.sql \
     /docker-entrypoint-initdb.d/01-create-extensions-rag.sql

# Override the base CMD to extend shared_preload_libraries: AGE, VectorChord,
# and pg_search all require preloading. ENTRYPOINT (the postgres
# docker-entrypoint) is still inherited. Keep `age` first to preserve the base
# image's behaviour.
CMD ["postgres", "-c", "shared_preload_libraries=age,vchord,pg_search"]
