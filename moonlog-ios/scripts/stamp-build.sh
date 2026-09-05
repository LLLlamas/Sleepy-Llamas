#!/usr/bin/env bash
# Stamps the build number and regenerates the Xcode project, in that order.
#
# Use this instead of `agvtool`. Two reasons agvtool is wrong here:
#
#   1. It writes into Moonlog.xcodeproj, which is generated and gitignored — the
#      next `xcodegen generate` throws the number away.
#   2. It also tries to write CFBundleVersion into an Info.plist file. Ours is
#      generated (GENERATE_INFOPLIST_FILE), so there is no file to write; agvtool
#      resolves the path to the literal string "YES" and fails with
#      `Cannot find "Moonlog.xcodeproj/../YES"`.
#
# project.yml is the source of truth, so the number is stamped there and ends up
# committed — which also means a shipped build traces back to a commit.
#
# App Store Connect requires each upload's build number to be higher than the
# last, so a Unix timestamp is used: monotonic, no bookkeeping.
set -euo pipefail
cd "$(dirname "$0")/.."

STAMP=$(date -u +%s)
sed -i '' "s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"${STAMP}\"/" project.yml

if ! grep -q "CURRENT_PROJECT_VERSION: \"${STAMP}\"" project.yml; then
  echo "error: failed to stamp project.yml — check the CURRENT_PROJECT_VERSION line" >&2
  exit 1
fi

xcodegen generate >/dev/null
echo "Stamped build ${STAMP} (marketing version $(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*: *//;s/"//g'))"
