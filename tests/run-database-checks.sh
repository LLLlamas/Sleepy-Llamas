#!/usr/bin/env bash
# Run only synthetic fixtures in a brand-new, disposable PostgreSQL cluster.
# Requires local PostgreSQL binaries; no Docker, network, email or production URL.
# Usage: bash tests/run-database-checks.sh
# Override binary discovery: PGBIN=/path/to/postgresql/bin bash tests/run-database-checks.sh
set -euo pipefail
umask 077

if [[ "$(id -u)" == 0 ]]; then
  printf '%s\n' 'Run this script as your ordinary user. PostgreSQL initdb refuses root.' >&2
  exit 1
fi

repository_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
pg_bin="${PGBIN:-}"
if [[ -z "$pg_bin" ]]; then
  for candidate in /opt/homebrew/opt/postgresql@16/bin /usr/local/opt/postgresql@16/bin; do
    if [[ -x "$candidate/initdb" && -x "$candidate/pg_ctl" && -x "$candidate/psql" ]]; then
      pg_bin="$candidate"
      break
    fi
  done
fi
if [[ -n "$pg_bin" ]]; then
  initdb_bin="$pg_bin/initdb"
  pg_ctl_bin="$pg_bin/pg_ctl"
  psql_bin="$pg_bin/psql"
else
  initdb_bin="$(command -v initdb || true)"
  pg_ctl_bin="$(command -v pg_ctl || true)"
  psql_bin="$(command -v psql || true)"
fi
for binary in "$initdb_bin" "$pg_ctl_bin" "$psql_bin"; do
  if [[ -z "$binary" || ! -x "$binary" ]]; then
    printf '%s\n' 'Local PostgreSQL tools are required. Set PGBIN to a directory containing initdb, pg_ctl and psql (for example /opt/homebrew/opt/postgresql@16/bin).' >&2
    exit 1
  fi
done

# Ignore caller connection settings. Every psql call below supplies an explicit
# private socket, port, test superuser and database; -X ignores personal psqlrc.
unset PGHOST PGHOSTADDR PGPORT PGDATABASE PGUSER PGSERVICE PGSERVICEFILE
unset PGPASSWORD PGPASSFILE PGOPTIONS PGDATA

# A short path also stays below macOS's Unix-socket path-length limit.
scratch_dir="$(mktemp -d /tmp/sleepy-llamas-db.XXXXXX)"
cluster_dir="$scratch_dir/cluster"
socket_dir="$scratch_dir/socket"
test_role='sleepy_llamas_test'
# No TCP listener exists; the port is a label inside the unique socket directory.
test_port=$((20000 + $$ % 30000))

cleanup() {
  result=$?
  trap - EXIT INT TERM
  if [[ -f "$cluster_dir/postmaster.pid" ]]; then
    if ! "$pg_ctl_bin" -D "$cluster_dir" -m fast -w -t 15 stop >"$scratch_dir/stop.log" 2>&1; then
      printf 'Temporary PostgreSQL did not stop. Preserving only its test directory for inspection: %s\n' "$scratch_dir" >&2
      cat "$scratch_dir/stop.log" >&2
      exit 1
    fi
  fi
  # This path comes only from the successful mktemp call above. Never remove a
  # caller-supplied PGDATA or an arbitrary path, even on initialization failure.
  case "$scratch_dir" in
    /tmp/sleepy-llamas-db.??????) rm -rf -- "$scratch_dir" ;;
    *) printf 'Unexpected temporary path; refusing cleanup: %s\n' "$scratch_dir" >&2; exit 1 ;;
  esac
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -m 700 "$socket_dir"

printf '%s\n' 'Initializing isolated database (synthetic data; TCP disabled)…'
if ! "$initdb_bin" -D "$cluster_dir" --username="$test_role" --auth-local=trust --auth-host=reject --no-locale --encoding=UTF8 >"$scratch_dir/initdb.log" 2>&1; then
  cat "$scratch_dir/initdb.log" >&2
  printf '%s\n' 'Initialization failed. In a restricted sandbox, local PostgreSQL shared-memory operations may require approval. No production connection was attempted.' >&2
  exit 1
fi
if ! "$pg_ctl_bin" -D "$cluster_dir" -l "$scratch_dir/postgres.log" -o "-k $socket_dir -h '' -p $test_port -c unix_socket_permissions=0700" -w -t 15 start >"$scratch_dir/start.log" 2>&1; then
  cat "$scratch_dir/start.log" >&2
  [[ ! -f "$scratch_dir/postgres.log" ]] || cat "$scratch_dir/postgres.log" >&2
  exit 1
fi

# An array preserves paths containing spaces without shell eval.
psql_test=("$psql_bin" -X --no-password --host="$socket_dir" --port="$test_port" --username="$test_role" --dbname=postgres --set=ON_ERROR_STOP=1 --quiet)
"${psql_test[@]}" <<'SQL'
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE TABLE public.app_config (key text PRIMARY KEY, value text NOT NULL);
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.app_config FROM PUBLIC, anon, authenticated;
CREATE TABLE public.availability (
  day date PRIMARY KEY,
  status text NOT NULL CHECK (status IN ('available', 'booked', 'unavailable')),
  child_name text,
  arrival_time time,
  departure_time time,
  notes text,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE public.availability ENABLE ROW LEVEL SECURITY;
-- Match the old public RPC signature so the migration must replace it in place.
CREATE FUNCTION public.sl_get_availability(p_from date, p_to date)
RETURNS TABLE (day date, status text, child_name text, arrival_time time,
  departure_time time, notes text, updated_at timestamptz)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT a.day, a.status, a.child_name, a.arrival_time, a.departure_time,
    a.notes, a.updated_at
  FROM public.availability AS a
  WHERE a.day BETWEEN p_from AND p_to ORDER BY a.day;
$$;
SQL

# pg_net is deliberately absent, and app_config is empty: tests cannot queue mail.
"${psql_test[@]}" --file="$repository_root/supabase/migrations/202611160001_consultation_inquiries.sql"
"${psql_test[@]}" --file="$repository_root/supabase/migrations/202611160002_public_availability_privacy.sql"
printf '%s\n' 'Checking durable inquiries, validation, retries, limits and anonymous access…'
"${psql_test[@]}" --file="$repository_root/tests/consultation-inquiries.sql"
printf '%s\n' 'Checking anonymous availability privacy and range filtering…'
"${psql_test[@]}" --file="$repository_root/tests/public-availability.sql"
printf '%s\n' 'All database checks passed. Stopping and removing the disposable cluster.'
