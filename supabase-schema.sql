-- ============================================================================
-- SLEEPY LLAMAS — Full Supabase Schema
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New Query)
--
-- Creates: availability, booking_requests, app_config tables
--          All sl_* RPC functions, triggers, email templates
--          RLS policies, grants, indexes
--
-- SECURITY MODEL:
--   • All tables have RLS enabled with ZERO policies
--   • All access goes through SECURITY DEFINER functions
--   • Admin PIN is bcrypt-hashed in app_config (never hardcoded)
--   • Edge Function auth via shared secret header
--   • FOR UPDATE row locks on all mutation RPCs
-- ============================================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ════════════════════════════════════════════════════════════════════════════
-- TABLES
-- ════════════════════════════════════════════════════════════════════════════

-- ── availability ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.availability (
  day            date PRIMARY KEY,
  status         text NOT NULL CHECK (status IN ('available','booked','unavailable')),
  child_name     text,
  arrival_time   time,
  departure_time time,
  notes          text,
  updated_at     timestamptz DEFAULT now()
);

ALTER TABLE public.availability ENABLE ROW LEVEL SECURITY;
-- Zero policies — all access via SECURITY DEFINER RPCs

-- ── booking_requests ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.booking_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','approved','declined','cancelled')),
  service         text NOT NULL
                    CHECK (service IN ('sleep-training','doula','consultation')),
  client_name     text NOT NULL,
  client_email    text NOT NULL,
  client_phone    text,
  child_name      text NOT NULL,
  start_date      date NOT NULL,
  end_date        date NOT NULL,
  weeks_needed    integer,
  days_per_week   integer,
  arrival_time    time,
  departure_time  time,
  notes           text,
  decided_at      timestamptz,
  decided_by      text,
  paid_at         timestamptz,
  paid_by         text,
  created_at      timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS booking_requests_status_idx ON public.booking_requests (status);
CREATE INDEX IF NOT EXISTS booking_requests_dates_idx  ON public.booking_requests (start_date, end_date);
CREATE INDEX IF NOT EXISTS booking_requests_paid_idx   ON public.booking_requests (paid_at) WHERE paid_at IS NULL;

ALTER TABLE public.booking_requests ENABLE ROW LEVEL SECURITY;

-- ── app_config ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
-- Revoke all direct access — only SECURITY DEFINER functions read this
REVOKE ALL ON public.app_config FROM anon, authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- SEED app_config
-- ════════════════════════════════════════════════════════════════════════════
-- NOTE: You MUST update these values before going live!
-- The admin_pin_hash below is for PIN '1234' — change it with:
--   UPDATE app_config SET value = crypt('YOUR_PIN', gen_salt('bf'))
--   WHERE key = 'admin_pin_hash';

INSERT INTO public.app_config (key, value) VALUES
  ('owner_email',       'sleepyllamas@gmail.com'),
  ('owner_name',        'Owner Name'),                    -- TODO: your real name
  ('sender_email',      'sleepyllamas@gmail.com'),
  ('sender_name',       'Sleepy Llamas'),
  ('email_fn_url',      'https://kozbrcqehylhzoocvfby.supabase.co/functions/v1/send-email'),
  ('email_fn_secret',   'CHANGE_ME_TO_A_32_CHAR_SECRET'), -- TODO: run openssl rand -base64 32
  ('admin_pin_hash',    crypt('1234', gen_salt('bf'))),   -- TODO: change PIN!
  ('venmo_handle',      'sleepy-llamas'),                 -- TODO
  ('zelle_display',     'sleepyllamas@gmail.com'),
  ('zelle_display_type','email')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;


-- ════════════════════════════════════════════════════════════════════════════
-- PUBLIC RPC: sl_get_availability
-- Returns availability rows for the calendar. Called on page load.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_get_availability(p_from date, p_to date)
RETURNS TABLE (
  day            date,
  status         text,
  child_name     text,
  arrival_time   time,
  departure_time time,
  notes          text,
  updated_at     timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.day, a.status, a.child_name, a.arrival_time, a.departure_time, a.notes, a.updated_at
  FROM public.availability a
  WHERE a.day BETWEEN p_from AND p_to
  ORDER BY a.day;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- PUBLIC RPC: sl_create_booking_request
-- Inserts a pending booking. Triggers owner notification email.
-- ════════════════════════════════════════════════════════════════════════════
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
  IF p_service NOT IN ('sleep-training', 'doula', 'consultation') THEN
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


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_verify_admin_pin
-- Bcrypt-checks PIN against app_config.admin_pin_hash
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_verify_admin_pin(p_pin text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash text;
BEGIN
  SELECT value INTO v_hash FROM public.app_config WHERE key = 'admin_pin_hash';
  IF v_hash IS NULL THEN RETURN false; END IF;
  RETURN crypt(p_pin, v_hash) = v_hash;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_set_availability
-- Sets a single day's status. PIN-gated.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_set_availability(
  p_pin            text,
  p_date           date,
  p_status         text,
  p_child_name     text DEFAULT NULL,
  p_arrival_time   time DEFAULT NULL,
  p_departure_time time DEFAULT NULL,
  p_notes          text DEFAULT NULL
)
RETURNS public.availability
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.availability;
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RAISE EXCEPTION 'Invalid PIN';
  END IF;

  IF p_status NOT IN ('available', 'booked', 'unavailable') THEN
    RAISE EXCEPTION 'Invalid status: %', p_status;
  END IF;

  INSERT INTO public.availability (day, status, child_name, arrival_time, departure_time, notes, updated_at)
  VALUES (p_date, p_status, p_child_name, p_arrival_time, p_departure_time, p_notes, now())
  ON CONFLICT (day) DO UPDATE SET
    status         = EXCLUDED.status,
    child_name     = EXCLUDED.child_name,
    arrival_time   = EXCLUDED.arrival_time,
    departure_time = EXCLUDED.departure_time,
    notes          = EXCLUDED.notes,
    updated_at     = now()
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_list_booking_requests
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_list_booking_requests(
  p_pin    text,
  p_status text DEFAULT 'pending'
)
RETURNS SETOF public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RAISE EXCEPTION 'Invalid PIN';
  END IF;

  RETURN QUERY
    SELECT * FROM public.booking_requests
    WHERE (p_status IS NULL OR status = p_status)
    ORDER BY created_at DESC;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_decide_booking_request
-- Approve or decline. On approve: books availability rows.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_decide_booking_request(
  p_pin    text,
  p_id     uuid,
  p_action text  -- 'approve' | 'decline'
)
RETURNS public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req  public.booking_requests;
  v_day  date;
  v_short text;
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_action NOT IN ('approve', 'decline') THEN
    RAISE EXCEPTION 'Invalid action: %', p_action;
  END IF;

  SELECT * INTO v_req FROM public.booking_requests
    WHERE id = p_id FOR UPDATE;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Booking request not found';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'Can only decide pending requests (current: %)', v_req.status;
  END IF;

  UPDATE public.booking_requests
    SET status     = CASE WHEN p_action = 'approve' THEN 'approved' ELSE 'declined' END,
        decided_at = now(),
        decided_by = 'owner'
    WHERE id = p_id
    RETURNING * INTO v_req;

  -- If approving, mark each day in the range as booked
  IF p_action = 'approve' THEN
    v_short := left(v_req.id::text, 8);
    FOR v_day IN SELECT generate_series(v_req.start_date, v_req.end_date, '1 day'::interval)::date
    LOOP
      INSERT INTO public.availability (day, status, child_name, arrival_time, departure_time, notes, updated_at)
      VALUES (v_day, 'booked', v_req.child_name, v_req.arrival_time, v_req.departure_time,
              'Booking #' || v_short, now())
      ON CONFLICT (day) DO UPDATE SET
        status         = 'booked',
        child_name     = EXCLUDED.child_name,
        arrival_time   = EXCLUDED.arrival_time,
        departure_time = EXCLUDED.departure_time,
        notes          = EXCLUDED.notes,
        updated_at     = now();
    END LOOP;
  END IF;

  -- Send email notification to client
  PERFORM sl_notify_client_of_decision(v_req, p_action);

  RETURN v_req;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_list_awaiting_payment
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_list_awaiting_payment(p_pin text)
RETURNS SETOF public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RETURN;  -- silent fail for security
  END IF;

  RETURN QUERY
    SELECT * FROM public.booking_requests
    WHERE status = 'approved' AND paid_at IS NULL
    ORDER BY decided_at DESC;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_mark_booking_paid
-- FOR UPDATE lock prevents race conditions from double-clicks.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_mark_booking_paid(p_pin text, p_id uuid)
RETURNS public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req public.booking_requests;
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req FROM public.booking_requests
    WHERE id = p_id FOR UPDATE;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF v_req.status <> 'approved' THEN
    RAISE EXCEPTION 'Can only mark approved bookings as paid';
  END IF;
  -- Idempotent: if already paid, return as-is
  IF v_req.paid_at IS NOT NULL THEN
    RETURN v_req;
  END IF;

  UPDATE public.booking_requests
    SET paid_at = now(), paid_by = 'owner'
    WHERE id = p_id
    RETURNING * INTO v_req;

  PERFORM sl_notify_client_of_payment(v_req);

  RETURN v_req;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- ADMIN RPC: sl_cancel_booking_request
-- Soft-cancels and frees calendar dates.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_cancel_booking_request(p_pin text, p_id uuid)
RETURNS public.booking_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_req   public.booking_requests;
  v_short text;
BEGIN
  IF NOT sl_verify_admin_pin(p_pin) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT * INTO v_req FROM public.booking_requests
    WHERE id = p_id FOR UPDATE;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF v_req.status NOT IN ('pending', 'approved') THEN
    RAISE EXCEPTION 'Can only cancel pending or approved bookings';
  END IF;

  -- Free the calendar dates (match by the booking short-ID tag)
  v_short := left(v_req.id::text, 8);
  DELETE FROM public.availability
    WHERE day BETWEEN v_req.start_date AND v_req.end_date
      AND notes = 'Booking #' || v_short;

  UPDATE public.booking_requests
    SET status = 'cancelled', decided_at = now(), decided_by = 'owner'
    WHERE id = p_id
    RETURNING * INTO v_req;

  PERFORM sl_notify_client_of_cancellation(v_req);

  RETURN v_req;
END;
$$;


-- ════════════════════════════════════════════════════════════════════════════
-- EMAIL HELPER: sl_notify_owner_of_request
-- Fired by AFTER INSERT trigger on booking_requests.
-- ════════════════════════════════════════════════════════════════════════════
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
  v_unit_price   numeric;
  v_unit_label   text;
  v_qty          integer;
  v_total        numeric;
  v_date_range   text;
  v_schedule     text := '';
BEGIN
  -- Bail if pg_net isn't available
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    RETURN NEW;
  END IF;

  -- Fetch config
  SELECT value INTO v_owner_email  FROM app_config WHERE key = 'owner_email';
  SELECT value INTO v_owner_name   FROM app_config WHERE key = 'owner_name';
  SELECT value INTO v_sender_email FROM app_config WHERE key = 'sender_email';
  SELECT value INTO v_sender_name  FROM app_config WHERE key = 'sender_name';
  SELECT value INTO v_fn_url       FROM app_config WHERE key = 'email_fn_url';
  SELECT value INTO v_fn_secret    FROM app_config WHERE key = 'email_fn_secret';

  IF v_fn_url IS NULL OR v_fn_secret IS NULL THEN RETURN NEW; END IF;

  -- Service label + pricing
  CASE NEW.service
    WHEN 'sleep-training' THEN v_svc_label := 'Overnight Sleep Training'; v_unit_price := 150; v_unit_label := 'night';
      v_qty := greatest((NEW.end_date - NEW.start_date), 1);
    WHEN 'doula' THEN v_svc_label := 'Doula Support'; v_unit_price := 200; v_unit_label := 'visit';
      v_qty := (NEW.end_date - NEW.start_date) + 1;
    WHEN 'consultation' THEN v_svc_label := 'Consultation'; v_unit_price := 75; v_unit_label := 'session';
      v_qty := 1;
    ELSE v_svc_label := NEW.service; v_unit_price := 0; v_unit_label := ''; v_qty := 0;
  END CASE;
  v_total := v_unit_price * v_qty;

  IF NEW.start_date = NEW.end_date THEN
    v_date_range := to_char(NEW.start_date, 'Mon DD, YYYY');
  ELSE
    v_date_range := to_char(NEW.start_date, 'Mon DD, YYYY') || ' → ' || to_char(NEW.end_date, 'Mon DD, YYYY');
  END IF;

  IF NEW.weeks_needed IS NOT NULL THEN
    v_schedule := v_schedule || '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Weeks needed</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">' || NEW.weeks_needed || '</td></tr>';
  END IF;
  IF NEW.days_per_week IS NOT NULL THEN
    v_schedule := v_schedule || '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Days/week</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">' || NEW.days_per_week || '</td></tr>';
  END IF;

  v_subject := 'New booking request from ' || NEW.client_name || ' (' || NEW.child_name || ')';

  v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

<!-- HEADER -->
<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">New Booking Request</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">$H$ || NEW.client_name || ' just requested ' || v_svc_label || ' for ' || NEW.child_name || $H$</p>
</td></tr>

<!-- BODY -->
<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">

  <!-- Booking details -->
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
      '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Departure</td><td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">' || to_char(NEW.departure_time, 'HH12:MI AM') || '</td></tr>'
      ELSE '' END || $H$
    $H$ || CASE WHEN v_total > 0 THEN
      '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Estimated total</td><td style="padding:8px 12px;font-size:18px;font-weight:700;color:#6b1a28;">&#36;' || v_total || ' <span style="font-size:12px;font-weight:400;color:#7a5a5f;">(' || v_qty || ' ' || v_unit_label || CASE WHEN v_qty > 1 THEN 's' ELSE '' END || ' × &#36;' || v_unit_price || '/' || v_unit_label || ')</span></td></tr>'
      ELSE '' END || $H$
  </table>

  <!-- Client info -->
  <div style="background:#fdf6f4;border-radius:8px;padding:14px 16px;margin-bottom:16px;border-left:3px solid #c89b6a;">
    <p style="margin:0 0 4px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#7a5a5f;">Client</p>
    <p style="margin:0;font-size:14px;color:#2a1418;"><strong>$H$ || NEW.client_name || $H$</strong>
      &nbsp;&middot;&nbsp; <a href="mailto:$H$ || NEW.client_email || $H$" style="color:#6b1a28;">$H$ || NEW.client_email || $H$</a>
      $H$ || CASE WHEN NEW.client_phone IS NOT NULL THEN ' &middot; ' || NEW.client_phone ELSE '' END || $H$
    </p>
  </div>

  $H$ || CASE WHEN NEW.notes IS NOT NULL AND NEW.notes <> '' THEN
    '<div style="background:#fdf6f4;border-radius:8px;padding:14px 16px;margin-bottom:16px;border-left:3px solid #d98295;"><p style="margin:0 0 4px;font-size:12px;letter-spacing:1px;text-transform:uppercase;color:#7a5a5f;">Notes</p><p style="margin:0;font-size:14px;color:#2a1418;line-height:1.5;">' || replace(NEW.notes, E'\n', '<br>') || '</p></div>'
    ELSE '' END || $H$

</td></tr>

<!-- FOOTER -->
<tr><td style="padding:20px;text-align:center;">
  <p style="margin:0;font-size:12px;color:#7a5a5f;">Sleepy Llamas &middot; Booking System</p>
</td></tr>

</table>
</td></tr></table>
</body></html>
$H$;

  -- Fire-and-forget email via pg_net
  BEGIN
    PERFORM net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'x-edge-secret', v_fn_secret
      ),
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

-- Trigger
DROP TRIGGER IF EXISTS trg_notify_owner_of_request ON public.booking_requests;
CREATE TRIGGER trg_notify_owner_of_request
  AFTER INSERT ON public.booking_requests
  FOR EACH ROW
  EXECUTE FUNCTION sl_notify_owner_of_request();


-- ════════════════════════════════════════════════════════════════════════════
-- EMAIL HELPER: sl_notify_client_of_decision
-- Sends approval (with payment options) or decline email.
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_notify_client_of_decision(
  v_req    public.booking_requests,
  p_action text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_sender_email text;
  v_sender_name  text;
  v_fn_url       text;
  v_fn_secret    text;
  v_venmo        text;
  v_zelle        text;
  v_zelle_type   text;
  v_subject      text;
  v_html         text;
  v_svc_label    text;
  v_unit_price   numeric;
  v_unit_label   text;
  v_qty          integer;
  v_total        numeric;
  v_date_range   text;
  v_venmo_url    text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN RETURN; END IF;

  SELECT value INTO v_sender_email FROM app_config WHERE key = 'sender_email';
  SELECT value INTO v_sender_name  FROM app_config WHERE key = 'sender_name';
  SELECT value INTO v_fn_url       FROM app_config WHERE key = 'email_fn_url';
  SELECT value INTO v_fn_secret    FROM app_config WHERE key = 'email_fn_secret';
  SELECT value INTO v_venmo        FROM app_config WHERE key = 'venmo_handle';
  SELECT value INTO v_zelle        FROM app_config WHERE key = 'zelle_display';
  SELECT value INTO v_zelle_type   FROM app_config WHERE key = 'zelle_display_type';

  IF v_fn_url IS NULL OR v_fn_secret IS NULL THEN RETURN; END IF;

  -- Pricing
  CASE v_req.service
    WHEN 'sleep-training' THEN v_svc_label := 'Overnight Sleep Training'; v_unit_price := 150; v_unit_label := 'night';
      v_qty := greatest((v_req.end_date - v_req.start_date), 1);
    WHEN 'doula' THEN v_svc_label := 'Doula Support'; v_unit_price := 200; v_unit_label := 'visit';
      v_qty := (v_req.end_date - v_req.start_date) + 1;
    WHEN 'consultation' THEN v_svc_label := 'Consultation'; v_unit_price := 75; v_unit_label := 'session';
      v_qty := 1;
    ELSE v_svc_label := v_req.service; v_unit_price := 0; v_unit_label := ''; v_qty := 0;
  END CASE;
  v_total := v_unit_price * v_qty;

  IF v_req.start_date = v_req.end_date THEN
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY');
  ELSE
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY') || ' → ' || to_char(v_req.end_date, 'Mon DD, YYYY');
  END IF;

  v_venmo_url := 'https://venmo.com/' || v_venmo || '?txn=pay&amount=' || v_total || '&note=' || replace(v_req.child_name || '''s care with Sleepy Llamas', ' ', '%20');

  IF p_action = 'approve' THEN
    v_subject := 'Almost there — complete payment to confirm your booking';
    v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">Almost Confirmed</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">One last step — complete payment to lock it in</p>
</td></tr>

<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Hi $H$ || v_req.client_name || $H$,</p>
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Your booking has been approved! Complete payment below to confirm your spot.</p>

  <table width="100%" style="border-collapse:collapse;margin:20px 0;border:1px solid #f0d2cb;border-radius:8px;overflow:hidden;">
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Service</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_svc_label || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Child</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_req.child_name || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Dates</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_date_range || $H$</td></tr>
    $H$ || CASE WHEN v_total > 0 THEN
      '<tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Total</td><td style="padding:8px 12px;font-size:20px;font-weight:700;color:#6b1a28;">&#36;' || v_total || '</td></tr>'
      ELSE '' END || $H$
  </table>

  <!-- Venmo Card -->
  <div style="background:#fdf6f4;border:1px solid #f0d2cb;border-radius:12px;padding:20px;margin:16px 0;text-align:center;">
    <p style="margin:0 0 8px;font-size:13px;font-weight:700;color:#7a5a5f;letter-spacing:1px;text-transform:uppercase;">Pay with Venmo</p>
    <a href="$H$ || v_venmo_url || $H$" style="display:inline-block;padding:14px 32px;background:#6b1a28;color:#fffaf5;text-decoration:none;border-radius:999px;font-size:15px;font-weight:600;">Pay &#36;$H$ || v_total || $H$ via Venmo →</a>
    <p style="margin:10px 0 0;font-size:12px;color:#7a5a5f;">Amount and note are pre-filled for you.</p>
  </div>

  <!-- Zelle Card -->
  <div style="background:#fdf6f4;border:1px solid #f0d2cb;border-radius:12px;padding:20px;margin:16px 0;text-align:center;">
    <p style="margin:0 0 8px;font-size:13px;font-weight:700;color:#7a5a5f;letter-spacing:1px;text-transform:uppercase;">Pay with Zelle</p>
    <p style="margin:0;font-size:18px;font-weight:700;color:#6b1a28;">$H$ || v_zelle || $H$</p>
    <p style="margin:8px 0 0;font-size:13px;color:#7a5a5f;">Open your banking app and send &#36;$H$ || v_total || $H$ to the $H$ || v_zelle_type || $H$ above.</p>
  </div>

  <p style="font-size:14px;color:#7a5a5f;text-align:center;margin:20px 0 0;">Once payment is received, you'll get a confirmation email with all the details.</p>
</td></tr>

<tr><td style="padding:20px;text-align:center;">
  <p style="margin:0;font-size:12px;color:#7a5a5f;">Sleepy Llamas &middot; Booking System</p>
</td></tr>

</table></td></tr></table>
</body></html>
$H$;

  ELSE  -- decline
    v_subject := 'About your booking request with Sleepy Llamas';
    v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">Booking Update</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">About your recent request</p>
</td></tr>

<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Hi $H$ || v_req.client_name || $H$,</p>
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Thank you so much for reaching out. Unfortunately, we're not able to take this booking for the dates you requested. We're genuinely sorry — we know finding the right support matters.</p>

  <div style="background:#fdf6f4;border:1px solid #f0d2cb;border-radius:8px;padding:14px 16px;margin:16px 0;">
    <p style="margin:0;font-size:13px;color:#7a5a5f;"><strong>Requested:</strong> $H$ || v_svc_label || $H$ for $H$ || v_req.child_name || $H$<br>$H$ || v_date_range || $H$</p>
  </div>

  <p style="font-size:14px;color:#7a5a5f;line-height:1.6;">Please check our calendar for other available dates — we'd love to work with your family.</p>
</td></tr>

<tr><td style="padding:20px;text-align:center;">
  <p style="margin:0;font-size:12px;color:#7a5a5f;">Sleepy Llamas &middot; Booking System</p>
</td></tr>

</table></td></tr></table>
</body></html>
$H$;
  END IF;

  BEGIN
    PERFORM net.http_post(
      url     := v_fn_url,
      headers := jsonb_build_object('Content-Type', 'application/json', 'x-edge-secret', v_fn_secret),
      body    := jsonb_build_object(
        'sender',      jsonb_build_object('name', v_sender_name, 'email', v_sender_email),
        'to',          jsonb_build_array(jsonb_build_object('email', v_req.client_email, 'name', v_req.client_name)),
        'subject',     v_subject,
        'htmlContent',  v_html
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[sl] client decision email failed: %', SQLERRM;
  END;
END;
$fn$;


-- ════════════════════════════════════════════════════════════════════════════
-- EMAIL HELPER: sl_notify_client_of_payment
-- "You're all set!" confirmation email
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_notify_client_of_payment(v_req public.booking_requests)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_sender_email text;
  v_sender_name  text;
  v_fn_url       text;
  v_fn_secret    text;
  v_svc_label    text;
  v_date_range   text;
  v_html         text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN RETURN; END IF;

  SELECT value INTO v_sender_email FROM app_config WHERE key = 'sender_email';
  SELECT value INTO v_sender_name  FROM app_config WHERE key = 'sender_name';
  SELECT value INTO v_fn_url       FROM app_config WHERE key = 'email_fn_url';
  SELECT value INTO v_fn_secret    FROM app_config WHERE key = 'email_fn_secret';

  IF v_fn_url IS NULL OR v_fn_secret IS NULL THEN RETURN; END IF;

  CASE v_req.service
    WHEN 'sleep-training' THEN v_svc_label := 'Overnight Sleep Training';
    WHEN 'doula' THEN v_svc_label := 'Doula Support';
    WHEN 'consultation' THEN v_svc_label := 'Consultation';
    ELSE v_svc_label := v_req.service;
  END CASE;

  IF v_req.start_date = v_req.end_date THEN
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY');
  ELSE
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY') || ' → ' || to_char(v_req.end_date, 'Mon DD, YYYY');
  END IF;

  v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">Booking Confirmed</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">You're all set — we can't wait to meet $H$ || v_req.child_name || $H$</p>
</td></tr>

<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">

  <div style="text-align:center;margin-bottom:20px;">
    <div style="display:inline-block;width:56px;height:56px;border-radius:50%;background:#c89b6a;line-height:56px;text-align:center;">
      <span style="font-size:28px;color:#fffaf5;">&#10003;</span>
    </div>
  </div>

  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Hi $H$ || v_req.client_name || $H$,</p>
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Your payment came through — everything is confirmed. Here are your booking details:</p>

  <table width="100%" style="border-collapse:collapse;margin:20px 0;border:1px solid #f0d2cb;border-radius:8px;overflow:hidden;">
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Service</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_svc_label || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;border-bottom:1px solid #f7e6e2;">Child</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;border-bottom:1px solid #f7e6e2;">$H$ || v_req.child_name || $H$</td></tr>
    <tr><td style="padding:8px 12px;font-size:13px;color:#7a5a5f;">Dates</td>
        <td style="padding:8px 12px;font-size:14px;font-weight:600;color:#2a1418;">$H$ || v_date_range || $H$</td></tr>
  </table>

  <div style="background:#fdf6f4;border:1px solid #f0d2cb;border-radius:8px;padding:16px;margin:20px 0;">
    <p style="margin:0 0 8px;font-size:13px;font-weight:700;color:#6b1a28;letter-spacing:1px;text-transform:uppercase;">Before Your First Night</p>
    <ul style="margin:0;padding:0 0 0 18px;font-size:14px;color:#2a1418;line-height:1.8;">
      <li>We'll reach out the day before with details and any last questions</li>
      <li>Reply with your child's sleep routine, any concerns, and what works</li>
      <li>Have any comfort items ready (blanket, pacifier, white noise machine)</li>
    </ul>
  </div>

  <p style="font-size:15px;color:#2a1418;line-height:1.6;text-align:center;">Thank you for trusting us with your family's rest. We're honored.<br><strong>— Sleepy Llamas</strong></p>
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
        'to',          jsonb_build_array(jsonb_build_object('email', v_req.client_email, 'name', v_req.client_name)),
        'subject',     'You''re all set — booking confirmed!',
        'htmlContent',  v_html
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[sl] payment confirmation email failed: %', SQLERRM;
  END;
END;
$fn$;


-- ════════════════════════════════════════════════════════════════════════════
-- EMAIL HELPER: sl_notify_client_of_cancellation
-- ════════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.sl_notify_client_of_cancellation(v_req public.booking_requests)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $fn$
DECLARE
  v_sender_email text;
  v_sender_name  text;
  v_fn_url       text;
  v_fn_secret    text;
  v_svc_label    text;
  v_date_range   text;
  v_html         text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN RETURN; END IF;

  SELECT value INTO v_sender_email FROM app_config WHERE key = 'sender_email';
  SELECT value INTO v_sender_name  FROM app_config WHERE key = 'sender_name';
  SELECT value INTO v_fn_url       FROM app_config WHERE key = 'email_fn_url';
  SELECT value INTO v_fn_secret    FROM app_config WHERE key = 'email_fn_secret';

  IF v_fn_url IS NULL OR v_fn_secret IS NULL THEN RETURN; END IF;

  CASE v_req.service
    WHEN 'sleep-training' THEN v_svc_label := 'Overnight Sleep Training';
    WHEN 'doula' THEN v_svc_label := 'Doula Support';
    WHEN 'consultation' THEN v_svc_label := 'Consultation';
    ELSE v_svc_label := v_req.service;
  END CASE;

  IF v_req.start_date = v_req.end_date THEN
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY');
  ELSE
    v_date_range := to_char(v_req.start_date, 'Mon DD, YYYY') || ' → ' || to_char(v_req.end_date, 'Mon DD, YYYY');
  END IF;

  v_html := $H$
<!DOCTYPE html><html><head><meta charset="utf-8"></head>
<body style="margin:0;padding:0;background:#fdf6f4;font-family:Arial,Helvetica,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#fdf6f4;padding:32px 16px;">
<tr><td align="center">
<table width="560" cellpadding="0" cellspacing="0" style="max-width:560px;width:100%;">

<tr><td style="background:linear-gradient(135deg,#3d0f17 0%,#6b1a28 100%);border-radius:16px 16px 0 0;padding:32px 28px;text-align:center;">
  <p style="margin:0 0 8px;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#c89b6a;">Booking Cancelled</p>
  <h1 style="margin:0;font-family:Georgia,serif;font-size:26px;font-weight:normal;color:#fffaf5;">Sleepy Llamas</h1>
  <p style="margin:8px 0 0;font-size:14px;color:#d98295;font-style:italic;">We're sorry — something came up</p>
</td></tr>

<tr><td style="background:#fffaf5;padding:28px;border:1px solid rgba(61,15,23,0.08);border-top:none;">
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">Hi $H$ || v_req.client_name || $H$,</p>
  <p style="font-size:15px;color:#2a1418;line-height:1.6;">We wanted to let you know that your booking for $H$ || v_req.child_name || $H$ has been cancelled. We understand this is disappointing, and we're truly sorry.</p>

  <div style="background:#fdf6f4;border:1px solid #f0d2cb;border-radius:8px;padding:14px 16px;margin:16px 0;">
    <p style="margin:0;font-size:13px;color:#7a5a5f;"><strong>Cancelled booking:</strong> $H$ || v_svc_label || $H$<br>$H$ || v_date_range || $H$</p>
  </div>

  <div style="background:#fdf6f4;border-left:3px solid #c89b6a;border-radius:8px;padding:14px 16px;margin:16px 0;">
    <p style="margin:0;font-size:14px;color:#2a1418;line-height:1.5;"><strong>Think this was a mistake?</strong> Just reply to this email right away and we'll sort it out.</p>
  </div>

  <p style="font-size:14px;color:#7a5a5f;line-height:1.6;">Otherwise, feel free to check our calendar for other available dates — we'd love to work with your family.</p>
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
        'to',          jsonb_build_array(jsonb_build_object('email', v_req.client_email, 'name', v_req.client_name)),
        'subject',     'Your Sleepy Llamas booking has been cancelled',
        'htmlContent',  v_html
      )
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING '[sl] cancellation email failed: %', SQLERRM;
  END;
END;
$fn$;


-- ════════════════════════════════════════════════════════════════════════════
-- GRANTS — public RPCs callable by anon
-- ════════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.sl_get_availability(date, date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_create_booking_request(text, text, text, text, text, date, date, integer, integer, time, time, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_verify_admin_pin(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_set_availability(text, date, text, text, time, time, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_list_booking_requests(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_decide_booking_request(text, uuid, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_list_awaiting_payment(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_mark_booking_paid(text, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.sl_cancel_booking_request(text, uuid) TO anon, authenticated;

-- Email helpers are INTERNAL ONLY — no anon grant
-- (sl_notify_owner_of_request, sl_notify_client_of_decision,
--  sl_notify_client_of_payment, sl_notify_client_of_cancellation)
