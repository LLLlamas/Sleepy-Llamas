#!/usr/bin/env bash
# Stamps the build, archives for release, and refuses to hand you an archive that
# fails any of the four checks in docs/testflight.md.
#
# The debug guard exists because it already happened: `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
# was set in the target's `base` settings rather than per-configuration, which
# defines DEBUG in Release too. The demo seed — a fake twin night — shipped inside
# a TestFlight build. Nothing in the test suite could catch that; only the binary
# can be asked.
#
#   ./scripts/archive.sh
#
# Leaves the archive in ~/Library/Developer/Xcode/Archives/<today>/ so it appears in
# Xcode's Organizer. Organizer reads only that directory, so an archive built to a
# custom -archivePath is invisible there. The build log is kept beside it.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

TIMEOUT=${MOONLOG_ARCHIVE_TIMEOUT:-900}
# Explicit, because two concurrent xcodebuild runs fight over the default
# DerivedData — and a reachability run in another pane is exactly that. Ignored
# by .gitignore's `.build/`.
DERIVED="$PWD/.build/DerivedData"

# --- the stamp must be undoable --------------------------------------------
# stamp-build.sh rewrites project.yml *before* the archive, because the number is
# compiled into the binary and there is no way to stamp afterwards. So a failed
# archive used to leave the tree dirty with a build number that was never shipped.
PREV=$(grep -m1 '^    CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *//;s/"//g')
STAMPED=no
SUCCEEDED=no
restore_stamp() {
    [ "$STAMPED" = yes ] || return 0
    [ "$SUCCEEDED" = yes ] && return 0
    sed -i '' "s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"${PREV}\"/" project.yml
    note "project.yml put back to build ${PREV} — nothing was shipped."
}
trap restore_stamp EXIT

# --- what counts as debug-only, derived rather than remembered --------------
# The old list was maintained by hand, and had already drifted: `moonlogTab` is a
# `#if DEBUG` launch argument in DemoSeed.swift and was never added to it. It
# passed only because the whole file is inside `#if DEBUG` and the other markers
# caught it. Reading the source instead means a new hook cannot be forgotten.
#
# The awk pass tracks `#if`/`#else`/`#endif` nesting and collects "moonlogXxx"
# string literals that are inside a DEBUG region — `#else` branches are *not*
# debug-only and are skipped.
MARKERS=$(find Sources -name '*.swift' -print0 | xargs -0 awk '
  FNR == 1 { depth = 0; dbg = 0 }
  /^[[:space:]]*#if[[:space:]]/ {
      depth++
      if (dbg == 0 && $0 ~ /#if[[:space:]]+DEBUG[[:space:]]*$/) dbg = depth
      next
  }
  /^[[:space:]]*#(else|elseif)/ { if (dbg == depth) dbg = 0; next }
  /^[[:space:]]*#endif/         { if (dbg == depth) dbg = 0; depth--; next }
  dbg > 0 {
      line = $0
      while (match(line, /"moonlog[A-Za-z]+"/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          line = substr(line, RSTART + RLENGTH)
      }
  }
' | sort -u)

# An empty pattern makes `grep -c` match nothing and the guard pass vacuously,
# which is the one failure mode worse than no guard at all.
[ -n "$MARKERS" ] || die "derived no debug markers from Sources/ — the guard would pass on anything."

# The nine the list was hard-coded with. Deriving must never lose one; if a hook
# is genuinely retired, delete it from here in the same change.
for required in moonlogDemoWrite moonlogDumpHandoff moonlogEditFirst moonlogOpenSheet \
                moonlogResetStore moonlogSeedDemo moonlogSettingsSheet moonlogShiftHours \
                moonlogStillGlyphs; do
    printf '%s\n' "$MARKERS" | grep -qx "$required" \
        || die "marker derivation lost '${required}'. Check the #if DEBUG scan in this script."
done
PATTERN=$(printf '%s' "$MARKERS" | tr '\n' '|')

say "Stamping"
./scripts/stamp-build.sh
STAMPED=yes
STAMP=$(grep -m1 '^    CURRENT_PROJECT_VERSION:' project.yml | sed 's/.*: *//;s/"//g')

DAY=$(date +%Y-%m-%d)
DEST="$HOME/Library/Developer/Xcode/Archives/${DAY}"
# Seconds, not just minutes: two archives a minute apart is normal when one has
# just been rejected by the guard, and at minute resolution the second silently
# overwrites the first — including the log the first one failed with.
NAME="Moonlog $(date '+%Y-%m-%d, %H.%M.%S').xcarchive"
LOG="${DEST}/${NAME%.xcarchive}.build.log"
mkdir -p "$DEST"

say "Archiving build ${STAMP} (timeout ${TIMEOUT}s)"
note "log: ${LOG}"
# Captured into a variable, not tested with `if !` — after `if ! cmd`, `$?` in
# the body is the status of the *inverted* test, which is always 0.
status=0
run_with_watchdog "$TIMEOUT" \
    xcodebuild -project Moonlog.xcodeproj -scheme Moonlog -configuration Release \
      -destination "generic/platform=iOS" -archivePath "${DEST}/${NAME}" \
      -derivedDataPath "$DERIVED" \
      -allowProvisioningUpdates archive >"$LOG" 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
        printf 'error: the archive was still running after %ss and was killed.\n' "$TIMEOUT" >&2
        printf '       -allowProvisioningUpdates blocks on an account prompt with no TTY.\n' >&2
        printf '       Open Xcode once, then retry. Log: %s\n' "$LOG" >&2
    else
        report_failure "$LOG" "archive"
    fi
    # A killed archive can leave a half-written .xcarchive behind, and the log
    # beside it is what upload.sh reads as "archive.sh verified this". Remove the
    # archive and rename the log so neither can be mistaken for a clean build.
    if [ -n "${NAME:-}" ]; then rm -rf "${DEST}/${NAME}"; fi
    mv "$LOG" "${LOG%.build.log}.failed.log" 2>/dev/null || true
    exit 1
fi

APP="${DEST}/${NAME}/Products/Applications/Moonlog.app"
[ -f "$APP/Moonlog" ] || die "no binary at ${APP}/Moonlog"

fail_archive() {
    printf 'error: %s\n' "$1" >&2
    # Guarded: an empty $NAME would make this `rm -rf` the whole day's archives.
    if [ -n "${NAME:-}" ]; then rm -rf "${DEST}/${NAME}"; fi
    mv "$LOG" "${LOG%.build.log}.failed.log" 2>/dev/null || true
    exit 1
}

# --- check 1: no Release build warnings ------------------------------------
# This is why the log is kept. The old script sent it to /dev/null, so the
# "Release build warnings: none" line in docs/testflight.md had to be answered by
# a *second*, identical `-destination generic/platform=iOS build`. Same
# configuration, same destination, same work, twice.
# Matched on the diagnostic *shape* — `/path/File.swift:12:5: warning:`, `ld:`,
# `clang:` — not on the word. A bare ` warning: ` also catches tool chatter:
# appintentsmetadataprocessor logs two "No AppIntents.framework dependency found"
# lines on every build of this app, and neither is a warning about our code.
WARN_RE='^/.+:[0-9]+:[0-9]+: warning:|^ld: warning:|^clang: warning:|^<unknown>:0: warning:'
WARNINGS=$(grep -cE "$WARN_RE" "$LOG" || true)
if [ "$WARNINGS" -ne 0 ]; then
    note "${WARNINGS} Release build warning(s) — first few:"
    grep -E "$WARN_RE" "$LOG" | sed 's/^/    /' | head -5
    note "(not fatal, but docs/testflight.md says a shipped build has none)"
else
    note "No Release build warnings."
fi

# --- check 2: no debug-only code, in the app or the embedded framework ------
# MoonlogCore is embedded, and the SWIFT_ACTIVE_COMPILATION_CONDITIONS mistake
# that caused this guard would have hit it too.
for binary in "$APP/Moonlog" "$APP/Frameworks/MoonlogCore.framework/MoonlogCore"; do
    [ -f "$binary" ] || fail_archive "expected a binary at ${binary}"
    leaked=$(strings "$binary" | grep -cE "$PATTERN" || true)
    if [ "$leaked" -ne 0 ]; then
        printf 'error: debug-only code is present in %s (%s markers).\n' "$(basename "$binary")" "$leaked" >&2
        printf '       Check SWIFT_ACTIVE_COMPILATION_CONDITIONS is per-config, not in base.\n' >&2
        fail_archive "debug-only code in the Release binary"
    fi
done
note "No debug-only code in the Release binaries."

# --- checks 3-5: the rest of the docs/testflight.md table, enforced ---------
PLIST="$APP/Info.plist"

BUILT=$(plutil -extract CFBundleVersion raw -o - "$PLIST")
[ "$BUILT" = "$STAMP" ] \
    || fail_archive "the archive says build ${BUILT} but we stamped ${STAMP}. Check manageAppVersionAndBuildNumber is still false in ExportOptions.plist."

ENCRYPTION=$(plutil -extract ITSAppUsesNonExemptEncryption raw -o - "$PLIST" 2>/dev/null || echo missing)
case "$ENCRYPTION" in
    false|0) : ;;
    *) fail_archive "ITSAppUsesNonExemptEncryption is '${ENCRYPTION}', not false — export compliance will prompt on every upload." ;;
esac

# iCloud in the entitlements without the capability is the launch-crash trap in
# docs/cloudkit.md: the container init succeeds and CloudKit traps on a
# background queue a moment later, with nothing to catch.
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -qi 'icloud'; then
    fail_archive "the app carries an iCloud entitlement. See docs/cloudkit.md — enable MOONLOG_CLOUDKIT in the same change or not at all."
fi
note "Build number, export compliance and entitlements all as expected."

SUCCEEDED=yes
say "Archive clean — all four checks passed."
echo "${DEST}/${NAME}"
echo "Upload it with: ./scripts/upload.sh"
