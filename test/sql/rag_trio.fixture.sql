-- RAG-trio schema fixture: the schema the ragu-postgresql image must be able to
-- host. Built in a throwaway session by test/pgtap.sh, then asserted by the shared
-- suite (rag_trio.pgtap.sql). Mirrors ragu-pglite's src/schema.sql + the BM25 index
-- it creates at runtime, so both siblings assert the identical shape.
--
-- The RAG extensions are already present (initdb.d); CREATE ... IF NOT EXISTS is
-- idempotent. pgtap is installed at test time (see test/pgtap.sh).

CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS pg_textsearch;
CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS pgtap;

CREATE TABLE IF NOT EXISTS chunk (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  doc_id    text NOT NULL,
  title     text NOT NULL,
  content   text NOT NULL,
  embedding vector(384),
  fts       tsvector GENERATED ALWAYS AS (to_tsvector('english', title || ' ' || content)) STORED
);

-- Vector: HNSW over cosine distance.
CREATE INDEX IF NOT EXISTS chunk_embedding_hnsw ON chunk USING hnsw (embedding vector_cosine_ops);
-- Lexical (native FTS): GIN over the generated tsvector.
CREATE INDEX IF NOT EXISTS chunk_fts_gin ON chunk USING gin (fts);
-- Lexical (fuzzy): trigram GIN.
CREATE INDEX IF NOT EXISTS chunk_content_trgm ON chunk USING gin (content gin_trgm_ops);
-- Lexical (BM25): pg_textsearch over raw text.
CREATE INDEX IF NOT EXISTS chunk_content_bm25 ON chunk USING bm25 (content) WITH (text_config = 'english');
