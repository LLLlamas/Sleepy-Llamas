#!/usr/bin/env bash
# Stamps the build, archives for release, and refuses to hand you an archive with
# debug-only code compiled in.
#
# The guard exists because it already happened: `SWIFT_ACTIVE_COMPILATION_CONDITIONS`
# was set in the target's `base` settings rather than per-configuration, which
# defines DEBUG in Release too. The demo seed — a fake twin night — shipped inside
# a TestFlight build. Nothing in the test suite could catch that; only the binary
# can be asked.
#
#   ./scripts/archive.sh
#
# Leaves the archive in ~/Library/Developer/Xcode/Archives/<today>/ so it appears in
# Xcode's Organizer. Organizer reads only that directory, so an archive built to a
# custom -archivePath is invisible there.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/stamp-build.sh

DAY=$(date +%Y-%m-%d)
DEST="$HOME/Library/Developer/Xcode/Archives/${DAY}"
NAME="Moonlog $(date '+%Y-%m-%d, %H.%M').xcarchive"
mkdir -p "$DEST"

echo "Archiving…"
xcodebuild -project Moonlog.xcodeproj -scheme Moonlog -configuration Release \
  -destination "generic/platform=iOS" -archivePath "${DEST}/${NAME}" \
  -allowProvisioningUpdates archive >/dev/null

BINARY="${DEST}/${NAME}/Products/Applications/Moonlog.app/Moonlog"
[ -f "$BINARY" ] || { echo "error: no binary at ${BINARY}" >&2; exit 1; }

# Markers that only exist inside `#if DEBUG`. If any survives, DEBUG leaked into
# the Release configuration and the demo seed is reachable in a shipped build.
LEAKED=$(strings "$BINARY" | grep -cE \
  "moonlogSeedDemo|moonlogOpenSheet|moonlogEditFirst|moonlogShiftHours|moonlogDemoWrite|moonlogDumpHandoff" \
  || true)
if [ "$LEAKED" -ne 0 ]; then
  echo "error: debug-only code is present in the Release binary (${LEAKED} markers)." >&2
  echo "       Check SWIFT_ACTIVE_COMPILATION_CONDITIONS is per-config, not in base." >&2
  rm -rf "${DEST}/${NAME}"
  exit 1
fi

echo "Archive clean: no debug-only code in the Release binary."
echo "${DEST}/${NAME}"
echo "Open Xcode → Window → Organizer → Archives to distribute."
