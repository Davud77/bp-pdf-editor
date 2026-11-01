#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
CHECK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/botplus-checks.XXXXXX")"
cleanup() {
  local result=$?
  trap - EXIT
  if [[ -n "$CHECK_DIRECTORY" && -d "$CHECK_DIRECTORY" ]]; then rm -rf -- "$CHECK_DIRECTORY"; fi
  exit "$result"
}
trap cleanup EXIT
[[ "$(uname -s)" == Darwin ]] || {
  printf 'Native checks require macOS.\n' >&2
  exit 1
}
sed '/^@main$/d' "$PROJECT_ROOT/ContentView.swift" > "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFiumSourceEditor.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFTextEditingUI.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFContentEditingUI.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFPageFormatting.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFGraphicMarks.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFDocumentWorkflows.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFRegionEditing.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFAttachmentExport.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFPathEditing.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFStructureUI.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFOfficeExport.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFComparison.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFRasterWorkflows.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFScanner.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFOCR.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFExchange.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/PDFThumbnailGrid.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/WorkspaceFeatures.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/AppUpdates.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
cat "$PROJECT_ROOT/Tests/NativeChecksMain.swift" >> "$CHECK_DIRECTORY/NativeChecks.swift"
mkdir -p "$CHECK_DIRECTORY/Modules" "$CHECK_DIRECTORY/ClangModules"
clang -target "$(uname -m)-apple-macos14.0" -I "$PROJECT_ROOT/Vendor/PDFium/include" -I "$PROJECT_ROOT/Native/PDFiumBridge/include" -c "$PROJECT_ROOT/Native/PDFiumBridge/PDFiumSave.c" -o "$CHECK_DIRECTORY/PDFiumSave.o"
SWIFT_MODULE_CACHE_PATH="$CHECK_DIRECTORY/Modules" \
CLANG_MODULE_CACHE_PATH="$CHECK_DIRECTORY/ClangModules" \
swiftc -swift-version 6 -parse-as-library -target "$(uname -m)-apple-macos14.0" \
  "${BOTPLUS_CHECK_OPTIMIZATION:--Onone}" \
  -module-cache-path "$CHECK_DIRECTORY/Modules" \
  -I "$PROJECT_ROOT/Native/PDFiumBridge/include" -Xcc -I"$PROJECT_ROOT/Vendor/PDFium/include" \
  -L "$PROJECT_ROOT/Vendor/PDFium/lib" -lpdfium -Xlinker -rpath -Xlinker "$PROJECT_ROOT/Vendor/PDFium/lib" \
  "$CHECK_DIRECTORY/PDFiumSave.o" "$CHECK_DIRECTORY/NativeChecks.swift" -o "$CHECK_DIRECTORY/NativeChecks"
"$CHECK_DIRECTORY/NativeChecks" "$CHECK_DIRECTORY"
