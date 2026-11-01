# BotPlus PDF Editor

<img src="docs/branding/AppIcon.png" width="128" height="128" alt="BotPlus PDF Editor logo">

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://www.apple.com/macos/)
[![AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)
[![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
[![PDFium](https://img.shields.io/badge/PDFium-8086-326CE5)](https://pdfium.googlesource.com/pdfium/)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-native-777777?logo=apple)](https://developer.apple.com/)

A native macOS PDF workspace built with SwiftUI, AppKit, and Apple PDFKit. Its ribbon ergonomics, dockable panels, and drafting-oriented workflows take inspiration from PDF-XChange Editor, with a bilingual Russian and English interface. Ribbon tab widths remain fixed when the active tab changes.

## Version 1.9 (13)

The new **Search** panel lists all matches with text snippets and page numbers.
Click a result or use previous/next to navigate. Open it with Cmd+F, the panels
menu, or Return in quick search. Search is case insensitive; scans require OCR first.

A broad implementation batch adds shared document views/splits, batch thumbnails,
interactive cropping, printing, attachments, measurements, explicit OCR, scanner,
FDF/XFDF, OCG controls, named destinations, basic OOXML text exports and structure
inspection. Native checks cover implementation and data preservation; manual and hardware acceptance remain pending.
Version 1.9 (13) includes the accumulated features and a new search panel. See
[implementation status](IMPLEMENTATION_STATUS.md) and [remaining roadmap](ROADMAP.md).

The working tree also supports JSON bookmark Next action trees for supported
action types and FDF/XFDF comment modification timestamps. Other action types,
structural form editing and complete rare-annotation appearance compatibility remain.

The content inspector also offers independent nested Form-resource transforms:
translation, separate X/Y scale and rotation with ancestor copies that isolate
other resource paths/pages. Individual child paths/text/images and Do invocations,
complex gradients/patterns/clipping/transparency still need further editing support.

## Remaining implementation

The working tree adds isolated OCMD conditions for nested Image/Form resources
and measurement copying between open PDFs. Calibrated X/Y and arbitrary-angle distance projections
with matching dimension lines, relative label placement and editable distance/perimeter/area label leaders with up to 32 waypoints are also available. Originals remain in the source PDF;
copies use independent groups, placement/calibration controls and destination Undo.
These changes are included in 1.9. Local packages are in `dist/1.9/`.

Remaining work covers complex navigation/TOC, native form structures and rare
FDF/XFDF appearances, shared-object geometry, nonlinear measurement metrics and
cross-document moves with coordinated Undo, scan dewarping/ICC, semantic comparison,
remaining optional-content cases/Usage, encryption compatibility, irreversible
redaction, full tagged PDF/PDF/UA, structural Office conversion and legacy decoration.
See [ROADMAP.md](ROADMAP.md) for precise limits. Manual/hardware acceptance and
optimization follow implementation.

## Start screen

![BotPlus PDF Editor with no open PDF](docs/images/start-screen.png)

## Features

- Start screen with Open PDF, Create Blank, and ten persisted recent files including path, byte size and last-opened date.
- GitHub release checking, system email composition, current-page form alignment, page replacement, and independent page margins with Undo.
- Dark, light, and system themes, selected under Help → UI Settings → Theme.
- Windows-style ribbon with 13 localized tabs, grouped commands, and a 40 pt quick-access/title/search row drawn into the transparent native titlebar area beside the macOS traffic lights.
- PDFKit viewport with PDF opening, drag and drop, continuous/single/two-page display, hand and text selection, page navigation, zoom, rotation, and guarded printing.
- Source content editor for images, paths/fills, text objects and whole PDF form groups; move, resize, rotate, delete, vector clipboard, Undo and image replacement. Shared form children are preserved.
- Document commands are disabled when no PDF is open; navigation and page deletion respect page boundaries.
- A consistent 5–2000% zoom range and logarithmic status slider; pointer-owned gestures work while the inspector keeps keyboard focus.
- Original PDF text block editing with word wrapping, searchable text insertion, and copy/cut/paste/delete commands under Home → Objects.
- Live free-text annotation editing with font size, color, opacity, and border controls; highlight/underline; rectangle, line, arrow, and grouped callout annotations.
- Annotation selection, dragging, four-corner resizing, Delete/Backspace removal, and live vector drag previews.
- Page insertion, duplication with annotations, deletion, and rotation. Save / Save As continues writing to the selected export URL.
- Panel icon strips, one drawer per sidebar, direct left/right docking buttons, detachable NSPanel windows, and persistent docking/width state (200–600 pt).
- Crop-box rulers based on PDFView coordinate conversion, with points/mm/inches, rotated-page support, clip-view scroll notifications, scale/page notifications, and live cursor hairlines.
- Russian and English UI language selection under Help → UI Settings.
- BotPlus app mark available as SVG, a SwiftUI preview, and a native icon asset catalog.

Commands without implemented PDF behavior show a localized development notice. The engineering measurement tools, advanced bookmark editing, interactive forms, and cryptographic signing are planned in [ROADMAP.md](ROADMAP.md).

## Technology

- macOS 14 or later; Swift 6; Xcode 16 or later recommended.
- Universal arm64/x86_64 release. UI uses Apple SDK frameworks including SwiftUI, AppKit, PDFKit, CoreText and UniformTypeIdentifiers; PDFium is the embedded source-editing dependency.
- PDFium 157.0.8086.0 is embedded for original PDF text editing; no separate installation is required. The pinned universal arm64/x86_64 library, headers, and notices are in `Vendor/PDFium`.
- App Sandbox is enabled with user-selected PDF read/write access. Signing and notarization identities are configured in Xcode for your distribution account.

## Build with Xcode

1. Open `BotPlusPDFEditor.xcodeproj`.
2. Select the `BotPlusPDFEditor` scheme and a My Mac destination.
3. Choose **Product → Run** (⌘R).

Or build from Terminal:

```sh
xcodebuild -project BotPlusPDFEditor.xcodeproj \
  -scheme BotPlusPDFEditor \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build/DerivedData build
```

The UI and PDFKit coordinator are in `ContentView.swift`; source-text editing is in `PDFiumSourceEditor.swift`, the in-page editor and properties panel in `PDFTextEditingUI.swift`, with a small C save bridge in `Native/PDFiumBridge`. The Xcode project includes the icon asset catalog and sandbox entitlements.

## Opening PDFs from Finder

The AppKit application delegate handles double-click, Open With, and Dock file
drops. Early launch events are queued until the workspace is ready. Reopening a
PDF selects its existing tab; closing the workspace does not discard subsequent
file-open events. SwiftUI remains hosted in NSHostingView, without a SwiftUI App
entry point or app-defined AppIntents.

## App icon

`docs/branding/AppIcon.png` is the transparent 1024 × 1024 app logo based on the supplied burgundy PDF artwork. `AppIconPreviewView` uses the same bundled `BrandIcon` image in the title bar and About dialog. To regenerate the standard macOS PNG icon set with Apple’s AppKit renderer:

```sh
swift Tools/export_app_icon.swift
```

This writes PNGs and `Contents.json` into `Assets.xcassets/AppIcon.appiconset` and `BrandIcon.imageset`, already connected to the Xcode target. See [branding sources and export notes](docs/branding/README.md). The previous vector logo is archived as `docs/branding/AppIcon-legacy.svg`.

## Runtime notes

The app defines no AppIntents types or shortcut declarations. Xcode may still invoke its metadata scanner for an application target; the scanner reports that extraction was skipped because AppIntents.framework is not linked. No private Live Text setter is used. PDFKit may still invoke system OCR when selecting or searching text. Viewport-to-SwiftUI state synchronization is deferred until after AppKit updates complete to avoid publishing ObservableObject changes during representable updates. Errors from macOS services such as `linkd.autoShortcut`, and PDFKit OCR model availability diagnostics, depend on the host runtime and cannot be suppressed by app code when those system services are unavailable.

## Workspace and editing

Home → Objects → Edit PDF Text groups fragments into text blocks. All text blocks receive outlines. Click to edit directly on the page; double-click selects a word. The Properties panel formats the whole block or selected characters. Drag the cross to move, corners to scale, the circular handle to rotate, and side handles to stretch the field. Apply with the panel button or Cmd+Return; Escape cancels the current edit. Width changes word wrapping without scaling the font. Block identity, width and explicit line breaks are stored in PDF marked content for subsequent edits, with a hidden, non-printing metadata backup for PDFKit versions that discard private content tags. Unchanged character styles are retained; unavailable original fonts use a suitable installed system font. CAD duplicate drawing passes are de-duplicated for editing. Multi-stream pages are coalesced before rewriting to preserve cross-stream text state. Incomplete glyph writes are rejected without replacing the displayed document. Blocks are inferred geometrically; complex table layouts may need separate edits. Adjacent paragraphs are not reflowed. Scanned images without a text layer require OCR.

Enable **View → Rulers** and choose pt/mm/in from the ruler corner or status bar. Two-finger scrolling pans the document with every tool. Pinch on the trackpad to zoom around the cursor; Command/Control-scroll also zooms. Coordinates are relative to the crop box: X increases to the right and Y increases upward in page space. Page rotation changes which PDF axis is shown by each ruler; ticks remain aligned with the displayed PDF.

Use the side-strip icons to open or collapse a drawer. The side strip selects the active panel; no duplicate bottom tabs are shown. The header arrows move a panel directly left or right. Detach opens an NSPanel; its native close button re-docks it. The panel header X hides the panel. Resize with the divider; widths are also constrained by the space available for the document viewport.

Use **Comment → Typewriter** and click a page to type in the live editor. Click Done or outside the popover to commit; Cancel restores existing text or removes a new annotation. Select PDF text and choose Highlight or Underline to create markup. Drag with Rectangle, Line, Arrow, or Callout to place vectors. Adjust defaults in the Properties inspector, or select an annotation and choose Apply to selected.

Use **Home → Select Comments** to select an annotation. Drag its body to move it, drag one of its four handles to resize it, or press Delete/Backspace to remove it. Double-click a free-text annotation to reopen its editor. Callouts use a standard line and free-text annotation linked by persisted BotPlus metadata; moving the text updates the leader, and deleting either component removes the group.

**Organize → Pages** inserts a blank page before the current page, duplicates the current page after it, or deletes it. Deletion keeps at least one page in the document.

BotPlus preserves appearance settings and callout associations in a hidden, non-printing metadata annotation on each annotated page. Visible annotations are standard PDF types, and existing document metadata remains unchanged. PDFKit appearance streams retain transparency for other PDF readers.

## Release build, DMG, and Git deployment

```sh
./build_and_deploy.sh --package-only
```

This builds Release for arm64, signs a staging copy, creates a writable HFS+ image, mounts it, adds the app and an Applications shortcut, detaches it, converts it to compressed UDZO, and verifies the result. Output files are `dist/<version>/BotPlus-PDF-Editor.dmg` and its SHA-256 checksum. Temporary mounts are cleaned up on failure or interruption.

```sh
./build_and_deploy.sh
```

GitHub Actions also runs the native checks and this packaging pipeline after a push to main. The resulting DMG and checksum are available as the workflow artifact.

The default command also stages source changes, commits with `feat: add dynamic rulers, dockable panels, and editing tools`, and pushes `main` to `https://github.com/Davud77/BotPlus-PDF-Editor.git`. Git credentials and the remote repository must already be available. Release binaries are ignored by Git.

An ad-hoc signature is the default for local use. Set `BOTPLUS_SIGNING_IDENTITY` to an installed Developer ID Application certificate name for distribution signing. Set `BOTPLUS_NOTARY_PROFILE` to an existing notarytool Keychain profile to submit the DMG and staple its notarization ticket. These credentials are read from the environment, never stored in the repository. Set `BOTPLUS_DERIVED_DATA` to choose another Xcode build directory.

## Native verification

```sh
./Tools/verify_native.sh
```

The checks exercise coordinate conversions at 0/90/180/270°, pan/zoom geometry, anchored gesture magnification, live text, PDF annotation and opacity round-trips, callout grouping, drag/resize/delete, page edits, and panel state. The test runner creates a hidden window and temporary PDFs; it does not modify project PDFs.

## Help and community

Help → Support opens the GitHub repository. Help → Telegram opens [t.me/botplus_pdf](https://t.me/botplus_pdf). The About dialog shows the app name, version, and © 2026 BotPlus.

## Repository setup

Review the files, then initialize and commit the local repository with:

```sh
./deploy_to_github.sh
```

To push after configuring Git credentials, run:

```sh
./deploy_to_github.sh --push
```

The script sets `origin` to `https://github.com/Davud77/BotPlus-PDF-Editor.git` and pushes the `main` branch only when `--push` is provided. Remote creation requires the explicit `--create-remote` option and an authenticated `gh` CLI; GitHub prompts for repository visibility.

## License

First-party source is licensed under **GNU AGPL v3.0 (AGPL-3.0-only)**; see [LICENSE](LICENSE). Help → License shows the bundled terms. PDFium components retain their individual licenses.

PDFium component notices are included in the app and listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

### Workspace editing details

The inspector shows document properties until text, an image, a vector object or an annotation is selected. Empty clicks clear selection. Thumbnail context menus provide page copy/paste, duplicate/delete, blank insertion and rotation; navigation centers the page. The in-place editor has no field background and all PDF content and editing handles are clipped to the document viewport. The font list contains system families/faces and PDF font names. Embedded subsets without a usable Unicode program require their full installed font or another font; unsupported glyphs are rejected without replacing the original text.

### Universal release and ribbon tools

The Release application and PDFium dylib contain both arm64 and x86_64 slices. CI runs native persistence checks on Apple Silicon and Intel. Implemented tools include colored/transparent highlight, underline and strikeout; editable text stamps, notes and URL/page links; rectangle, ellipse, cloud, pencil and partial Ink erasing; PDF image content insertion; basic AcroForm fields and JSON data; bookmark tree operations, batch changes, TOC and HTML/text export; page import/extract/split/swap/crop; editable watermark/header/Bates annotations; PNG export, file merging, read-aloud and word count. Thumbnail size controls switch between a grid and one page per panel width. Dock widths stay constant between panels. Undo/Redo uses bounded document history and preserves bookmark targets. The working tree includes named-destination editing, calibrated measurements, explicit Vision OCR and basic text-based DOCX/XLSX/PPTX export. Full structural Office conversion, cryptographic signatures and unconnected external integrations remain unavailable. The current functional remainder is listed in [ROADMAP.md](ROADMAP.md).

Version 1.1 supports thumbnail pinch gestures and Ctrl/Command+wheel zoom. A bounded raster cache and guarded PDFView updates reduce repeated rendering during panel gestures.

## Performance checks (1.2)

Run `BOTPLUS_BENCH_PDF="/absolute/path/document.pdf" BOTPLUS_BENCH_PAGES="1,3" BOTPLUS_BENCH_REPORT="$PWD/performance.json" ./Tools/verify_native.sh`. Add `BOTPLUS_CHECK_OPTIMIZATION=-O` for optimized diagnostics. The report contains timings and counts, with no extracted text or source filename; the input PDF stays read-only and temporary copies are removed.

Opening reads file bytes asynchronously in the application. Unchanged source bytes and Undo snapshots share a bounded cache; native form changes invalidate it. Cached line geometry reduces block clustering work and the editor takes exclusive ownership of the parsed page. Loaded PDFs retain original streams while page identities/order, outlines and attributes stay unchanged. Reassembled documents use a separate page graph; this conservative path can still take seconds. See [PERFORMANCE.md](PERFORMANCE.md).

## New in 1.4

Live margin preview; headers/footers, watermark and Bates templates with ranges, styling and persistent replacement/removal; color/image backgrounds behind original PDF objects; PNG/JPEG/TIFF export with DPI, transparency, rotation, progress and cancellation. Export uses an independent snapshot and a new subfolder. Raster output is limited to 40 MP per page. Untagged decoration created by older versions is kept.

### Zoom fixes in 1.4.1

Queued PDF gestures are bound to their document. Unchanged selection state no longer republishes every viewport update; content outlines are reused across zoom/pan. Cold thumbnail gestures start with a lightweight raster and upgrade after settling. The actual thumbnail cache now renders annotations on new blank pages. Native handler tests cover focus-free zoom, burst/reverse deltas, document switching and caches; physical trackpad pinch is not synthesized by the test API.

### Update 1.5

Thumbnails default to panel width, with buttons and pinch/Ctrl/Command + wheel controls; no size slider. One hover router selects the PDF viewport or thumbnails independently of keyboard focus. Screen-coordinate splitters coalesce updates at 60 Hz and defer preferences writes; thumbnail rasters are reused during resizing.

The current implementation uses NSCollectionView for native selection, rubber-band tracking, autoscrolling and item reuse. Arrow/Home/End/Page Up/Page Down keys navigate; Shift extends/contracts a range, Cmd+A selects all and Escape clears selection. Cmd+C/X/V and Delete target pages while the grid has focus. The `#` menu switches between PDF page labels and physical numbering. Compilation is complete; interactive acceptance remains pending.

Protect → Signatures/Initials supports typing, drawing and PNG/JPEG/TIFF import, opacity, borders and up to 20 local presets. Home → Stamp shares the editor with {date}/{file}/{page} tokens. Marks can be exported as transparent PNG, are inserted at the current page center and selected in the content editor for move/scale/rotation/deletion. These are graphic marks, not certificate/PKCS#7 signatures.

The full preset library can be imported/exported as JSON. Import merges IDs and validates size/geometry, with no executable templates. Limits: 20 presets and a 16 MB library.

### Update 1.6

Organize → Extract / Split / Page Order supports ranges, page-count or top-level bookmark groups, reverse order ranges, direct internal links and Undo. Independent export workers support cancellation/progress and protect the original file. Output does not inherit the source encryption.

View → Snapshot copies a region as PNG at 72–600 DPI (Properties). Previous/Next View and top arrows restore each document’s page, zoom, center and display mode. Session history holds up to 150 views and clears after structural changes or Undo. Search runs on Enter; high-DPI raster enlargement is corrected.

Snapshot is also available on Home. Smaller page-break margins keep adjacent sheets compact; short-page centering uses outer document insets instead of padding each page.
