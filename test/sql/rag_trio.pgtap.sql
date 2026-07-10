-- Shared pgTAP suite for the ragu-* siblings: asserts the RAG-trio extensions,
-- schema, and one index per modality are present. Portable pgTAP (plan ->
-- assertions -> finish), so the SAME assertions run against both siblings:
--   * ragu-postgresql — the server image, via test/pgtap.sh (this repo), against
--     a schema fixture (rag_trio.fixture.sql), and
--   * ragu-pglite     — in-process in PGlite (vitest), against its createDb schema.
-- Kept in sync by hand for now; a shared corpus/test repo is the eventual target.

BEGIN;
SELECT plan(11);

-- Retrieval extensions (the RAG trio + fuzzy lexical).
SELECT has_extension('vector');
SELECT has_extension('pg_trgm');
SELECT has_extension('pg_textsearch');
SELECT has_extension('age');

-- Chunk schema.
SELECT has_table('chunk');
SELECT has_column('chunk', 'embedding');
SELECT col_type_is('chunk', 'embedding', 'vector(384)');

-- One index per lexical/vector modality.
SELECT has_index('chunk', 'chunk_embedding_hnsw');
SELECT has_index('chunk', 'chunk_fts_gin');
SELECT has_index('chunk', 'chunk_content_trgm');
SELECT has_index('chunk', 'chunk_content_bm25');

SELECT * FROM finish();
ROLLBACK;
