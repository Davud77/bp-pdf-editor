#!/bin/bash
set -euo pipefail

# Default: build, package, commit, and push. Use --package-only for a local artifact.
PACKAGE_ONLY=false
for argument in "$@"; do
  case "$argument" in
    --package-only) PACKAGE_ONLY=true ;;
    --help|-h)
      cat <<'HELP'
Usage: ./build_and_deploy.sh [--package-only]

Builds the universal arm64/x86_64 Release app and writes dist/<version>/BotPlus-PDF-Editor.dmg.
By default, commits source changes and pushes main to Davud77/BotPlus-PDF-Editor.
--package-only builds and packages without changing Git or contacting GitHub.

Optional environment variables:
  BOTPLUS_DERIVED_DATA      Xcode build directory (default: build/DerivedData)
  BOTPLUS_SIGNING_IDENTITY  Installed Developer ID Application certificate name
  BOTPLUS_NOTARY_PROFILE    Existing notarytool Keychain profile for notarization

Without a Developer ID identity, the app receives a local ad-hoc signature.
Public Gatekeeper-trusted distribution requires Developer ID and notarization.
HELP
      exit 0 ;;
    *) printf 'Unknown option: %s\n' "$argument" >&2; exit 2 ;;
  esac
done

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DERIVED_DATA="${BOTPLUS_DERIVED_DATA:-$PROJECT_ROOT/build/DerivedData}"
RELEASE_VERSION="$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);.*/\1/p' "$PROJECT_ROOT/BotPlusPDFEditor.xcodeproj/project.pbxproj" | head -n 1)"
[[ "$RELEASE_VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { printf 'Invalid release version.\n' >&2; exit 1; }
DIST_DIRECTORY="$PROJECT_ROOT/dist/$RELEASE_VERSION"
DMG_PATH="$DIST_DIRECTORY/BotPlus-PDF-Editor.dmg"
REPOSITORY_URL="https://github.com/Davud77/BotPlus-PDF-Editor.git"
COMMIT_MESSAGE="feat: add dynamic rulers, dockable panels, and editing tools"
TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/botplus-release.XXXXXX")"
MOUNT_POINT="$TEMP_DIRECTORY/volume"
MOUNTED=false

cleanup() {
  local result=$?
  trap - EXIT INT TERM
  if [[ "$MOUNTED" == true ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || hdiutil detach -force "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -n "$TEMP_DIRECTORY" && -d "$TEMP_DIRECTORY" ]]; then
    rm -rf -- "$TEMP_DIRECTORY"
  fi
  exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ "$(uname -s)" != Darwin ]]; then
  printf 'This pipeline requires macOS and Xcode.\n' >&2
  exit 1
fi
if [[ -n "${BOTPLUS_NOTARY_PROFILE:-}" && -z "${BOTPLUS_SIGNING_IDENTITY:-}" ]]; then
  printf 'Notarization requires BOTPLUS_SIGNING_IDENTITY.\n' >&2
  exit 1
fi
for executable in xcodebuild hdiutil codesign ditto git shasum; do
  command -v "$executable" >/dev/null || { printf 'Required tool is missing: %s\n' "$executable" >&2; exit 1; }
done
cd "$PROJECT_ROOT"

xcodebuild -project "$PROJECT_ROOT/BotPlusPDFEditor.xcodeproj" \
  -scheme BotPlusPDFEditor -configuration Release \
  -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

APP_BUNDLE="$DERIVED_DATA/Build/Products/Release/BotPlusPDFEditor.app"
[[ -d "$APP_BUNDLE" ]] || { printf 'Release app bundle was not produced.\n' >&2; exit 1; }
# Sign a staging copy so packaging does not mutate Xcode's products.
STAGED_APP="$TEMP_DIRECTORY/BotPlus PDF Editor.app"
ditto "$APP_BUNDLE" "$STAGED_APP"
ENTITLEMENTS="$PROJECT_ROOT/BotPlusPDFEditor/BotPlusPDFEditor.entitlements"
for library in "$STAGED_APP/Contents/Frameworks/"*.dylib; do
  [[ -f "$library" ]] || continue
  if [[ -n "${BOTPLUS_SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$BOTPLUS_SIGNING_IDENTITY" "$library"
  else
    codesign --force --sign - "$library"
  fi
  codesign --verify --strict "$library"
done
if [[ -n "${BOTPLUS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$BOTPLUS_SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$STAGED_APP"
else
  codesign --force --sign - --entitlements "$ENTITLEMENTS" "$STAGED_APP"
fi
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

APP_KILOBYTES="$(du -sk "$STAGED_APP" | awk '{print $1}')"
IMAGE_MEGABYTES=$((APP_KILOBYTES / 1024 * 2 + 64))
READ_WRITE_IMAGE="$TEMP_DIRECTORY/ReadWrite.dmg"
mkdir -p "$MOUNT_POINT" "$DIST_DIRECTORY"
hdiutil create -size "${IMAGE_MEGABYTES}m" -fs HFS+ -volname 'BotPlus PDF Editor' "$READ_WRITE_IMAGE"
hdiutil attach -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" "$READ_WRITE_IMAGE"
MOUNTED=true
ditto "$STAGED_APP" "$MOUNT_POINT/BotPlus PDF Editor.app"
ln -s /Applications "$MOUNT_POINT/Applications"
hdiutil detach "$MOUNT_POINT"
MOUNTED=false
hdiutil convert "$READ_WRITE_IMAGE" -format UDZO -imagekey zlib-level=9 -o "$TEMP_DIRECTORY/BotPlus-PDF-Editor.dmg"
hdiutil verify "$TEMP_DIRECTORY/BotPlus-PDF-Editor.dmg"
mv -f "$TEMP_DIRECTORY/BotPlus-PDF-Editor.dmg" "$DMG_PATH"

if [[ -n "${BOTPLUS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$BOTPLUS_SIGNING_IDENTITY" "$DMG_PATH"
fi
if [[ -n "${BOTPLUS_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$BOTPLUS_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  xcrun stapler staple "$STAGED_APP"
  xcrun stapler validate "$STAGED_APP"
fi
(cd "$DIST_DIRECTORY" && shasum -a 256 BotPlus-PDF-Editor.dmg > BotPlus-PDF-Editor.dmg.sha256)
# Dedicated, bounded ZIP for the sandboxed updater: regular files only, no
# /Applications symlink, resource forks or privileged installer scripts.
UPDATE_ZIP="$DIST_DIRECTORY/BotPlus-PDF-Editor-update.zip"
ditto -c -k --keepParent --norsrc "$STAGED_APP" "$TEMP_DIRECTORY/BotPlus-PDF-Editor-update.zip"
mv -f "$TEMP_DIRECTORY/BotPlus-PDF-Editor-update.zip" "$UPDATE_ZIP"
(cd "$DIST_DIRECTORY" && shasum -a 256 BotPlus-PDF-Editor-update.zip > BotPlus-PDF-Editor-update.zip.sha256)
printf 'DMG ready: %s\nUpdate archive ready: %s\n' "$DMG_PATH" "$UPDATE_ZIP"

if [[ "$PACKAGE_ONLY" == true ]]; then exit 0; fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  [[ "$(git rev-parse --show-toplevel)" == "$PROJECT_ROOT" ]] || {
    printf 'Refusing to commit an enclosing repository. Initialize Git in this project directory first.\n' >&2
    exit 1
  }
else
  git init --initial-branch=main
fi
if git rev-parse --verify HEAD >/dev/null 2>&1; then git branch -M main; else git symbolic-ref HEAD refs/heads/main; fi
if git remote get-url origin >/dev/null 2>&1; then
  CURRENT_ORIGIN="$(git remote get-url origin)"
  case "${CURRENT_ORIGIN%/}" in
    "$REPOSITORY_URL"|"${REPOSITORY_URL%.git}"|git@github.com:Davud77/BotPlus-PDF-Editor.git|ssh://git@github.com/Davud77/BotPlus-PDF-Editor.git) ;;
    *) printf 'Origin points to a different repository. Expected %s\n' "$REPOSITORY_URL" >&2; exit 1 ;;
  esac
else
  git remote add origin "$REPOSITORY_URL"
fi
git add --all
if ! git diff --cached --quiet; then git commit -m "$COMMIT_MESSAGE"; fi
git push --set-upstream origin main
