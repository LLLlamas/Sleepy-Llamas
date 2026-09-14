#!/usr/bin/env bash
# The whole TestFlight ritual, in order, in one command.
#
#   ./scripts/ship.sh              # guards, both suites, archive, upload
#   ./scripts/ship.sh --skip-ui    # skip the ~4-minute reachability suite
#   ./scripts/ship.sh --no-upload  # stop after a verified archive
#
# It exists because the ritual was four commands composed by hand out of
# docs/testflight.md every time, one of which needed the archive's
# <day>/<name>.xcarchive path typed into it.
#
# Output is filtered at every step — a raw xcodebuild log must never land in a
# terminal or an agent's context. The logs are kept beside the archive.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

SKIP_UI=no
UPLOAD=yes
for arg in "$@"; do
    case "$arg" in
        --skip-ui)   SKIP_UI=yes ;;
        --no-upload) UPLOAD=no ;;
        *) die "unknown option '${arg}'. Use --skip-ui or --no-upload." ;;
    esac
done

SIM=${MOONLOG_SIM:-iPhone 17 Pro}
DERIVED="$PWD/.build/DerivedData"
TEST_LOG_DIR="$PWD/.build/logs"
mkdir -p "$TEST_LOG_DIR"

# --- step 1: the two hard constraints in CLAUDE.md --------------------------
say "Pre-flight"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[ "$BRANCH" = "moonlog-ios" ] \
    || die "on branch '${BRANCH}'. This app ships from moonlog-ios only — main builds the live website."

# Constraint 2: git status should only ever show moonlog-ios/.
# cut -c4-, not awk $2: a renamed or space-containing path breaks field splitting.
STRAY=$(git status --porcelain | cut -c4- | grep -v '^moonlog-ios/' || true)
if [ -n "$STRAY" ]; then
    printf 'error: changes outside moonlog-ios/:\n' >&2
    printf '%s\n' "$STRAY" | sed 's/^/    /' >&2
    die "the PWA and the website are frozen. Stash or revert these first."
fi
note "branch ${BRANCH}, nothing touched outside moonlog-ios/"
note "$(git log --oneline -1)"

# --- step 2: the fast suite -------------------------------------------------
run_suite() {
    local scheme="$1" label="$2" log="${TEST_LOG_DIR}/$1-test.log"
    say "${label} (${scheme})"
    note "log: ${log}"
    local started; started=$(date +%s)
    local status=0
    run_with_watchdog "${MOONLOG_TEST_TIMEOUT:-1800}" \
        xcodebuild -project Moonlog.xcodeproj -scheme "$scheme" \
          -destination "platform=iOS Simulator,name=${SIM}" \
          -derivedDataPath "$DERIVED" test >"$log" 2>&1 || status=$?
    if [ "$status" -ne 0 ]; then
        if [ "$status" -eq 124 ]; then
            printf 'error: %s was still running after the timeout and was killed.\n' "$label" >&2
            printf '       A test that hangs here is usually XCUITest waiting on an animation\n' >&2
            printf '       to settle — see the -moonlogStillGlyphs note in MoonlogUITestCase.\n' >&2
        fi
        grep -E '(error:|failed|XCTAssert)' "$log" | tail -25 >&2 || true
        die "${label} failed. Log: ${log}"
    fi
    # grep -c prints its count and *also* exits 1 on zero, so `|| echo` would
    # print both. Swallow the status instead.
    note "passed in $(( $(date +%s) - started ))s — $(grep -cE '^Test Case .* passed' "$log" || true) test cases"
}

run_suite Moonlog "Unit suite"

# --- step 3: the slow one that catches what a green unit suite cannot -------
if [ "$SKIP_UI" = yes ]; then
    say "Reachability suite SKIPPED (--skip-ui)"
    note "Three features have shipped built-and-unreachable with the unit suite green."
    note "Only skip this when the tree has not changed since a run that passed."
else
    run_suite MoonlogUI "Reachability suite"
fi

# --- step 4 and 5 -----------------------------------------------------------
./scripts/archive.sh

if [ "$UPLOAD" = yes ]; then
    ./scripts/upload.sh
else
    say "Stopping before upload (--no-upload)."
fi

BUILD=$(grep -m1 '^    CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *//;s/"//g')
VERSION=$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*: *//;s/"//g')

say "Shipped ${VERSION} (${BUILD})"
cat <<NEXT
  Two things this script deliberately does not do, because both are prose:

    1. Add the row to docs/testflight.md — what changed and how to test it.
    2. git commit -m "Ship ${VERSION} (${BUILD}) to TestFlight"
       (project.yml + docs/testflight.md; that is all a ship commit has ever touched)
NEXT
