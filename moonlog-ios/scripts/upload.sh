#!/usr/bin/env bash
# Uploads an archive to TestFlight. Defaults to the newest one, so the
# <day>/<name>.xcarchive path stops being typed by hand.
#
#   ./scripts/upload.sh                       # newest archive
#   ./scripts/upload.sh path/to/one.xcarchive
#
# Not through Organizer: `xcodebuild -exportArchive` with `destination: upload`
# does the same thing from the command line and authenticates with the same Xcode
# account session, so cloud-managed distribution signing works exactly as it does
# in the GUI — no App Store Connect API key is needed, and there is none here.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

TIMEOUT=${MOONLOG_UPLOAD_TIMEOUT:-1800}

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ]; then
    # Newest by mtime across every day directory.
    ARCHIVE=$(find "$HOME/Library/Developer/Xcode/Archives" -maxdepth 2 -name 'Moonlog *.xcarchive' \
                -print0 2>/dev/null | xargs -0 stat -f '%m %N' 2>/dev/null \
              | sort -rn | head -1 | cut -d' ' -f2-)
fi
[ -n "$ARCHIVE" ] && [ -d "$ARCHIVE" ] || die "no archive found. Run ./scripts/archive.sh first."

# archive.sh writes this log beside the archive and only gets that far if all
# four checks passed. No log means the archive was not produced by archive.sh, so
# nothing has asked its binary whether the demo seed is in it.
BUILD_LOG="${ARCHIVE%.xcarchive}.build.log"
if [ ! -f "$BUILD_LOG" ] && [ "${MOONLOG_ALLOW_UNVERIFIED:-no}" != yes ]; then
    die "no build log beside ${ARCHIVE} — it did not come from ./scripts/archive.sh, so it is unverified.
       Re-archive, or set MOONLOG_ALLOW_UNVERIFIED=yes if you are certain."
fi

BUILD=$(plutil -extract CFBundleVersion raw -o - \
          "${ARCHIVE}/Products/Applications/Moonlog.app/Info.plist" 2>/dev/null || echo unknown)
LOG="${ARCHIVE%.xcarchive}.upload.log"

say "Uploading build ${BUILD} to TestFlight (timeout ${TIMEOUT}s)"
note "archive: ${ARCHIVE}"
note "log:     ${LOG}"

# With `destination: upload` no .ipa is left on disk, so -exportPath only ever
# receives the manifest and logs.
status=0
run_with_watchdog "$TIMEOUT" \
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportOptionsPlist ExportOptions.plist \
      -exportPath "$(dirname "$ARCHIVE")/export-${BUILD}" \
      -allowProvisioningUpdates >"$LOG" 2>&1 || status=$?

if [ "$status" -ne 0 ]; then
    if [ "$status" -eq 124 ]; then
        printf 'error: the upload was still running after %ss and was killed.\n' "$TIMEOUT" >&2
        printf '       Nothing partial reaches TestFlight — App Store Connect only accepts a\n' >&2
        printf '       complete upload — so retrying is safe. Log: %s\n' "$LOG" >&2
    else
        report_failure "$LOG" "upload"
    fi
    exit 1
fi

say "Build ${BUILD} uploaded."
note "App Store Connect processes it before it appears in TestFlight; that wait is Apple's."
note "Still to do by hand: commit project.yml and add the row to docs/testflight.md."
