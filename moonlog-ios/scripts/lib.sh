# Shared by archive.sh, upload.sh and ship.sh. Sourced, never executed.
#
# Two things live here because all three scripts need them and a third copy of a
# watchdog is a third place for it to be subtly wrong.
#
# `/bin/bash` on this machine is **3.2.57** and there is no `timeout`/`gtimeout`
# installed, so the watchdog is hand-rolled and nothing here may use bash 4
# syntax (no associative arrays, no `mapfile`, no `wait -n`).

# A step heading, so a run is never silent. The long steps print this before they
# block; the old script sent everything to /dev/null and read as hung whether it
# was doing twelve seconds of work or waiting forever on a signing prompt.
say() { printf '\n▸ %s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# run_with_watchdog SECONDS CMD...
#
# Returns the command's status, or 124 if the watchdog had to kill it. Exists
# because `-allowProvisioningUpdates` can block indefinitely on an Xcode account
# prompt when there is no TTY to answer it: without this, a ship session hangs
# with no output and no end. A named failure is always better than a wait.
#
# Redirections belong on the *call* — `run_with_watchdog 900 xcodebuild … >"$LOG" 2>&1`
# — and are inherited by the background child.
run_with_watchdog() {
    local seconds="$1"; shift
    "$@" &
    local pid=$!
    ( sleep "$seconds"; kill -TERM "$pid" 2>/dev/null
      sleep 5;          kill -KILL "$pid" 2>/dev/null ) &
    local dog=$!

    local status=0
    wait "$pid" || status=$?

    # Kill the watchdog *and* its sleep, or an orphan sleep outlives the script
    # and fires a TERM at whatever has reused the pid by then.
    pkill -P "$dog" 2>/dev/null || true
    kill "$dog" 2>/dev/null || true
    wait "$dog" 2>/dev/null || true

    # 128+n means killed by signal n; the only thing signalling here is the dog.
    if [ "$status" -ge 128 ]; then return 124; fi
    return "$status"
}

# Never let a raw build log into a terminal or an agent's context. Prints the
# errors and the last few lines, nothing else.
report_failure() {
    local log="$1" step="$2"
    printf 'error: %s failed. Log: %s\n' "$step" "$log" >&2
    grep -E '(error:|error$|\*\* [A-Z ]+ FAILED)' "$log" 2>/dev/null | tail -20 >&2 \
        || tail -20 "$log" >&2
}
