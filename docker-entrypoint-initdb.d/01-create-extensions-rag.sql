-- RAG extensions for the default database.
-- Apache AGE is already created by 00-create-extension-age.sql (base image).
-- This script runs afterwards (lexicographic order) on first cluster init.

-- Vector similarity search over embeddings.
CREATE EXTENSION IF NOT EXISTS vector;

-- Trigram indexes for lexical / fuzzy text matching (hybrid retrieval).
CREATE EXTENSION IF NOT EXISTS pg_trgm;
