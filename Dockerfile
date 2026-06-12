# Ragù PostgreSQL — a RAG-ready PostgreSQL 18 image.
#
# Base: apache/age:release_PG18_1.7.0
#   = official postgres:18 (Debian) + Apache AGE 1.7.0 (graph extension),
#     with `shared_preload_libraries=age` (inherited CMD) and a base init
#     script that runs `CREATE EXTENSION age` in the default database.
#
# Added on top for Retrieval-Augmented Generation workloads:
#   - pgvector : vector similarity search over embeddings
#   - vchord   : VectorChord — scalable, disk-friendly vector indexing on top
#                of pgvector (RaBitQ); requires preloading
#   - pg_trgm  : trigram / lexical search (built-in contrib, enabled via init)
#
# The result is a single PostgreSQL that can back graph ("GraphRAG"), vector,
# and hybrid (vector + lexical) retrieval in one database.
FROM apache/age:release_PG18_1.7.0

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
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSL -o /tmp/vchord.deb \
        "https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_VERSION}/postgresql-${PG_MAJOR}-vchord_${VCHORD_VERSION}-1_${arch}.deb"; \
    apt-get install -y --no-install-recommends /tmp/vchord.deb; \
    rm -f /tmp/vchord.deb; \
    apt-get purge -y --auto-remove curl; \
    rm -rf /var/lib/apt/lists/*

# Enable the RAG extensions in the default database on first init.
# The base image's 00-create-extension-age.sql creates AGE; this runs after it
# (lexicographic order) to add vector, vchord, and pg_trgm.
COPY docker-entrypoint-initdb.d/01-create-extensions-rag.sql \
     /docker-entrypoint-initdb.d/01-create-extensions-rag.sql

# Override the base CMD to extend shared_preload_libraries: AGE and VectorChord
# both require preloading. ENTRYPOINT (the postgres docker-entrypoint) is still
# inherited. Keep `age` first to preserve the base image's behaviour.
CMD ["postgres", "-c", "shared_preload_libraries=age,vchord"]
