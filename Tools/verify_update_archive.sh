#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/botplus-update-checks.XXXXXX")"
trap 'rm -rf -- "$CHECK_DIRECTORY"' EXIT
VERSION="${2:-$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);.*/\1/p' "$PROJECT_ROOT/BotPlusPDFEditor.xcodeproj/project.pbxproj" | head -n 1)}"
ARCHIVE="${1:-$PROJECT_ROOT/dist/$VERSION/BotPlus-PDF-Editor-update.zip}"
[[ -n "$VERSION" ]] || { printf 'Pass the expected archive version as the second argument.\n' >&2; exit 1; }
[[ -f "$ARCHIVE" ]] || { printf 'Missing update archive: %s\n' "$ARCHIVE" >&2; exit 1; }
# Isolate UserDefaults as well as all install targets from the developer's app.
cat "$PROJECT_ROOT/AppUpdates.swift" > "$CHECK_DIRECTORY/Checks.swift"
cat "$PROJECT_ROOT/Tests/UpdateInstallChecks.swift" >> "$CHECK_DIRECTORY/Checks.swift"
mkdir "$CHECK_DIRECTORY/fixture"
swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  -module-cache-path "$CHECK_DIRECTORY/modules" "$CHECK_DIRECTORY/Checks.swift" -o "$CHECK_DIRECTORY/Checks"
"$CHECK_DIRECTORY/Checks" "$ARCHIVE" "$CHECK_DIRECTORY/fixture" "$PROJECT_ROOT/BotPlusPDFEditor/BotPlusPDFEditor.entitlements" "$VERSION"
