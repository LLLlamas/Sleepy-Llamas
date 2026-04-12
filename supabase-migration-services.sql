-- ============================================================================
-- MIGRATION: Update service types + add package/special_care columns
-- Run this in Supabase SQL Editor AFTER the initial schema.
-- Idempotent — safe to re-run.
-- ============================================================================

-- 1. Drop the old service constraint and add the new one
ALTER TABLE public.booking_requests
  DROP CONSTRAINT IF EXISTS booking_requests_service_check;

ALTER TABLE public.booking_requests
  ADD CONSTRAINT booking_requests_service_check
  CHECK (service IN ('overnight-doula','overnight-sleep-training','consultation',
                     -- Keep old values so existing rows don't break:
                     'sleep-training','doula'));

-- 2. Add new columns (IF NOT EXISTS via DO block)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'booking_requests' AND column_name = 'package') THEN
    ALTER TABLE public.booking_requests ADD COLUMN package text;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'booking_requests' AND column_name = 'special_care') THEN
    ALTER TABLE public.booking_requests ADD COLUMN special_care boolean DEFAULT false;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'booking_requests' AND column_name = 'special_care_notes') THEN
    ALTER TABLE public.booking_requests ADD COLUMN special_care_notes text;
  END IF;
END $$;

-- 3. Update sl_create_booking_request to accept new service values
-- (The existing function already accepts any text and validates with IF/THEN,
--  so we just need to update the validation list)
CREATE OR REPLACE FUNCTION public.sl_create_booking_request(
  p_service        text,
  p_client_name    text,
  p_client_email   text,
  p_client_phone   text,
  p_child_name     text,
  p_start_date     date,
  p_end_date       date,
  p_weeks_needed   integer DEFAULT NULL,
  p_days_per_week  integer DEFAULT NULL,
  p_arrival_time   time DEFAULT NULL,
  p_departure_time time DEFAULT NULL,
  p_notes          text DEFAULT NULL
)
RETURNS public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.booking_requests;
BEGIN
  -- Input validation
  IF trim(coalesce(p_client_name, '')) = '' THEN
    RAISE EXCEPTION 'Client name is required';
  END IF;
  IF trim(coalesce(p_client_email, '')) = '' OR
     p_client_email !~ '^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$' THEN
    RAISE EXCEPTION 'Valid email is required';
  END IF;
  IF trim(coalesce(p_child_name, '')) = '' THEN
    RAISE EXCEPTION 'Child name is required';
  END IF;
  IF p_service NOT IN ('overnight-doula', 'overnight-sleep-training', 'consultation') THEN
    RAISE EXCEPTION 'Invalid service type';
  END IF;
  IF p_start_date < CURRENT_DATE THEN
    RAISE EXCEPTION 'Start date cannot be in the past';
  END IF;
  IF p_end_date < p_start_date THEN
    RAISE EXCEPTION 'End date cannot be before start date';
  END IF;
  IF length(trim(coalesce(p_client_name, ''))) > 80 THEN
    RAISE EXCEPTION 'Client name too long (max 80 chars)';
  END IF;
  IF length(trim(coalesce(p_child_name, ''))) > 60 THEN
    RAISE EXCEPTION 'Child name too long (max 60 chars)';
  END IF;
  IF length(trim(coalesce(p_notes, ''))) > 2000 THEN
    RAISE EXCEPTION 'Notes too long (max 2000 chars)';
  END IF;

  INSERT INTO public.booking_requests (
    service, client_name, client_email, client_phone, child_name,
    start_date, end_date, weeks_needed, days_per_week,
    arrival_time, departure_time, notes
  ) VALUES (
    p_service,
    trim(p_client_name),
    lower(trim(p_client_email)),
    nullif(trim(coalesce(p_client_phone, '')), ''),
    trim(p_child_name),
    p_start_date,
    p_end_date,
    p_weeks_needed,
    p_days_per_week,
    p_arrival_time,
    p_departure_time,
    nullif(trim(coalesce(p_notes, '')), '')
  )
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;

-- Re-grant execute
GRANT EXECUTE ON FUNCTION public.sl_create_booking_request(text, text, text, text, text, date, date, integer, integer, time, time, text) TO anon, authenticated;

-- 4. Update the owner notification email to show new service labels
CREATE OR REPLACE FUNCTION public.sl_notify_owner_of_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_owner_email  text;
  v_owner_name   text;
  v_sender_email text;
  v_sender_name  text;
  v_fn_url       text;
  v_fn_secret    text;
  v_subject      text;
  v_html         text;
  v_svc_label    text;
  v_date_range   text;
  v_schedule     text := '';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN RETURN NEW; END IF;

  SELECT value INTO v_owner_email  FROM app_config WHERE key = 'owner_email';
  SELECT value INTO v_owner_name   FROM app_config WHERE key = 'owner_name';
  SELECT value INTO v_sender_email FROM app_config WHERE key = 'sender_email';
  SELECT value INTO v_sender_name  FROM app_config WHERE key = 'sender_name';
  SELECT value INTO v_fn_url       FROM app_config WHERE key = 'email_fn_url';
  SELECT value INTO v_fn_secret    FROM app_config WHERE key = 'email_fn_secret';
  IF v_fn_url IS NULL OR v_fn_secret IS NULL THEN RETURN NEW; END IF;

  CASE NEW.service
    WHEN 'overnight-doula' THEN v_svc_label := 'Overnight Doula Support';
    WHEN 'overnight-sleep-training' THEN v_svc_label := 'Overnight Sleep Training';
    WHEN 'consultation' THEN v_svc_label := 'Consultation(s)';
    WHEN 'sleep-training' THEN v_svc_label := 'Overnight Sleep Training';
    WHEN 'doula' THEN v_svc_label := 'Doula Support';
    ELSE v_svc_label := NEW.service;
  END CASE;

  IF NEW.start_date = NEW.end_date THEN
    v_date_range := to_char(NEW.start_date, 'Mon DD, YYYY');
  ELSE
    v_date_range := to_char(NEW.start_date, 'Mon DD, YYYY') || ' → ' || to_char(NEW.end_date, 'Mon DD, YYYY');
  END IF;

  IF NEW.weeks_needed IS NOT NULL THEN
    v_schedule := v_schedule || '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Weeks needed</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">' || NEW.weeks_needed || '</td></tr>';
  END IF;
  IF NEW.days_per_week IS NOT NULL THEN
    v_schedule := v_schedule || '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Nights/week</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">' || NEW.days_per_week || '</td></tr>';
  END IF;

  v_subject := 'New booking request from ' || NEW.client_name || ' (' || NEW.child_name || ')';

  v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">
<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">New Booking Request</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">$H$ || NEW.client_name || ' just requested ' || v_svc_label || ' for ' || NEW.child_name || $H$</p>
</td></tr>
<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">
  <table width="100%" style="border-collapse:collapse;margin-bottom:20px;border:1px solid #f0d2cb;border-radius:8px;overflow:hidden;">
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Service</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_svc_label || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Child</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || NEW.child_name || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Dates</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_date_range || $H$</td></tr>
    $H$ || v_schedule || $H$
    $H$ || CASE WHEN NEW.arrival_time IS NOT NULL THEN
      '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Arrival</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">' || to_char(NEW.arrival_time, 'HH12:MI AM') || '</td></tr>'
      ELSE '' END || $H$
    $H$ || CASE WHEN NEW.departure_time IS NOT NULL THEN
      '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Departure</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">' || to_char(NEW.departure_time, 'HH12:MI AM') || '</td></tr>'
      ELSE '' END || $H$
  </table>
  <div style="background:#fdf6f4;border-radius:8px;padding:14px 16px;margin-bottom:16px;border-left:3px solid #c89b6a;">
    <p style="margin:0 0 4px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#7a5a5f;">Client</p>
    <p style="margin:0;font-size:14px;color:#2a1418;"><strong>$H$ || NEW.client_name || $H$</strong>
      &nbsp;&middot;&nbsp; <a href="mailto:$H$ || NEW.client_email || $H$" style="color:#6b1a28;">$H$ || NEW.client_email || $H$</a>
      $H$ || CASE WHEN NEW.client_phone IS NOT NULL THEN ' &middot; ' || NEW.client_phone ELSE '' END || $H$</p>
  </div>
  $H$ || CASE WHEN NEW.notes IS NOT NULL AND NEW.notes <> '' THEN
    '<div style="background:#fdf6f4;border-radius:8px;padding:14px 16px;margin-bottom:16px;border-left:3px solid #d98295;"><p style="margin:0 0 4px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#7a5a5f;">Notes</p><p style="margin:0;font-size:14px;color:#2a1418;line-height:1.5;">' || replace(NEW.notes, E'\n', '<br>') || '</p></div>'
    ELSE '' END || $H$
</td></tr>
<tr><td style="padding:20px;text-align:center;">
  <p style="margin:0;font-size:12px;color:#7a5a5f;">Sleepy Llamas &middot; Booking System</p>
</td></tr>
</table></td></tr></table>
</body></html>
$H$;

  BEGIN
    PERFORM net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := jsonb_build_object(
        'sender',      jsonb_build_object('name', v_sender_name, 'email', v_sender_email),
        'to',          jsonb_build_array(jsonb_build_object('email', v_owner_email, 'name', v_owner_name)),
        'subject',     v_subject,
        'htmlContent',  v_html
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[sl] owner email failed: %', SQLERRM;
  END;
  RETURN NEW;
END;
$fn$;
