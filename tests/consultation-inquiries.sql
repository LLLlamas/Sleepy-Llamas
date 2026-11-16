-- Run only in an isolated disposable Postgres database with the migration applied.
-- Example bootstrap: CREATE ROLE anon; CREATE ROLE authenticated;
-- CREATE TABLE public.app_config (key text PRIMARY KEY, value text NOT NULL);
-- No production data, email configuration, or pg_net extension is needed.
\set ON_ERROR_STOP on
BEGIN;
DO $test$
DECLARE
  v_details jsonb := '{"client_name":" Test Parent ","client_email":"PARENT@example.test","service":"general-family-consult","contact_format":"video","referral_source":"A class"}';
  v_id uuid := '11111111-1111-4111-8111-111111111111';
  v_receipt jsonb;
  v_bad jsonb;
  v_count integer;
BEGIN
  v_receipt := public.sl_create_consultation_inquiry(v_id, v_details, '');
  IF v_receipt <> jsonb_build_object('id',v_id) THEN RAISE EXCEPTION 'receipt must contain only id'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.consultation_inquiries WHERE id=v_id AND client_name='Test Parent' AND client_email='parent@example.test'
    AND child_name IS NULL AND referral_source='A class' AND owner_notification='not_configured') THEN RAISE EXCEPTION 'durable row normalization failed'; END IF;
  IF public.sl_create_consultation_inquiry(v_id,v_details,'') <> v_receipt THEN RAISE EXCEPTION 'retry receipt changed'; END IF;
  IF (SELECT count(*) FROM public.consultation_inquiries) <> 1 THEN RAISE EXCEPTION 'retry inserted duplicate'; END IF;

  FOREACH v_bad IN ARRAY ARRAY[
    v_details || '{"client_name":""}', v_details || '{"client_email":"invalid"}',
    v_details || '{"contact_format":"fax"}', v_details || '{"service":"invented"}',
    v_details || '{"service":"home-consult","contact_format":"video"}',
    v_details || '{"service":"home-consult","contact_format":"in-person"}',
    v_details || '{"service":"caregiver-training","contact_format":"video"}',
    v_details || '{"service":"caregiver-training","contact_format":"in-person"}',
    v_details || '{"notes":123}', v_details || '{"extra":"unrecognized"}',
    v_details || jsonb_build_object('notes',repeat('a',2001)),
    v_details || jsonb_build_object('referral_source',repeat('a',161)),
    'null'::jsonb, '[]'::jsonb
  ] LOOP
    BEGIN
      PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_bad,'');
      RAISE EXCEPTION 'invalid fixture was accepted: %', v_bad;
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM <> 'invalid_inquiry' THEN RAISE; END IF;
    END;
  END LOOP;
  BEGIN
    PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details,'spam');
    RAISE EXCEPTION 'honeypot accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invalid_inquiry' THEN RAISE; END IF; END;
  BEGIN
    PERFORM public.sl_create_consultation_inquiry(v_id,v_details || '{"client_email":"other@example.test"}','');
    RAISE EXCEPTION 'id collision accepted';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'invalid_inquiry' THEN RAISE; END IF; END;

  PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details,'');
  PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details,'');
  BEGIN
    PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details,'');
    RAISE EXCEPTION 'email limit not enforced';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'inquiry_rate_limit' THEN RAISE; END IF; END;
  -- An existing request may be retried even when the email limit has been reached.
  PERFORM public.sl_create_consultation_inquiry(v_id,v_details,'');
  FOR v_count IN 1..57 LOOP
    PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details || jsonb_build_object('client_email','fixture' || v_count || '@example.test'),'');
  END LOOP;
  BEGIN
    PERFORM public.sl_create_consultation_inquiry(gen_random_uuid(),v_details || '{"client_email":"overlimit@example.test"}','');
    RAISE EXCEPTION 'global limit not enforced';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM <> 'inquiry_rate_limit' THEN RAISE; END IF; END;
  IF (SELECT count(*) FROM public.consultation_inquiries) <> 60 THEN RAISE EXCEPTION 'invalid requests wrote data'; END IF;
  IF has_table_privilege('anon','public.consultation_inquiries','SELECT') OR has_table_privilege('anon','public.consultation_inquiries','INSERT') THEN RAISE EXCEPTION 'anonymous direct table access'; END IF;
  IF has_function_privilege('anon','public.sl_queue_consultation_notice(uuid)','EXECUTE') THEN RAISE EXCEPTION 'anonymous notification access'; END IF;
  IF NOT has_function_privilege('anon','public.sl_create_consultation_inquiry(uuid,jsonb,text)','EXECUTE') THEN RAISE EXCEPTION 'public submission is unavailable'; END IF;
  RAISE NOTICE 'PASS: durable save, normalization, retry, validation, honeypot, ID collision, email/global limits, and grants';
END;
$test$;
SET LOCAL ROLE anon;
DO $test$
BEGIN
  PERFORM * FROM public.consultation_inquiries;
  RAISE EXCEPTION 'anonymous inquiry read was allowed';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'PASS: anonymous inquiry read denied';
END;
$test$;
RESET ROLE;
DELETE FROM public.consultation_inquiries;
SET LOCAL ROLE anon;
DO $test$
DECLARE v_id uuid := '22222222-2222-4222-8222-222222222222';
BEGIN
  IF public.sl_create_consultation_inquiry(v_id,'{"client_name":"Anonymous Submitter","client_email":"anon@example.test","service":"fit-call","contact_format":"phone"}'::jsonb,'') <> jsonb_build_object('id',v_id) THEN
    RAISE EXCEPTION 'anonymous submit failed';
  END IF;
  RAISE NOTICE 'PASS: anonymous caller can submit through the validated RPC';
END;
$test$;
RESET ROLE;
ROLLBACK;
