-- RAG extensions for the default database.
-- Apache AGE is already created by 00-create-extension-age.sql (base image).
-- This script runs afterwards (lexicographic order) on first cluster init.

-- Vector similarity search over embeddings (HNSW / IVFFlat indexing).
CREATE EXTENSION IF NOT EXISTS vector;

-- Tiger Data pg_textsearch: BM25 full-text search (pure C on native PG pages).
CREATE EXTENSION IF NOT EXISTS pg_textsearch;

-- Trigram indexes for lexical / fuzzy text matching (hybrid retrieval).
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- repology/libversion: version-string comparison functions + `versiontext` type.
CREATE EXTENSION IF NOT EXISTS libversion;
