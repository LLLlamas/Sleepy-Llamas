-- Public availability needs dates and statuses only. Keep the existing result
-- shape for deployed clients, but never expose a family's name or care notes.
-- Apply after the original Sleepy Llamas schema and services migration.
CREATE OR REPLACE FUNCTION public.sl_get_availability(p_from date, p_to date)
RETURNS TABLE (
  day date,
  status text,
  child_name text,
  arrival_time time,
  departure_time time,
  notes text,
  updated_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
  SELECT a.day, a.status, NULL::text, NULL::time, NULL::time,
         NULL::text, a.updated_at
  FROM public.availability AS a
  WHERE a.day BETWEEN p_from AND p_to
  ORDER BY a.day;
$$;

REVOKE ALL ON FUNCTION public.sl_get_availability(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sl_get_availability(date, date) TO anon, authenticated;
