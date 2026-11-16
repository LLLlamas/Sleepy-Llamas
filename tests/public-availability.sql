-- Isolated database regression test; apply the availability privacy migration first.
-- The fixture table should match public.availability in supabase-schema.sql.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.availability (day,status,child_name,arrival_time,departure_time,notes,updated_at) VALUES
 ('2030-01-01','booked','Private Child A','20:00','07:00','Private care note A','2026-11-15 10:00:00+00'),
 ('2030-01-02','unavailable','Private Child B','21:00','06:00','Private care note B','2026-11-15 11:00:00+00'),
 ('2030-01-03','available','Private Child C','22:00','08:00','Private care note C','2026-11-15 12:00:00+00');
SET LOCAL ROLE anon;
DO $test$
DECLARE v_rows jsonb; v_count integer;
BEGIN
  SELECT jsonb_agg(to_jsonb(a) ORDER BY day) INTO v_rows FROM public.sl_get_availability('2030-01-01','2030-01-02') a;
  IF jsonb_array_length(v_rows) <> 2 OR v_rows->0->>'day' <> '2030-01-01' OR v_rows->0->>'status' <> 'booked'
    OR v_rows->1->>'day' <> '2030-01-02' OR v_rows->1->>'status' <> 'unavailable' THEN
    RAISE EXCEPTION 'public date/status range changed: %',v_rows;
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_rows) r WHERE r->>'child_name' IS NOT NULL OR r->>'notes' IS NOT NULL
    OR r->>'arrival_time' IS NOT NULL OR r->>'departure_time' IS NOT NULL) THEN
    RAISE EXCEPTION 'private availability fields leaked';
  END IF;
  IF v_rows::text LIKE '%Private%' THEN RAISE EXCEPTION 'private fixture text leaked'; END IF;
  SELECT count(*) INTO v_count FROM public.sl_get_availability('2030-01-03','2030-01-03');
  IF v_count <> 1 THEN RAISE EXCEPTION 'single-day range failed'; END IF;
  SELECT count(*) INTO v_count FROM public.sl_get_availability('2030-01-02','2030-01-01');
  IF v_count <> 0 THEN RAISE EXCEPTION 'reversed range exposed records'; END IF;
  BEGIN
    SELECT count(*) INTO v_count FROM public.availability;
    IF v_count <> 0 THEN RAISE EXCEPTION 'anonymous direct table read exposed records'; END IF;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'PASS: anonymous RPC returns dates/statuses with null private fields; range filtering and direct-table protection hold';
END;
$test$;
RESET ROLE;
DO $test$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.availability WHERE day='2030-01-01' AND child_name='Private Child A' AND notes='Private care note A') THEN
    RAISE EXCEPTION 'privacy RPC altered underlying owner data';
  END IF;
  RAISE NOTICE 'PASS: owner data remains intact';
END;
$test$;
ROLLBACK;
