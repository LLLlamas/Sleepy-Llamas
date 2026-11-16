-- Consultation inquiries are requests for a conversation, not reserved nights.
-- Apply AFTER supabase-schema.sql / supabase-migration-services.sql to the existing
-- project. This migration adds no secrets and makes no changes to existing bookings.
-- Frontend requires PUBLIC_SUPABASE_URL and PUBLIC_SUPABASE_ANON_KEY at build time.
-- Owner email uses the existing app_config + pg_net + send-email relay when configured.
-- A saved inquiry is NOT proof of delivered email. Monitor consultation_inquiries in
-- the Supabase dashboard and pg_net responses; owner_notification tracks queuing only.
-- No deployment or production-data mutation is performed by saving this file.

BEGIN;

CREATE TABLE IF NOT EXISTS public.consultation_inquiries (
  id uuid PRIMARY KEY,
  client_name text NOT NULL CHECK (length(client_name) BETWEEN 1 AND 80),
  client_email text NOT NULL CHECK (length(client_email) <= 254),
  service text NOT NULL,
  contact_format text NOT NULL,
  child_name text,
  stage text,
  location text,
  client_phone text,
  notes text,
  referral_source text,
  created_at timestamptz NOT NULL DEFAULT now(),
  owner_notification text NOT NULL DEFAULT 'not_configured'
    CHECK (owner_notification IN ('not_configured', 'queued', 'queue_failed')),
  notification_request_id bigint
);
CREATE INDEX IF NOT EXISTS consultation_inquiries_created_idx ON public.consultation_inquiries (created_at);
CREATE INDEX IF NOT EXISTS consultation_inquiries_email_created_idx ON public.consultation_inquiries (client_email, created_at);
ALTER TABLE public.consultation_inquiries ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.consultation_inquiries FROM PUBLIC, anon, authenticated;
-- Deliberately no public SELECT/INSERT policy. Only the validated RPC may insert;
-- owner access remains through the existing project dashboard/admin connection.

CREATE OR REPLACE FUNCTION public.sl_queue_consultation_notice(p_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_row public.consultation_inquiries;
  v_config jsonb;
  v_text text;
  v_request_id bigint;
BEGIN
  SELECT * INTO v_row FROM public.consultation_inquiries WHERE id = p_id;
  IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_extension WHERE extname = 'pg_net') THEN RETURN; END IF;
  SELECT jsonb_object_agg(key, value) INTO v_config FROM public.app_config
    WHERE key IN ('owner_email', 'owner_name', 'sender_email', 'sender_name', 'email_fn_url', 'email_fn_secret');
  IF coalesce(v_config->>'owner_email', '') = '' OR coalesce(v_config->>'sender_email', '') = ''
    OR coalesce(v_config->>'email_fn_url', '') !~ '^https://'
    OR length(coalesce(v_config->>'email_fn_secret', '')) < 24
    OR v_config->>'email_fn_secret' = 'CHANGE_ME_TO_A_32_CHAR_SECRET' THEN RETURN; END IF;
  -- Escape user text before rendering it inside the existing relay's HTML email.
  v_text := jsonb_pretty(jsonb_build_object(
    'Inquiry reference', v_row.id, 'Name', v_row.client_name, 'Reply email', v_row.client_email,
    'Service', v_row.service, 'Format', v_row.contact_format, 'Child age(s) / due date', v_row.stage,
    'Neighborhood / ZIP', v_row.location, 'Phone', v_row.client_phone,
    'Child name (optional)', v_row.child_name, 'Situation / questions', v_row.notes, 'How they heard about Catalina', v_row.referral_source));
  v_text := replace(replace(replace(v_text, '&', '&amp;'), '<', '&lt;'), '>', '&gt;');
  SELECT net.http_post(
    url := v_config->>'email_fn_url',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_config->>'email_fn_secret'),
    body := jsonb_build_object(
      'sender', jsonb_build_object('name', coalesce(v_config->>'sender_name', 'Sleepy Llamas'), 'email', v_config->>'sender_email'),
      'to', jsonb_build_array(jsonb_build_object('name', coalesce(v_config->>'owner_name', 'Catalina'), 'email', v_config->>'owner_email')),
      'subject', 'New Sleepy Llamas inquiry',
      'htmlContent', '<h1>A family would like to talk</h1><p>This is an inquiry, not a confirmed appointment. Reply to the parent email below.</p><pre style="white-space:pre-wrap">' || v_text || '</pre>'
    )
  ) INTO v_request_id;
  UPDATE public.consultation_inquiries SET owner_notification = 'queued', notification_request_id = v_request_id WHERE id = p_id;
EXCEPTION WHEN OTHERS THEN
  -- An unavailable notification must not discard the saved family request.
  UPDATE public.consultation_inquiries SET owner_notification = 'queue_failed' WHERE id = p_id;
  RAISE WARNING 'Consultation notification could not be queued for %', p_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.sl_queue_consultation_notice(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.sl_create_consultation_inquiry(
  p_request_id uuid, p_details jsonb, p_website text DEFAULT ''
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $function$
DECLARE
  v_field text;
  v_limit integer;
  v_details jsonb := '{}'::jsonb;
  v_existing public.consultation_inquiries;
  v_email text;
BEGIN
  IF p_request_id IS NULL OR jsonb_typeof(p_details) IS DISTINCT FROM 'object'
    OR length(p_details::text) > 12000 OR coalesce(p_website, '') <> '' THEN
    RAISE EXCEPTION 'invalid_inquiry';
  END IF;
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(p_details) AS k(key) WHERE key NOT IN
    ('client_name', 'client_email', 'service', 'contact_format', 'child_name', 'stage', 'location', 'client_phone', 'notes', 'referral_source')) THEN
    RAISE EXCEPTION 'invalid_inquiry';
  END IF;
  FOREACH v_field IN ARRAY ARRAY['client_name','client_email','service','contact_format','child_name','stage','location','client_phone','notes','referral_source'] LOOP
    IF p_details ? v_field AND jsonb_typeof(p_details->v_field) NOT IN ('string', 'null') THEN RAISE EXCEPTION 'invalid_inquiry'; END IF;
    v_details := v_details || jsonb_build_object(v_field, btrim(coalesce(p_details->>v_field, '')));
    v_limit := CASE v_field WHEN 'client_name' THEN 80 WHEN 'client_email' THEN 254 WHEN 'child_name' THEN 60
      WHEN 'referral_source' THEN 160 WHEN 'stage' THEN 100 WHEN 'location' THEN 160 WHEN 'client_phone' THEN 40 WHEN 'notes' THEN 2000 ELSE 60 END;
    IF length(v_details->>v_field) > v_limit THEN RAISE EXCEPTION 'invalid_inquiry'; END IF;
  END LOOP;
  v_email := lower(v_details->>'client_email');
  v_details := v_details || jsonb_build_object('client_email', v_email);
  IF v_details->>'client_name' = '' OR v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
    OR v_details->>'service' NOT IN ('fit-call', 'general-family-consult', 'newborn-postpartum-consult', 'first-weeks-plan',
      'home-consult', 'caregiver-training', 'overnight-doula', 'overnight-sleep-training', 'not-sure')
    OR v_details->>'contact_format' NOT IN ('phone', 'video', 'in-person', 'not-sure')
    OR (v_details->>'service' IN ('home-consult', 'caregiver-training') AND v_details->>'contact_format' <> 'in-person')
    OR (v_details->>'contact_format' = 'in-person' AND v_details->>'location' = '') THEN
    RAISE EXCEPTION 'invalid_inquiry';
  END IF;

  -- A single transaction lock makes the global/email limits and retry check atomic.
  -- Basic anonymous abuse guard: max 3 per email and 60 overall per rolling hour.
  -- This is not a substitute for edge-level protections if public spam increases.
  PERFORM pg_catalog.pg_advisory_xact_lock(170113, 1);
  SELECT * INTO v_existing FROM public.consultation_inquiries WHERE id = p_request_id;
  IF FOUND THEN
    IF jsonb_build_object('client_name',v_existing.client_name,'client_email',v_existing.client_email,'service',v_existing.service,
      'contact_format',v_existing.contact_format,'child_name',coalesce(v_existing.child_name,''),'stage',coalesce(v_existing.stage,''),
      'location',coalesce(v_existing.location,''),'client_phone',coalesce(v_existing.client_phone,''),'notes',coalesce(v_existing.notes,''),'referral_source',coalesce(v_existing.referral_source,'')) = v_details THEN
      RETURN jsonb_build_object('id', v_existing.id);
    END IF;
    RAISE EXCEPTION 'invalid_inquiry';
  END IF;
  IF (SELECT count(*) FROM public.consultation_inquiries WHERE created_at > now() - interval '1 hour' AND client_email = v_email) >= 3
    OR (SELECT count(*) FROM public.consultation_inquiries WHERE created_at > now() - interval '1 hour') >= 60 THEN
    RAISE EXCEPTION 'inquiry_rate_limit';
  END IF;
  INSERT INTO public.consultation_inquiries (id,client_name,client_email,service,contact_format,child_name,stage,location,client_phone,notes,referral_source)
  VALUES (p_request_id,v_details->>'client_name',v_email,v_details->>'service',v_details->>'contact_format',
    nullif(v_details->>'child_name',''),nullif(v_details->>'stage',''),nullif(v_details->>'location',''),
    nullif(v_details->>'client_phone',''),nullif(v_details->>'notes',''),nullif(v_details->>'referral_source',''));
  PERFORM public.sl_queue_consultation_notice(p_request_id);
  RETURN jsonb_build_object('id', p_request_id);
END;
$function$;
REVOKE ALL ON FUNCTION public.sl_create_consultation_inquiry(uuid,jsonb,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_create_consultation_inquiry(uuid,jsonb,text) TO anon, authenticated;

COMMIT;
