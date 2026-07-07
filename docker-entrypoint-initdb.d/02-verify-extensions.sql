-- Fail the first-init LOUDLY if any expected extension is missing.
--
-- Runs after 00 (age) and 01 (vector, vchord, pg_textsearch, pg_trgm, libversion)
-- on first cluster init. With the entrypoint's ON_ERROR_STOP, a missing
-- extension here aborts init so the container never starts with an incomplete
-- set — converting the intermittent partial-init flake into a deterministic,
-- caught failure (see docs/roadmap and ADR-0005/ADR-0007). No-op once all six exist.
DO $$
DECLARE
  expected text[] := ARRAY['age', 'vector', 'vchord', 'pg_textsearch', 'pg_trgm', 'libversion'];
  missing  text[];
BEGIN
  SELECT array_agg(e ORDER BY e) INTO missing
  FROM unnest(expected) AS e
  WHERE e NOT IN (SELECT extname FROM pg_extension);

  IF missing IS NOT NULL THEN
    RAISE EXCEPTION 'init incomplete — missing extension(s): %', array_to_string(missing, ', ');
  END IF;
END
$$;
