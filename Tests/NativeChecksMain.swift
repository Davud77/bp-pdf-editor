// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus

import ObjectiveC



extension PDFViewerView {
    fileprivate func checkMagnify(_ delta: CGFloat, anchor: CGPoint) { applyMagnification(delta, at: anchor) }
    fileprivate func checkQueuedMagnify(_ delta: CGFloat, anchor: CGPoint) { queueMagnification(delta,at: anchor) }
    fileprivate func checkFlushMagnify() { flushMagnification() }
    fileprivate func checkDraw(page: PDFPage, start: CGPoint, end: CGPoint, tool: PDFTool) {
        commitDrawing(Preview(page: page, start: start, end: end, tool: tool))
    }
}
extension PDFViewer.Coordinator {
    fileprivate func checkCommand(_ command: ViewerCommand, view: PDFViewerView) { perform(command, on: view) }
    fileprivate func checkContentOutlines(view: PDFViewerView) { refreshContentOutlines(view) }
    fileprivate func checkSync(view: PDFViewerView) { observeScroll(in: view); syncPage(); syncMetrics(for: view) }
}

@main
struct NativeChecks {
    @MainActor static func main() throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError("CHECK FAILED: \(message)") }
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try checkWorkspaceCompletion(root: root)
        try checkBookmarkActions(root: root)
        try checkTOCAndMerge(root: root)
        try checkContinuedDevelopment(root: root)
        try checkNamedDestinationLifecycle(root: root)
        try checkLayerConfiguration(root: root)
        try checkTabTraversal(root: root)
        try checkBookmarkDestinationExchange(root: root)
        try checkPerspectiveCorrection(root: root)
        try checkScanLighting(root: root)
        try checkNestedCurveSnapping(root: root)
        try checkInkCurveEditing(root: root)
        try checkStructureActualText(root: root)
        try checkAnnotationBatchSelection(root: root)
        try checkStructureReadingOrder(root: root)
        try checkHeaderTemplates(root: root)
        try checkXFDFInkGeometry(root: root)
        try checkMembershipEditing(root: root)
        try checkFDFComments(root: root)
        try checkMeasurementTransforms(root: root)
        try checkMeasurementBatchScaling(root: root)
        try checkLayerStateSettings(root: root)
        try checkEmptyTagDeletion(root: root)
        try checkAffineMeasurements(root: root)
        try checkExtendedLayerUsage(root: root)
        try checkLayerUsageMetadata(root: root)
        try checkMeasurementPageTransfer(root: root)
        try checkMeasurementDocumentCopy(root: root)
        try checkDirectionalMeasurements(root: root)
        try checkCustomDirectionMeasurements(root: root)
        try checkMeasurementLabelLeaders(root: root)
        try checkMeasurementElbowLeaders(root: root)
        try checkMeasurementPolylineLeaders(root: root)
        try checkMeasurementLeaderAnchors(root: root)
        try checkContourMeasurementLeaders(root: root)
        try checkBookmarkActionChains(root: root)
        try checkCommentModificationDates(root: root)
        try checkIndependentFormTransforms(root: root)
        try checkLayerLockAuthoring(root: root)
        try checkWrittenInkOriginRepair()
        try checkLayerRadioAuthoring(root: root)
        try checkLayerOrderEditing(root: root)
        try checkOrderSections(root: root)
        try checkOrderReparenting(root: root)
        try checkMembershipCreation(root: root)
        try checkMembershipPageBinding(root: root)
        try checkDirectMemberships(root: root)
        try checkXObjectConditions(root: root)
        try checkNestedXObjectConditions(root: root)
        if ProcessInfo.processInfo.environment["BOTPLUS_CHECK_WORKSPACE_ONLY"] == "1" { return }
        try checkUpdatePolicies(root: root)
        try checkRelease12(root: root)
        try checkContentEditor(root: root)
        if let path = ProcessInfo.processInfo.environment["BOTPLUS_BENCH_PDF"] { try benchmarkRelease12(root: root,path: path) }

        let customSymbols: Set<String> = ["botplus.floppy", "botplus.bookmark.plus"]
        var checkedSymbols = Set<String>()
        for tab in RibbonTab.allCases {
            for command in RibbonView.groups(for: tab).flatMap(\.commands) {
                if customSymbols.contains(command.symbol) { continue }
                let resolved = SystemSymbolCatalog.name(command.symbol)
                expect(NSImage(systemSymbolName: resolved, accessibilityDescription: nil) != nil,
                       "ribbon icon is available on this OS: \(tab.title.en)/\(command.id)")
                checkedSymbols.insert(command.symbol)
            }
        }
        expect(RibbonView.groups(for: .bookmarks).flatMap(\.commands).first { $0.id == "bookmarkAdd" }?.symbol == "botplus.bookmark.plus", "bookmark add uses our composed icon")
        expect(NSImage(systemSymbolName: "bookmark", accessibilityDescription: nil) != nil, "bookmark component exists")
        expect(NSImage(systemSymbolName: "plus.circle.fill", accessibilityDescription: nil) != nil, "plus component exists")
        expect(SystemSymbolCatalog.name("botplus.nonexistent.regression") == "questionmark.square", "missing symbol has a cached compatible fallback")
        expect(SystemSymbolCatalog.name("botplus.nonexistent.regression") == "questionmark.square", "fallback remains stable across view updates")
        print("PASS: all \(RibbonTab.allCases.count) ribbon tabs, \(checkedSymbols.count) icons and composed bookmark icon")
        let document = PDFDocument()
        let page = PDFPage()
        page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        page.setBounds(CGRect(x: 12, y: 20, width: 588, height: 752), for: .cropBox)
        document.insert(page, at: 0)
        document.insert(PDFPage(), at: 1)
        document.page(at: 1)?.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
        let initial = root.appendingPathComponent("native-checks.pdf")
        expect(document.write(to: initial), "initial PDF writes")
        let manager = DocumentManager(recent: RecentPDFStore(defaults: UserDefaults(suiteName: "BotPlusNativeChecks")!))
        manager.open(initial)
        let item = manager.selected!
        let pdf = PDFViewerView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 500, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = pdf
        let coordinator = PDFViewer.Coordinator(manager: manager)
        coordinator.attach(pdf); coordinator.update(pdf)
        expect(pdf.hitTest(CGPoint(x: -1,y: 10)) == nil,"offscreen text editors never hit-test outside the viewport")
        pdf.displayBox = .cropBox; pdf.displayMode = .singlePageContinuous; pdf.scaleFactor = 1.5
        pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
        let activePage = item.document.page(at: 0)!
        pdf.go(to: activePage)

        for rotation in [0, 90, 180, 270] {
            activePage.rotation = rotation
            pdf.installDocument(nil); pdf.installDocument(item.document); pdf.scaleFactor = 1.5
            pdf.go(to: activePage); pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
            let sample = CGPoint(x: 110, y: 240)
            let mapped = pdf.convert(sample, from: activePage)
            let roundTrip = pdf.convert(mapped, to: activePage)
            expect(hypot(roundTrip.x - sample.x, roundTrip.y - sample.y) < 0.001, "rotated PDF conversion round-trip \(rotation)")
            coordinator.checkSync(view: pdf)
            expect(manager.rulerMetrics.valid, "ruler metrics valid for \(rotation)")
            expect(abs(manager.rulerMetrics.horizontalPointsPerPixel) > 0.001, "horizontal ruler has a real PDF-space derivative")
            expect(abs(manager.rulerMetrics.verticalPointsPerPixel) > 0.001, "vertical ruler has a real PDF-space derivative")
        }
        activePage.rotation = 0; pdf.installDocument(nil); pdf.installDocument(item.document); pdf.scaleFactor = 1.5
        pdf.go(to: activePage); pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded()
        coordinator.checkSync(view: pdf)
        let beforePan = manager.rulerMetrics
        let clip = pdf.internalScrollView!.contentView
        clip.scroll(to: clip.constrainBoundsRect(CGRect(origin: CGPoint(x: clip.bounds.minX + 35, y: clip.bounds.minY + 45), size: clip.bounds.size)).origin)
        pdf.internalScrollView!.reflectScrolledClipView(clip)
        coordinator.checkSync(view: pdf)
        expect(manager.rulerMetrics != beforePan, "clip-view pan updates ruler offset")
        let beforeZoom = manager.rulerMetrics
        pdf.scaleFactor = 2
        coordinator.checkSync(view: pdf)
        expect(manager.rulerMetrics != beforeZoom, "PDF scale updates ruler derivative")
        expect(abs(RulerUnit.millimeters.pointsPerUnit * 25.4 - 72) < 0.00001, "mm conversion")
        expect(RulerUnit.inches.pointsPerUnit == 72, "inch conversion")
        for _ in 0..<1104 {
            expect(RulerLabelFormatter.label(value: 0,minorInterval: 1,digits: 0,language: .en) == "0","ruler zero label")
            expect(RulerLabelFormatter.label(value: 1.25,minorInterval: 0.01,digits: 2,language: .en) == "1.25","ruler fractional label")
        }
        expect(RulerLabelFormatter.label(value: -0.00001,minorInterval: 0.1,digits: 2,language: .en) == "0.00","ruler suppresses negative zero")
        expect(RulerLabelFormatter.label(value: 1.25,minorInterval: 0.01,digits: 2,language: .ru) == "1,25","ruler follows selected Russian locale")
        expect(RulerLabelFormatter.label(value: -1000,minorInterval: 1,digits: 0,language: .en) == "-1000","ruler negative coordinate has no group separator")
        expect(RulerLabelFormatter.label(value: .infinity,minorInterval: 1,digits: 0,language: .en).isEmpty,"invalid ruler geometry is not formatted")
        let blankText = try PDFSourceTextReader.pages(data: Data(contentsOf: initial))
        expect(blankText == ["",""],"embedded-text reader keeps blank pages empty without OCR")
        var canRenderOffscreen = ProcessInfo.processInfo.environment["BOTPLUS_SKIP_OFFSCREEN"] != "1"
        #if arch(x86_64)
        // macos-15-intel is a headless VM: SwiftUI's offscreen renderer can
        // abort inside MTLLoader after returning its image. Real Intel Macs
        // still run this check; all numeric/PDF checks always run in CI.
        canRenderOffscreen = canRenderOffscreen && ProcessInfo.processInfo.environment["CI"] != "true"
        #endif
        if canRenderOffscreen {
            let rulerImage = ImageRenderer(content: RulerBar(axis: .horizontal,manager: manager).frame(width: 500,height: 24))
            expect(rulerImage.cgImage != nil,"ruler Canvas renders numeric labels")
            print("PASS: real ruler Canvas rendering")
        } else { print("SKIP: offscreen SwiftUI Canvas on the Intel CI VM without a supported Metal device") }
        print("PASS: 1104 typed ruler label passes and RU/EN numbers")
        let scrollBefore = clip.bounds.origin
        let wheelCG = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0)!
        wheelCG.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let wheel = NSEvent(cgEvent: wheelCG)!
        pdf.scrollWheel(with: wheel)
        expect(clip.bounds.origin != scrollBefore, "two-finger scrolling changes the internal clip origin")
        let downwardDelta = clip.bounds.minY - scrollBefore.y
        expect(downwardDelta * (clip.isFlipped ? 1 : -1) > 0, "downward scrolling follows native document direction")
        coordinator.checkSync(view: pdf)
        let zoomBeforeGesture = pdf.scaleFactor
        let anchor = CGPoint(x: pdf.bounds.midX, y: pdf.bounds.midY)
        let anchorPage = pdf.page(for: anchor, nearest: true)!
        let anchorPDFPoint = pdf.convert(anchor, to: anchorPage)
        pdf.checkMagnify(0.15, anchor: anchor)
        expect(pdf.scaleFactor > zoomBeforeGesture, "trackpad gesture increases zoom")
        let afterAnchor = pdf.convert(anchorPDFPoint, from: anchorPage)
        let anchorError = hypot(afterAnchor.x - anchor.x, afterAnchor.y - anchor.y)
        let oneClipUnit = pdf.convert(CGPoint(x: 1, y: 1), from: clip) - pdf.convert(.zero, from: clip)
        let toleranceX = max(1, abs(oneClipUnit.x) * 0.5 + 0.05)
        let toleranceY = max(1, abs(oneClipUnit.y) * 0.5 + 0.05)
        let aligned = abs(afterAnchor.x - anchor.x) < toleranceX && abs(afterAnchor.y - anchor.y) < toleranceY
        if !aligned { FileHandle.standardError.write(Data("Anchor error \(anchorError), native tolerances \(toleranceX), \(toleranceY)\n".utf8)) }
        expect(aligned, "gesture zoom retains its anchor within native clip alignment")
        pdf.checkMagnify(-0.15, anchor: anchor)
        expect(abs(pdf.scaleFactor - zoomBeforeGesture) < 0.001, "reverse trackpad gesture restores zoom")
        let responderBefore = window.firstResponder
        let queuedZoom = pdf.scaleFactor
        pdf.checkQueuedMagnify(0.04,anchor: anchor); pdf.checkQueuedMagnify(0.06,anchor: anchor)
        pdf.checkFlushMagnify()
        expect(abs(pdf.scaleFactor - queuedZoom*exp(0.10)) < 0.001,"queued zoom preserves accumulated gesture deltas")
        expect(window.firstResponder === responderBefore,"gesture zoom does not require a click or change focus")
        pdf.checkMagnify(-0.10,anchor: anchor)

        // These run the same native drawing entry point used when a drag ends.
        pdf.strokeColor = NSColor.red.withAlphaComponent(0.45); pdf.strokeWidth = 3
        pdf.checkDraw(page: activePage, start: CGPoint(x: 60, y: 80), end: CGPoint(x: 140, y: 130), tool: .rectangle)
        let rectangle = activePage.annotations.last!
        pdf.checkDraw(page: activePage, start: CGPoint(x: 160, y: 90), end: CGPoint(x: 230, y: 150), tool: .arrow)
        let arrow = activePage.annotations.last!
        expect(arrow.endLineStyle == .openArrow, "arrow ornament")
        expect(rectangle.border?.lineWidth == 3, "configured vector stroke")

        pdf.onCreateText = { page, point, leader in
            let text = PDFAnnotation(bounds: CGRect(x: point.x, y: point.y - 60, width: 140, height: 60), forType: .freeText, withProperties: nil)
            text.contents = "Grouped callout"; text.color = .clear; text.font = NSFont.systemFont(ofSize: 16); text.fontColor = .blue
            if let leader, let group = AnnotationMetadata.group(of: leader) { AnnotationMetadata.setOpacity(1, on: text); AnnotationMetadata.setGroup(group, on: text) }
            page.addAnnotation(text); pdf.selectAnnotation(text)
        }
        pdf.checkDraw(page: activePage, start: CGPoint(x: 300, y: 650), end: CGPoint(x: 420, y: 560), tool: .callout)
        let calloutText = pdf.selectedAnnotation!
        let leader = activePage.annotations.first { $0.type == "Line" && AnnotationMetadata.group(of: $0) == AnnotationMetadata.group(of: calloutText) }!
        pdf.selectAnnotation(leader)
        expect(pdf.selectedAnnotation === calloutText, "callout leader selects text component")
        calloutText.bounds = calloutText.bounds.offsetBy(dx: 15, dy: 15)
        pdf.updateCalloutLeader(for: calloutText)
        expect(abs(leader.bounds.minX + leader.endPoint.x - calloutText.bounds.minX) < 0.001, "callout leader follows its text box")

        let freeText = PDFAnnotation(bounds: CGRect(x: 70, y: 300, width: 260, height: 60), forType: .freeText, withProperties: nil)
        freeText.contents = "Before"; freeText.font = NSFont.systemFont(ofSize: 18); freeText.fontColor = .red
        freeText.color = .red; let border = PDFBorder(); border.lineWidth = 2; freeText.border = border
        activePage.addAnnotation(freeText)
        let editor = FreeTextEditorController(annotation: freeText, language: .en)
        _ = editor.view
        editor.textView.string = "BotPlus live typing\nSecond line"
        editor.textDidChange(Notification(name: NSText.didChangeNotification))
        expect(freeText.contents == editor.textView.string, "live typing updates PDF annotation before commit")
        editor.popoverDidClose(Notification(name: NSPopover.didCloseNotification))
        expect(freeText.font?.pointSize == 18, "editor font setting persists")

        // Use real mouse events to select and translate an annotation, then delete it.
        pdf.activeTool = .selectComments
        func mouse(_ type: NSEvent.EventType, point: CGPoint) -> NSEvent {
            let screen = pdf.convert(pdf.convert(point, from: activePage), to: nil)
            return NSEvent.mouseEvent(with: type, location: screen, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let originalBounds = rectangle.bounds
        let center = CGPoint(x: originalBounds.midX, y: originalBounds.midY)
        pdf.mouseDown(with: mouse(.leftMouseDown, point: center))
        pdf.mouseDragged(with: mouse(.leftMouseDragged, point: CGPoint(x: center.x + 20, y: center.y + 15)))
        pdf.mouseUp(with: mouse(.leftMouseUp, point: CGPoint(x: center.x + 20, y: center.y + 15)))
        expect(abs(rectangle.bounds.minX - originalBounds.minX - 20) < 0.01, "annotation moves in page coordinates")
        let corner = CGPoint(x: rectangle.bounds.maxX, y: rectangle.bounds.maxY)
        let originalWidth = rectangle.bounds.width
        pdf.mouseDown(with: mouse(.leftMouseDown, point: corner))
        pdf.mouseDragged(with: mouse(.leftMouseDragged, point: CGPoint(x: corner.x + 25, y: corner.y + 25)))
        pdf.mouseUp(with: mouse(.leftMouseUp, point: CGPoint(x: corner.x + 25, y: corner.y + 25)))
        expect(abs(rectangle.bounds.width - originalWidth - 25) < 0.01, "resize handle changes annotation bounds")
        let deletion = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51)!
        pdf.keyDown(with: deletion)
        expect(!activePage.annotations.contains(rectangle), "Delete removes selected annotation")

        let image = activePage.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: root.appendingPathComponent("annotation-render.png"))
        manager.saveDocument()
        let reopened = PDFDocument(url: initial)!
        let metadataContainers = reopened.page(at: 0)!.annotations.filter { AnnotationMetadata.isContainer($0) }
        expect(!metadataContainers.isEmpty && metadataContainers.allSatisfy { !$0.shouldDisplay && !$0.shouldPrint }, "metadata is invisible and non-printing in saved PDF")
        AnnotationMetadata.restore(reopened)
        let savedText = reopened.page(at: 0)!.annotations.first { $0.contents == freeText.contents }!
        expect(savedText.contents == freeText.contents, "FreeText contents round-trip through real PDF file")
        let savedArrow = reopened.page(at: 0)!.annotations.first { $0.type == "Line" }!
        expect(savedArrow.endLineStyle == .openArrow, "arrow survives PDF reopening")
        expect(savedArrow.border?.lineWidth == 3, "stroke width survives reopening")
        expect(abs(AnnotationMetadata.alpha(of: savedArrow) - 0.45) < 0.001, "opacity survives PDF reopening")
        expect(reopened.page(at: 0)!.annotations.filter { AnnotationMetadata.group(of: $0) != nil }.count == 2, "callout association survives PDF reopening")
        pdf.go(to: activePage)
        coordinator.checkSync(view: pdf)
        expect(pdf.currentPage === activePage, "duplicate targets the active page")
        coordinator.checkCommand(.duplicatePage, view: pdf)
        expect(item.pageCount == 3, "duplicate current page")
        expect(item.document.page(at: 1)!.annotations.filter { !AnnotationMetadata.isContainer($0) }.count == activePage.annotations.filter { !AnnotationMetadata.isContainer($0) }.count, "duplicate preserves annotations")
        coordinator.checkCommand(.insertBlankPage, view: pdf)
        expect(item.pageCount == 4 && pdf.currentPage!.annotations.isEmpty, "insert clean blank page")
        coordinator.checkCommand(.deletePage, view: pdf)
        expect(item.pageCount == 3, "delete active page")
        manager.saveDocument()
        expect(PDFDocument(url: initial)!.pageCount == 3, "page edits survive reopening")

        let panels = PanelWorkspaceModel()
        panels.setDock(.left, for: .bookmarks); panels.select(.bookmarks)
        expect(panels.activePanel(on: .left) == .bookmarks, "tab selects drawer")
        panels.toggleDrawer(.bookmarks)
        expect(panels.activePanel(on: .left) == nil, "icon collapses entire tabbed drawer")
        panels.select(.bookmarks); panels.setPinned(false, for: .bookmarks); panels.collapseAutoHiddenPanels()
        expect(panels.activePanel(on: .left) == nil, "auto-hide collapses unpinned drawer")
        panels.select(.bookmarks); panels.setPinned(true, for: .bookmarks); panels.collapseAutoHiddenPanels()
        expect(panels.activePanel(on: .left) == .bookmarks, "pinned drawer survives viewport click")
        panels.setWidth(900, for: .bookmarks); expect(panels.configuration(for: .bookmarks).width == 600, "panel maximum width")
        panels.setWidth(20, for: .bookmarks); expect(panels.configuration(for: .bookmarks).width == 200, "panel minimum width")
        try runPDFiumChecks(root: root)
        try runTextBlockChecks()
        try runInlineTextChecks()
        try runRibbonFeatureChecks(root: root)
        let originalPages = item.pageCount
        coordinator.checkCommand(.duplicatePageAt(0),view: pdf)
        expect(item.pageCount == originalPages+1,"thumbnail menu duplicates the requested page")
        coordinator.checkCommand(.deletePageAt(1),view: pdf)
        expect(item.pageCount == originalPages,"thumbnail menu deletes the requested page")
        coordinator.checkCommand(.blankPageAt(1),view: pdf)
        expect(item.pageCount == originalPages+1,"thumbnail menu inserts a blank page at the requested index")
        coordinator.checkCommand(.deletePageAt(1),view: pdf)
        pdf.scaleFactor = 0.3
        coordinator.checkCommand(.page(0),view: pdf)
        let centeredRect = pdf.convert(item.document.page(at: 0)!.bounds(for: .cropBox),from: item.document.page(at: 0)!)
        expect(abs(centeredRect.midY-pdf.bounds.midY) < 2,"thumbnail navigation centers a short page vertically")
        expect(pdf.pageBreakMargins.top == 2 && pdf.pageBreakMargins.bottom == 2,"short-page centering does not enlarge per-page margins")
        if item.pageCount > 1 {
            let nextRect = pdf.convert(item.document.page(at: 1)!.bounds(for: .cropBox),from: item.document.page(at: 1)!)
            let gap = abs(centeredRect.midY-nextRect.midY)-(centeredRect.height+nextRect.height)/2
            expect(gap < 20,"adjacent pages remain compact when a short first page is centered")
        }

        // Use an isolated pasteboard, preserving the user's clipboard.
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        pdf.go(to: activePage)
        let pasteTarget = pdf.currentPage!
        let existingCount = pasteTarget.annotations.filter { !AnnotationMetadata.isContainer($0) }.count
        let copiedData = coordinator.checkClipboardData(arrow)
        expect(copiedData != nil, "serializes a copied annotation object")
        if !board.name.rawValue.isEmpty {
            expect(coordinator.checkCopy(arrow,board: board), "copies an annotation object to the system pasteboard")
            coordinator.checkPaste(view: pdf,board: board)
        } else {
            print("SKIP: system pasteboard unavailable in this execution sandbox; object data round-trip still checked")
            expect(coordinator.checkPasteData(copiedData!,view: pdf), "pastes serialized annotation data")
        }
        let afterPasteCount = pasteTarget.annotations.filter { !AnnotationMetadata.isContainer($0) }.count
        expect(afterPasteCount == existingCount + 1, "pastes the copied annotation onto the current page")
        let pasted = pdf.selectedAnnotation!
        expect(pasted !== arrow && pasted.type == "Line", "paste creates an independent object")
        expect(abs(AnnotationMetadata.alpha(of: pasted) - 0.45) < 0.001, "clipboard preserves opacity")
        expect(pdf.deleteSelectedAnnotation(), "Object Delete removes the pasted annotation")
        let light = NSAppearance(named: .aqua)!
        var lightValue: CGFloat = 0
        light.performAsCurrentDrawingAppearance { lightValue = NSColor(Palette.ribbon).usingColorSpace(.deviceRGB)!.redComponent }
        let dark = NSAppearance(named: .darkAqua)!
        var darkValue: CGFloat = 0
        dark.performAsCurrentDrawingAppearance { darkValue = NSColor(Palette.ribbon).usingColorSpace(.deviceRGB)!.redComponent }
        expect(lightValue > 0.8 && darkValue < 0.3, "theme palette resolves both light and dark appearances")
        coordinator.detach(); pdf.stopEventMonitoring(); window.close()
        print("PASS: rulers, two-finger scrolling, anchored gesture zoom, live text, opacity and callout persistence, drag/resize/delete, page edits, panel invariants")
        // Preserve AppKit's synchronous entry point for geometry checks. Run
        // the async formatting suite only after legacy viewport checks finish.
        let status = FormattingCheckStatus()
        Task { @MainActor in
            do { try await checkPDFKitBackgroundGetter(); try checkAppDiagnostics(root: root); try await checkSearchPanel(root: root); try await checkStructuralGraphics(root: root); try await checkFormatting(root: root) }
            catch { status.error = error }
            status.finished = true
        }
        let deadline = Date(timeIntervalSinceNow: 120)
        while !status.finished && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        expect(status.finished, "async formatting checks finish")
        if let error = status.error { throw error }

    }
}

@MainActor
private func checkWorkspaceCompletion(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) {
        if !condition() { fatalError("CHECK FAILED: \(message)") }
    }
    let suite = "BotPlusWorkspaceChecks-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults))
    let other = DocumentManager(recent: RecentPDFStore(defaults: defaults))
    let document = PDFDocument(); document.insert(PDFPage(),at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("group-close.pdf"),document: document)
    let duplicate = PDFDocumentItem(shared: item.store,page: 0,zoom: 2)
    manager.insertDocument(item); manager.insertDocument(duplicate)
    item.store.revision += 1
    expect(manager.documentsRequiringSaveForClosing([item.id],managers: [manager]).isEmpty,"retained view keeps shared edits alive")
    expect(manager.documentsRequiringSaveForClosing([item.id,duplicate.id],managers: [manager]).count == 1,"shared document saved once")
    let external = PDFDocumentItem(shared: item.store,page: 0,zoom: 1)
    other.insertDocument(external)
    expect(manager.documentsRequiringSaveForClosing([item.id,duplicate.id],managers: [manager,other]).isEmpty,"another window keeps shared edits alive")
    var saved: Bool?
    manager.saveDocumentsForClosing([item]) { saved = $0 }
    expect(saved == true && !item.store.hasChanges,"named document saved before group close")
    expect(manager.documents.count == 2,"saving alone does not close any view")
    expect(PDFDocument(url: item.url)?.pageCount == 1,"group save reopens as PDF")
    item.store.revision += 1
    let originalURL = item.url,savedRevision = item.store.savedRevision
    do {
        try manager.saveForClosing(item,to: root.appendingPathComponent("missing-parent/failed.pdf"))
        fatalError("save into missing directory succeeded")
    } catch { }
    expect(item.url == originalURL && item.store.savedRevision == savedRevision && item.store.hasChanges,"failed save preserves URL and dirty state")
    item.isUntitled = true
    try manager.saveForClosing(item,to: root.appendingPathComponent("new-group-close.pdf"))
    expect(!item.isUntitled && !item.store.hasChanges && duplicate.url == item.url,"Save As updates all views of shared document")
    let secondDocument = PDFDocument(); secondDocument.insert(PDFPage(),at: 0)
    let second = PDFDocumentItem(url: root.appendingPathComponent("second-group-close.pdf"),document: secondDocument)
    manager.insertDocument(second); item.store.revision += 1; second.store.revision += 1
    saved = nil
    manager.saveDocumentsForClosing([item,second]) { saved = $0 }
    expect(saved == true && !item.store.hasChanges && !second.store.hasChanges,"group saves distinct documents sequentially")
    expect(PDFDocument(url: second.url)?.pageCount == 1,"second document persists")
    second.store.revision += 1
    expect(manager.documentsRequiringSaveForClosing(manager.documents.map(\.id),managers: [manager]).map(\.id) == [second.id],"changes after saving are detected before close")

    let storage = PDFScanStorage(parent: root),neighbor = root.appendingPathComponent("external-scan.txt")
    try Data("keep".utf8).write(to: neighbor)
    try storage.prepare()
    let temporary = storage.folder.appendingPathComponent("scan.tiff")
    try Data("temporary scan".utf8).write(to: temporary)
    try storage.cleanup(); try storage.cleanup()
    expect(!FileManager.default.fileExists(atPath: storage.folder.path),"scanner cleanup removes private session directory and is repeatable")
    expect(FileManager.default.fileExists(atPath: neighbor.path),"scanner cleanup leaves external files alone")
    try storage.prepare(); try storage.cleanup()
    let model = PDFScannerModel()
    try model.storage.prepare()
    try Data("late scan".utf8).write(to: model.folder.appendingPathComponent("late.tiff"))
    model.receive(neighbor,error: nil)
    expect(model.files.isEmpty && !FileManager.default.fileExists(atPath: model.folder.path),"late callbacks after stop cannot restore scans")
    print("PASS: shared-view group save, Save As, write failure, save/reopen, changed-document recheck and scanner session cleanup")

    manager.select(item.id)
    let rootOutline = PDFOutline(),first = PDFOutline(),child = PDFOutline(),link = PDFOutline()
    first.label = "Раздел Ёж 🦔"; child.label = "Second"; link.label = "Site"
    first.destination = PDFDestination(page: document.page(at: 0)!,at: CGPoint(x: 17,y: 55))
    child.action = PDFActionGoTo(destination: PDFDestination(page: document.page(at: 0)!,at: .zero))
    link.action = PDFActionURL(url: URL(string: "https://example.com")!)
    first.insertChild(child,at: 0); rootOutline.insertChild(first,at: 0); rootOutline.insertChild(link,at: 1)
    document.outlineRoot = rootOutline
    var options = PDFBookmarkTextOptions(); options.first = "["; options.second = "]"
    let plan = PDFBookmarkTextPlan.make(nodes: [first,child,link],document: document,operation: .affix,options: options)!
    expect(plan.count == 3 && plan[0].after == "[Раздел Ёж 🦔]" && first.label == "Раздел Ёж 🦔","Unicode title preview does not mutate document")
    options.range = "1"
    let filtered = PDFBookmarkTextPlan.make(nodes: [first,child,link],document: document,operation: .affix,options: options)!
    expect(filtered.count == 2 && filtered.allSatisfy { $0.page == 1 },"page filter includes GoTo actions and excludes external URLs")
    options.range = "2"
    expect(PDFBookmarkTextPlan.make(nodes: [first],document: document,operation: .affix,options: options) == nil,"out-of-bounds range rejected")
    options.range = "all"; options.first = "Ёж"; options.second = "Лис"
    let replacement = PDFBookmarkTextPlan.make(nodes: [first,child,link],document: document,operation: .replace,options: options)!
    expect(replacement.count == 1 && replacement[0].after == "Раздел Лис 🦔","literal Unicode replacement excludes unchanged rows")
    options.first = ""
    expect(PDFBookmarkTextPlan.make(nodes: [first],document: document,operation: .replace,options: options)!.isEmpty,"empty search produces no changes")
    options.letterCase = 1
    expect(PDFBookmarkTextPlan.make(nodes: [first],document: document,operation: .letterCase,options: options)!.first?.after == "раздел ёж 🦔","case preview supports Cyrillic")
    let coordinator = PDFViewer.Coordinator(manager: manager)
    coordinator.showBookmarkTextEditor(item: item,operation: .affix)
    let request = manager.bookmarkTextRequest!
    options.first = "New "; options.second = ""; options.range = "all"
    let preview = request.load(options)!
    child.label = "Changed elsewhere"
    expect(request.apply([preview[0]]) != nil && first.label == "Раздел Ёж 🦔","stale preview cannot overwrite concurrent document changes")
    let refreshed = request.load(options)!
    let action = link.action
    expect(request.apply([refreshed[0]]) == nil && first.label == "New Раздел Ёж 🦔" && child.label == "Changed elsewhere","apply modifies selected preview row only")
    expect(link.action === action && first.numberOfChildren == 1 && first.destination?.point == CGPoint(x: 17,y: 55),"title edits preserve actions, destinations and hierarchy")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!
    expect(reopened.outlineRoot?.child(at: 0)?.label == "New Раздел Ёж 🦔","batch title edit survives save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.outlineRoot?.child(at: 0)?.label == "Раздел Ёж 🦔","batch title change undoes in one operation")
    manager.undoDocument(redo: true)
    expect(item.document.outlineRoot?.child(at: 0)?.label == "New Раздел Ёж 🦔","batch title change redoes in one operation")
    print("PASS: Unicode bookmark preview, page ranges, selective apply, stale-preview guard, preserved actions, save/reopen and Undo/Redo")
}

@MainActor
private func checkStructureReadingOrder(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let content = (0..<4).map { "/P << /MCID \($0) >> BDC \(20+$0*30) 20 20 20 re f EMC\n" }.joined()
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R /Lang (en) /MarkInfo << /Marked true >> /StructTreeRoot 5 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /StructParents 0 /Resources << >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /StructTreeRoot /K [6 0 R 7 0 R 8 0 R] /ParentTree 11 0 R /ParentTreeNextKey 1 /RoleMap << /Custom /P >> >>",
        "<< /Type /StructElem /S /Sect /T (A) /P 5 0 R /K [9 0 R 10 0 R] >>",
        "<< /Type /StructElem /S /P /T (B) /P 5 0 R /Pg 3 0 R /K 1 /ActualText (B text) >>",
        "<< /Type /StructElem /S /P /T (C) /P 5 0 R /Pg 3 0 R /K 2 >>",
        "<< /Type /StructElem /S /Custom /T (A1) /P 6 0 R /Pg 3 0 R /K 0 >>",
        "<< /Type /StructElem /S /P /T (A2) /P 6 0 R /Pg 3 0 R /K 3 >>",
        "<< /Nums [0 [9 0 R 7 0 R 8 0 R 10 0 R]] >>"
    ]
    func fixture(_ objects: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (i,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
    }
    let data = fixture(objects),report = try PDFDocumentExtras.structure(data,russian: false)
    expect(report.nodes.map(\.title) == ["A","A1","A2","B","C"],"structure inspector preserves nested logical order")
    expect(!report.nodes[0].canMoveUp && report.nodes[0].canMoveDown && report.nodes[3].canMoveUp && report.nodes[3].canMoveDown && !report.nodes[4].canMoveDown,"sibling movement boundaries are reported")
    let reordered = try PDFDocumentExtras.reorderStructure(data,node: report.nodes[3],direction: -1),reorderedReport = try PDFDocumentExtras.structure(reordered,russian: false)
    expect(reorderedReport.nodes.map(\.title) == ["B","A","A1","A2","C"] && reorderedReport.nodes[0].actual == "B text","root siblings move with complete subtrees and properties intact")
    let nested = try PDFDocumentExtras.reorderStructure(data,node: report.nodes[2],direction: -1),nestedReport = try PDFDocumentExtras.structure(nested,russian: false)
    expect(nestedReport.nodes.map(\.title) == ["A","A2","A1","B","C"],"nested siblings reorder within their parent")
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef? { var d: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(parent,key,&d); return d }
    func array(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFArrayRef? { var a: CGPDFArrayRef?; CGPDFDictionaryGetArray(parent,key,&a); return a }
    let cg = CGPDFDocument(CGDataProvider(data: reordered as CFData)!)!,tree = dictionary(cg.catalog!,"StructTreeRoot")!,parentTree = dictionary(tree,"ParentTree")!,nums = array(parentTree,"Nums")!
    var bindings: CGPDFArrayRef?; CGPDFArrayGetArray(nums,1,&bindings)
    var titles: [String] = [],mcids: [Int] = []
    for index in 0..<CGPDFArrayGetCount(bindings!) {
        var node: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(bindings!,index,&node)
        var text: CGPDFStringRef?; CGPDFDictionaryGetString(node!,"T",&text); titles.append(CGPDFStringCopyTextString(text!)! as String)
        var value: CGPDFInteger = -1; CGPDFDictionaryGetInteger(node!,"K",&value); mcids.append(value)
    }
    expect(titles == ["A1","B","C","A2"] && mcids == [0,1,2,3] && dictionary(tree,"RoleMap") != nil,"ParentTree bindings and MCIDs stay unchanged after reorder")
    expect(report.rootCanAcceptChildren && report.nodes[0].canAcceptChildren && !report.nodes[3].canAcceptChildren && report.nodes[3].canReparent,"parent capabilities distinguish tag containers from content leaves")
    let reparented = try PDFDocumentExtras.reparentStructure(data,node: report.nodes[3],parent: report.nodes[0]),reparentedReport = try PDFDocumentExtras.structure(reparented,russian: false)
    let movedB = reparentedReport.nodes.first { $0.title == "B" }!
    expect(movedB.depth == 1 && movedB.parentObjectID == reparentedReport.nodes[0].objectID && movedB.actual == "B text","complete subtree moves to chosen parent without changing properties")
    let reparentCG = CGPDFDocument(CGDataProvider(data: reparented as CFData)!)!,reparentRoot = dictionary(reparentCG.catalog!,"StructTreeRoot")!,reparentNums = array(dictionary(reparentRoot,"ParentTree")!,"Nums")!
    var reparentBindings: CGPDFArrayRef?; CGPDFArrayGetArray(reparentNums,1,&reparentBindings)
    var boundB: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(reparentBindings!,1,&boundB)
    var bMCID: CGPDFInteger = -1; CGPDFDictionaryGetInteger(boundB!,"K",&bMCID)
    let bParent = dictionary(boundB!,"P")!; var bParentTitle: CGPDFStringRef?; CGPDFDictionaryGetString(bParent,"T",&bParentTitle)
    expect(bMCID == 1 && CGPDFStringCopyTextString(bParentTitle!)! as String == "A","ParentTree retains the same content owner after parent-link update")
    var scopeObjects = objects
    scopeObjects[1] = "<< /Type /Pages /Kids [3 0 R 12 0 R] /Count 2 >>"
    let scopedContent = [0,2,3].map { "/P << /MCID \($0) >> BDC \(20+$0*30) 20 20 20 re f EMC\n" }.joined()
    scopeObjects[3] = "<< /Length \(scopedContent.utf8.count) >>\nstream\n"+scopedContent+"endstream"
    scopeObjects[5] = "<< /Type /StructElem /S /Sect /T (A) /P 5 0 R /Pg 3 0 R /K [9 0 R 10 0 R] >>"
    scopeObjects[6] = "<< /Type /StructElem /S /Sect /T (B) /P 5 0 R /Pg 12 0 R /K [] >>"
    scopeObjects[8] = "<< /Type /StructElem /S /Custom /T (A1) /P 6 0 R /K 0 >>"
    scopeObjects[10] = "<< /Nums [0 [9 0 R null 8 0 R 10 0 R]] >>"
    scopeObjects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> >>")
    let scopeData = fixture(scopeObjects),scopeReport = try PDFDocumentExtras.structure(scopeData,russian: false)
    let scopedMove = try PDFDocumentExtras.reparentStructure(scopeData,node: scopeReport.nodes.first { $0.title == "A1" }!,parent: scopeReport.nodes.first { $0.title == "B" }!)
    let scopeCG = CGPDFDocument(CGDataProvider(data: scopedMove as CFData)!)!,scopeTree = dictionary(scopeCG.catalog!,"StructTreeRoot")!,scopeNums = array(dictionary(scopeTree,"ParentTree")!,"Nums")!
    var scopeBindings: CGPDFArrayRef?; CGPDFArrayGetArray(scopeNums,1,&scopeBindings)
    var scopeOwner: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(scopeBindings!,0,&scopeOwner)
    let scopePage = dictionary(scopeOwner!,"Pg"); var structParents: CGPDFInteger = -1
    expect(scopePage != nil && CGPDFDictionaryGetInteger(scopePage!,"StructParents",&structParents) && structParents == 0,"reparent pins previous effective Pg instead of adopting a different page")
    expect(report.nodes[3].canWrap,"grouping parent exposes Div creation")
    let wrapped = try PDFDocumentExtras.wrapStructure(data,node: report.nodes[3],title: "Группа β"),wrappedReport = try PDFDocumentExtras.structure(wrapped,russian: false)
    expect(wrappedReport.nodes.map(\.title) == ["A","A1","A2","Группа β","B","C"] && wrappedReport.nodes[3].role == "Div" && wrappedReport.nodes[4].parentObjectID == wrappedReport.nodes[3].objectID,"new Div wraps an existing subtree in its original position")
    let wrappedCG = CGPDFDocument(CGDataProvider(data: wrapped as CFData)!)!,wrappedTree = dictionary(wrappedCG.catalog!,"StructTreeRoot")!,wrappedNums = array(dictionary(wrappedTree,"ParentTree")!,"Nums")!
    var wrappedBindings: CGPDFArrayRef?; CGPDFArrayGetArray(wrappedNums,1,&wrappedBindings)
    var wrappedOwner: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(wrappedBindings!,1,&wrappedOwner)
    var wrappedMCID: CGPDFInteger = -1; CGPDFDictionaryGetInteger(wrappedOwner!,"K",&wrappedMCID)
    expect(wrappedMCID == 1 && dictionary(wrappedOwner!,"P") != nil,"wrapping leaves original content ownership in ParentTree")
    var listObjects = objects; listObjects[5] = "<< /Type /StructElem /S /L /T (A) /P 5 0 R /K [9 0 R 10 0 R] >>"
    let listData = fixture(listObjects),listReport = try PDFDocumentExtras.structure(listData,russian: false),listChild = listReport.nodes.first { $0.title == "A1" }!
    expect(!listChild.canWrap,"special list parents do not expose generic Div wrapping")
    do { _ = try PDFDocumentExtras.wrapStructure(listData,node: listChild,title: "Bad"); fatalError("Div inserted into special list hierarchy") } catch { }
    func deepFixture(_ lengths: [Int]) -> Data {
        var bodies = ["<< /Type /Catalog /Pages 2 0 R /Lang (en) /MarkInfo << /Marked true >> /StructTreeRoot 5 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << >> /Contents 4 0 R >>","<< /Length 0 >>\nstream\nendstream",""]
        var next = 6,roots: [Int] = []
        for (branch,count) in lengths.enumerated() {
            roots.append(next)
            for depth in 0..<count {
                let id = next,parent = depth == 0 ? 5 : id-1,k = depth+1 < count ? "[\(id+1) 0 R]" : "[]"
                bodies.append("<< /Type /StructElem /S /Sect /T (Branch\(branch)-\(depth)) /P \(parent) 0 R /K \(k) >>"); next += 1
            }
        }
        bodies[4] = "<< /Type /StructTreeRoot /K ["+roots.map { "\($0) 0 R" }.joined(separator: " ")+"] >>"; return fixture(bodies)
    }
    let deep = deepFixture([128]),deepReport = try PDFDocumentExtras.structure(deep,russian: false)
    do { _ = try PDFDocumentExtras.wrapStructure(deep,node: deepReport.nodes[0],title: "Too deep"); fatalError("wrapping exceeded structural depth limit") } catch { }
    let branches = deepFixture([71,71]),branchReport = try PDFDocumentExtras.structure(branches,russian: false)
    do { _ = try PDFDocumentExtras.reparentStructure(branches,node: branchReport.nodes[0],parent: branchReport.nodes.first { $0.title == "Branch1-70" }!); fatalError("reparenting exceeded structural depth limit") } catch { }
    let toRoot = try PDFDocumentExtras.reparentStructure(data,node: report.nodes[2],parent: nil),toRootReport = try PDFDocumentExtras.structure(toRoot,russian: false)
    expect(toRootReport.nodes.map(\.title) == ["A","A1","B","C","A2"] && toRootReport.nodes.last?.depth == 0,"nested tag moves to end of structure root")
    let lastChild = toRootReport.nodes.first { $0.title == "A1" }!
    let emptied = try PDFDocumentExtras.reparentStructure(toRoot,node: lastChild,parent: nil),emptyReport = try PDFDocumentExtras.structure(emptied,russian: false)
    expect(emptyReport.nodes[0].title == "A" && emptyReport.nodes[0].canAcceptChildren,"moving last child keeps a valid empty parent container")
    do { _ = try PDFDocumentExtras.reparentStructure(data,node: report.nodes[0],parent: report.nodes[0]); fatalError("self-parent cycle accepted") } catch { }
    do { _ = try PDFDocumentExtras.reparentStructure(data,node: report.nodes[2],parent: report.nodes[3]); fatalError("tag appended to marked-content leaf") } catch { }
    var cycleObjects = objects
    cycleObjects[8] = "<< /Type /StructElem /S /Sect /T (A1) /P 6 0 R /K [12 0 R] >>"
    cycleObjects[10] = "<< /Nums [0 [12 0 R 7 0 R 8 0 R 10 0 R]] >>"
    cycleObjects.append("<< /Type /StructElem /S /P /T (A11) /P 9 0 R /Pg 3 0 R /K 0 >>")
    let cycleData = fixture(cycleObjects),cycleReport = try PDFDocumentExtras.structure(cycleData,russian: false)
    do { _ = try PDFDocumentExtras.reparentStructure(cycleData,node: cycleReport.nodes[0],parent: cycleReport.nodes[1]); fatalError("ancestor moved into descendant") } catch { }
    do { _ = try PDFDocumentExtras.reorderStructure(data,node: report.nodes[0],direction: -1); fatalError("tag moved before first sibling") } catch { }
    do { _ = try PDFDocumentExtras.reorderStructure(data,node: report.nodes[0],direction: 2); fatalError("invalid tag movement accepted") } catch { }
    objects[5] = "<< /Type /StructElem /S /Sect /T (A) /P 5 0 R /Pg 3 0 R /K [9 0 R 0 10 0 R] >>"
    let mixedData = fixture(objects),mixedReport = try PDFDocumentExtras.structure(mixedData,russian: false),mixedNode = mixedReport.nodes.first { $0.title == "A2" }!
    expect(!mixedNode.canMoveUp && !mixedNode.canMoveDown && !mixedNode.canReparent,"mixed tag/MCID lists are read-only for order/parent edits")
    do { _ = try PDFDocumentExtras.reorderStructure(mixedData,node: mixedNode,direction: -1); fatalError("mixed list reordered") } catch { }
    let suite = "BotPlusReadingOrder-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("reading-order.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showStructure(item: item,view: view)
    let request = manager.structureRequest!,selected = request.report.nodes.first { $0.title == "B" }!
    expect(request.reorder?(selected,-1) == nil,"structure order command installs catalog transaction")
    expect(request.reorder?(selected,-1) != nil,"old reading-order editor rejects replaced document")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(saved.nodes.map(\.title) == ["B","A","A1","A2","C"],"reading order survives file save/reopen")
    manager.undoDocument(redo: false)
    let undo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(undo.nodes.map(\.title) == ["A","A1","A2","B","C"],"Undo restores logical order")
    manager.undoDocument(redo: true)
    let redo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(redo.nodes.map(\.title) == ["B","A","A1","A2","C"],"Redo restores logical order change")
    view.installDocument(item.document); coordinator.showStructure(item: item,view: view)
    let parentEditor = manager.structureRequest!,sourceB = parentEditor.report.nodes.first { $0.title == "B" }!,targetA = parentEditor.report.nodes.first { $0.title == "A" }!
    expect(parentEditor.reparent?(sourceB,targetA) == nil,"reparent editor installs atomic tree transaction")
    expect(parentEditor.reparent?(sourceB,targetA) != nil,"stale parent editor rejects replaced document")
    try manager.saveForClosing(item,to: item.url)
    let savedParent = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(savedParent.nodes.first { $0.title == "B" }?.depth == 1,"new parent survives file save/reopen")
    manager.undoDocument(redo: false)
    let parentUndo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(parentUndo.nodes.first { $0.title == "B" }?.depth == 0,"Undo restores original parent")
    manager.undoDocument(redo: true)
    let parentRedo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(parentRedo.nodes.first { $0.title == "B" }?.depth == 1,"Redo restores new parent")
    view.installDocument(item.document); coordinator.showStructure(item: item,view: view)
    let wrapperEditor = manager.structureRequest!,toWrap = wrapperEditor.report.nodes.first { $0.title == "B" }!
    expect(wrapperEditor.wrap?(toWrap,"Wrapped") == nil,"Div creation installs atomic structure transaction")
    expect(wrapperEditor.wrap?(toWrap,"Duplicate") != nil,"stale Div editor cannot create another container")
    try manager.saveForClosing(item,to: item.url)
    let savedWrap = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(savedWrap.nodes.contains { $0.role == "Div" && $0.title == "Wrapped" } && savedWrap.nodes.first { $0.title == "B" }?.depth == 2,"created Div survives save/reopen")
    manager.undoDocument(redo: false)
    let wrapUndo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(!wrapUndo.nodes.contains { $0.title == "Wrapped" } && wrapUndo.nodes.first { $0.title == "B" }?.depth == 1,"Undo removes created wrapper without removing content tag")
    manager.undoDocument(redo: true)
    let wrapRedo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(wrapRedo.nodes.contains { $0.title == "Wrapped" },"Redo restores created wrapper")
    print("PASS: tag reading order/reparenting/Div creation, page scope, cycle/depth/sibling limits, mixed-list refusal, preserved MCID/ParentTree and save/Undo/Redo")
}

@MainActor
private func checkAnnotationBatchSelection(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    func near(_ a: CGRect,_ b: CGRect) -> Bool { zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy { abs($0-$1) < 0.01 } }
    let document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 500,height: 500),for: .mediaBox); document.insert(page,at: 0)
    let other = PDFPage(); document.insert(other,at: 1)
    let line = PDFAnnotation(bounds: CGRect(x: 90,y: 90,width: 100,height: 10),forType: .line,withProperties: nil)
    line.contents = "Batch line"; line.startPoint = CGPoint(x: 0,y: 5); line.endPoint = CGPoint(x: 100,y: 5); line.endLineStyle = .openArrow
    let square = PDFAnnotation(bounds: CGRect(x: 230,y: 100,width: 60,height: 40),forType: .square,withProperties: nil); square.contents = "Batch square"
    let ink = PDFAnnotation(bounds: CGRect(x: 100,y: 220,width: 100,height: 100),forType: .ink,withProperties: nil); ink.contents = "Batch ink"
    let curveNodes = [PDFPathNode(kind: .move,point: CGPoint(x: 100,y: 220)),PDFPathNode(kind: .curve,point: CGPoint(x: 200,y: 220),control1: CGPoint(x: 100,y: 320),control2: CGPoint(x: 200,y: 320))]
    let curveRecord = PDFInkCurveGeometry.apply(curveNodes,to: ink)!; AnnotationMetadata.setInkCurves(curveRecord,on: ink)
    let label = PDFAnnotation(bounds: CGRect(x: 330,y: 260,width: 70,height: 30),forType: .freeText,withProperties: nil); label.contents = "Linked label"
    let leader = PDFAnnotation(bounds: CGRect(x: 290,y: 240,width: 60,height: 25),forType: .line,withProperties: nil); leader.contents = "Linked leader"; leader.startPoint = .zero; leader.endPoint = CGPoint(x: 60,y: 25)
    AnnotationMetadata.setGroup("Batch callout",on: label); AnnotationMetadata.setGroup("Batch callout",on: leader)
    let hidden = PDFAnnotation(bounds: CGRect(x: 100,y: 100,width: 20,height: 20),forType: .text,withProperties: nil); hidden.shouldDisplay = false
    let widget = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 140,y: 120,width: 60,height: 25),name: "Do not marquee",choices: [])
    for annotation in [line,square,ink,label,leader,hidden,widget] { page.addAnnotation(annotation) }
    let elsewhere = PDFAnnotation(bounds: CGRect(x: 10,y: 10,width: 20,height: 20),forType: .square,withProperties: nil); other.addAnnotation(elsewhere)
    let suite = "BotPlusAnnotationBatch-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),item = PDFDocumentItem(url: root.appendingPathComponent("annotation-batch.pdf"),document: document)
    manager.insertDocument(item); manager.tool = .selectComments
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 650,height: 700)),window = NSWindow(contentRect: view.frame,styleMask: [.titled],backing: .buffered,defer: false)
    window.isReleasedWhenClosed = false; window.contentView = view; defer { window.close() }
    view.installDocument(document); view.activeTool = .selectComments
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(view)
    view.selectAnnotation(line); view.selectAnnotation(square,extending: true)
    expect(view.selectedAnnotations.count == 2 && view.annotationSelectionUnitCount == 2 && view.selectedAnnotation === square,"extended selection preserves primary clicked object")
    view.selectAnnotation(ink,extending: true); view.selectAnnotation(square,extending: true,toggle: true)
    expect(view.selectedAnnotations.count == 2 && !view.selectedAnnotations.contains { $0 === square },"Cmd-style toggle removes only selected unit")
    view.selectAnnotation(leader,extending: true)
    expect(view.selectedAnnotations.count == 4 && view.annotationSelectionUnitCount == 3 && view.selectedAnnotation === label,"linked parts expand once and count as one logical unit")
    view.selectAnnotation(label,extending: true,toggle: true)
    expect(view.selectedAnnotations.count == 2,"toggle removes complete linked unit")
    view.selectAnnotations([line,elsewhere])
    expect(view.selectedAnnotations.count == 1 && view.selectedAnnotations[0] === line,"selection cannot span PDF pages")
    view.selectAnnotations(in: CGRect(x: 70,y: 70,width: 250,height: 110),page: page)
    if view.selectedAnnotations.count != 2 { FileHandle.standardError.write(Data(("Rectangle selected: "+view.selectedAnnotations.map { ($0.contents ?? $0.type ?? "?")+" "+String(describing: $0.bounds) }.joined(separator: "; ")+"\n").utf8)) }
    expect(view.selectedAnnotations.count == 2 && !view.selectedAnnotations.contains { $0 === widget || $0 === hidden },"selection rectangle excludes hidden annotations and widgets")
    func absolute(_ annotation: PDFAnnotation,_ p: CGPoint) -> CGPoint { CGPoint(x: annotation.bounds.minX+p.x,y: annotation.bounds.minY+p.y) }
    func nearPoint(_ a: CGPoint,_ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y) < 0.01 }
    let beforeLine = line.bounds,beforeSquare = square.bounds,beforeStart = absolute(line,line.startPoint),beforeEnd = absolute(line,line.endPoint)
    item.historyDate = .distantPast
    expect(view.translateAnnotationSelection(dx: 20,dy: 15) && line.bounds == beforeLine.offsetBy(dx: 20,dy: 15) && square.bounds == beforeSquare.offsetBy(dx: 20,dy: 15),"group movement preserves relative geometry")
    expect(line.endLineStyle == .openArrow && line.endPoint == CGPoint(x: 100,y: 5),"moving group preserves local endpoints and arrow style")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    expect(view.selectedAnnotations.isEmpty && view.selectedAnnotation == nil,"document replacement clears obsolete selection references")
    func find(_ name: String) -> PDFAnnotation { item.document.page(at: 0)!.annotations.first { $0.contents == name }! }
    expect(nearPoint(absolute(find("Batch line"),find("Batch line").startPoint),beforeStart) && nearPoint(absolute(find("Batch line"),find("Batch line").endPoint),beforeEnd) && near(find("Batch square").bounds,beforeSquare),"Undo restores moved geometry despite native arrow-bounds normalization")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    expect(nearPoint(absolute(find("Batch line"),find("Batch line").endPoint),CGPoint(x: beforeEnd.x+20,y: beforeEnd.y+15)),"Redo restores group move")
    let currentLine = find("Batch line"),currentSquare = find("Batch square"),currentInk = find("Batch ink")
    view.selectAnnotations([currentLine,currentSquare]); AnnotationMetadata.setLocked(true,on: currentSquare)
    let lockedBounds = currentLine.bounds,historyCount = item.undoHistory.count
    expect(!view.translateAnnotationSelection(dx: 20,dy: 0) && !view.deleteSelectedAnnotation() && !view.rotateAnnotationSelection(clockwise: true) && currentLine.bounds == lockedBounds && item.undoHistory.count == historyCount,"locked member rejects whole batch without partial mutation/Undo")
    let lockedColor = currentLine.color
    view.strokeColor = NSColor.systemGreen.withAlphaComponent(0.4); view.strokeWidth = 2; manager.annotationOpacity = 0.4
    coordinator.checkCommand(.applyAnnotationStyle,view: view)
    expect(currentLine.color == lockedColor,"locked selection rejects partial styling")
    _ = coordinator.performAdditionalFeature("annotationBatchLock:0",on: view,item: item)
    expect(view.canModifyAnnotationSelection,"batch unlock includes all selected parts")
    coordinator.checkCommand(.applyAnnotationStyle,view: view)
    expect(abs(AnnotationMetadata.alpha(of: currentLine)-0.4) < 0.001 && abs(AnnotationMetadata.alpha(of: currentSquare)-0.4) < 0.001 && currentLine.border?.lineWidth == 2 && currentSquare.border?.lineWidth == 2,"style applies to all selected annotations")

    _ = coordinator.performAdditionalFeature("annotationBatchPrint:0",on: view,item: item)
    expect(!currentLine.shouldPrint && !currentSquare.shouldPrint,"print flag applies to complete selection")
    _ = coordinator.performAdditionalFeature("annotationBatchVisible:0",on: view,item: item)
    expect(!currentLine.shouldDisplay && !currentSquare.shouldDisplay,"visibility applies to complete selection")
    _ = coordinator.performAdditionalFeature("annotationBatchVisible:1",on: view,item: item)
    _ = coordinator.performAdditionalFeature("annotationBatchPrint:1",on: view,item: item)
    view.selectAnnotations([currentLine,currentInk])
    let board = NSPasteboard(name: NSPasteboard.Name("BotPlusBatch-"+UUID().uuidString)); defer { board.releaseGlobally() }
    expect(coordinator.checkCopy(view.selectedAnnotations,board: board),"multiple annotations copy to one private clipboard payload")
    let copiedDocument = PDFDocument(data: board.data(forType: ObjectClipboard.annotations)!)!; AnnotationMetadata.restore(copiedDocument)
    let copied = copiedDocument.page(at: 0)!.annotations.filter { !AnnotationMetadata.isContainer($0) }
    expect(copied.count == 2 && copied.contains { $0.contents == "Batch line" } && copied.contains { AnnotationMetadata.inkCurves($0) != nil },"clipboard preserves selected content and Ink curve metadata")
    expect(currentLine.page === item.document.page(at: 0) && currentInk.page === item.document.page(at: 0),"copy preserves source ownership")
    let beforePaste = item.document.page(at: 0)!.annotations.count
    expect(coordinator.checkPasteData(board.data(forType: ObjectClipboard.annotations)!,view: view) && view.selectedAnnotations.count == 2 && item.document.page(at: 0)!.annotations.count == beforePaste+2,"paste selects all inserted annotations")
    let pasted = view.selectedAnnotations
    expect(view.deleteSelectedAnnotation() && pasted.allSatisfy { $0.page == nil },"batch deletion removes all selected objects")
    view.selectAnnotations([currentLine,currentInk,currentSquare])
    let union = view.annotationSelectionBounds,center = CGPoint(x: union.midX,y: union.midY),oldAbsoluteEnd = CGPoint(x: currentLine.bounds.minX+currentLine.endPoint.x,y: currentLine.bounds.minY+currentLine.endPoint.y)
    let oldInk = try PDFInkCurveGeometry.read(currentInk,record: AnnotationMetadata.inkCurves(currentInk)),oldControl = oldInk[1].control1
    item.historyDate = .distantPast
    expect(view.rotateAnnotationSelection(clockwise: true),"supported group rotates atomically")
    let expectedEnd = CGPoint(x: center.x+(oldAbsoluteEnd.y-center.y),y: center.y-(oldAbsoluteEnd.x-center.x))
    expect(hypot(currentLine.bounds.minX+currentLine.endPoint.x-expectedEnd.x,currentLine.bounds.minY+currentLine.endPoint.y-expectedEnd.y) < 0.001 && currentLine.endLineStyle == .openArrow,"group rotation maps line endpoints and retains arrows")
    let rotatedInk = try PDFInkCurveGeometry.read(currentInk,record: AnnotationMetadata.inkCurves(currentInk)),expectedControl = CGPoint(x: center.x+(oldControl.y-center.y),y: center.y-(oldControl.x-center.x))
    expect(hypot(rotatedInk[1].control1.x-expectedControl.x,rotatedInk[1].control1.y-expectedControl.y) < 0.001,"group rotation preserves editable cubic controls")
    coordinator.showAnnotationScale(item: item,view: view)
    let staleScale = manager.annotationScaleRequest!; view.selectAnnotation(currentSquare)
    expect(staleScale.apply(110,90) != nil,"scale editor rejects a changed selection")
    view.selectAnnotations([currentLine,currentInk,currentSquare]); coordinator.showAnnotationScale(item: item,view: view)
    let scaleRequest = manager.annotationScaleRequest!,scaleBox = view.annotationSelectionBounds,preScaleControl = rotatedInk[1].control1
    let beforeScaleHistory = item.undoHistory.count
    expect(scaleRequest.apply(-10,90) != nil && item.undoHistory.count == beforeScaleHistory,"invalid scale leaves history and geometry unchanged")
    item.historyDate = .distantPast
    expect(scaleRequest.apply(110,90) == nil,"numeric nonuniform group scaling applies")
    let scaledInk = try PDFInkCurveGeometry.read(currentInk,record: AnnotationMetadata.inkCurves(currentInk))
    let expectedScaledControl = CGPoint(x: scaleBox.midX+(preScaleControl.x-scaleBox.midX)*1.1,y: scaleBox.midY+(preScaleControl.y-scaleBox.midY)*0.9)
    expect(nearPoint(scaledInk[1].control1,expectedScaledControl) && currentLine.border?.lineWidth == 2,"group scale maps editable controls and keeps stroke width")
    expect(scaleRequest.apply(110,90) != nil,"old scale editor rejects changed geometry")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    let scaleUndoInk = find("Batch ink"),scaleUndoNodes = try PDFInkCurveGeometry.read(scaleUndoInk,record: AnnotationMetadata.inkCurves(scaleUndoInk))
    expect(nearPoint(scaleUndoNodes[1].control1,preScaleControl),"Undo restores full group geometry before scaling")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let scaleRedoInk = find("Batch ink"),scaleRedoNodes = try PDFInkCurveGeometry.read(scaleRedoInk,record: AnnotationMetadata.inkCurves(scaleRedoInk))
    expect(nearPoint(scaleRedoNodes[1].control1,expectedScaledControl),"Redo restores group scaling")
    view.selectAnnotations([find("Batch line"),find("Batch ink")]); coordinator.showAnnotationRotation(item: item,view: view)
    let angleEditor = manager.annotationRotationRequest!,angleBox = view.annotationSelectionBounds,preAngleControl = scaleRedoNodes[1].control1
    let beforeAngleHistory = item.undoHistory.count
    expect(angleEditor.apply(.nan) != nil && angleEditor.apply(361) != nil && item.undoHistory.count == beforeAngleHistory,"invalid rotation leaves history unchanged")
    expect(angleEditor.apply(0) == nil && item.undoHistory.count == beforeAngleHistory,"zero-angle rotation does not create an Undo entry")
    let radians = CGFloat.pi/6,dx = preAngleControl.x-angleBox.midX,dy = preAngleControl.y-angleBox.midY
    let expectedAngleControl = CGPoint(x: angleBox.midX+dx*cos(radians)-dy*sin(radians),y: angleBox.midY+dx*sin(radians)+dy*cos(radians))
    item.historyDate = .distantPast
    expect(angleEditor.apply(30) == nil,"numeric angle applies to Line and Ink")
    let angleInk = find("Batch ink"),angleNodes = try PDFInkCurveGeometry.read(angleInk,record: AnnotationMetadata.inkCurves(angleInk))
    expect(nearPoint(angleNodes[1].control1,expectedAngleControl) && find("Batch line").endLineStyle == .openArrow,"arbitrary rotation maps exact controls and retains arrow ending")
    expect(angleEditor.apply(30) != nil,"angle editor rejects changed geometry")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    let angleUndo = try PDFInkCurveGeometry.read(find("Batch ink"),record: AnnotationMetadata.inkCurves(find("Batch ink")))
    expect(nearPoint(angleUndo[1].control1,preAngleControl),"Undo restores arbitrary rotation")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let angleRedo = try PDFInkCurveGeometry.read(find("Batch ink"),record: AnnotationMetadata.inkCurves(find("Batch ink")))
    expect(nearPoint(angleRedo[1].control1,expectedAngleControl),"Redo restores arbitrary rotation")
    view.selectAnnotations([find("Batch line"),find("Batch ink")])
    let flipBox = view.annotationSelectionBounds,preFlipControl = angleRedo[1].control1
    expect(view.flipAnnotationSelection(horizontal: true),"horizontal reflection applies to selected geometry")
    let flippedNodes = try PDFInkCurveGeometry.read(find("Batch ink"),record: AnnotationMetadata.inkCurves(find("Batch ink")))
    expect(nearPoint(flippedNodes[1].control1,CGPoint(x: 2*flipBox.midX-preFlipControl.x,y: preFlipControl.y)),"reflection mirrors editable controls about common center")
    expect(view.flipAnnotationSelection(horizontal: true),"second reflection applies")
    let twiceFlipped = try PDFInkCurveGeometry.read(find("Batch ink"),record: AnnotationMetadata.inkCurves(find("Batch ink")))
    expect(nearPoint(twiceFlipped[1].control1,preFlipControl),"double reflection restores control geometry")
    let verticalBox = view.annotationSelectionBounds
    expect(view.flipAnnotationSelection(horizontal: false),"vertical reflection applies")
    let verticallyFlipped = try PDFInkCurveGeometry.read(find("Batch ink"),record: AnnotationMetadata.inkCurves(find("Batch ink")))
    expect(nearPoint(verticallyFlipped[1].control1,CGPoint(x: preFlipControl.x,y: 2*verticalBox.midY-preFlipControl.y)),"vertical reflection mirrors exact cubic control")
    view.selectAnnotations([find("Batch line"),find("Batch square")]); let beforeMixedRotation = find("Batch line").bounds
    expect(!view.rotateAnnotationSelection(degrees: 30) && find("Batch line").bounds == beforeMixedRotation,"unsupported arbitrary shape rotation rejects whole group")
    view.selectAnnotation(find("Linked label")); let oldLabel = find("Linked label").bounds
    expect(!view.rotateAnnotationSelection(clockwise: true) && !view.flipAnnotationSelection(horizontal: true) && find("Linked label").bounds == oldLabel,"unsupported appearance types are not partially transformed")
    view.selectAnnotations([find("Batch line"),find("Batch square"),find("Batch ink")]); try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    expect(saved.page(at: 0)!.annotations.contains { $0.contents == "Batch ink" && AnnotationMetadata.inkCurves($0) != nil },"rotated group saves and reopens with cubic metadata")
    let measurement = PDFAnnotation(bounds: CGRect(x: 50,y: 350,width: 100,height: 10),forType: .ink,withProperties: nil)
    let measurePath = NSBezierPath(); measurePath.move(to: .zero); measurePath.line(to: CGPoint(x: 100,y: 0)); measurement.add(measurePath)
    let measure = EngineeringMeasure(kind: .distance,points: [CGPoint(x: 50,y: 350),CGPoint(x: 150,y: 350)],scale: EngineeringScale(unit: .mm),dimensionOffset: nil)
    AnnotationMetadata.setMeasurement(measure,on: measurement); AnnotationMetadata.setGroup("Batch measure",on: measurement)
    let measureLabel = PDFAnnotation(bounds: CGRect(x: 70,y: 380,width: 100,height: 20),forType: .freeText,withProperties: nil); AnnotationMetadata.setGroup("Batch measure",on: measureLabel)
    item.document.page(at: 0)!.addAnnotation(measurement); item.document.page(at: 0)!.addAnnotation(measureLabel)
    view.selectAnnotation(measurement)
    expect(view.translateAnnotationSelection(dx: 10,dy: 10) && AnnotationMetadata.measurement(measurement)?.points == [CGPoint(x: 60,y: 360),CGPoint(x: 160,y: 360)] && AnnotationMetadata.measurement(measurement)?.value == measure.value,"group movement translates calibrated points without changing measured value")
    let popupBoard = NSPasteboard(name: NSPasteboard.Name("BotPlusPopup-"+UUID().uuidString)); defer { popupBoard.releaseGlobally() }
    let sourcePopup = hidden.popup,sourcePage = hidden.page
    expect(coordinator.checkCopy([hidden],board: popupBoard) && hidden.page === sourcePage && hidden.popup === sourcePopup && sourcePopup?.page === sourcePage,"copying a note keeps the source popup attached")
    let noteCount = item.document.page(at: 0)!.annotations.count
    expect(coordinator.checkPasteData(popupBoard.data(forType: ObjectClipboard.annotations)!,view: view),"note and dependent popup paste")
    let pastedNote = view.selectedAnnotation!
    expect(view.selectedAnnotations.count == 1 && pastedNote.type == "Text" && pastedNote.popup?.page === item.document.page(at: 0),"popup is attached to pasted note and not independently selected")
    expect(view.deleteSelectedAnnotation() && item.document.page(at: 0)!.annotations.count == noteCount,"deleting note removes dependent popup")
    coordinator.detach()
    print("PASS: annotation multi-select/rectangle/logical groups, move/flags/clipboard/delete, 90-degree/arbitrary-angle/scale geometry, locks, calibrated points and saved editable Ink")
}

@MainActor
private func checkStructureActualText(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let content = "/Span << /MCID 0 >> BDC 0 0 1 rg 20 20 40 20 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Lang (en) /MarkInfo << /Marked true >> /StructTreeRoot 5 0 R /Outlines 9 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /StructParents 0 /Resources << >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /StructTreeRoot /K [6 0 R] /ParentTree 8 0 R /ParentTreeNextKey 1 /RoleMap << /Custom /Span >> >>",
        "<< /Type /StructElem /S /Custom /P 5 0 R /Pg 3 0 R /K 0 /Alt (Old alternative) /ActualText (Old text) /T (Title) /Lang (en-US) /E (Expansion) /A << /O /Layout /Placement /Inline >> >>",
        "<< /S /Custom /ActualText (Unrelated) >>",
        "<< /Nums [0 [6 0 R]] >>",
        "<< /Type /Outlines /First 10 0 R /Last 10 0 R /Count 1 >>",
        "<< /Parent 9 0 R /Title (Keep Fit) /Dest [3 0 R /FitV null] >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (i,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8))
    let report = try PDFDocumentExtras.structure(data,russian: false),node = report.nodes[0]
    expect(node.actual == "Old text" && node.hasActual,"structure report distinguishes ActualText presence")
    expect(node.title == "Title" && node.language == "en-US" && node.expansion == "Expansion","structure report reads title, own language and abbreviation expansion")
    let attributes = PDFStructureProperties(title: "Раздел ①",language: "de-DE",expansion: "Расшифровка сокращения")
    let propertyData = try PDFDocumentExtras.setStructure(data,language: "en",node: node,alternative: node.alternative,properties: attributes),propertyReport = try PDFDocumentExtras.structure(propertyData,russian: false)
    expect(propertyReport.nodes[0].title == "Раздел ①" && propertyReport.nodes[0].language == "de-DE" && propertyReport.nodes[0].expansion == "Расшифровка сокращения" && propertyReport.nodes[0].actual == "Old text","independent tag properties update without changing replacement text")
    let clearedProperties = try PDFDocumentExtras.setStructure(propertyData,language: "en",node: propertyReport.nodes[0],alternative: node.alternative,properties: PDFStructureProperties(title: "",language: "",expansion: "")),clearedReport = try PDFDocumentExtras.structure(clearedProperties,russian: false)
    expect(clearedReport.nodes[0].title.isEmpty && clearedReport.nodes[0].language.isEmpty && clearedReport.nodes[0].expansion.isEmpty && clearedReport.plainText.contains("Lang: <inherit>"),"empty properties remove title/expansion and restore language inheritance")
    do { _ = try PDFDocumentExtras.setStructure(data,language: "en",node: node,alternative: node.alternative,properties: PDFStructureProperties(language: "bad_tag!")); fatalError("invalid element language accepted") } catch { }

    let value = "Замещающий текст ①\nвторая строка"
    let changed = try PDFDocumentExtras.setStructure(data,language: "ru-RU",node: node,alternative: "Описание",actualText: .set(value))
    let result = try PDFDocumentExtras.structure(changed,russian: true)
    expect(result.language == "ru-RU" && result.nodes[0].actual == value && result.nodes[0].hasActual && result.nodes[0].alternative == "Описание","ActualText Unicode/multiline and Alt are independent")
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef? { var d: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(parent,key,&d); return d }
    func array(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFArrayRef? { var a: CGPDFArrayRef?; CGPDFDictionaryGetArray(parent,key,&a); return a }
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!,tree = dictionary(cg.catalog!,"StructTreeRoot")!,children = array(tree,"K")!
    var element: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(children,0,&element)
    var mcid: CGPDFInteger = -1; CGPDFDictionaryGetInteger(element!,"K",&mcid)
    var text: CGPDFStringRef?; CGPDFDictionaryGetString(element!,"T",&text)
    expect(mcid == 0 && dictionary(tree,"ParentTree") != nil && dictionary(tree,"RoleMap") != nil && dictionary(element!,"A") != nil && text.flatMap(CGPDFStringCopyTextString).map { $0 as String } == "Title","ActualText edits preserve MCID/ParentTree/RoleMap, attributes and title")
    let preserved = try PDFDocumentExtras.setStructure(changed,language: "ru-RU",node: result.nodes[0],alternative: "Other")
    let preservedReport = try PDFDocumentExtras.structure(preserved,russian: false)
    expect(preservedReport.nodes[0].actual == value,"legacy Alt-only API preserves ActualText")
    let empty = try PDFDocumentExtras.setStructure(changed,language: "ru-RU",node: result.nodes[0],alternative: "Описание",actualText: .set("")),emptyReport = try PDFDocumentExtras.structure(empty,russian: false)
    expect(emptyReport.nodes[0].hasActual && emptyReport.nodes[0].actual.isEmpty,"explicit empty ActualText differs from removal")
    let removed = try PDFDocumentExtras.setStructure(empty,language: "ru-RU",node: emptyReport.nodes[0],alternative: "Описание",actualText: .remove),removedReport = try PDFDocumentExtras.structure(removed,russian: false)
    expect(!removedReport.nodes[0].hasActual,"ActualText can be removed")
    expect(emptyReport.plainText.contains("ActualText: \"\"") && removedReport.plainText.contains("ActualText: <absent>"),"exported structure report distinguishes empty and absent replacement text")
    var forged = node; forged.objectID = 7
    do { _ = try PDFDocumentExtras.setStructure(data,language: "en",node: forged,alternative: "",actualText: .set("Bad")); fatalError("unreachable structure-like object modified") } catch PDFSourceError.alreadyUsed { }
    do { _ = try PDFDocumentExtras.setStructure(data,language: "en",node: nil,alternative: "",actualText: .set("Bad")); fatalError("replacement accepted without selected tag") } catch { }
    let suite = "BotPlusActualText-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("actual-text.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showStructure(item: item,view: view)
    let request = manager.structureRequest!
    expect(request.apply("ru-RU",request.report.nodes[0],"Описание",.set(value)) == nil,"ActualText editor installs guarded catalog transaction")
    expect(request.apply("en",request.report.nodes[0],"",.remove) != nil,"stale structure editor rejects replaced document")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(saved.nodes[0].actual == value,"ActualText survives editor save/reopen")
    let savedBookmarks = try PDFDocumentExtras.bookmarkExchange(Data(contentsOf: item.url))
    expect(savedBookmarks.first?.view == "/FitV null","structure editing preserves exact bookmark destination modes")
    manager.undoDocument(redo: false)
    let undo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(undo.nodes[0].actual == "Old text","Undo restores previous ActualText")
    manager.undoDocument(redo: true)
    let redo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(redo.nodes[0].actual == value,"Redo restores replacement text")
    view.installDocument(item.document); coordinator.showStructure(item: item,view: view)
    let propertyEditor = manager.structureRequest!,propertyNode = manager.structureRequest!.report.nodes[0]
    expect(propertyEditor.applyProperties?("ru-RU",propertyNode,propertyNode.alternative,.preserve,PDFStructureProperties(title: "Titre",language: "fr-CA",expansion: "Expanded")) == nil,"extended structure editor applies element properties")
    try manager.saveForClosing(item,to: item.url)
    let savedProperties = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(savedProperties.nodes[0].language == "fr-CA" && savedProperties.nodes[0].title == "Titre" && savedProperties.nodes[0].actual == value,"element language/title persist independently of ActualText")
    manager.undoDocument(redo: false)
    let propertyUndo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(propertyUndo.nodes[0].language == "en-US" && propertyUndo.nodes[0].title == "Title","Undo restores original element properties")
    manager.undoDocument(redo: true)
    let propertyRedo = try PDFDocumentExtras.structure(manager.serializedData(item),russian: false)
    expect(propertyRedo.nodes[0].language == "fr-CA" && propertyRedo.nodes[0].expansion == "Expanded","Redo restores extended element properties")
    print("PASS: tagged ActualText/title/language/expansion, empty/remove/inherit, Alt independence, MCID/ParentTree preservation, reachability and save/Undo/Redo")
}

@MainActor
private func checkInkCurveEditing(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 500,height: 500),for: .mediaBox); document.insert(page,at: 0)
    let annotation = PDFAnnotation(bounds: CGRect(x: 100,y: 100,width: 100,height: 150),forType: .ink,withProperties: nil)
    let native = NSBezierPath(); native.move(to: .zero); native.curve(to: CGPoint(x: 100,y: 0),controlPoint1: CGPoint(x: 0,y: 150),controlPoint2: CGPoint(x: 100,y: 150)); annotation.add(native)
    let border = PDFBorder(); border.lineWidth = 3; annotation.border = border; annotation.color = NSColor.red.withAlphaComponent(0.6); annotation.contents = "Editable curve"; page.addAnnotation(annotation)
    var nodes = try PDFInkCurveGeometry.read(annotation,record: nil)
    expect(nodes.count == 2 && nodes[1].kind == .curve && nodes[1].control1 == CGPoint(x: 100,y: 250),"native Ink curves expose cubic controls in page coordinates")
    nodes[1].control1 = CGPoint(x: 125,y: 300); nodes[1].control2 = CGPoint(x: 175,y: 300)
    nodes += [PDFPathNode(kind: .move,point: CGPoint(x: 300,y: 100)),PDFPathNode(kind: .line,point: CGPoint(x: 360,y: 100)),PDFPathNode(kind: .line,point: CGPoint(x: 360,y: 160)),PDFPathNode(kind: .close)]
    let record = PDFInkCurveGeometry.apply(nodes,to: annotation)!
    AnnotationMetadata.setInkCurves(record,on: annotation)
    let edited = try PDFInkCurveGeometry.read(annotation,record: AnnotationMetadata.inkCurves(annotation))
    expect(edited[1].kind == .curve && hypot(edited[1].control1.x-125,edited[1].control1.y-300) < 0.00001 && edited.last?.kind == .close,"Ink metadata retains exact controls, separate strokes and closure")
    expect(annotation.paths?.count == 2 && record.strokes[0].count > 20 && annotation.border?.lineWidth == 3 && annotation.contents == "Editable curve","compatible Ink paths have detailed geometry and preserve styling/content")
    let box = annotation.bounds
    annotation.bounds = box.offsetBy(dx: 20,dy: 30)
    let moved = try PDFInkCurveGeometry.read(annotation,record: record)
    expect(hypot(moved[1].control1.x-145,moved[1].control1.y-330) < 0.00001,"normalized controls follow annotation moves")
    let old = annotation.bounds
    for path in annotation.paths ?? [] { annotation.remove(path) }
    for points in record.strokes {
        let path = NSBezierPath()
        for (i,p) in points.enumerated() { let scaled = CGPoint(x: p.x*old.width*2,y: p.y*old.height*0.5); if i == 0 { path.move(to: scaled) } else { path.line(to: scaled) } }; annotation.add(path)
    }
    annotation.bounds = CGRect(x: old.minX,y: old.minY,width: old.width*2,height: old.height*0.5)
    let resized = try PDFInkCurveGeometry.read(annotation,record: record)
    expect(resized[1].kind == .curve && abs(resized[1].control1.x-(old.minX+(145-old.minX)*2)) < 0.001,"controls follow nonuniform resize")
    var invalid = nodes; invalid[0].kind = .line
    let before = annotation.bounds
    expect(PDFInkCurveGeometry.apply(invalid,to: annotation) == nil && annotation.bounds == before,"invalid node sequence leaves annotation untouched")
    invalid = nodes; invalid[1].control1.x = .nan
    expect(!PDFInkCurveGeometry.valid(invalid),"Ink editor rejects nonfinite controls")
    let suite = "BotPlusInkCurves-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),item = PDFDocumentItem(url: root.appendingPathComponent("ink-curves.pdf"),document: document)
    manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    manager.selectedAnnotation = annotation; coordinator.showAnnotationVertices(item: item,view: view)
    let request = manager.pathRequest!
    expect(request.ink && request.nodes.contains { $0.kind == .curve },"annotation command opens curve-aware editor")
    var changed = request.nodes; changed[1].control1.y += 40
    expect(request.apply(changed) == nil,"curve edit applies through guarded Undo transaction")
    expect(request.apply(changed) != nil,"old curve editor rejects changed document state")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!; AnnotationMetadata.restore(reopened)
    let restored = reopened.page(at: 0)!.annotations.first { $0.type == "Ink" }!,restoredRecord = AnnotationMetadata.inkCurves(restored)
    let restoredNodes = try PDFInkCurveGeometry.read(restored,record: restoredRecord)
    expect(restoredRecord != nil && restoredNodes[1].kind == .curve && abs(restoredNodes[1].control1.y-changed[1].control1.y) < 0.01,"saved PDF retains editable cubic geometry in BotPlus")
    expect(restored.border?.lineWidth == 3 && restored.contents == "Editable curve","saved Ink retains line width and text")
    manager.undoDocument(redo: false)
    let undone = item.document.page(at: 0)!.annotations.first { $0.type == "Ink" }!
    let undoneNodes = try PDFInkCurveGeometry.read(undone,record: AnnotationMetadata.inkCurves(undone))
    expect(abs(undoneNodes[1].control1.y-request.nodes[1].control1.y) < 0.01,"Undo restores previous curve controls")
    manager.undoDocument(redo: true)
    let redone = item.document.page(at: 0)!.annotations.first { $0.type == "Ink" }!
    let redoneNodes = try PDFInkCurveGeometry.read(redone,record: AnnotationMetadata.inkCurves(redone))
    expect(abs(redoneNodes[1].control1.y-changed[1].control1.y) < 0.01,"Redo restores edited curve controls")
    for path in restored.paths ?? [] { restored.remove(path) }
    let replacement = NSBezierPath(); replacement.move(to: .zero); replacement.line(to: CGPoint(x: 40,y: 20)); restored.add(replacement)
    let external = try PDFInkCurveGeometry.read(restored,record: restoredRecord)
    expect(external.allSatisfy { $0.kind != .curve },"mismatched native strokes invalidate stale curve metadata")
    AnnotationMetadata.setLocked(true,on: redone); manager.selectedAnnotation = redone; manager.pathRequest = nil; view.installDocument(item.document)
    coordinator.showAnnotationVertices(item: item,view: view)
    expect(manager.pathRequest == nil,"locked Ink cannot open a modifying editor")
    print("PASS: Ink cubic controls/strokes, compatible paths, metadata/save/reopen, move/resize, stale/lock guards and Undo/Redo")
}

@MainActor
private func checkNestedCurveSnapping(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let arch = PDFBezierSegment(p0: CGPoint(x: 50,y: 150),p1: CGPoint(x: 50,y: 250),p2: CGPoint(x: 150,y: 250),p3: CGPoint(x: 150,y: 150))
    expect(arch.extrema.contains { hypot($0.x-100,$0.y-225) < 0.00001 },"cubic extrema solve derivative roots")
    let crossings = arch.intersections(from: CGPoint(x: 0,y: 200),to: CGPoint(x: 200,y: 200))
    let firstT = (1-sqrt(CGFloat(1)/3))/2
    expect(crossings.count == 2 && crossings.contains { hypot($0.x-arch.point(firstT).x,$0.y-200) < 0.00001 },"line/cubic intersections find both roots")
    let tangent = arch.intersections(from: CGPoint(x: 0,y: 225),to: CGPoint(x: 200,y: 225))
    expect(tangent.count == 1 && abs(tangent[0].x-100) < 0.00001,"line/cubic tangency found without a sign change")
    expect(arch.intersections(from: CGPoint(x: 0,y: 200),to: CGPoint(x: 5,y: 200)).isEmpty,"curve intersections respect finite segment length")
    let inverted = PDFBezierSegment(p0: CGPoint(x: 50,y: 250),p1: CGPoint(x: 50,y: 150),p2: CGPoint(x: 150,y: 150),p3: CGPoint(x: 150,y: 250))
    let curveCrossings = arch.intersections(with: inverted)
    expect(curveCrossings.count == 2 && curveCrossings.allSatisfy { abs($0.y-200) < 0.0001 } && curveCrossings.contains { hypot($0.x-arch.point(firstT).x,$0.y-200) < 0.0002 },"cubic/cubic crossings agree with independent analytic roots")
    let tangentCurve = PDFBezierSegment(p0: CGPoint(x: 0,y: 225),p1: CGPoint(x: 60,y: 225),p2: CGPoint(x: 120,y: 225),p3: CGPoint(x: 200,y: 225))
    let curveTangencies = arch.intersections(with: tangentCurve)
    expect(curveTangencies.count == 1 && hypot(curveTangencies[0].x-100,curveTangencies[0].y-225) < 0.0002,"cubic hull subdivision retains tangencies")
    expect(arch.intersections(with: arch).isEmpty && arch.intersections(with: PDFBezierSegment(p0: arch.p3,p1: arch.p2,p2: arch.p1,p3: arch.p0)).isEmpty,"coincident/reversed curves have no unique intersection snap")
    expect(arch.intersections(with: inverted,in: CGRect(x: 0,y: 0,width: 10,height: 10)).isEmpty && arch.intersections(with: inverted,precision: .nan).isEmpty,"curve intersections respect search region and finite precision")
    let t = CGFloat(0.314159),exact = arch.point(t),nearest = arch.nearest(to: exact,tolerance: 0.5)
    expect(nearest.map { hypot($0.x-exact.x,$0.y-exact.y) < 0.001 } == true,"bounded cubic search returns a point on the curve")
    let query = CGPoint(x: exact.x+0.7,y: exact.y+0.4),offset = arch.nearest(to: query,tolerance: 2)!
    let reference = (0...20000).map { arch.point(CGFloat($0)/20000) }.map { hypot($0.x-query.x,$0.y-query.y) }.min()!
    expect(hypot(offset.x-query.x,offset.y-query.y) <= reference+0.001,"nearest distance agrees with dense independent reference")
    expect(arch.nearest(to: CGPoint(x: 250,y: 250),tolerance: 1) == nil && arch.nearest(to: .zero,tolerance: .nan) == nil,"curve snapping obeys tolerance and rejects nonfinite input")
    let nonuniform = PDFBezierSegment(p0: .zero,p1: .zero,p2: .zero,p3: CGPoint(x: 100,y: 0))
    expect(nonuniform.nearest(to: CGPoint(x: 50,y: 0),tolerance: 1).map { abs($0.x-50) < 0.001 } == true,"collinear nonuniform cubic is not treated as a linear parameterization")
    expect(nonuniform.arcMidpoint().map { abs($0.x-50) < 0.0001 && abs($0.y) < 0.0001 } == true && abs(nonuniform.point(0.5).x-12.5) < 0.0001,"arc midpoint follows length rather than cubic parameter")
    let asymmetric = PDFBezierSegment(p0: .zero,p1: CGPoint(x: 0,y: 200),p2: CGPoint(x: 10,y: 20),p3: CGPoint(x: 150,y: 20))
    var samples: [(CGPoint,CGFloat)] = [(asymmetric.p0,0)],length: CGFloat = 0
    for step in 1...30000 { let p = asymmetric.point(CGFloat(step)/30000),last = samples.last!.0; length += hypot(p.x-last.x,p.y-last.y); samples.append((p,length)) }
    let referenceMidpoint = samples.min { abs($0.1-length/2) < abs($1.1-length/2) }!.0
    expect(asymmetric.arcMidpoint().map { hypot($0.x-referenceMidpoint.x,$0.y-referenceMidpoint.y) < 0.02 } == true,"asymmetric arc midpoint agrees with independent length integration")
    expect(PDFBezierSegment(p0: .zero,p1: .zero,p2: .zero,p3: .zero).arcMidpoint() == nil,"zero-length curve has no arc midpoint")

    let loop = PDFBezierSegment(p0: .zero,p1: CGPoint(x: 100,y: 200),p2: CGPoint(x: -100,y: 200),p3: .zero)
    expect(loop.nearest(to: CGPoint(x: 0,y: 151),tolerance: 2).map { abs($0.y-150) < 0.001 } == true,"closed cubic loop does not collapse to its coincident endpoints")
    let pageContent = "q 1 0 0 1 30 40 cm /Outer Do Q\nq 1 0 0 1 200 40 cm /Outer Do Q\nq 1 0.5 0.25 1 350 40 cm /Outer Do Q\n50 150 m 50 250 150 250 150 150 c S\n0 200 m 200 200 l S\n220 150 m 220 350 230 170 370 170 c S\n50 350 m 50 450 150 450 150 350 c S\n50 450 m 50 350 150 350 150 450 c S\n"
    let outerContent = "q 1 0 0 1 5 7 cm /Inner Do Q\n",innerContent = "0 0 m 10 0 l S\n20 0 m 20 10 30 10 30 0 c S\n"
    func stream(_ text: String,_ extra: String = "") -> String { "<< /Length \(text.utf8.count) \(extra) >>\nstream\n"+text+"endstream" }
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [-100 -100 500 500] /Rotate 90 /Resources << /XObject << /Outer 5 0 R >> >> /Contents 4 0 R >>",
        stream(pageContent),
        stream(outerContent,"/Type /XObject /Subtype /Form /BBox [-300 -300 400 400] /Matrix [0 2 -2 0 10 20] /Resources << /XObject << /Inner 6 0 R >> >>"),
        stream(innerContent,"/Type /XObject /Subtype /Form /BBox [-20 -20 100 100] /Matrix [1 0 0 1 3 4] /Resources << >>")
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (i,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8))
    let session = try PDFContentSession(data: data,pageIndex: 0)
    for point in [CGPoint(x: 18,y: 76),CGPoint(x: 18,y: 96),CGPoint(x: 188,y: 76),CGPoint(x: 188,y: 96),CGPoint(x: 347,y: 70),CGPoint(x: 352,y: 90)] {
        let candidate = session.snapCandidate(near: point,tolerance: 0.01)
        expect(candidate?.kind == .endpoint && candidate.map { hypot($0.point.x-point.x,$0.point.y-point.y) < 0.001 } == true,"nested/reused Form matrices map endpoints once into page coordinates")
    }
    expect(session.snapCandidate(near: CGPoint(x: 18,y: 86),tolerance: 0.01)?.kind == .midpoint,"nested Form midpoint follows rotation/scale/translation")
    expect(session.snapCandidate(near: CGPoint(x: 349.5,y: 80),tolerance: 0.01)?.kind == .midpoint,"nested Form midpoint follows shear")
    expect(session.snapCandidate(near: CGPoint(x: 3,y: 126),tolerance: 0.01)?.kind == .extremum,"nested cubic control points follow parent transforms")
    let nestedCurve = PDFBezierSegment(p0: CGPoint(x: 18,y: 116),p1: CGPoint(x: -2,y: 116),p2: CGPoint(x: -2,y: 136),p3: CGPoint(x: 18,y: 136)),nestedPoint = nestedCurve.point(0.314159)
    expect(session.snapCandidate(near: nestedPoint,tolerance: 0.01)?.kind == .nearest,"nearest curve snapping works inside reused forms")

    expect(session.snapCandidate(near: CGPoint(x: 100,y: 225),tolerance: 0.1)?.kind == .extremum,"source cubic exposes curve extremum as a distinct snap type")
    let crossing = session.snapCandidate(near: arch.point(firstT),tolerance: 0.01)
    expect(crossing?.kind == .intersection && crossing.map { abs($0.point.y-200) < 0.001 } == true,"source line/cubic intersection participates in snap selection")
    let curvedCrossing = session.snapCandidate(near: CGPoint(x: arch.point(firstT).x,y: 400),tolerance: 0.01)
    expect(curvedCrossing?.kind == .intersection && curvedCrossing.map { abs($0.point.y-400) < 0.0002 } == true,"source cubic/cubic intersection participates in snapping without a line segment")
    let onCurve = session.snapCandidate(near: exact,tolerance: 0.1)
    expect(onCurve?.kind == .nearest && onCurve.map { hypot($0.point.x-exact.x,$0.point.y-exact.y) < 0.001 } == true,"source cubic supports nearest-curve snapping")
    let sourceArcMidpoint = asymmetric.arcMidpoint()!,shiftedArcMidpoint = CGPoint(x: sourceArcMidpoint.x+220,y: sourceArcMidpoint.y+150)
    expect(session.snapCandidate(near: shiftedArcMidpoint,tolerance: 0.01)?.kind == .curveMidpoint,"source curve half-length is a separate snap type")
    expect(session.snapCandidate(near: shiftedArcMidpoint,tolerance: 0.01)?.kind == .curveMidpoint,"cached arc midpoint keeps the same result")
    expect(session.snapCandidate(near: CGPoint(x: 0,y: 0),tolerance: 0.1) == nil,"local Form coordinates are not mistaken for page coordinates")
    let before = data; _ = session.vectorSnapPoints; _ = session.snapCandidate(near: exact,tolerance: 0.1)
    expect(session.data == before,"snap inspection never rewrites source PDF")
    let destination = root.appendingPathComponent("nested-curve-snaps.pdf"); try data.write(to: destination)
    let reopened = try PDFContentSession(data: Data(contentsOf: destination),pageIndex: 0)
    expect(reopened.snapCandidate(near: CGPoint(x: 188,y: 86),tolerance: 0.01)?.kind == .midpoint,"nested geometry works after file reopen")
    print("PASS: nested/reused Form transforms, cubic extrema/arc midpoint/line-curve/curve-curve intersections, bounded nearest points, degeneracies and unchanged PDF")
}

@MainActor
private func checkScanLighting(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let space = CGColorSpaceCreateDeviceRGB(),context = CIContext(options: [.cacheIntermediates:false])
    let painter = CGContext(data: nil,width: 400,height: 200,bitsPerComponent: 8,bytesPerRow: 0,space: space,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for x in 0..<400 {
        let value = 0.35+0.55*Double(x)/399
        painter.setFillColor(CGColor(gray: value,alpha: 1)); painter.fill(CGRect(x: x,y: 0,width: 1,height: 200))
    }
    painter.setFillColor(CGColor(gray: 0.03,alpha: 1)); painter.fill(CGRect(x: 20,y: 30,width: 360,height: 4))
    let cg = painter.makeImage()!,image = CIImage(cgImage: cg)
    func gray(_ image: CIImage,_ x: Double,_ y: Double) -> Double {
        let area = image.applyingFilter("CIAreaAverage",parameters: [kCIInputExtentKey:CIVector(cgRect: CGRect(x: x-1,y: y-1,width: 2,height: 2))])
        var bytes = [UInt8](repeating: 0,count: 4)
        context.render(area,toBitmap: &bytes,rowBytes: 4,bounds: CGRect(x: 0,y: 0,width: 1,height: 1),format: .RGBA8,colorSpace: space)
        return Double(bytes[0])/255
    }
    let corrected = try PDFRasterEngine.correctLighting(image,strength: 1),unchanged = try PDFRasterEngine.correctLighting(image,strength: 0)
    let before = abs(gray(image,40,110)-gray(image,360,110)),after = abs(gray(corrected,40,110)-gray(corrected,360,110))
    expect(before > 0.25 && after < before*0.25,"local lighting correction reduces a broad paper gradient")
    expect(gray(corrected,40,110) > 0.85 && gray(corrected,200,32) < 0.25,"lighting correction whitens paper while retaining dark strokes")
    expect(abs(gray(unchanged,40,110)-gray(image,40,110)) < 0.005 && corrected.extent == image.extent,"zero strength and image dimensions preserved")
    let half = try PDFRasterEngine.correctLighting(image,strength: 0.5)
    expect(gray(half,40,110) > gray(image,40,110) && gray(half,40,110) < gray(corrected,40,110),"lighting strength interpolates correction")
    do { _ = try PDFRasterEngine.correctLighting(image,strength: .nan); fatalError("nonfinite lighting accepted") } catch { }
    let buffer = NSMutableData(); var media = CGRect(x: 0,y: 0,width: 400,height: 200)
    let pdf = CGContext(consumer: CGDataConsumer(data: buffer)!,mediaBox: &media,nil)!
    pdf.beginPDFPage(nil); pdf.draw(cg,in: media); pdf.endPDFPage(); pdf.closePDF()
    var options = PDFRasterOptions(); options.dpi = 72; options.correctLighting = true; options.lightingStrength = 1
    let output = try PDFRasterEngine.process(data: buffer as Data,indices: [0],options: options,progress: { _ in })
    let document = PDFDocument(data: output)!,bounds = document.page(at: 0)!.bounds(for: .mediaBox)
    let png = try PDFSnapshotRenderer.render(data: output,index: 0,region: bounds,dpi: 72),saved = CIImage(data: png)!
    expect(abs(gray(saved,40,110)-gray(saved,360,110)) < 0.1 && gray(saved,200,32) < 0.25,"PDF output uses the same lighting correction and retains strokes")
    try output.write(to: root.appendingPathComponent("corrected-lighting.pdf"))
    print("PASS: local illumination gradient reduction, retained strokes, strength/limits and shared raster PDF output")
}

@MainActor
private func checkPerspectiveCorrection(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let quad = PDFPerspectiveQuad(topLeft: CGPoint(x: 0.175,y: 0.85),topRight: CGPoint(x: 0.75,y: 0.75),bottomRight: CGPoint(x: 0.825,y: 0.1),bottomLeft: CGPoint(x: 0.1,y: 0.15))
    expect(quad.valid,"convex perspective quadrilateral accepted")
    var invalid = quad; invalid.topRight = quad.bottomLeft
    expect(!invalid.valid,"crossing perspective quadrilateral rejected")
    invalid = quad; invalid.topLeft.x = -.infinity
    expect(!invalid.valid,"nonfinite perspective coordinates rejected")
    invalid = quad; invalid.bottomRight.x = 1.1
    expect(!invalid.valid,"perspective corners outside image rejected")
    let color = CGColorSpaceCreateDeviceRGB()
    let painter = CGContext(data: nil,width: 240,height: 300,bitsPerComponent: 8,bytesPerRow: 0,space: color,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    painter.setFillColor(CGColor(gray: 1,alpha: 1)); painter.fill(CGRect(x: 0,y: 0,width: 240,height: 300))
    let colors = [CGColor(red: 1,green: 0,blue: 0,alpha: 1),CGColor(red: 0,green: 1,blue: 0,alpha: 1),CGColor(red: 0,green: 0,blue: 1,alpha: 1),CGColor(red: 1,green: 1,blue: 0,alpha: 1)]
    let boxes = [CGRect(x: 10,y: 240,width: 50,height: 50),CGRect(x: 180,y: 240,width: 50,height: 50),CGRect(x: 180,y: 10,width: 50,height: 50),CGRect(x: 10,y: 10,width: 50,height: 50)]
    for (box,fill) in zip(boxes,colors) { painter.setFillColor(fill); painter.fill(box) }
    painter.setStrokeColor(CGColor(gray: 0,alpha: 1)); painter.setLineWidth(2)
    for y in stride(from: 80,to: 240,by: 30) { painter.move(to: CGPoint(x: 70,y: y)); painter.addLine(to: CGPoint(x: 170,y: y)); painter.strokePath() }
    let original = CIImage(cgImage: painter.makeImage()!),context = CIContext(options: [.cacheIntermediates:false])
    func point(_ p: CGPoint) -> CIVector { CIVector(x: p.x*400,y: p.y*400) }
    let projected = original.applyingFilter("CIPerspectiveTransform",parameters: ["inputTopLeft":point(quad.topLeft),"inputTopRight":point(quad.topRight),"inputBottomRight":point(quad.bottomRight),"inputBottomLeft":point(quad.bottomLeft)])
    let canvas = projected.composited(over: CIImage(color: CIColor(red: 0,green: 0,blue: 0)).cropped(to: CGRect(x: 0,y: 0,width: 400,height: 400)))
    let corrected = try PDFRasterEngine.correctPerspective(canvas,quad: quad)
    func sample(_ image: CIImage,_ x: Double,_ y: Double) -> [UInt8] {
        let rect = CGRect(x: image.extent.minX+image.extent.width*x-1,y: image.extent.minY+image.extent.height*y-1,width: 2,height: 2)
        let mean = image.applyingFilter("CIAreaAverage",parameters: [kCIInputExtentKey:CIVector(cgRect: rect)])
        var bytes = [UInt8](repeating: 0,count: 4)
        context.render(mean,toBitmap: &bytes,rowBytes: 4,bounds: CGRect(x: 0,y: 0,width: 1,height: 1),format: .RGBA8,colorSpace: color); return bytes
    }
    func checkColors(_ image: CIImage) {
        let tl = sample(image,0.14,0.88),tr = sample(image,0.86,0.88),br = sample(image,0.86,0.12),bl = sample(image,0.14,0.12)
        expect(tl[0] > 180 && tl[1] < 80 && tr[1] > 180 && tr[0] < 80,"perspective retains top corner colors and orientation")
        expect(br[2] > 180 && br[0] < 80 && bl[0] > 180 && bl[1] > 180,"perspective retains bottom corner colors and orientation")
    }
    checkColors(corrected)
    let cg = context.createCGImage(canvas,from: CGRect(x: 0,y: 0,width: 400,height: 400))!
    let buffer = NSMutableData(); var media = CGRect(x: 0,y: 0,width: 400,height: 400)
    let pdf = CGContext(consumer: CGDataConsumer(data: buffer)!,mediaBox: &media,nil)!
    pdf.beginPDFPage(nil); pdf.draw(cg,in: media); pdf.endPDFPage(); pdf.closePDF()
    let source = buffer as Data
    var options = PDFRasterOptions(); options.dpi = 72; options.perspectiveMode = 1; options.quad = quad
    let output = try PDFRasterEngine.process(data: source,indices: [0],options: options,progress: { _ in })
    let document = PDFDocument(data: output)!,bounds = document.page(at: 0)!.bounds(for: .mediaBox)
    expect(bounds.width > 50 && bounds.width < 400 && bounds.height > 50 && bounds.height < 400,"perspective copy uses rectified dimensions")
    let png = try PDFSnapshotRenderer.render(data: output,index: 0,region: bounds,dpi: 72)
    checkColors(CIImage(data: png)!)
    let destination = root.appendingPathComponent("perspective.pdf"); try output.write(to: destination)
    expect(PDFDocument(url: destination)?.pageCount == 1 && PDFDocument(data: source)?.page(at: 0)?.bounds(for: .mediaBox) == media,"rectified copy reopens and source keeps its geometry")
    options.quad = invalid
    do { _ = try PDFRasterEngine.process(data: source,indices: [0],options: options,progress: { _ in }); fatalError("invalid perspective exported") } catch { }
    print("PASS: perspective convexity/limits, projected color targets, corner orientation, shared PDF correction engine and saved copy")
}

@MainActor
private func checkBookmarkDestinationExchange(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    func fixture(_ bodies: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (i,body) in bodies.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var end = "xref\n0 \(bodies.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(bodies.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
    }
    func hex(_ value: String) -> String { "<FEFF"+value.utf16.map { String(format: "%04X",UInt32($0)) }.joined()+">" }
    let name = "Раздел / ①",named = hex(name)
    let modes = ["/XYZ null 140 0","/Fit","/FitH null","/FitV 12","/FitR 0 1 100 120","/FitB","/FitBH 50","/FitBV null"]
    let payloads = modes.enumerated().map { "/Title (Mode\($0.offset)) /Dest [4 0 R \($0.element)]" }+[
        "/Title (Named target) /Dest \(named)",
        "/Title (Named GoTo) /A << /S /GoTo /D \(named) >>",
        "/Title (Remote fit) /A << /S /GoToR /F (../drawings/plan.pdf) /D [7 /FitR 0 1 50 60] /NewWindow false >>",
        "/Title (Remote name) /A << /S /GoToR /F << /Type /Filespec /F (other.pdf) >> /D (RemoteTarget) >>",
        "/Title (URL) /A << /S /URI /URI (https://example.com/a?b=1) >>",
        "/Title (Next) /A << /S /Named /N /NextPage >>",
        "/Title (Reset) /A << /S /ResetForm /Fields [(one) \(hex("два"))] /Flags 1 >>",
        "/Title (Group) /Count -1 /First 22 0 R /Last 22 0 R"
    ]
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 5 0 R /Names << /Dests << /Names [\(named) [4 0 R /FitH null]] >> >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 200 200] >>",
        "<< /Type /Page /Parent 2 0 R /Resources << >> >>",
        "<< /Type /Page /Parent 2 0 R /Resources << >> >>",
        "<< /Type /Outlines /First 6 0 R /Last 21 0 R /Count 16 >>"
    ]
    for (i,payload) in payloads.enumerated() {
        let id = i+6
        let style = i == 0 ? "/C [0.1 0.2 0.3] /F 3" : ""
        objects.append("<< \(style) /Parent 5 0 R \(i > 0 ? "/Prev \(id-1) 0 R" : "") \(i+1 < payloads.count ? "/Next \(id+1) 0 R" : "") \(payload) >>")
    }
    objects.append("<< /Parent 21 0 R /Title (Nested) /Dest [3 0 R /XYZ null null null] >>")
    let source = fixture(objects),records = try PDFDocumentExtras.bookmarkExchange(source)
    expect(records.count == 16 && records.prefix(8).map(\.view) == modes.map { PDFDestinationView(expression: $0)!.expression },"JSON export reads all Fit modes and null operands directly")
    expect(records[8].destinationName == name && records[8].page == 2 && records[8].view == "/FitH null" && records[9].destinationName == name,"named Dest and GoTo carry Unicode name and resolved fallback")
    expect(records[10].action?.view == "/FitR 0 1 50 60" && records[10].action?.pdfFile == "../drawings/plan.pdf" && records[10].action?.newWindow == false && records[11].action?.destinationName == "RemoteTarget","remote Fit, relative paths, NewWindow and named remote targets retained")
    expect(records[15].children.count == 1 && records[15].isOpen == false,"JSON exports collapsed hierarchy")
    expect(records[0].color == [0.1,0.2,0.3] && records[0].style == 3,"JSON retains outline RGB and bold/italic flags")
    let bytes = try JSONEncoder().encode(records),decoded = try JSONDecoder().decode([PDFBookmarkExchange].self,from: bytes)
    expect(decoded.allSatisfy { $0.valid(pageCount: 2) },"new JSON destination descriptors validate")
    var base = Array(objects.prefix(5)); base[0] = "<< /Type /Catalog /Pages 2 0 R /Outlines 5 0 R >>"; base[4] = "<< /Type /Outlines /First 6 0 R /Last 6 0 R /Count 1 >>"
    base.append("<< /Title (Existing) /Parent 5 0 R /Dest [3 0 R /FitV null] /C [1 0 0] /F 2 >>")
    let target = fixture(base),output = try PDFDocumentExtras.appendBookmarkExchange(target,records: decoded)
    let legacyOutput = try PDFDocumentExtras.appendBookmarkExchange(target,records: PDFBookmarkExchange.plain("2\tOld",count: 2))
    let legacyRows = try PDFDocumentExtras.bookmarkExchange(legacyOutput)
    expect(legacyRows.last?.page == 2 && legacyRows.last?.view == "/XYZ 0 200 null","legacy TXT/page-only import retains top-of-page navigation")
    let nativeOnly = PDFBookmarkExchange(title: "Parent",children: [decoded[0]])
    expect(nativeOnly.outline(document: PDFDocument(data: target)!) == nil,"legacy native helper rejects an unrepresentable child without dropping it")

    let result = try PDFDocumentExtras.bookmarkExchange(output)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    expect(result.count == 17 && result[0].view == "/FitV null","import appends and keeps existing exact destination")
    let encodedResult = try encoder.encode(Array(result.dropFirst())),encodedOriginal = try encoder.encode(records)
    expect(encodedResult == encodedOriginal,"JSON to PDF to JSON retains complete new records")
    let importedNames = try PDFDocumentExtras.namedTargets(output)
    expect(importedNames.count == 1 && importedNames[0].name == name && importedNames[0].viewExpression == "/FitH null","missing named destination is installed once")
    let second = try PDFDocumentExtras.appendBookmarkExchange(output,records: [decoded[8]])
    let secondNames = try PDFDocumentExtras.namedTargets(second)
    expect(secondNames.count == 1,"matching existing name reused")
    var conflicting = decoded[8]; conflicting.page = 1
    do { _ = try PDFDocumentExtras.appendBookmarkExchange(output,records: [conflicting]); fatalError("conflicting target silently redirected") } catch PDFSourceError.alreadyUsed { }
    var malformed = decoded[0]; malformed.view = "/FitR null 0 1 2"
    expect(!malformed.valid(pageCount: 2),"invalid Fit parameters rejected")
    malformed = decoded[0]; malformed.action = PDFBookmarkActionExchange(kind: "named",name: 1)
    expect(!malformed.valid(pageCount: 2),"conflicting action and local destination rejected")
    var unknown = objects; unknown[5] = "<< /Parent 5 0 R /Title (Unknown) /Next 7 0 R /A << /S /JavaScript /JS (app.alert) >> >>"
    do { _ = try PDFDocumentExtras.bookmarkExchange(fixture(unknown)); fatalError("unsupported action silently exported") } catch { }
    unknown = objects; unknown[5] = "<< /Parent 5 0 R /Title (Chain) /Next 7 0 R /A << /S /GoTo /D [3 0 R /Fit] /Next << /S /Named /N /NextPage >> >> >>"
    let supportedChain = try PDFDocumentExtras.bookmarkExchange(fixture(unknown))
    expect(supportedChain.first?.nextActions?.first?.action?.kind == "named","supported action chain is preserved rather than rejected")
    unknown = objects; unknown[5] = "<< /Parent 5 0 R /Title (Unresolved) /Next 7 0 R /Dest (Missing) >>"
    do { _ = try PDFDocumentExtras.bookmarkExchange(fixture(unknown)); fatalError("unresolved name silently exported") } catch { }
    let suite = "BotPlusBookmarkDestinationExchange-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: target)!
    let item = PDFDocumentItem(url: root.appendingPathComponent("bookmark-destination-exchange.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(target,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    try coordinator.applyBookmarkExchange(decoded,item: item,view: view)
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.bookmarkExchange(Data(contentsOf: item.url))
    expect(saved.count == 17 && saved[1].view == modes[0],"exact bookmark import survives editor transaction and disk save")
    manager.undoDocument(redo: false)
    let undo = try PDFDocumentExtras.bookmarkExchange(manager.serializedData(item))
    expect(undo.count == 1 && undo[0].view == "/FitV null","Undo removes imported bookmarks and restores original mode")
    manager.undoDocument(redo: true)
    let redo = try PDFDocumentExtras.bookmarkExchange(manager.serializedData(item))
    expect(redo.count == 17 && redo[9].destinationName == name,"Redo restores exact and named navigation")
    print("PASS: JSON all Fit/null modes, Unicode local/remote names, relative files, name conflicts, unsupported-action rejection and append/save/Undo/Redo")
}

@MainActor
private func checkTabTraversal(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let content = "0 0 1 rg 20 20 40 40 re f\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 9 0 R /AcroForm << /Fields [7 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [10 20 210 220] >>",
        "<< /Type /Pages /Parent 2 0 R /Kids [5 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /Tabs /C /Resources << >> >>",
        "<< /Type /Page /Parent 3 0 R /Tabs /R /Rotate 90 /Resources << >> /Contents 6 0 R /Annots [7 0 R 8 0 R] /Custom (retain) >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /Annot /Subtype /Widget /FT /Tx /T (Field) /V (keep) /Rect [20 30 80 60] /P 5 0 R >>",
        "<< /Type /Annot /Subtype /Link /Rect [80 30 100 60] /Dest [4 0 R /FitH null] >>",
        "<< /Type /StructTreeRoot /K [] /ParentTree << /Nums [] >> >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var trailer = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { trailer += String(format: "%010lld 00000 n \n",Int64(offset)) }
    trailer += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(trailer.utf8))
    let initial = try PDFDocumentExtras.tabTraversal(data,pageIndex: 0)
    expect(initial.value == "R" && initial.hasStructure,"Tabs follows nested page tree order and detects structure")
    for mode in PDFTabTraversal.allCases {
        let changed = try PDFDocumentExtras.setTabTraversal(data,pageIndex: 0,mode: mode)
        let rule = try PDFDocumentExtras.tabTraversal(changed,pageIndex: 0),other = try PDFDocumentExtras.tabTraversal(changed,pageIndex: 1)
        expect(rule.value == mode.rawValue && other.value == "C","all supported Tabs rules change only the requested page")
        let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!,page = cg.page(at: 1)!,dict = page.dictionary!
        var annotations: CGPDFArrayRef?; CGPDFDictionaryGetArray(dict,"Annots",&annotations)
        expect(annotations.map(CGPDFArrayGetCount) == 2 && page.rotationAngle == 90 && page.getBoxRect(.mediaBox) == CGRect(x: 10,y: 20,width: 200,height: 200),"Tabs preserves annotations, rotation and inherited geometry")
        var structure: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(cg.catalog!,"StructTreeRoot",&structure)
        var field: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(annotations!,0,&field)
        var value: CGPDFStringRef?; CGPDFDictionaryGetString(field!,"V",&value)
        expect(structure != nil && value.flatMap(CGPDFStringCopyTextString).map { $0 as String } == "keep","Tabs preserves structure and field values")
        if mode == .unspecified { var tab: CGPDFObjectRef?; expect(!CGPDFDictionaryGetObject(dict,"Tabs",&tab),"unspecified removes Tabs key") }
    }
    do { _ = try PDFDocumentExtras.setTabTraversal(data,pageIndex: 2,mode: .rows); fatalError("invalid Tabs page accepted") } catch { }
    let suite = "BotPlusTabTraversal-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!
    let item = PDFDocumentItem(url: root.appendingPathComponent("tab-traversal.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showTabTraversal(item: item,view: view)
    let stale = manager.tabTraversalRequest!
    expect(stale.current == "R","Tabs editor reads original rule")
    expect(view.document === item.document,"Tabs view remains attached")
    let applied = stale.apply(.structure)
    if let applied { FileHandle.standardError.write(Data(("Tabs apply error: "+applied+"\n").utf8)) }
    expect(applied == nil,"Tabs editor installs guarded transaction")
    expect(stale.apply(.columns) != nil,"old Tabs editor rejects a replaced document")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.tabTraversal(Data(contentsOf: item.url),pageIndex: 0)
    expect(saved.value == "S","Tabs survives disk save/reopen")
    manager.undoDocument(redo: false)
    let undone = try PDFDocumentExtras.tabTraversal(manager.serializedData(item),pageIndex: 0)
    expect(undone.value == "R","Undo restores Tabs")
    manager.undoDocument(redo: true)
    let redone = try PDFDocumentExtras.tabTraversal(manager.serializedData(item),pageIndex: 0)
    expect(redone.value == "S","Redo restores Tabs")
    print("PASS: PDF Tabs row/column/structure/reset, nested pages, annotation/geometry preservation, stale guard and save/Undo/Redo")
}

@MainActor
private func checkLayerConfiguration(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let order = "/Order [5 0 R [6 0 R] [(Folder) 7 0 R [5 0 R]]]"
    let content = "q /OC /L1 BDC 0 0 1 rg 20 20 40 40 re f EMC Q\nq /OC /M BDC 1 0 0 rg 70 20 40 40 re f EMC Q\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Lang (en) /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R 8 0 R] /D << /BaseState /ON \(order) /Locked [7 0 R] /RBGroups [[5 0 R 6 0 R]] /OFF [6 0 R] /AS [9 0 R] >> /Configs [<< /Name (Other) /BaseState /OFF /Order [8 0 R] >>] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Properties << /L1 5 0 R /L2 6 0 R /M 10 0 R >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (Parent) /Usage << /View << /ViewState /ON >> /Print << /PrintState /ON /Subtype /Watermark >> /CreatorInfo << /Creator (Fixture) /Subtype /Artwork >> /Language << /Lang (en-US) /Preferred true >> >> >>",
        "<< /Type /OCG /Name (Child) /Intent [/View /Design] /Usage << /Zoom << /min 0 /max 2 >> >> >>",
        "<< /Type /OCG /Name (Locked) /Intent /Design /Usage << /Print << /PrintState /OFF >> >> >>",
        "<< /Type /OCG /Name (Unlisted) /Usage << /Export << /ExportState /OFF >> >> >>",
        "<< /Event /Export /OCGs [8 0 R] /Category [/Export] >>",
        "<< /Type /OCMD /OCGs [5 0 R 6 0 R] /P /AllOn /VE [/And 5 0 R 6 0 R] >>"
    ]
    func fixture(_ objects: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var trailer = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { trailer += String(format: "%010lld 00000 n \n",Int64(offset)) }
        trailer += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(trailer.utf8)); return data
    }
    let data = fixture(objects),config = try PDFDocumentExtras.layerConfiguration(data)
    expect(config.groups.count == 4 && config.rows.map(\.title) == ["Parent","Child","Folder","Locked","Parent"],"OCG Order displays nested groups and nonselectable labels")
    expect(config.rows.map(\.depth) == [0,1,0,1,2] && Set(config.rows.map(\.id)).count == config.rows.count,"Order depths and repeated OCG occurrences have stable unique row IDs")
    expect(config.groups.first { $0.name == "Unlisted" } != nil && !config.rows.contains { $0.title == "Unlisted" },"catalog inspection keeps unlisted groups outside the configured outline")
    let empty = try PDFDocumentExtras.layerConfiguration(fixture(objects.map { $0.replacingOccurrences(of: order,with: "/Order []") }))
    expect(empty.hasOrder && empty.rows.isEmpty && empty.groups.count == 4,"explicit empty Order hides groups without losing catalog entries")
    let absent = try PDFDocumentExtras.layerConfiguration(fixture(objects.map { $0.replacingOccurrences(of: order,with: "") }))
    expect(!absent.hasOrder && absent.rows.isEmpty,"missing Order does not fabricate a configured group list")
    let parent = config.groups.first { $0.name == "Parent" }!,child = config.groups.first { $0.name == "Child" }!,locked = config.groups.first { $0.name == "Locked" }!
    expect(parent.printState == true && parent.viewState == true && child.intent == ["View","Design"] && locked.locked,"reads Print/View Usage, intents and locked state")
    let updated = try PDFDocumentExtras.setLayerUsage(data,entry: parent,viewState: nil,printState: false)
    let updatedConfig = try PDFDocumentExtras.layerConfiguration(updated),updatedParent = updatedConfig.groups.first { $0.name == "Parent" }!
    expect(updatedParent.printState == false && updatedParent.viewState == nil && updatedParent.visible,"Print policy does not alter base visibility and removes inherited View override")
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef? { var result: CGPDFDictionaryRef?; return CGPDFDictionaryGetDictionary(parent,key,&result) ? result : nil }
    func array(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFArrayRef? { var result: CGPDFArrayRef?; return CGPDFDictionaryGetArray(parent,key,&result) ? result : nil }
    func name(_ parent: CGPDFDictionaryRef,_ key: String) -> String? { var result: UnsafePointer<CChar>?; return CGPDFDictionaryGetName(parent,key,&result) ? result.map { String(cString: $0) } : nil }
    func cg(_ data: Data) -> CGPDFDocument { CGPDFDocument(CGDataProvider(data: data as CFData)!)! }
    let pdf = cg(updated),props = dictionary(pdf.catalog!,"OCProperties")!,defaultConfig = dictionary(props,"D")!
    let ocgs = array(props,"OCGs")!; var parentDictionary: CGPDFDictionaryRef?; _ = CGPDFArrayGetDictionary(ocgs,0,&parentDictionary)
    let usage = dictionary(parentDictionary!,"Usage")!
    expect(name(dictionary(usage,"Print")!,"Subtype") == "Watermark" && dictionary(usage,"CreatorInfo") != nil && dictionary(usage,"Language") != nil,"usage edits retain Print subtype and unrelated usage categories")
    let applications = array(defaultConfig,"AS")!
    var events: [String] = []
    for index in 0..<CGPDFArrayGetCount(applications) { var entry: CGPDFDictionaryRef?; if CGPDFArrayGetDictionary(applications,index,&entry),let entry { events.append(name(entry,"Event") ?? "") } }
    expect(events == ["Export","Print"],"writes Print AS application and retains unrelated Export application")
    expect(array(props,"Configs").map(CGPDFArrayGetCount) == 1 && array(defaultConfig,"RBGroups") != nil && array(defaultConfig,"Locked") != nil,"retains alternate configs, radio groups and locks")
    let resources = dictionary(pdf.page(at: 1)!.dictionary!,"Resources")!,membership = dictionary(dictionary(resources,"Properties")!,"M")!
    expect(name(membership,"P") == "AllOn" && array(membership,"VE") != nil && array(membership,"OCGs").map(CGPDFArrayGetCount) == 2,"usage updates preserve OCMD membership and visibility expressions")
    let inherited = try PDFDocumentExtras.setLayerUsage(updated,entry: updatedParent,viewState: nil,printState: nil)
    let inheritedConfig = try PDFDocumentExtras.layerConfiguration(inherited)
    expect(inheritedConfig.groups.first { $0.name == "Parent" }?.printState == nil,"inherit clears explicit print state")
    let inheritedPDF = cg(inherited),inheritedDefault = dictionary(dictionary(inheritedPDF.catalog!,"OCProperties")!,"D")!
    expect(array(inheritedDefault,"AS").map(CGPDFArrayGetCount) == 1,"inherit removes only the layer's exact usage application")
    do { _ = try PDFDocumentExtras.setLayerUsage(data,entry: locked,viewState: nil,printState: true); fatalError("locked layer policy changed") } catch PDFSourceError.permission { }
    let toggled = try PDFDocumentExtras.setLayer(updated,entry: child,visible: true),toggleGroups = try PDFDocumentExtras.layers(toggled)
    expect(toggleGroups.first { $0.name == "Parent" }?.visible == false && toggleGroups.first { $0.name == "Child" }?.visible == true,"radio visibility behavior survives usage editing")
    expect(toggleGroups.first { $0.name == "Parent" }?.printState == false,"visibility toggles preserve print usage")
    let presets = try PDFDocumentExtras.layerPresets(data)
    expect(presets.count == 2 && presets[1].name == "Other" && presets[1].canMakeDefault,"alternative OCG configurations are listed")
    let switched = try PDFDocumentExtras.makeLayerPresetDefault(data,index: 0)
    let switchedConfig = try PDFDocumentExtras.layerConfiguration(switched)
    expect(switchedConfig.groups.allSatisfy { !$0.visible } && switchedConfig.rows.map(\.title) == ["Unlisted"],"BaseState OFF materializes visibility and selected hierarchy")
    let switchedPDF = cg(switched),switchedProps = dictionary(switchedPDF.catalog!,"OCProperties")!,switchedDefault = dictionary(switchedProps,"D")!
    expect(name(switchedDefault,"BaseState") == "ON" && array(switchedDefault,"OFF").map(CGPDFArrayGetCount) == 4 && array(switchedProps,"Configs").map(CGPDFArrayGetCount) == 1,"default obeys BaseState ON and old default replaces selected alternate")
    let restoredPreset = try PDFDocumentExtras.makeLayerPresetDefault(switched,index: 0),restoredConfig = try PDFDocumentExtras.layerConfiguration(restoredPreset)
    expect(restoredConfig.groups.map(\.visible) == config.groups.map(\.visible) && restoredConfig.rows.map(\.title) == config.rows.map(\.title),"switching back restores original visibility, hierarchy and locks")
    expect(restoredConfig.groups.first { $0.name == "Locked" }?.locked == true,"previous default keeps Locked rules")
    var unchangedObjects = objects
    unchangedObjects[0] = objects[0].replacingOccurrences(of: "/Name (Other) /BaseState /OFF",with: "/Name (Other) /BaseState /Unchanged /OFF [5 0 R]")
    let unchangedPreset = try PDFDocumentExtras.makeLayerPresetDefault(fixture(unchangedObjects),index: 0),unchangedGroups = try PDFDocumentExtras.layers(unchangedPreset)
    expect(unchangedGroups.first { $0.name == "Parent" }?.visible == false && unchangedGroups.first { $0.name == "Child" }?.visible == false && unchangedGroups.first { $0.name == "Unlisted" }?.visible == true,"Unchanged preset starts with persisted current states")
    var designObjects = objects
    designObjects[0] = objects[0].replacingOccurrences(of: "/Name (Other)",with: "/Name (Other) /Intent /Design")
    let designData = fixture(designObjects),designPresets = try PDFDocumentExtras.layerPresets(designData)
    expect(designPresets.last?.canMakeDefault == false,"non-View preset cannot become document default")
    do { _ = try PDFDocumentExtras.makeLayerPresetDefault(designData,index: 0); fatalError("Design intent installed as default") } catch { }
    let createdPreset = try PDFDocumentExtras.editLayerPreset(data,operation: .create("  Слой проекта ①  "))
    let createdPresets = try PDFDocumentExtras.layerPresets(createdPreset)
    expect(createdPresets.count == 3 && createdPresets.last?.name == "Слой проекта ①" && createdPresets.last?.creator == "BotPlus PDF Editor","current OCG configuration saved with normalized Unicode name")
    let activatedCopy = try PDFDocumentExtras.makeLayerPresetDefault(createdPreset,index: 1),copyConfiguration = try PDFDocumentExtras.layerConfiguration(activatedCopy)
    expect(copyConfiguration.groups.map(\.visible) == config.groups.map(\.visible) && copyConfiguration.rows.map(\.title) == config.rows.map(\.title),"saved configuration retains visibility and full hierarchy")
    expect(copyConfiguration.groups.first { $0.name == "Locked" }?.locked == true,"saved configuration retains lock rules")
    let renamedPreset = try PDFDocumentExtras.editLayerPreset(createdPreset,operation: .rename(1,"Новая / конфигурация"))
    let renamedPresets = try PDFDocumentExtras.layerPresets(renamedPreset)
    expect(renamedPresets.last?.name == "Новая / конфигурация","alternative configuration can be renamed with PDF delimiters")
    let renamedDefault = try PDFDocumentExtras.editLayerPreset(renamedPreset,operation: .rename(-1,"Основная")),defaultPresets = try PDFDocumentExtras.layerPresets(renamedDefault)
    expect(defaultPresets.first?.name == "Основная","default configuration can be named")
    let removedPreset = try PDFDocumentExtras.editLayerPreset(renamedDefault,operation: .remove(1)),remainingPresets = try PDFDocumentExtras.layerPresets(removedPreset)
    expect(remainingPresets.count == 2 && remainingPresets.last?.name == "Other","remove deletes only selected alternative")
    do { _ = try PDFDocumentExtras.editLayerPreset(data,operation: .remove(-1)); fatalError("default configuration deleted") } catch { }
    do { _ = try PDFDocumentExtras.editLayerPreset(data,operation: .create("oThEr")); fatalError("ambiguous duplicate preset name accepted") } catch PDFSourceError.alreadyUsed { }
    do { _ = try PDFDocumentExtras.editLayerPreset(data,operation: .create(" \n ")); fatalError("empty preset name accepted") } catch { }
    let suite = "BotPlusLayerPolicy-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),source = PDFDocument(data: data)!,view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500))
    let item = PDFDocumentItem(url: root.appendingPathComponent("layer-policy.pdf"),document: source,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item); view.installDocument(source)
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.layerCommand("layersRefresh",item: item,view: view)
    let selected = manager.layerEntries.first { $0.name == "Parent" }!
    coordinator.showLayerPolicy("layerPolicy:\(selected.id)",item: item,view: view)
    expect(manager.layerPolicyRequest!.apply(nil,false) == nil,"layer policy editor installs catalog transaction")
    try manager.saveForClosing(item,to: item.url)
    let savedGroups = try PDFDocumentExtras.layers(Data(contentsOf: item.url))
    expect(savedGroups.first { $0.name == "Parent" }?.printState == false,"print policy survives file save/reopen")
    manager.undoDocument(redo: false)
    let undone = try PDFDocumentExtras.layers(manager.serializedData(item))
    expect(undone.first { $0.name == "Parent" }?.printState == true,"Undo restores original usage")
    manager.undoDocument(redo: true)
    let redone = try PDFDocumentExtras.layers(manager.serializedData(item))
    expect(redone.first { $0.name == "Parent" }?.printState == false,"Redo restores edited usage")
    coordinator.layerCommand("layerPreset:0",item: item,view: view)
    expect(manager.layerError != nil,"preset action rejects the stale snapshot after Undo/Redo")
    view.installDocument(item.document) // Mirror the view reload normally driven by SwiftUI.
    coordinator.layerCommand("layersRefresh",item: item,view: view)
    coordinator.layerCommand("layerPreset:0",item: item,view: view)
    expect(manager.layerError == nil && manager.layerEntries.allSatisfy { !$0.visible },"preset menu installs default in editor")
    try manager.saveForClosing(item,to: item.url)
    let savedPreset = try PDFDocumentExtras.layers(Data(contentsOf: item.url))
    expect(savedPreset.allSatisfy { !$0.visible },"chosen preset survives file save/reopen")
    manager.undoDocument(redo: false)
    let undoPreset = try PDFDocumentExtras.layers(manager.serializedData(item))
    expect(undoPreset.first { $0.name == "Parent" }?.visible == true,"Undo restores previous default configuration")
    manager.undoDocument(redo: true)
    let redoPreset = try PDFDocumentExtras.layers(manager.serializedData(item))
    expect(redoPreset.allSatisfy { !$0.visible },"Redo restores chosen default")
    view.installDocument(item.document); coordinator.showLayerPresetEditor(item: item,view: view)
    let presetEditor = manager.layerPresetRequest!
    expect(presetEditor.apply(.create("Редактор")) == nil,"preset management applies through guarded editor transaction")
    expect(presetEditor.apply(.remove(0)) != nil,"stale preset manager cannot edit replaced document")
    try manager.saveForClosing(item,to: item.url)
    let editorSaved = try PDFDocumentExtras.layerPresets(Data(contentsOf: item.url))
    expect(editorSaved.count == 3 && editorSaved.last?.name == "Редактор","new preset survives file save/reopen")
    manager.undoDocument(redo: false)
    let editorUndo = try PDFDocumentExtras.layerPresets(manager.serializedData(item))
    expect(editorUndo.count == 2,"Undo restores configuration list before creation")
    manager.undoDocument(redo: true)
    let editorRedo = try PDFDocumentExtras.layerPresets(manager.serializedData(item))
    expect(editorRedo.count == 3 && editorRedo.last?.name == "Редактор","Redo restores created preset")
    print("PASS: OCG Order/Usage, preset create/rename/remove/default swap, ON/OFF/Unchanged/View constraints, OCMD/radio/locks preservation and save/Undo/Redo")
}

@MainActor
private func checkNamedDestinationLifecycle(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let content = "BT /F1 12 Tf 20 150 Td (Tree and Legacy stay in page content) Tj ET\n20 20 40 40 re S\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Names << /Dests 8 0 R >> /Dests << /Legacy [4 0 R /FitV null] >> /Outlines 5 0 R /OpenAction (Tree) /AA << /WC 15 0 R >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Annots [9 0 R 10 0 R 11 0 R 17 0 R] /Contents 12 0 R /Resources << /Font << /F1 14 0 R >> >> >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
        "<< /Type /Outlines /First 6 0 R /Last 7 0 R /Count 2 >>",
        "<< /Title (Tree bookmark) /Parent 5 0 R /Next 7 0 R /Dest (Tree) >>",
        "<< /Title (Legacy bookmark) /Parent 5 0 R /Prev 6 0 R /A << /S /GoTo /D /Legacy >> >>",
        "<< /Kids [13 0 R] /Limits [(Tree) (Tree)] >>",
        "<< /Type /Annot /Subtype /Link /Rect [10 10 30 30] /Dest (Tree) >>",
        "<< /Type /Annot /Subtype /Link /Rect [40 10 60 30] /A << /S /GoTo /D /#54ree >> >>",
        "<< /Type /Annot /Subtype /Link /Rect [70 10 90 30] /A << /S /GoToR /F (other.pdf) /D (Tree) >> >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Names [(Tree) [4 0 R /FitH null]] /Limits [(Tree) (Tree)] >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /S /GoTo /D (Tree) /Next [<< /S /GoTo /D (Legacy) >> << /S /GoToR /F (other.pdf) /D (Tree) >>] >>",
        "<< /Title (Tree) /Subject (Legacy) >>",
        "<< /Type /Annot /Subtype /Link /Rect [100 10 120 30] /A 18 0 R >>",
        "<< /S /GoTo /D 19 0 R >>",
        "(Tree)"
    ]
    func makeFixture(_ objects: [String]) -> Data {
        var fixture = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(fixture.count); fixture.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = fixture.count
        var trailer = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { trailer += String(format: "%010lld 00000 n \n",Int64(offset)) }
        trailer += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R /Info 16 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; fixture.append(Data(trailer.utf8)); return fixture
    }
    let fixture = makeFixture(objects)
    let initial = try PDFDocumentExtras.namedTargets(fixture)
    expect(Set(initial.map(\.name)) == ["Tree","Legacy"],"reads both NameTree Kids and legacy Dests")
    let escapedFixture = makeFixture(objects.map { $0.replacingOccurrences(of: "/Legacy ",with: "/Legacy#20name ") })
    let escapedTargets = try PDFDocumentExtras.namedTargets(escapedFixture)
    expect(escapedTargets.first { $0.name == "Legacy name" }?.viewExpression.flatMap(PDFDestinationView.init(expression:))?.mode == .FitV,"legacy escaped destination names retain their view expression")
    let expressions = ["/XYZ null 100 0","/Fit","/FitH null","/FitV 20","/FitR 10 20 100 150","/FitB","/FitBH 50","/FitBV null"]
    var targets = initial
    for (index,expression) in expressions.enumerated() { targets.append(PDFNamedTarget(name: "Mode\(index)",page: 1,viewExpression: expression)) }
    let withModes = try PDFDocumentExtras.writeNamedTargets(fixture,targets: targets,bookmarks: [:])
    let restoredModes = try PDFDocumentExtras.namedTargets(withModes)
    for (index,expression) in expressions.enumerated() {
        let actual = restoredModes.first { $0.name == "Mode\(index)" }?.viewExpression
        expect(actual.flatMap(PDFDestinationView.init(expression:)) == PDFDestinationView(expression: expression),"Fit/XYZ/null mode preserved: \(expression)")
    }
    expect(PDFDestinationView(expression: "/FitR 0 null 10 20") == nil && PDFDestinationView(expression: "/Fit 10") == nil && PDFDestinationView(expression: "/XYZ null null -1") == nil,"invalid view operand counts, FitR rectangle and negative zoom rejected")
    var renamed = initial
    let treeIndex = renamed.firstIndex { $0.name == "Tree" }!
    renamed[treeIndex].name = "Цель переименована"
    let updated = try PDFDocumentExtras.writeNamedTargets(fixture,targets: renamed,bookmarks: [:])
    func cg(_ bytes: Data) -> CGPDFDocument { CGPDFDocument(CGDataProvider(data: bytes as CFData)!)! }
    func text(_ dictionary: CGPDFDictionaryRef,_ key: String) -> String? {
        var value: CGPDFStringRef?; if CGPDFDictionaryGetString(dictionary,key,&value),let value { return CGPDFStringCopyTextString(value) as String? }
        var name: UnsafePointer<CChar>?; if CGPDFDictionaryGetName(dictionary,key,&name),let name { return String(cString: name) }; return nil
    }
    func annotations(_ document: CGPDFDocument) -> [CGPDFDictionaryRef] {
        var array: CGPDFArrayRef?; guard CGPDFDictionaryGetArray(document.page(at: 1)!.dictionary!,"Annots",&array),let array else { return [] }
        return (0..<CGPDFArrayGetCount(array)).compactMap { index in var value: CGPDFDictionaryRef?; return CGPDFArrayGetDictionary(array,index,&value) ? value : nil }
    }
    func dictionary(_ dictionary: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef? { var value: CGPDFDictionaryRef?; return CGPDFDictionaryGetDictionary(dictionary,key,&value) ? value : nil }
    let renamedDocument = cg(updated),links = annotations(renamedDocument)
    expect(text(links[0],"Dest") == "Цель переименована" && text(dictionary(links[1],"A")!,"D") == "Цель переименована","renames literal and escaped-name Link destinations")
    expect(text(dictionary(links[2],"A")!,"D") == "Tree","does not rewrite remote GoToR destinations")
    expect(text(dictionary(links[3],"A")!,"D") == "Цель переименована","renames indirect GoTo action and indirect destination string")
    expect(text(renamedDocument.catalog!,"OpenAction") == "Цель переименована","renames catalog OpenAction destination")
    let nextAction = dictionary(dictionary(renamedDocument.catalog!,"AA")!,"WC")!
    expect(text(nextAction,"D") == "Цель переименована","renames additional-action GoTo destination")
    var next: CGPDFArrayRef?; _ = CGPDFDictionaryGetArray(nextAction,"Next",&next)
    var remoteNext: CGPDFDictionaryRef?; _ = CGPDFArrayGetDictionary(next!,1,&remoteNext)
    expect(text(remoteNext!,"D") == "Tree","preserves remote action nested in Next array")
    let pdf = PDFDocument(data: updated)!
    expect((pdf.page(at: 0)?.string ?? "").contains("Tree and Legacy") && (pdf.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String) == "Tree","destination rename leaves content streams and document metadata unchanged")
    let loaded = try PDFDocumentExtras.namedTargets(updated)
    let deleted = try PDFDocumentExtras.writeNamedTargets(updated,targets: loaded.filter { $0.name != "Цель переименована" },bookmarks: [:])
    let deletedDocument = cg(deleted),deletedLinks = annotations(deletedDocument)
    var explicit: CGPDFArrayRef?; expect(CGPDFDictionaryGetArray(deletedLinks[0],"Dest",&explicit),"deleting used name converts Link target to explicit destination")
    var mode: UnsafePointer<CChar>?; expect(CGPDFArrayGetName(explicit!,1,&mode) && String(cString: mode!) == "FitH","deletion preserves original Fit view mode")
    var nullValue: CGPDFObjectRef?; _ = CGPDFArrayGetObject(explicit!,2,&nullValue)
    expect(CGPDFObjectGetType(nullValue!) == .null,"deletion preserves null operand")
    var targetPage: CGPDFDictionaryRef?; _ = CGPDFArrayGetDictionary(explicit!,0,&targetPage)
    expect(targetPage == deletedDocument.page(at: 2)!.dictionary,"explicit replacement points to original destination page")
    var swapped = initial
    for index in swapped.indices { swapped[index].name = swapped[index].name == "Tree" ? "Legacy" : "Tree" }
    let swapData = try PDFDocumentExtras.writeNamedTargets(fixture,targets: swapped,bookmarks: [:]),swapDocument = cg(swapData)
    expect(text(annotations(swapDocument)[0],"Dest") == "Legacy","simultaneous name swaps use original identity instead of sequential replacement")
    let saved = root.appendingPathComponent("named-destination-lifecycle.pdf"); try deleted.write(to: saved)
    let reopened = try PDFDocumentExtras.namedTargets(Data(contentsOf: saved))
    expect(reopened.map(\.name) == ["Legacy"],"deleted names stay removed after file save/reopen")
    let suite = "BotPlusNamedLifecycle-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),source = PDFDocument(data: fixture)!
    let item = PDFDocumentItem(url: root.appendingPathComponent("named-destination-transaction.pdf"),document: source,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(fixture,item: item)
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(source)
    let coordinator = PDFViewer.Coordinator(manager: manager)
    coordinator.showNamedDestinations(item: item,view: view)
    expect(manager.namedRequest!.apply(renamed) == nil,"named destination editor installs rewritten source transaction")
    let installed = try manager.serializedData(item),installedCG = cg(installed)
    expect(text(annotations(installedCG)[0],"Dest") == "Цель переименована","transaction retains updated named Link reference")
    try manager.saveForClosing(item,to: item.url)
    let writtenCG = cg(try Data(contentsOf: item.url))
    expect(text(annotations(writtenCG)[0],"Dest") == "Цель переименована","named destination editor save keeps rewritten references")
    manager.undoDocument(redo: false)
    let undone = try PDFDocumentExtras.namedTargets(manager.serializedData(item))
    expect(Set(undone.map(\.name)) == ["Tree","Legacy"],"one Undo restores original named destination table")
    manager.undoDocument(redo: true)
    let redoneData = try manager.serializedData(item),redoneCG = cg(redoneData)
    expect(text(annotations(redoneCG)[0],"Dest") == "Цель переименована","Redo restores changed named references")
    print("PASS: all destination modes/nulls, NameTree/legacy names, Unicode rename, local/remote/indirect actions, deletion preserving navigation and save/reopen")
}

@MainActor
private func checkContinuedDevelopment(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let suite = "BotPlusContinued-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument()
    for _ in 0..<12 { document.insert(PDFPage(),at: document.pageCount) }
    let item = PDFDocumentItem(url: root.appendingPathComponent("continued.pdf"),document: document)
    manager.insertDocument(item)
    func line(_ text: String,_ x: Double,_ y: Double,_ width: Double = 210) -> PDFTOCTextLine { PDFTOCTextLine(text: text,bounds: CGRect(x: x,y: y,width: width,height: 12),fontSize: 12) }
    let input = [line("СОДЕРЖАНИЕ",30,760),line("1. Перенесённый",30,720),line("заголовок ...... 3",30,702),line("1.1 Подраздел",45,675,150),line("4",230,675,12),line("Введение .... ii",330,720),line("Другая глава......8",330,690),line("Неверная .... 999",330,660)]
    var options = PDFHeadingOptions(); options.columns = 2; options.logicalLabels = false
    let parsed = PDFTOCRecognizer.candidates(lines: input,bounds: CGRect(x: 0,y: 0,width: 600,height: 800),document: document,options: options)
    expect(parsed.count == 4,"TOC parser reads columns, Roman numbers and separate number fragments and skips out-of-range targets")
    expect(parsed[0].title == "1. Перенесённый заголовок" && parsed[0].page == 2,"TOC wrapped title is joined with correct target")
    expect(parsed[1].level == 1 && parsed[1].page == 3 && parsed[2].page == 1 && parsed[3].page == 7,"column reading order and numbered hierarchy retained")
    options.columns = 0
    expect(PDFTOCRecognizer.candidates(lines: input,bounds: CGRect(x: 0,y: 0,width: 600,height: 800),document: document,options: options).map(\.page) == parsed.map(\.page),"automatic TOC columns match explicit two-column reading")

    let tree = PDFOutline(),remote = PDFOutline(),named = PDFOutline(),reset = PDFOutline(),local = PDFOutline()
    remote.label = "Remote"; remote.action = PDFActionRemoteGoTo(pageIndex: 5,at: CGPoint(x: 9,y: 24),fileURL: root.appendingPathComponent("Русский файл.pdf"))
    named.label = "Next"; named.action = PDFActionNamed(name: .nextPage)
    reset.label = "Reset"; let resetAction = PDFActionResetForm(); resetAction.fields = ["one","два"]; resetAction.fieldsIncludedAreCleared = false; reset.action = resetAction
    local.label = "Local"; local.destination = PDFDestination(page: document.page(at: 2)!,at: CGPoint(x: 18,y: 90)); local.destination?.zoom = 30; local.isOpen = true; local.insertChild(named,at: 0)
    for node in [remote,reset,local] { tree.insertChild(node,at: tree.numberOfChildren) }; document.outlineRoot = tree
    let exchange = (0..<tree.numberOfChildren).map { PDFBookmarkExchange.read(tree.child(at: $0)!,document: document) }
    let decoded = try JSONDecoder().decode([PDFBookmarkExchange].self,from: JSONEncoder().encode(exchange))
    let imported = decoded.compactMap { $0.outline(document: document) }
    expect(imported.count == 3 && (imported[0].action as? PDFActionRemoteGoTo)?.pageIndex == 5,"JSON retains remote GoTo")
    expect((imported[1].action as? PDFActionResetForm)?.fields == ["one","два"] && (imported[1].action as? PDFActionResetForm)?.fieldsIncludedAreCleared == false,"JSON retains reset-form field lists and inclusion rule")
    expect(imported[2].isOpen && imported[2].destination?.zoom == 30 && (imported[2].child(at: 0)?.action as? PDFActionNamed)?.name == .nextPage,"JSON keeps hierarchy, open state, large zoom and named actions")
    let oldJSON = Data(#"[{"title":"Old","page":1,"children":[]}]"#.utf8)
    let oldRecords = try JSONDecoder().decode([PDFBookmarkExchange].self,from: oldJSON)
    expect(oldRecords.first?.outline(document: document)?.label == "Old","legacy JSON remains compatible")
    var invalid = decoded[0]
    invalid.unsupportedAction = "UnknownAction"
    expect(!invalid.valid(pageCount: document.pageCount) && invalid.outline(document: document) == nil,"unsupported action import is rejected without silent data loss")

    let page = document.page(at: 0)!,text = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 30,y: 650,width: 150,height: 30),name: "Текст",choices: [])
    let list = PDFWidgetFactory.make(.formChoice,bounds: CGRect(x: 300,y: 650,width: 150,height: 60),name: "List",choices: ["First","Second"])
    list.values = ["one","two"]; list.isListChoice = true; list.setValue(NSNumber(value: 1<<21),forAnnotationKey: .widgetFieldFlags)
    text.maximumLength = 5; text.hasComb = true; text.widgetStringValue = "ABC"
    let note = PDFAnnotation(bounds: CGRect(x: 5,y: 5,width: 10,height: 10),forType: .text,withProperties: nil); note.contents = "keep note"
    page.addAnnotation(list); page.addAnnotation(note); page.addAnnotation(text)
    let nonWidgetSlots = page.annotations.enumerated().filter { $0.element.type != "Widget" }.map { ($0.offset,ObjectIdentifier($0.element)) }
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 700)); view.installDocument(document)
    coordinator.showFormOrder(item: item,view: view)
    expect(manager.formOrderRequest!.apply([text,list]) == nil,"form order applies through guarded UI transaction")
    expect(page.annotations.filter { $0.type == "Widget" }.map(ObjectIdentifier.init) == [text,list].map(ObjectIdentifier.init) && nonWidgetSlots.allSatisfy { ObjectIdentifier(page.annotations[$0.0]) == $0.1 },"field ordering preserves non-widget annotation slots")
    expect(!PDFFormOrder.apply([text,text],page: page),"duplicate field ordering rejected")
    let dataValues: [String:PDFFDF.FieldValue] = ["Текст":.text("Ёж (test)\nстрока"),"Choice":.array(["one","два"]),"radio":.name("Да/#")]
    let fdfRoundtrip = try PDFFDF.read(PDFFDF.write(dataValues))
    expect(fdfRoundtrip == dataValues,"FDF Unicode, literal text, array and escaped names round trip")
    let xmlRoundtrip = try PDFXFDF.read(PDFXFDF.forms(dataValues))
    expect(xmlRoundtrip.multipleValues["Choice"] == ["one","два"] && xmlRoundtrip.values["Текст"] == "Ёж (test)\nстрока","XFDF retains all multi-select values and Unicode text")
    let indirect = Data("%FDF-1.2\n1 0 obj << /FDF << /Fields [2 0 R] >> >> endobj\n2 0 obj << /T (Parent) /Kids [<< /T (Child) /V (a\\050b\\051\\nline) >>] >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF".utf8)
    let indirectFields = try PDFFDF.read(indirect)
    expect(indirectFields["Parent.Child"] == .text("a(b)\nline"),"FDF indirect objects, nested field paths and octal escapes")
    do { _ = try PDFFDF.read(Data("%FDF-1.2\n1 0 obj << /FDF << /Fields [1 0 R] >> /Kids [1 0 R] >> endobj\ntrailer << /Root 1 0 R >>".utf8)); fatalError("cyclic FDF accepted") } catch { }
    expect(coordinator.applyFDF(["Текст":.text("12345678"),"List":.array(["one","two"])],item: item),"FDF imports known editable fields")
    expect(text.widgetStringValue == "12345" && AnnotationMetadata.formSelections(list) == ["one","two"] && PDFWidgetFactory.stringValue(list) == "one","FDF honors maximum length and safely retains multi-selection values")
    text.isReadOnly = true
    expect(!coordinator.applyFDF(["Текст":.text("replace")],item: item) && text.widgetStringValue == "12345","FDF does not overwrite read-only fields")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!,widgets = saved.page(at: 0)!.annotations.filter { $0.type == "Widget" }
    AnnotationMetadata.restore(saved)
    expect(saved.outlineRoot?.child(at: 2)?.isOpen == true,"bookmark open state survives native PDF serialization")
    expect(widgets.map(\.fieldName) == ["Текст","List"] && widgets[0].hasComb && widgets[1].values == ["one","two"],"field order, Comb and export values survive PDF save/reopen")
    expect(AnnotationMetadata.formSelections(widgets[1]) == ["one","two"],"all FDF multi-selection values survive compatible PDF metadata round trip")
    let selectionStamp = PDFDocumentState.stamp(document)
    AnnotationMetadata.setFormSelections(["one"],on: list)
    expect(PDFDocumentState.stamp(document) != selectionStamp,"changing remaining multi-selection values invalidates cached save state")
    AnnotationMetadata.setFormSelections(["one","two"],on: list)
    expect(coordinator.fdfValues(item)["List"] == .array(["one","two"]),"all compatible multi-selection values export back to FDF")
    expect(PDFFormRule(kind: .integer,minimum: 1,maximum: 10).issue("11",russian: true) != nil && PDFFormRule(kind: .integer).issue("1.5",russian: true) != nil,"numeric form rules enforce type and bounds")
    expect(PDFFormRule(kind: .date).issue("2024-02-29",russian: false) == nil && PDFFormRule(kind: .date).issue("2026-02-29",russian: false) != nil,"date form rules validate actual calendar days")
    text.isReadOnly = false; manager.selectedAnnotation = text; coordinator.showFormRule(item: item)
    let ruleStamp = PDFDocumentState.stamp(document)
    expect(manager.formRuleRequest!.apply(PDFFormRule(kind: .integer,minimum: 0,maximum: 100)) == nil && PDFDocumentState.stamp(document) != ruleStamp,"form rules update guarded metadata and invalidate cached saves")
    let beforeInvalidImport = text.widgetStringValue
    expect(!coordinator.applyFDF(["Текст":.text("invalid")],item: item) && text.widgetStringValue == beforeInvalidImport,"FDF rejects values violating BotPlus rules without overwriting fields")
    expect(coordinator.formIssues(item: item).contains { $0.name == "Текст" },"form report lists current rule violations")

    let measurement = PDFAnnotation(bounds: CGRect(x: 0,y: 0,width: 72,height: 5),forType: .ink,withProperties: nil)
    AnnotationMetadata.setMeasurement(EngineeringMeasure(kind: .distance,points: [.zero,CGPoint(x: 72,y: 0)],scale: EngineeringScale(unit: .mm)),on: measurement)
    AnnotationMetadata.setGroup("test-measure",on: measurement); page.addAnnotation(measurement)
    let label = PDFAnnotation(bounds: CGRect(x: 0,y: 10,width: 140,height: 24),forType: .freeText,withProperties: nil); AnnotationMetadata.setGroup("test-measure",on: label); page.addAnnotation(label)
    manager.selectedAnnotation = measurement
    coordinator.showEngineeringScale(item: item,view: view)
    var scaleOptions = EngineeringScaleOptions(); scaleOptions.selectedOnly = true; scaleOptions.denominator = 100; scaleOptions.unit = .mm
    expect(manager.engineeringScaleRequest!.apply(scaleOptions) == nil && abs(AnnotationMetadata.measurement(measurement)!.value-2540) < 0.001,"measurement scale recalculates existing value")
    expect(label.contents == measurement.contents,"linked measurement label is recalculated")
    expect(page.annotations.filter { AnnotationMetadata.decoration(of: $0) == "engineeringDimension" }.count == 3,"distance calibration creates dimension line and two extension lines")
    expect(page.annotations.contains { $0.type == "Line" && $0.startLineStyle == .closedArrow && $0.endLineStyle == .closedArrow },"dimension line uses native vector arrowheads")
    manager.selectedAnnotation = nil; coordinator.showEngineeringScale(item: item,view: view)
    scaleOptions.selectedOnly = false; scaleOptions.range = "all"
    expect(manager.engineeringScaleRequest!.apply(scaleOptions) == nil && EngineeringCalibration.read(document.page(at: 11)!)?.unit == .mm,"document-wide page calibration applied")
    try manager.saveForClosing(item,to: item.url)
    let calibrated = PDFDocument(url: item.url)!; AnnotationMetadata.restore(calibrated)
    expect(EngineeringCalibration.read(calibrated.page(at: 11)!)?.millimetersPerPoint == (25.4/72)*100,"page calibration survives save/reopen")
    let restored = calibrated.page(at: 0)!.annotations.compactMap(AnnotationMetadata.measurement).first!
    expect(AnnotationMetadata.formRule(calibrated.page(at: 0)!.annotations.first { $0.fieldName == "Текст" }!)?.kind == .integer,"form validation rule survives PDF metadata save/reopen")
    expect(abs(restored.value-2540) < 0.001,"existing measurement metadata survives save/reopen")
    let lineAnnotation = PDFAnnotation(bounds: CGRect(x: 10,y: 20,width: 80,height: 60),forType: .line,withProperties: nil)
    lineAnnotation.startPoint = CGPoint(x: 3,y: 4); lineAnnotation.endPoint = CGPoint(x: 70,y: 50); lineAnnotation.endLineStyle = .openArrow; page.addAnnotation(lineAnnotation)
    manager.selectedAnnotation = lineAnnotation
    coordinator.showAnnotationVertices(item: item,view: view)
    var vertices = manager.annotationVertexRequest!.initial
    expect(vertices[0].vertices[0].point == CGPoint(x: 13,y: 24),"annotation vertex editor uses absolute page coordinates")
    vertices[0].vertices[1].x = 150; vertices[0].vertices[1].y = 120
    expect(manager.annotationVertexRequest!.apply(vertices) == nil && lineAnnotation.endLineStyle == .openArrow,"vertex edit keeps arrow style")
    expect(lineAnnotation.bounds.minX+lineAnnotation.endPoint.x == 150 && lineAnnotation.bounds.minY+lineAnnotation.endPoint.y == 120,"line endpoints updated with rebased annotation bounds")
    let ink = PDFAnnotation(bounds: CGRect(x: 20,y: 30,width: 100,height: 100),forType: .ink,withProperties: nil),stroke = NSBezierPath()
    stroke.move(to: .zero); stroke.line(to: CGPoint(x: 70,y: 0)); stroke.line(to: CGPoint(x: 20,y: 60)); stroke.close(); ink.add(stroke); page.addAnnotation(ink)
    var inkVertices = try PDFAnnotationVertexGeometry.read(ink); inkVertices[0].vertices[1].x = 120
    expect(inkVertices[0].closed && PDFAnnotationVertexGeometry.apply(inkVertices,to: ink),"polygonal Ink vertices preserve path closure")
    let updatedInk = try PDFAnnotationVertexGeometry.read(ink)
    expect(updatedInk[0].vertices[1].x == 120,"Ink local coordinates are correctly rebased")
    let curved = PDFAnnotation(bounds: CGRect(x: 0,y: 0,width: 100,height: 100),forType: .ink,withProperties: nil),curve = NSBezierPath()
    curve.move(to: .zero); curve.curve(to: CGPoint(x: 100,y: 100),controlPoint1: CGPoint(x: 30,y: 0),controlPoint2: CGPoint(x: 70,y: 100)); curved.add(curve)
    do { _ = try PDFAnnotationVertexGeometry.read(curved); fatalError("curved Ink silently flattened") } catch { }
    var rasterOptions = PDFRasterOptions(); rasterOptions.dpi = 72; rasterOptions.mode = 1; rasterOptions.angle = 2
    let rasterBytes = try PDFRasterEngine.process(data: manager.serializedData(item),indices: [0],options: rasterOptions,progress: { _ in })
    let rasterCopy = PDFDocument(data: rasterBytes)!
    expect(rasterCopy.pageCount == 1 && rasterCopy.page(at: 0)!.annotations.isEmpty && document.pageCount == 12,"shared preview/output raster engine creates separate flattened copy")
    rasterOptions.left = 10; rasterOptions.right = 10; rasterOptions.top = 5; rasterOptions.bottom = 5; rasterOptions.normalizePaper = true
    let croppedBytes = try PDFRasterEngine.process(data: manager.serializedData(item),indices: [0],options: rasterOptions,progress: { _ in })
    let cropped = PDFDocument(data: croppedBytes)!,croppedBox = cropped.page(at: 0)!.bounds(for: .mediaBox),originalBox = page.bounds(for: .cropBox)
    expect(abs(croppedBox.width-originalBox.width*0.8) < 0.01 && abs(croppedBox.height-originalBox.height*0.9) < 0.01,"scan border crop and paper normalization preserve physical cropped dimensions")
    try manager.saveForClosing(item,to: item.url)
    let verticesPDF = PDFDocument(url: item.url)!,savedLine = verticesPDF.page(at: 0)!.annotations.first { $0.type == "Line" && $0.endLineStyle == .openArrow }!
    expect(savedLine.bounds.minX+savedLine.endPoint.x == 150,"edited annotation vertices survive save/reopen")
    let gray = CGContext(data: nil,width: 700,height: 700,bitsPerComponent: 8,bytesPerRow: 700,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    gray.setFillColor(CGColor(gray: 1,alpha: 1)); gray.fill(CGRect(x: 0,y: 0,width: 700,height: 700)); gray.setFillColor(CGColor(gray: 0,alpha: 1))
    for y in stride(from: 70,to: 630,by: 30) { gray.fill(CGRect(x: 80,y: y,width: 500,height: 4)) }
    let image = CIImage(cgImage: gray.makeImage()!),rotation = CGAffineTransform(translationX: 350,y: 350).rotated(by: 3*Double.pi/180).translatedBy(x: -350,y: -350)
    let tilted = CIContext().createCGImage(image.transformed(by: rotation).cropped(to: image.extent),from: image.extent)!
    let angle = try PDFRasterEngine.suggestDeskew(image: tilted)
    expect(abs(angle+3) < 0.3,"deskew estimates corrective angle for rotated scan lines (\(angle))")
    let pairs = PDFTextComparison.pairs(left: ["alpha","beta","gamma"],right: ["new","alpha","beta","change","gamma"])
    expect(pairs.count == 5 && pairs[0].0 == nil && pairs[0].1 == 0 && pairs[3].0 == nil && pairs[4].0 == 2 && pairs[4].1 == 4,"text anchors identify inserted pages and retain shifted matches")
    let deletions = PDFTextComparison.pairs(left: ["a","b","c"],right: ["a","c"])
    expect(deletions.count == 3 && deletions[1].0 == 1 && deletions[1].1 == nil,"text anchors identify deleted pages")
    let changes = PDFTextComparison.changes(left: "same\nold words",right: "same\nnew words")
    expect(changes.added == ["new words"] && changes.removed == ["old words"] && !changes.truncated,"text comparison reports only changed lines")
    let leftDoc = PDFDocument(),rightDoc = PDFDocument()
    for _ in 0..<2 { leftDoc.insert(PDFPage(),at: leftDoc.pageCount) }; for _ in 0..<3 { rightDoc.insert(PDFPage(),at: rightDoc.pageCount) }
    let comparison = try PDFVisualComparison.compare(left: PDFDocumentSerializer.data(leftDoc),right: PDFDocumentSerializer.data(rightDoc),offset: 0,tolerance: 20,leftText: ["first","last"],rightText: ["first","new","last"],alignText: true,progress: { _ in })
    expect(comparison.count == 3 && comparison[1].leftPage == nil && comparison[1].rightPage == 1 && comparison[1].addedLines == ["new"],"visual/text comparison uses aligned page pairs")
    let report = PDFTextComparison.html(rows: comparison,leftName: "<script>alert(1)</script>",rightName: "B & C")
    expect(!report.contains("<script>") && report.contains("&lt;script&gt;") && report.contains("data:image/png;base64,"),"HTML comparison report escapes document names and embeds visual diffs")
    let editedPage = PDFOCREditPage(index: 0,mediaBox: CGRect(x: 0,y: 0,width: 612,height: 792),rasterToPage: .identity,lines: [PDFOCRLine(text: "Исправленный текст OCR",bounds: CGRect(x: 20,y: 300,width: 250,height: 20)),PDFOCRLine(text: "Not selected",bounds: CGRect(x: 20,y: 250,width: 200,height: 20),selected: false)])
    let editedOCR = try PDFOCREngine.render(pages: [editedPage]),ocrDocument = PDFDocument(data: editedOCR.layer)!
    expect(editedOCR.lines == 1 && (ocrDocument.string ?? "").contains("Исправленный") && !(ocrDocument.string ?? "").contains("Not selected"),"OCR result editor preserves corrected searchable Unicode and excludes deselected lines")
    var invalidOCR = editedPage; invalidOCR.lines[0].bounds.size.width = 0
    expect(!PDFOCREngine.valid(pages: [invalidOCR]),"OCR metric editor rejects zero-sized text boxes")
    let ocrOverlay = try PDFDocumentExtras.overlay(PDFDocumentSerializer.data(leftDoc),layer: editedOCR.layer,indices: editedOCR.pages)
    let searchable = PDFDocument(data: ocrOverlay)!
    expect(searchable.pageCount == 2 && (searchable.page(at: 0)?.string ?? "").contains("Исправленный"),"reviewed OCR layer overlays original pages without replacing page count")
    let snapData = NSMutableData(); var snapBox = CGRect(x: 0,y: 0,width: 200,height: 200)
    let snapConsumer = CGDataConsumer(data: snapData)!,snapContext = CGContext(consumer: snapConsumer,mediaBox: &snapBox,nil)!
    snapContext.beginPDFPage(nil); snapContext.move(to: CGPoint(x: 10,y: 50)); snapContext.addLine(to: CGPoint(x: 190,y: 50)); snapContext.move(to: CGPoint(x: 100,y: 10)); snapContext.addLine(to: CGPoint(x: 100,y: 190)); snapContext.strokePath(); snapContext.endPDFPage(); snapContext.closePDF()
    let snapSession = try PDFContentSession(data: snapData as Data,pageIndex: 0)
    expect(snapSession.snapCandidate(near: CGPoint(x: 10,y: 50),tolerance: 1)?.kind == .endpoint,"engineering snapping classifies endpoints")
    expect(snapSession.snapCandidate(near: CGPoint(x: 100,y: 100),tolerance: 1)?.kind == .midpoint,"engineering snapping classifies segment midpoints")
    expect(snapSession.snapCandidate(near: CGPoint(x: 100.2,y: 50.1),tolerance: 1)?.kind == .intersection,"engineering snapping classifies intersections with explicit tie priority")
    print("PASS: geometric TOC/JSON actions, forms/FDF, calibration, annotation vertices and shared raster preview/output engine")
}

@MainActor
private func checkTOCAndMerge(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let suite = "BotPlusTOCMerge-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument()
    for _ in 0..<3 { document.insert(PDFPage(),at: document.pageCount) }
    let item = PDFDocumentItem(url: root.appendingPathComponent("toc-and-merge.pdf"),document: document)
    manager.insertDocument(item)
    let tree = PDFOutline(),a = PDFOutline(),b = PDFOutline(),otherPoint = PDFOutline(),otherURL = PDFOutline(),urlA = PDFOutline(),urlB = PDFOutline()
    for node in [a,b,otherPoint] { node.label = "Дубликат"; node.destination = PDFDestination(page: document.page(at: 0)!,at: CGPoint(x: 10,y: 40)) }
    otherPoint.destination = PDFDestination(page: document.page(at: 0)!,at: CGPoint(x: 10,y: 90))
    for node in [urlA,urlB,otherURL] { node.label = "Site"; node.action = PDFActionURL(url: URL(string: "https://example.com/a")!) }
    otherURL.action = PDFActionURL(url: URL(string: "https://example.com/b")!)
    let childA = PDFOutline(),childB = PDFOutline(); childA.label = "First child"; childB.label = "Second child"
    a.insertChild(childA,at: 0); b.insertChild(childB,at: 0)
    for node in [a,b,otherPoint,urlA,urlB,otherURL] { tree.insertChild(node,at: tree.numberOfChildren) }; document.outlineRoot = tree
    var mergeOptions = PDFBookmarkTextOptions()
    let preview = PDFBookmarkTextPlan.make(nodes: [tree,a,b],document: document,operation: .merge,options: mergeOptions)!
    expect(preview.count == 1 && tree.numberOfChildren == 6,"merge preview does not alter the original tree")
    guard case .merge(let groups) = preview[0].mutation else { fatalError("wrong merge payload") }
    expect(groups.count == 2 && groups[0].duplicates.count == 1 && groups[1].duplicates.count == 1,"merge matches complete targets and keeps different coordinates/URLs separate")
    mergeOptions.range = "1"
    let ranged = PDFBookmarkTextPlan.make(nodes: [tree],document: document,operation: .merge,options: mergeOptions)!
    guard case .merge(let rangedGroups) = ranged[0].mutation else { fatalError("wrong range merge payload") }
    expect(rangedGroups.count == 1 && rangedGroups[0].keeper === a,"merge respects page range and excludes URL targets")
    let coordinator = PDFViewer.Coordinator(manager: manager)
    coordinator.showBookmarkTextEditor(item: item,operation: .merge)
    let mergeRequest = manager.bookmarkTextRequest!,undoCount = item.undoHistory.count
    let changes = mergeRequest.load(PDFBookmarkTextOptions())!
    expect(item.undoHistory.count == undoCount,"opening/previewing merge does not create Undo steps")
    expect(mergeRequest.apply(changes) == nil && tree.numberOfChildren == 4,"selected merge groups applied")
    expect(a.numberOfChildren == 2 && a.child(at: 0) === childA && a.child(at: 1) === childB,"merge preserves and appends all descendants")
    expect(otherPoint.parent === tree && otherURL.parent === tree,"different targets survive merging")
    manager.undoDocument(redo: false)
    expect(item.document.outlineRoot?.numberOfChildren == 6 && item.document.outlineRoot?.child(at: 1)?.child(at: 0)?.label == "Second child","one Undo restores duplicates and their original children")
    manager.undoDocument(redo: true)
    expect(item.document.outlineRoot?.numberOfChildren == 4,"merge Redo works")
    try manager.saveForClosing(item,to: item.url)
    let reopenedMerge = PDFDocument(url: item.url)
    expect(reopenedMerge?.outlineRoot?.child(at: 0)?.numberOfChildren == 2,"merged children survive save/reopen (live: \(item.document.outlineRoot?.child(at: 0)?.numberOfChildren ?? -1), saved: \(reopenedMerge?.outlineRoot?.child(at: 0)?.numberOfChildren ?? -1), root: \(reopenedMerge?.outlineRoot?.numberOfChildren ?? -1))")

    // Create a fresh tree for a large, wrapping, multi-column TOC.
    let source = item.document,tocRoot = PDFOutline()
    for index in 0..<90 {
        let node = PDFOutline(); node.label = "Раздел \(index+1) — проверка переноса длинного заголовка и сохранения текста"
        node.destination = PDFDestination(page: source.page(at: index%3)!,at: CGPoint(x: 18,y: 120+index))
        tocRoot.insertChild(node,at: index)
    }
    let huge = PDFOutline(); huge.label = String(repeating: "Длинный заголовок с переносом ",count: 180)+"КонецДлинногоЗаголовка"
    huge.destination = PDFDestination(page: source.page(at: 0)!,at: CGPoint(x: 0,y: 80)); tocRoot.insertChild(huge,at: tocRoot.numberOfChildren)
    source.outlineRoot = tocRoot
    var options = PDFTOCOptions(); options.columns = 2; options.numberOffset = 7; options.numberPrefix = "стр. "
    let entries = try PDFTOCRenderer.entries(document: source,options: options)
    let result = try PDFTOCRenderer.render(entries: entries,options: options)
    let generated = PDFDocument(data: result.data)!
    expect(result.pageCount > 1 && result.entryCount == 91 && source.pageCount == 3,"multi-column preview is paginated without changing source")
    let text = generated.string ?? ""
    expect(text.contains("Раздел") && text.contains("КонецДлинногоЗаголовка"),"TOC keeps searchable Cyrillic and the end of a title spanning columns/pages")
    expect(text.contains("стр. \(result.pageCount+1+7)"),"physical numbers include inserted-page count and custom offset")
    expect(result.links.filter { $0.target.title == huge.label }.count > 1,"oversized title spans multiple linked fragments without truncation")
    for link in result.links {
        expect(generated.page(at: link.pageIndex)!.bounds(for: .mediaBox).contains(link.bounds),"TOC fragment/link remains inside paper")
    }
    if let previewPath = ProcessInfo.processInfo.environment["BOTPLUS_TOC_PREVIEW_PATH"],let image = generated.page(at: 0)?.thumbnail(of: CGSize(width: 1190,height: 1684),for: .mediaBox),let tiff = image.tiffRepresentation,let bitmap = NSBitmapImageRep(data: tiff),let png = bitmap.representation(using: .png,properties: [:]) {
        try png.write(to: URL(fileURLWithPath: previewPath))
    }
    options.columns = 3; options.landscape = true; options.font = 1; options.leaders = 1
    let alternate = try PDFTOCRenderer.render(entries: Array(entries.prefix(12)),options: options)
    let paper = PDFDocument(data: alternate.data)!.page(at: 0)!.bounds(for: .mediaBox)
    expect(paper.width > paper.height && (PDFDocument(data: alternate.data)?.string ?? "").contains("Раздел"),"landscape/three-column serif rendering works")
    options.columns = 1; options.font = 2; options.numbering = 1; options.numberPrefix = "PDF:"
    let labels = try PDFTOCRenderer.render(entries: Array(entries.prefix(3)),options: options)
    expect((PDFDocument(data: labels.data)?.string ?? "").contains("PDF:"+entries[0].logicalLabel),"logical PDF labels are used without physical page shifting")
    options.fontSize = .infinity
    do { _ = try PDFTOCRenderer.render(entries: entries,options: options); fatalError("invalid font accepted") } catch PDFTOCError.options { }

    // Apply the same preview through the actual coordinator, then reopen and undo it.
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 600)); view.installDocument(source)
    coordinator.createTOC(item: item,view: view)
    let request = manager.tocRequest!
    options = PDFTOCOptions(); options.columns = 2
    let built = try request.load(options)
    tocRoot.child(at: 0)?.label = "Changed during preview"
    expect(request.apply(built) != nil && source.pageCount == 3,"stale TOC preview cannot be inserted")
    let fresh = try request.load(options)
    expect(request.apply(fresh) == nil && source.pageCount == 3+fresh.pageCount,"TOC insertion applies all rendered pages")
    let link = source.page(at: 0)!.annotations.first { $0.type == "Link" }!
    expect(link.destination?.page === source.page(at: fresh.pageCount),"TOC links point to original pages after insertion")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!,savedLink = reopened.page(at: 0)!.annotations.first { $0.type == "Link" }!
    expect(savedLink.destination?.page === reopened.page(at: fresh.pageCount),"TOC link targets survive save/reopen")
    manager.undoDocument(redo: false)
    expect(item.pageCount == 3 && item.document.outlineRoot?.child(at: 0)?.label == "Changed during preview","one Undo removes complete inserted TOC and keeps source bookmarks")
    manager.undoDocument(redo: true)
    expect(item.pageCount == 3+fresh.pageCount,"TOC Redo restores complete insertion")
    print("PASS: target-aware duplicate merge/descendants, range/cancel/Undo, multi-column searchable TOC, overflowing titles, numbering/fonts/paper, stale-preview guard and saved navigation links")
}

@MainActor
private func checkBookmarkActions(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let suite = "BotPlusBookmarkActions-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults))
    let document = PDFDocument(); for _ in 0..<3 { document.insert(PDFPage(),at: document.pageCount) }
    let item = PDFDocumentItem(url: root.appendingPathComponent("bookmark-actions.pdf"),document: document)
    manager.insertDocument(item)
    let tree = PDFOutline(),ten = PDFOutline(),two = PDFOutline(),external = PDFOutline(),section = PDFOutline(),broken = PDFOutline(),named = PDFOutline(),remote = PDFOutline()
    ten.label = "Раздел 10"; two.label = "Раздел 2"; external.label = "Website"; section.label = "Section"; broken.label = "Broken"; named.label = "Next"; remote.label = "Other PDF"
    let shared = PDFDestination(page: document.page(at: 1)!,at: CGPoint(x: 22,y: 77)); shared.zoom = 1
    ten.destination = shared; two.action = PDFActionGoTo(destination: shared)
    external.action = PDFActionURL(url: URL(string: "https://example.com")!)
    broken.destination = PDFDestination(page: PDFPage(),at: .zero)
    named.action = PDFActionNamed(name: .nextPage)
    remote.action = PDFActionRemoteGoTo(pageIndex: 1,at: CGPoint(x: 30,y: 40),fileURL: root.appendingPathComponent("unopened-external.pdf"))
    let nestedB = PDFOutline(),nestedA = PDFOutline(); nestedB.label = "B"; nestedA.label = "A"
    nestedB.destination = PDFDestination(page: document.page(at: 2)!,at: .zero)
    nestedA.destination = PDFDestination(page: document.page(at: 0)!,at: .zero)
    section.insertChild(nestedB,at: 0); section.insertChild(nestedA,at: 1)
    for node in [ten,external,two,section,broken,named,remote] { tree.insertChild(node,at: tree.numberOfChildren) }
    document.outlineRoot = tree
    var options = PDFBookmarkTextOptions(); options.zoom = 175
    let zooms = PDFBookmarkTextPlan.make(nodes: [ten,two,external,broken],document: document,operation: .zoom,options: options)!
    expect(zooms.count == 2 && shared.zoom == 1,"zoom preview only includes valid local targets and never mutates")
    PDFBookmarkTextPlan.apply([zooms[1]])
    expect((two.action as? PDFActionGoTo)?.destination.zoom == 1.75 && ten.destination?.zoom == 1,"selective zoom does not mutate shared destinations")
    expect((two.action as? PDFActionGoTo)?.destination.point == CGPoint(x: 22,y: 77),"zoom keeps target coordinates")
    options.zoom = .nan
    expect(PDFBookmarkTextPlan.make(nodes: [ten],document: document,operation: .zoom,options: options) == nil,"invalid zoom rejected")
    options.zoom = 175; options.range = "1"
    expect(PDFBookmarkTextPlan.make(nodes: [ten,two],document: document,operation: .zoom,options: options)!.isEmpty,"zoom respects page range")
    options.range = "all"
    let rows = PDFBookmarkValidator.rows(document: document,russian: true)
    expect(rows.filter { $0.status == .invalid }.map(\.node).contains { $0 === broken },"validator finds orphaned page targets")
    expect(rows.first { $0.node === external }?.status == .external && rows.first { $0.node === remote }?.status == .external,"external links and PDFs are not marked as broken local targets")
    expect(rows.first { $0.node === named }?.status == .other && rows.first { $0.node === section }?.status == .noTarget,"named actions and section headers are classified separately")
    expect(rows.first { $0.node === two }?.page == 1,"explicit GoTo target is resolved")
    expect(rows.first { $0.node === nestedA }?.path == "Section / A","validation retains hierarchical context")

    // Range sorting moves matching siblings within their old slots and leaves URL entries in place.
    options.range = "2"; options.recursive = false
    let partial = PDFBookmarkTextPlan.make(nodes: [tree,section],document: document,operation: .sort,options: options)!
    expect(partial.count == 1 && tree.child(at: 0) === ten,"sort preview does not change the tree")
    PDFBookmarkTextPlan.apply(partial)
    expect(tree.child(at: 0) === two && tree.child(at: 1) === external && tree.child(at: 2) === ten,"natural numeric order and fixed positions outside range")
    expect(section.child(at: 0) === nestedB,"nonrecursive sorting leaves nested groups alone")
    options.range = "all"; options.recursive = true; options.sortMode = 2
    let byPage = PDFBookmarkTextPlan.make(nodes: [tree,section],document: document,operation: .sort,options: options)!
    PDFBookmarkTextPlan.apply(byPage)
    expect(section.child(at: 0) === nestedA && section.child(at: 1) === nestedB,"recursive page order sorts each sibling group independently")
    expect(ten.parent === tree && two.parent === tree && nestedA.parent === section,"sorting preserves parent-child hierarchy")
    broken.removeFromParent()

    // UI transaction guards, single Undo and serialization use the same code as ribbon commands.
    let coordinator = PDFViewer.Coordinator(manager: manager)
    coordinator.showBookmarkTextEditor(item: item,operation: .clearActions)
    let request = manager.bookmarkTextRequest!
    let clear = request.load(PDFBookmarkTextOptions())!
    (remote.action as? PDFActionRemoteGoTo)?.pageIndex = 2
    expect(request.apply(clear.filter { $0.node === external }) != nil && external.action != nil,"remote-action edits invalidate stale previews")
    let fresh = request.load(PDFBookmarkTextOptions())!
    let removalError = request.apply(fresh.filter { $0.node === external })
    expect(removalError == nil && external.action == nil,"only selected action is removed (error: \(removalError ?? "none"), action: \(external.action?.type ?? "none"))")
    expect(external.label == "Website" && section.numberOfChildren == 2 && remote.action != nil,"clear actions preserves titles, hierarchy and unchecked actions")
    manager.undoDocument(redo: false)
    func find(_ title: String) -> PDFOutline? { manager.bookmarkNodes().first { $0.label == title } }
    expect(find("Website")?.action is PDFActionURL,"Undo restores removed URL action")
    expect((find("Other PDF")?.action as? PDFActionRemoteGoTo)?.pageIndex == 2 && (find("Next")?.action as? PDFActionNamed)?.name == .nextPage,"Undo preserves remote and named actions")
    let local = find("Раздел 2")!
    expect((local.destination ?? (local.action as? PDFActionGoTo)?.destination)?.page === item.document.page(at: 1),"Undo rebinds explicit GoTo to restored PDF pages")
    manager.undoDocument(redo: true)
    expect(find("Website")?.action == nil,"Redo reapplies clear actions")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!
    let nodes = (0..<(saved.outlineRoot?.numberOfChildren ?? 0)).compactMap { saved.outlineRoot?.child(at: $0) }
    expect(nodes.first { $0.label == "Website" }?.action == nil,"removed action stays removed after save/reopen")
    expect(nodes.first { $0.label == "Other PDF" }?.action is PDFActionRemoteGoTo,"remote action survives PDF save/reopen")
    expect(nodes.first { $0.label == "Next" }?.action is PDFActionNamed,"named action survives PDF save/reopen")
    coordinator.showBookmarkTextEditor(item: item,operation: .sort)
    let sortRequest = manager.bookmarkTextRequest!
    options = PDFBookmarkTextOptions(); options.sortMode = 1
    let reorder = sortRequest.load(options)!
    let original = manager.bookmarkNodes().map { $0.label ?? "" }
    expect(!reorder.isEmpty && sortRequest.apply(reorder) == nil,"sorting applies through preview transaction")
    manager.undoDocument(redo: false)
    expect(manager.bookmarkNodes().map { $0.label ?? "" } == original,"one Undo restores complete original bookmark order")
    print("PASS: bookmark action/zoom/order previews, range sorting, target diagnostics, stale-action guard, shared destination isolation, Undo/Redo and PDF round trip")
}

extension PDFViewer.Coordinator {
    fileprivate func checkCopy(_ annotation: PDFAnnotation, board: NSPasteboard) -> Bool { copyAnnotationObjects(annotation, board: board) }
    fileprivate func checkPaste(view: PDFViewerView, board: NSPasteboard) { pasteObjects(on: view, board: board) }
    fileprivate func checkClipboardData(_ annotation: PDFAnnotation) -> Data? { annotationClipboardData(annotation) }
    fileprivate func checkClipboardData(_ annotations: [PDFAnnotation]) -> Data? { annotationClipboardData(annotations) }
    fileprivate func checkCopy(_ annotations: [PDFAnnotation],board: NSPasteboard) -> Bool { copyAnnotationObjects(annotations,board: board) }
    fileprivate func checkPasteData(_ data: Data, view: PDFViewerView) -> Bool { pasteAnnotationData(data,on: view) }
}

@MainActor
private func runPDFiumChecks(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("PDFIUM CHECK FAILED: \(message)") }
    }
    // Initialize through the same document-session path before calling fixture APIs.
    let seed = PDFDocument(); let seedPage = PDFPage(); seedPage.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); seed.insert(seedPage,at: 0)
    let initialize = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 16,color: .black)
    _ = try initialize.applying(text: "Seed",fontSize: 16,color: .black)
    let document = FPDF_CreateNewDocument()!
    let page = FPDFPage_New(document,0,612,792)!
    let object = "Helvetica".withCString { FPDFPageObj_NewTextObj(document,$0,16) }!
    let original = "Original PDF content"
    let utf16 = Array(original.utf16) + [0]
    expect(utf16.withUnsafeBufferPointer { FPDFText_SetText(object,$0.baseAddress) } != 0, "fixture text")
    var matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 72,f: 700)
    expect(FPDFPageObj_SetMatrix(object,&matrix) != 0, "fixture matrix")
    expect(FPDFPage_InsertObject(page,object) != 0, "fixture insertion")
    let rectangle = FPDFPageObj_CreateNewRect(400,400,60,60)!
    _ = FPDFPageObj_SetFillColor(rectangle,255,255,0,255); _ = FPDFPath_SetDrawMode(rectangle,FPDF_FILLMODE_WINDING,0)
    expect(FPDFPage_InsertObject(page,rectangle) != 0, "fixture vector")
    expect(FPDFPage_GenerateContent(page) != 0, "fixture content")
    var length = 0
    let bytes = BotPlusPDFium_SaveDocument(document,&length)!
    let data = Data(bytes: bytes,count: length); BotPlusPDFium_Free(bytes)
    FPDF_ClosePage(page); FPDF_CloseDocument(document)
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    expect(session.snapshot.text.contains(original), "reads the original content object")
    let replacement = "Новый исходный текст"
    let edited = try session.applying(text: replacement,fontSize: 18,color: .systemBlue,width: 400)
    let pdf = PDFDocument(data: edited)!
    expect(pdf.page(at: 0)!.string?.contains(replacement) == true, "replacement is searchable PDF page text")
    expect(pdf.page(at: 0)!.string?.contains(original) != true, "old original text is removed, not covered by an annotation")
    expect(pdf.page(at: 0)!.annotations.filter { $0.shouldDisplay || $0.shouldPrint }.isEmpty, "source editing creates no visible or printable overlay annotation")
    let path = root.appendingPathComponent("edited-content.pdf")
    expect(pdf.write(to: path), "modified content saves")
    let reopenedText = PDFDocument(url: path)?.page(at: 0)?.string ?? ""
    if !reopenedText.contains(replacement) {
        FileHandle.standardError.write(Data("PDFKit saved text extraction: \(reopenedText.debugDescription)\n".utf8))
    }
    expect(reopenedText.filter { !$0.isWhitespace }.contains(replacement.filter { !$0.isWhitespace }), "all modified characters survive reopening")
    let memory = edited as NSData
    let checkDoc = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil)!
    let checkPage = FPDF_LoadPage(checkDoc,0)!
    expect(FPDFPage_CountObjects(checkPage) == 2, "editing preserves the vector object")
    FPDF_ClosePage(checkPage); FPDF_CloseDocument(checkDoc)
    let removing = try PDFSourceSession.editing(data: edited,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    let deleted = try removing.applying(text: "",fontSize: 18,color: .black)
    expect(PDFDocument(data: deleted)?.page(at: 0)?.string?.contains(replacement) != true, "source Delete removes the text layer object")
    let adding = try PDFSourceSession.adding(data: deleted,pageIndex: 0,point: CGPoint(x: 72,y: 600),fontSize: 16,color: .black)
    let added = try adding.applying(text: "Вставленный текст\nВторая строка",fontSize: 16,color: .black)
    expect(PDFDocument(data: added)?.page(at: 0)?.string?.contains("Вставленный текст") == true, "native add/paste creates searchable text")
    expect(PDFDocument(data: added)?.page(at: 0)?.string?.contains("Вторая строка") == true, "multiline content text")

    // Quartz commonly wraps imported PDF pages inside a Form XObject.
    let wrapped = NSMutableData()
    let consumer = CGDataConsumer(data: wrapped)!
    var media = CGRect(x: 0,y: 0,width: 612,height: 792)
    let context = CGContext(consumer: consumer,mediaBox: &media,nil)!
    context.beginPDFPage(nil); context.drawPDFPage(PDFDocument(data: data)!.page(at: 0)!.pageRef!); context.endPDFPage(); context.closePDF()
    let formSession = try PDFSourceSession.editing(data: wrapped as Data,pageIndex: 0,point: CGPoint(x: 100,y: 705))
    let changedForm = try formSession.applying(text: "Form text replaced",fontSize: 16,color: .black)
    expect(PDFDocument(data: changedForm)?.page(at: 0)?.string?.contains("Form text replaced") == true, "imported/Form text editing")
    expect(PDFDocument(data: changedForm)?.page(at: 0)?.string?.contains(original) != true, "imported original text removed")
    print("PASS: PDFium original text replacement, Cyrillic, deletion, searchable insertion, vector preservation, and imported PDF content")
}

@MainActor
private func runTextBlockChecks() throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("BLOCK CHECK FAILED: \(message)") }
    }
    // Deliberately continue BT/ET and its font state across /Contents streams,
    // as CAD producers do. Also keep a neighboring column and a vector path.
    let first = "BT /F1 14 Tf 1 0 0 1 72 700 Tm (Fragmented) Tj 1 0 0 1 156 700 Tm (text) Tj\n"
    let second = "1 0 0 1 72 682 Tm (continues here.) Tj 1 0 0 1 380 700 Tm (Neighbor column) Tj ET\n0 0 0 RG 400 400 40 40 re S\n"
    let bold = "BT /F1 14 Tf 1 0 0 1 72 500 Tm (Duplicated) Tj 1 0 0 1 72.01 500 Tm (Duplicated) Tj ET\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 6 0 R >> >> /Contents [4 0 R 5 0 R 7 0 R] >>",
        "<< /Length \(first.utf8.count) >>\nstream\n"+first+"endstream",
        "<< /Length \(second.utf8.count) >>\nstream\n"+second+"endstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length \(bold.utf8.count) >>\nstream\n"+bold+"endstream"
    ]
    var data = Data("%PDF-1.7\n".utf8), offsets = [0]
    for (index,object) in objects.enumerated() {
        offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(object)\nendobj\n".utf8))
    }
    let xref = data.count
    var ending = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { ending += String(format: "%010lld 00000 n \n",Int64(offset)) }
    ending += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(ending.utf8))
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    expect(session.snapshot.fragmentCount >= 3,"word fragments and the next line belong to one paragraph")
    expect(session.snapshot.text.contains("Fragmented text continues here."),"complete paragraph reconstruction")
    expect(!session.snapshot.text.contains("Neighbor"),"adjacent column stays separate")
    let original = try session.applying(text: session.snapshot.text,fontSize: session.snapshot.fontSize,color: session.snapshot.color)
    expect(original == data,"no-op leaves the original PDF byte-for-byte unchanged")
    let editing = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    let replacement = "Fragmented edited text continues here -; Cyrillic: Привет."
    let changed = try editing.applying(text: replacement,fontSize: 14,color: .black,width: 110)
    let page = PDFDocument(data: changed)!.page(at: 0)!
    let text = page.string ?? ""
    let withoutWhitespace = text.filter { !$0.isWhitespace }
    if !withoutWhitespace.contains(replacement.filter { !$0.isWhitespace }) {
        FileHandle.standardError.write(Data("PDFKit column reading order: \(text.debugDescription)\n".utf8))
    }
    let scopedBlock = try PDFSourceSession.editing(data: changed,pageIndex: 0,point: CGPoint(x: 80,y: 705))
    expect(scopedBlock.snapshot.text.filter { !$0.isWhitespace } == replacement.filter { !$0.isWhitespace },"wrapped block retains every character, punctuation and Cyrillic")
    expect(withoutWhitespace.contains("Привет"),"PDFKit also extracts the new Cyrillic word")
    let serialized = PDFDocument(data: changed)!.dataRepresentation()!
    let afterPDFKit = try PDFSourceSession.editing(data: serialized,pageIndex: 0,point: editing.resultingPoint!)
    expect(afterPDFKit.snapshot.text.filter { !$0.isWhitespace } == replacement.filter { !$0.isWhitespace },"block text survives PDFKit serialization")
    expect(abs(afterPDFKit.snapshot.width-110) < 0.01,"block width persists through PDFKit serialization")
    expect(text.contains("Neighbor column"),"text in the following content stream survives save/reopen")
    expect((editing.resultingBounds?.height ?? 0) > editing.snapshot.bounds.height,"block grows vertically instead of clipping new text")
    let memory = changed as NSData
    let doc = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil)!, nativePage = FPDF_LoadPage(doc,0)!
    let paths = (0..<FPDFPage_CountObjects(nativePage)).filter { FPDFPageObj_GetType(FPDFPage_GetObject(nativePage,$0)) == FPDF_PAGEOBJ_PATH }.count
    expect(paths == 1,"preserves unrelated vector content")
    FPDF_ClosePage(nativePage); FPDF_CloseDocument(doc)
    let duplicate = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 100,y: 505))
    expect(duplicate.snapshot.text == "Duplicated","coincident CAD drawing passes become one editable word")
    let duplicateAfterSave = try PDFSourceSession.editing(data: changed,pageIndex: 0,point: CGPoint(x: 100,y: 505))
    expect(duplicateAfterSave.snapshot.text == "Duplicated","duplicate detection also works after page regeneration")
    let invalid = try PDFSourceSession.editing(data: data,pageIndex: 0,point: CGPoint(x: 160,y: 705))
    do {
        _ = try invalid.applying(text: "Unsupported 🦄",fontSize: 14,color: .black)
        fatalError("BLOCK CHECK FAILED: unsupported glyph must be rejected")
    } catch PDFSourceError.unsupportedGlyph { }
    print("PASS: paragraph blocks, separate columns, cross-stream text scopes, wrapping, Unicode punctuation, CAD duplicates, and unsupported glyph protection")
}

@MainActor
private func runInlineTextChecks() throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("INLINE CHECK FAILED: \(message)") } }
    let seed = PDFDocument(), blank = PDFPage(); blank.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); seed.insert(blank,at: 0)
    let adding = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 14,color: .black)
    let data = try adding.applying(text: "Alpha Beta Gamma",fontSize: 14,color: .black,width: 260)
    let previewSession = try PDFSourceSession.editing(data: data,pageIndex: 0,point: adding.resultingPoint!)
    let suppressed = try previewSession.previewWithoutSelectedText()
    expect(PDFDocument(data: suppressed)?.page(at: 0)?.string?.contains("Alpha") != true,"vector preview suppresses the original selected text without a field background")
    expect(PDFDocument(data: data)?.page(at: 0)?.string?.contains("Alpha") == true,"vector preview leaves the real document unchanged")
    let fonts = try PDFSourceSession.documentFonts(data: data)
    expect(Set(NSFontManager.shared.availableFontFamilies).isSubset(of: Set(fonts)),"font catalog contains all system families")
    expect(fonts.contains { $0.contains("Arial") },"font catalog includes embedded PDF font names")
    for name in ["Helvetica","Menlo-Regular","AmericanTypewriter"] {
        guard PDFFontCatalog.font(named: name,size: 14) != nil else { continue }
        let source = try PDFSourceSession.adding(data: seed.dataRepresentation()!,pageIndex: 0,point: CGPoint(x: 72,y: 700),fontSize: 14,color: .black,fontName: name)
        let changed = try source.applying(text: "System font; 123-ABC",fontSize: 14,color: .black)
        let saved = PDFDocument(data: changed)!.dataRepresentation()!
        expect(PDFDocument(data: saved)?.page(at: 0)?.string?.contains("System font; 123-ABC") == true,"system collection/CFF font persists searchable text: \(name)")
    }
    let blocks = try PDFSourceSession.blocks(data: data,pageIndex: 0)
    expect(blocks.count == 1,"catalog shows one frame around the complete text block")
    let session = try PDFSourceSession.editing(data: data,pageIndex: 0,point: adding.resultingPoint!)
    let document = PDFDocument(data: data)!, page = document.page(at: 0)!
    let pdf = PDFView(frame: CGRect(x: 0,y: 0,width: 600,height: 760))
    let window = NSWindow(contentRect: pdf.frame,styleMask: [.titled],backing: .buffered,defer: false)
    window.isReleasedWhenClosed = false; window.contentView = pdf
    pdf.document = document; pdf.scaleFactor = 1; pdf.go(to: page); pdf.layoutDocumentView()
    let model = PDFTextPropertiesModel()
    let inline = PDFInlineTextEditor(snapshot: session.snapshot,page: page,pdfView: pdf,model: model)
    expect(inline.isAttached && model.active,"editor and inspector are active directly on the PDF page")
    expect(pdf.clipsToBounds && inline.editor.clipsToBounds,"PDF editor clips page, text, and overlays to the viewport")
    expect(!inline.editor.drawsBackground,"in-place editor has no white field background")
    expect(inline.quad().count == 4,"selected frame has a real quadrilateral")
    let beta = (inline.editor.string as NSString).range(of: "Beta")
    inline.editor.setSelectedRange(beta)
    inline.apply(.size(24)); inline.apply(.color(.red)); inline.apply(.bold(true))
    let before = inline.attributedText.attributes(at: 0,effectiveRange: nil)
    let selected = inline.attributedText.attributes(at: beta.location,effectiveRange: nil)
    expect((before[.font] as! NSFont).pointSize == 14,"partial formatting leaves neighboring text unchanged")
    expect((selected[.font] as! NSFont).pointSize == 24,"partial selection receives the requested size")
    expect(NSFontManager.shared.traits(of: selected[.font] as! NSFont).contains(.boldFontMask),"partial selection receives bold")
    let numeric = NSTextField(frame: CGRect(x: 5,y: 5,width: 80,height: 24)); pdf.addSubview(numeric)
    _ = window.makeFirstResponder(numeric)
    let numberResponder = window.firstResponder
    let textBeforeGeometry = inline.editor.string
    inline.apply(.angle(12))
    expect(window.firstResponder === numberResponder,"geometry input must not steal focus from its text field")
    expect(inline.editor.string == textBeforeGeometry,"geometry controls must not replace selected document text")
    inline.apply(.angle(0)); numeric.removeFromSuperview()
    inline.editor.setSelectedRange(NSRange(location: 0,length: 0)); inline.apply(.width(300))
    let originalPose = inline.geometry
    inline.beginDrag(.move,at: CGPoint(x: 72,y: 700)); inline.drag(to: CGPoint(x: 102,y: 680)); inline.endDrag()
    expect(abs(inline.geometry.origin.x-originalPose.origin.x-30) < 0.001,"move handle changes PDF coordinates")
    let center = inline.geometry.point(x: inline.width/2,y: inline.ascent-inline.height/2)
    inline.beginDrag(.rotate,at: CGPoint(x: center.x+100,y: center.y)); inline.drag(to: CGPoint(x: center.x+cos(.pi/6)*100,y: center.y+sin(.pi/6)*100)); inline.endDrag()
    expect(abs(inline.geometry.angle-originalPose.angle - .pi/6) < 0.001,"rotation handle changes the text block angle")
    let widthBefore = inline.width
    let first = inline.geometry.point(x: inline.width,y: 0)
    inline.beginDrag(.width(1),at: first); inline.drag(to: inline.geometry.point(x: inline.width+40,y: 0)); inline.endDrag()
    expect(abs(inline.width-widthBefore-40) < 0.001,"side handle stretches the field without changing font size")
    expect((inline.attributedText.attribute(.font,at: 0,effectiveRange: nil) as! NSFont).pointSize == 14,"field stretching preserves font size")
    let edited = try session.applying(text: inline.attributedText.string,fontSize: 14,color: .black,width: inline.width,richText: inline.attributedText,geometry: inline.geometry)
    let reload = try PDFSourceSession.editing(data: edited,pageIndex: 0,point: session.resultingPoint!)
    expect(reload.snapshot.text == "Alpha Beta Gamma","inline edits preserve complete searchable text")
    expect(abs(reload.snapshot.geometry.angle - .pi/6) < 0.001,"rotation persists in the original PDF content")
    let reloadedBeta = (reload.snapshot.attributedText.string as NSString).range(of: "Beta")
    let reloadedFont = reload.snapshot.attributedText.attribute(.font,at: reloadedBeta.location,effectiveRange: nil) as! NSFont
    expect(abs(reloadedFont.pointSize-24) < 0.01,"partial font size persists after saving")
    inline.cancel(); expect(!inline.isAttached && !model.active,"cancel removes the in-place editor and its temporary mask")
    window.close()
    print("PASS: inline text editor, block catalog, partial formatting, move, rotation, field stretching, source save, and cleanup")
}

@MainActor
private func runRibbonFeatureChecks(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("FEATURE CHECK FAILED: "+message) } }
    let document = PDFDocument()
    let first = PDFRasterizer.textPage("Hello annotation tools\nSecond line for markup")!
    document.insert(first,at: 0); document.insert(PDFRasterizer.textPage("Second page")!,at: 1)
    let url = root.appendingPathComponent("ribbon-features.pdf"); expect(document.write(to: url),"create searchable source page")
    let manager = DocumentManager(recent: RecentPDFStore(defaults: UserDefaults(suiteName: "BotPlusNativeChecks")!)); manager.open(url); let item = manager.selected!,page = item.document.page(at: 0)!
    let textOnly = try PDFSourceTextReader.pages(data: Data(contentsOf: url),indices: [0])
    expect(textOnly[0].contains("Hello annotation tools"),"embedded-text reader preserves source text without Vision")
    expect(manager.embeddedText(in: item,indices: [0])?.contains("Hello annotation tools") == true,"document text commands use the existing text layer")
    let pdf = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 800))
    let featureWindow = NSWindow(contentRect: pdf.frame,styleMask: [.titled],backing: .buffered,defer: false)
    featureWindow.isReleasedWhenClosed = false; featureWindow.contentView = pdf
    defer { featureWindow.close() }
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(pdf); coordinator.update(pdf)
    pdf.layoutDocumentView(); pdf.layoutSubtreeIfNeeded(); pdf.go(to: page)
    manager.annotationColor = .purple; manager.annotationOpacity = 0.37
    for (command,type) in [(ViewerCommand.highlight,"Highlight"),(.underline,"Underline"),(.strike,"StrikeOut")] {
        pdf.setCurrentSelection(page.selection(for: page.bounds(for: .cropBox)),animate: false)
        coordinator.checkCommand(command,view: pdf)
        let markup = page.annotations.filter { $0.type == type }
        if markup.isEmpty { print("MARKUP DIAGNOSTIC",page.string ?? "nil",pdf.currentSelection?.string ?? "nil",pdf.document === item.document); fflush(nil) }
        expect(!markup.isEmpty,"working "+type); expect(abs(Double(AnnotationMetadata.alpha(of: markup[0]))-0.37) < 0.01,"markup uses selected opacity")
        expect(AnnotationMetadata.group(of: markup[0]) != nil,"multiline markup is grouped for property changes")
    }
    for tool in [PDFTool.rectangle,.ellipse,.line,.arrow,.cloud,.pencil] {
        let count = page.annotations.count
        pdf.checkDraw(page: page,start: CGPoint(x: 70,y: 400),end: CGPoint(x: 180,y: 480),tool: tool)
        expect(page.annotations.count == count+1,"draw tool creates a real annotation: "+String(describing: tool))
        if tool == .pencil || tool == .cloud { expect(!(page.annotations.last!.paths ?? []).isEmpty,"ink annotation has vector paths") }
    }
    let stamp = PDFAnnotation(bounds: CGRect(x: 200,y: 250,width: 180,height: 44),forType: .freeText,withProperties: nil)
    stamp.contents = "APPROVED"; stamp.font = .boldSystemFont(ofSize: 18); stamp.fontColor = .red; stamp.color = .clear
    let border = PDFBorder(); border.lineWidth = 2; stamp.border = border; page.addAnnotation(stamp)
    let note = PDFAnnotation(bounds: CGRect(x: 240,y: 220,width: 24,height: 24),forType: .text,withProperties: nil); note.contents = "Persistent note"; note.iconType = .note; page.addAnnotation(note)
    let link = PDFAnnotation(bounds: CGRect(x: 250,y: 180,width: 80,height: 20),forType: .link,withProperties: nil); link.action = PDFActionURL(url: URL(string: "https://github.com/Davud77/BotPlus-PDF-Editor")!); page.addAnnotation(link)
    for (offset,tool) in [PDFTool.formText,.formCheckbox,.formRadio,.formChoice,.formButton].enumerated() {
        let widget = PDFWidgetFactory.make(tool,bounds: CGRect(x: 300,y: 400-offset*36,width: 180,height: 28),name: "Field\(offset)",choices: ["Yes","No"])
        if tool == .formText { widget.widgetStringValue = "Filled text" }
        if tool == .formCheckbox { widget.buttonWidgetState = .onState }
        page.addAnnotation(widget)
    }
    manager.addBookmark(title: "Zebra",page: page); manager.addBookmark(title: "Alpha",page: item.document.page(at: 1)!)
    manager.addBookmark(title: "Alpha",page: item.document.page(at: 1)!)
    let initialOutline = manager.bookmarkRoot()!; coordinator.sortBookmarks(initialOutline); coordinator.mergeBookmarks(initialOutline,document: item.document)
    expect(initialOutline.numberOfChildren == 2 && initialOutline.child(at: 0)?.label == "Alpha","bookmarks sort and merge duplicates")
    manager.selectedOutline = nil
    let beforeUndo = item.pageCount
    item.historyDate = .distantPast
    coordinator.checkCommand(.duplicatePageAt(1),view: pdf)
    manager.undoDocument(redo: false); expect(item.pageCount == beforeUndo,"undo restores document pages")
    manager.undoDocument(redo: true); expect(item.pageCount == beforeUndo+1,"redo restores page operation")
    manager.undoDocument(redo: false); coordinator.update(pdf)
    coordinator.createTOC(item: item,view: pdf)
    let toc = manager.tocRequest!,tocResult = try toc.load(PDFTOCOptions())
    expect(pdf.document === item.document,"TOC preview view remains attached to the current document")
    let stableStamp = PDFDocumentState.stamp(item.document)
    expect((0..<5).allSatisfy { _ in PDFDocumentState.stamp(item.document) == stableStamp },"rich annotation state fingerprint is stable across repeated PDFKit reads")
    let tocError = toc.apply(tocResult)
    expect(tocError == nil,"TOC preview applies through the current editor workflow: "+(tocError ?? ""))
    expect(item.pageCount == 3 && (item.document.page(at: 0)?.string ?? "").contains("СОДЕРЖАНИЕ"),"TOC creates a searchable PDF page")
    expect(ThumbnailGestureView.zoom(0.5,delta: 0.2) > 0.5,"pinch-out increases thumbnail size")
    expect(ThumbnailGestureView.zoom(0.5,delta: -0.2) < 0.5,"pinch-in decreases thumbnail size")
    expect(ThumbnailGestureView.zoom(0.99,delta: 2) == 1 && ThumbnailGestureView.zoom(0.01,delta: -2) == 0,"thumbnail gesture range is clamped")
    let gesture = ThumbnailGestureView(frame: .zero); gesture.manager = manager
    manager.thumbnailZoom = 0.5
    gesture.adjust(0.1); gesture.adjust(0.1)
    gesture.flush()
    expect(abs(manager.thumbnailZoom-0.65) < 0.00001,"thumbnail gesture deltas coalesce without a focused thumbnail")
    let cache = PDFThumbnailCache(),key = UUID()
    let one = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 100,ratio: 792/612)
    let two = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 101,ratio: 792/612)
    let enlarged = cache.image(page: page,documentID: key,index: 0,revision: 1,width: 600,ratio: 792/612,interactive: true)
    expect(one === two && two === enlarged && cache.renderCount == 1,"thumbnail gestures reuse the current raster through the whole width range")
    _ = cache.image(page: page,documentID: key,index: 0,revision: 2,width: 100,ratio: 792/612)
    expect(cache.renderCount == 2,"document edits invalidate thumbnail content")
    _ = cache.image(page: page,documentID: key,index: 0,revision: 2,width: 600,ratio: 792/612)
    expect(cache.renderCount == 3,"thumbnail detail upgrades after interactive zoom")
    let panel = PanelWorkspaceModel(); panel.setWidth(380,for: .thumbnails); panel.select(.thumbnails); panel.select(.bookmarks)
    expect(panel.configuration(for: .bookmarks).width == 380,"switching left panels keeps the dock width")
    let output = root.appendingPathComponent("ribbon-features-saved.pdf"); AnnotationMetadata.prepareForSave(item.document)
    expect(item.document.write(to: output),"save all feature annotations")
    let reopened = PDFDocument(url: output)!; AnnotationMetadata.restore(reopened)
    let annotations = (0..<reopened.pageCount).flatMap { reopened.page(at: $0)?.annotations ?? [] }
    for type in ["Text","Link","Ink","Circle","Square","Highlight","Underline","StrikeOut","Widget"] { expect(annotations.contains { $0.type == type },"persist "+type) }
    expect(annotations.contains { $0.contents == "APPROVED" },"persist engineering text stamp")
    expect(annotations.contains { $0.fieldName == "Field0" && $0.widgetStringValue == "Filled text" },"persist form input")
    expect(reopened.outlineRoot?.numberOfChildren == 2,"persist outline hierarchy")
    let image = NSImage(size: CGSize(width: 16,height: 16),flipped: false) { rect in NSColor.red.setFill(); NSBezierPath(rect: rect).fill(); return true }
    let imageRef = image.cgImage(forProposedRect: nil,context: nil,hints: nil)!
    let imageData = try PDFSourceSession.insertingImage(data: item.document.dataRepresentation()!,pageIndex: 1,image: imageRef,bounds: CGRect(x: 80,y: 60,width: 100,height: 100))
    let imageInfo = try PDFSourceSession.objectInfo(data: imageData,pageIndex: 1,point: CGPoint(x: 120,y: 100))
    expect(imageInfo?.kind == "image" && imageInfo?.pixelSize?.width == CGFloat(imageRef.width),"inserted image retains real pixel dimensions independently of Retina backing scale")
    let imageDoc = PDFDocument(data: imageData)!
    expect((imageDoc.page(at: 1)?.string ?? "").contains("Hello annotation"),"image insertion preserves neighboring text")
    expect(imageDoc.dataRepresentation() != nil,"inserted image survives PDFKit persistence")
    coordinator.detach()
    print("PASS: colored markup, vector drawings, notes, stamps, links, forms, bookmarks/TOC, fixed dock widths, and PDF image insertion")
}

@MainActor
private func checkRelease12(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let suite = "BotPlusRelease12Checks-"+UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = RecentPDFStore(defaults: defaults)
    for index in 0..<12 {
        let url = root.appendingPathComponent("recent-\(index).pdf")
        try Data(repeating: 0,count: index+1).write(to: url); store.remember(url)
    }
    expect(store.files.count == 10,"recent list is capped at 10")
    expect(store.files.first?.name == "recent-11.pdf","recent list is newest first")
    store.remember(root.appendingPathComponent("recent-5.pdf"))
    expect(store.files.count == 10 && store.files.first?.name == "recent-5.pdf","recent duplicate moves to front")
    expect(store.files.first?.size == 6,"recent list stores actual byte size")
    let reloaded = RecentPDFStore(defaults: defaults)
    expect(reloaded.files.map(\.path) == store.files.map(\.path),"recent list persists")
    let recentURL = try reloaded.resolve(reloaded.files[0]); expect(recentURL.lastPathComponent == "recent-5.pdf","recent path can be resolved")
    expect(ReleaseUpdate.isNewer("v1.2.1",than: "1.2"),"patch update comparison")
    expect(!ReleaseUpdate.isNewer("v1.2",than: "1.2"),"same release isn't an update")
    expect(!ReleaseUpdate.isNewer("v1.1.2",than: "1.2"),"older release isn't an update")
    expect(!ReleaseUpdate.isNewer("https://invalid.example",than: "1.2"),"malformed update tag is rejected")
    expect(PDFPageRange.parse("1–3, 5, 2",count: 6) == [0,1,2,4],"page range parsing, normalization and duplicate removal")
    expect(PDFPageRange.parse("4-2",count: 6) == nil,"reverse page range is rejected")
    expect(PDFPageRange.parse("0,7",count: 6) == nil,"out-of-bounds range is rejected")
    let manager = DocumentManager(recent: store)
    manager.createBlankDocument()
    expect(manager.selected?.isUntitled == true && manager.selected?.pageCount == 1,"start-screen blank command")
    expect(store.files.count == 10,"unsaved blank files never enter recent list")
    manager.perform(.feature("license")); expect(manager.isLicensePresented,"license works without a file dependency")
    let item = manager.selected!
    let before = manager.contentRevision
    manager.perform(.tool(.textSelection)); manager.perform(.layout(.single)); manager.refreshPresentation()
    expect(manager.contentRevision == before,"presentation-only changes don't invalidate thumbnail/text caches")
    _ = try manager.serializedData(item)
    let count = manager.serializationCount
    _ = try manager.serializedData(item); _ = manager.snapshot(item)
    expect(manager.serializationCount == count,"source and undo share immutable serialized bytes")
    manager.send(.refresh); _ = try manager.serializedData(item)
    expect(manager.serializationCount == count+1,"real document refresh invalidates serialized snapshot")
    let page = item.document.page(at: 0)!
    let liveField = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 20,y: 100,width: 100,height: 20),name: "native-value",choices: [])
    page.addAnnotation(liveField); manager.send(.refresh)
    _ = try manager.serializedData(item); let beforeField = manager.serializationCount
    liveField.widgetStringValue = "Filled through PDFKit"
    let fieldData = try manager.serializedData(item)
    expect(manager.serializationCount == beforeField+1,"native field edits invalidate cache without a ribbon refresh")
    let reopenedField = PDFDocument(data: fieldData)?.page(at: 0)?.annotations.first { $0.fieldName == "native-value" }
    expect(reopenedField?.widgetStringValue == "Filled through PDFKit","native field value survives cached save")
    for value in ["Second fill","Third fill"] {
        liveField.widgetStringValue = value
        let bytes = try manager.serializedData(item)
        let currentField = PDFDocument(data: bytes)?.page(at: 0)?.annotations.first { $0.fieldName == "native-value" }
        expect(currentField?.widgetStringValue == value,"fresh writer doesn't return a previous native form value")
    }
    page.removeAnnotation(liveField); manager.send(.refresh)
    _ = try manager.serializedData(item)
    let shape = PDFAnnotation(bounds: CGRect(x: 60,y: 50,width: 70,height: 90),forType: .square,withProperties: nil)
    shape.contents = "Live shape"; shape.color = .systemBlue; page.addAnnotation(shape)
    let shapeBytes = try manager.serializedData(item)
    expect(PDFDocument(data: shapeBytes)?.page(at: 0)?.annotations.contains(where: { $0.contents == "Live shape" }) == true,"byte-backed writer persists new annotations")
    shape.bounds = CGRect(x: 30,y: 40,width: 50,height: 60); shape.contents = "Moved shape"
    let movedBytes = try manager.serializedData(item)
    let savedShape = PDFDocument(data: movedBytes)?.page(at: 0)?.annotations.first { $0.contents == "Moved shape" }
    expect(savedShape?.bounds == shape.bounds,"byte-backed writer persists changed annotation bounds/content")
    page.removeAnnotation(shape); manager.send(.refresh)
    expect(PDFPageOperations.crop(item.document,indices: [0],left: 10,right: 20,top: 30,bottom: 40),"independent margins apply")
    let box = page.bounds(for: .cropBox),media = page.bounds(for: .mediaBox)
    expect(box.minX == media.minX+10 && box.minY == media.minY+40 && box.width == media.width-30 && box.height == media.height-70,"independent crop geometry")
    expect(!PDFPageOperations.crop(item.document,indices: [0],left: .infinity,right: 0,top: 0,bottom: 0),"invalid crop doesn't partially change PDF")
    expect(page.bounds(for: .cropBox) == box,"failed crop is atomic")
    let field1 = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 20,y: 200,width: 100,height: 20),name: "one",choices: [])
    let field2 = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 180,y: 100,width: 60,height: 30),name: "two",choices: [])
    PDFPageOperations.align([field1,field2],mode: 2)
    expect(field1.bounds.maxX == field2.bounds.maxX,"form fields align right without changing widths")
    PDFPageOperations.align([field1,field2],mode: 4)
    expect(field1.bounds.maxY == field2.bounds.maxY,"form fields align top")
    let replacement = PDFDocument(); let newPage = PDFRasterizer.textPage("Replacement")!; replacement.insert(newPage,at: 0)
    let rootOutline = PDFOutline(),node = PDFOutline(); node.label = "Retained bookmark"; node.destination = PDFDestination(page: page,at: CGPoint(x: 40,y: 400)); rootOutline.insertChild(node,at: 0); item.document.outlineRoot = rootOutline
    expect(PDFPageOperations.replace(item.document,targets: [0],source: replacement,sources: [0]),"pages can be replaced")
    expect(item.document.pageCount == 1 && node.destination?.page === item.document.page(at: 0),"replacement repairs bookmark targets")
    let url = root.appendingPathComponent("replaced-check.pdf"); try PDFDocumentSerializer.save(item.document,to: url)
    expect((PDFDocument(url: url)?.page(at: 0)?.string ?? "").contains("Replacement"),"replacement survives save/reopen")
    _ = try manager.serializedData(item)
    node.label = "Updated after initial save"; node.destination?.zoom = 2
    item.document.documentAttributes = [PDFDocumentAttribute.titleAttribute:"Live title"]
    let bookmarkBytes = try manager.serializedData(item),bookmarkPDF = PDFDocument(data: bookmarkBytes)
    expect(bookmarkPDF?.outlineRoot?.child(at: 0)?.label == "Updated after initial save","live bookmark changes survive byte-backed snapshots")
    expect(bookmarkPDF?.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Live title","live attributes survive byte-backed snapshots")
    let loaded = PDFDocument(data: bookmarkBytes)!
    let streamItem = PDFDocumentItem(url: url,document: loaded,preserveStreams: true)
    manager.insertDocument(streamItem); manager.seedSerializedData(bookmarkBytes,item: streamItem)
    expect(streamItem.canPreserveStreams,"loaded complete PDF is eligible for stream-preserving snapshots")
    let streamPage = loaded.page(at: 0)!
    let streamField = PDFWidgetFactory.make(.formText,bounds: CGRect(x: 10,y: 80,width: 120,height: 30),name: "stream-field",choices: [])
    streamPage.addAnnotation(streamField)
    for value in ["First native value","Changed native value"] {
        streamField.widgetStringValue = value
        let bytes = try manager.serializedData(streamItem)
        let saved = PDFDocument(data: bytes)?.page(at: 0)?.annotations.first { $0.fieldName == "stream-field" }
        expect(saved?.widgetStringValue == value,"stream-preserving writer records repeated native field edits")
    }
    loaded.outlineRoot?.child(at: 0)?.label = "Stream bookmark update"
    let streamBytes = try manager.serializedData(streamItem)
    expect(PDFDocument(data: streamBytes)?.outlineRoot?.child(at: 0)?.label == "Stream bookmark update","stream-preserving writer records live bookmark edits")
    loaded.insert(PDFRasterizer.textPage("New page")!,at: 0)
    expect(!streamItem.canPreserveStreams,"page graph changes disable stream preservation")
    print("PASS: recent files, blank start action, updates, cache invalidation, margins, field alignment and page replacement")
}

@MainActor
private func benchmarkRelease12(root: URL,path: String) throws {
    let source = URL(fileURLWithPath: path)
    let lease = FileAccessLease(source); _ = lease
    var timings: [[String:Any]] = []
    func measure<T>(_ label: String,_ work: () throws -> T) rethrows -> T {
        let begin = Date.timeIntervalSinceReferenceDate
        let result = try work()
        let milliseconds = (Date.timeIntervalSinceReferenceDate-begin)*1000
        timings.append(["operation":label,"milliseconds":milliseconds]); print(String(format: "PERF %@ %.2f ms",label,milliseconds)); fflush(nil); return result
    }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: UserDefaults(suiteName: "BotPlusBenchmark")!))
    measure("open and seed immutable source",{ manager.open(source) })
    guard let item = manager.selected else { throw PDFSourceError.document }; let document = item.document
    let data = try measure("serialized snapshot cold",{ try manager.serializedData(item) })
    _ = try measure("serialized snapshot warm (20 requests)",{
        for _ in 0..<20 { _ = try manager.serializedData(item) }; return true
    })
    let cache = PDFThumbnailCache()
    for index in [0,2].filter({ $0 < document.pageCount }) {
        guard let page = document.page(at: index) else { continue }
        let box = page.bounds(for: .cropBox),ratio = box.height/max(1,box.width)
        _ = measure("thumbnail page \(index+1) cold",{ cache.image(page: page,documentID: item.id,index: index,revision: 0,width: 150,ratio: ratio) })
        _ = measure("thumbnail page \(index+1) warm (20 requests)",{
            for _ in 0..<20 { _ = cache.image(page: page,documentID: item.id,index: index,revision: 0,width: 150,ratio: ratio) }; return true
        })
    }
    let indices = ProcessInfo.processInfo.environment["BOTPLUS_BENCH_PAGES"].flatMap { PDFPageRange.parse($0,count: document.pageCount) } ?? [0]
    for index in indices where index < document.pageCount {
        let blocks = try measure("text block catalog page \(index+1)",{ try PDFSourceSession.blocks(data: data,pageIndex: index) })
        if let first = blocks.first {
            _ = try measure("text editor session page \(index+1)",{ try PDFSourceSession.editing(data: data,pageIndex: index,point: first.point) })
        }
    }
    _ = try measure("system and embedded font catalog",{ try PDFSourceSession.documentFonts(data: data) })
    let output = root.appendingPathComponent("benchmark-copy.pdf")
    try measure("save temporary copy",{ try PDFDocumentSerializer.write(try manager.serializedData(item),to: output) })
    if let page = document.page(at: 0) {
        let annotation = PDFAnnotation(bounds: CGRect(x: 20,y: 20,width: 40,height: 40),forType: .square,withProperties: nil)
        page.addAnnotation(annotation); manager.send(.refresh)
        let edited = try measure("snapshot after annotation edit",{ try manager.serializedData(item) })
        let originalText = try PDFSourceTextReader.pages(data: data),savedText = try PDFSourceTextReader.pages(data: edited)
        guard originalText.count == savedText.count else { fatalError("Benchmark save changed page count") }
        for index in originalText.indices {
            let original = originalText[index].filter { !$0.isWhitespace },saved = savedText[index].filter { !$0.isWhitespace }
            if original != saved {
                let sameScalars = original.unicodeScalars.map(\.value).sorted() == saved.unicodeScalars.map(\.value).sorted()
                print("PERF text extraction page \(index+1): original \(original.count), saved \(saved.count), same scalar multiset \(sameScalars)")
                fflush(nil)
                guard sameScalars else { fatalError("Benchmark save changed searchable characters") }
            }
        }
        func artwork(_ bytes: Data) throws -> [[Int]] {
            let storage = bytes as NSData
            guard let native = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
            defer { FPDF_CloseDocument(native) }
            var pages: [[Int]] = []
            func count(_ object: FPDF_PAGEOBJECT,depth: Int,into counts: inout [Int]) {
                guard depth < 32 else { return }
                let kind = FPDFPageObj_GetType(object)
                if kind == FPDF_PAGEOBJ_PATH { counts[0] += 1 }
                if kind == FPDF_PAGEOBJ_IMAGE { counts[1] += 1 }
                if kind == FPDF_PAGEOBJ_FORM {
                    for index in 0..<max(0,FPDFFormObj_CountObjects(object)) {
                        if let child = FPDFFormObj_GetObject(object,UInt(index)) { count(child,depth: depth+1,into: &counts) }
                    }
                }
            }
            for index in 0..<FPDF_GetPageCount(native) {
                guard let page = FPDF_LoadPage(native,index) else { throw PDFSourceError.page }
                var counts = [0,0]
                for index in 0..<max(0,FPDFPage_CountObjects(page)) { if let object = FPDFPage_GetObject(page,index) { count(object,depth: 0,into: &counts) } }
                pages.append(counts); FPDF_ClosePage(page)
            }
            return pages
        }
        guard try artwork(data) == artwork(edited) else { fatalError("Benchmark save changed vector/image object counts") }
        print("PASS: benchmark annotation save preserves searchable characters and vector/image counts on every page")
        try measure("save edited temporary copy",{ try PDFDocumentSerializer.write(try manager.serializedData(item),to: output) })
    }
    let report: [String:Any] = ["appVersion":BotPlusBrand.version,"pageCount":document.pageCount,"inputBytes":data.count,"serializationCount":manager.serializationCount,"thumbnailRenders":cache.renderCount,"timings":timings]
    let reportData = try JSONSerialization.data(withJSONObject: report,options: [.prettyPrinted,.sortedKeys])
    if let reportPath = ProcessInfo.processInfo.environment["BOTPLUS_BENCH_REPORT"] { try reportData.write(to: URL(fileURLWithPath: reportPath)) }
    print("PERF: report complete; source PDF was read only")
}

@MainActor
private func checkContentEditor(root: URL) throws {
    func expect(_ value: @autoclosure () throws -> Bool,_ message: String) rethrows { if try !value() { fatalError("CONTENT CHECK FAILED: "+message) } }
    _ = PDFiumRuntime.ready
    let document = FPDF_CreateNewDocument()!,page = FPDFPage_New(document,0,612,792)!
    let rectangle = FPDFPageObj_CreateNewRect(100,100,90,60)!
    _ = FPDFPageObj_SetFillColor(rectangle,0,255,0,180); _ = FPDFPageObj_SetStrokeColor(rectangle,255,0,0,255)
    _ = FPDFPageObj_SetStrokeWidth(rectangle,2); _ = FPDFPath_SetDrawMode(rectangle,FPDF_FILLMODE_WINDING,1)
    FPDFPage_InsertObject(page,rectangle)
    let diagonal = FPDFPageObj_CreateNewPath(220,200)!
    _ = FPDFPath_LineTo(diagonal,320,300); _ = FPDFPageObj_SetStrokeColor(diagonal,0,0,0,255)
    _ = FPDFPageObj_SetStrokeWidth(diagonal,2); _ = FPDFPath_SetDrawMode(diagonal,FPDF_FILLMODE_NONE,1)
    FPDFPage_InsertObject(page,diagonal); expect(FPDFPage_GenerateContent(page) != 0,"fixture generation")
    var size = 0; let pointer = BotPlusPDFium_SaveDocument(document,&size)!
    let fixture = Data(bytes: pointer,count: size); BotPlusPDFium_Free(pointer); FPDF_ClosePage(page); FPDF_CloseDocument(document)
    let adding = try PDFSourceSession.adding(data: fixture,pageIndex: 0,point: CGPoint(x: 20,y: 700),fontSize: 14,color: .black)
    let data = try adding.applying(text: "Untouched",fontSize: 14,color: .black)
    let session = try PDFContentSession(data: data,pageIndex: 0)
    let selected = session.select(at: CGPoint(x: 140,y: 130),tolerance: 3)!
    expect(selected.kind == "path" && selected.fillEnabled,"selects interior of a real filled vector object")
    expect(session.select(at: CGPoint(x: 270,y: 250),tolerance: 3)?.kind == "path","selects diagonal by path geometry")
    expect(session.select(at: CGPoint(x: 220,y: 290),tolerance: 3) == nil,"bounding box corner away from a diagonal does not select it")
    let target = selected.bounds.offsetBy(dx: 30,dy: 40)
    let style = PDFContentSession.Style(stroke: .blue,fill: .yellow,width: 3,opacity: 0.4,strokeEnabled: true,fillEnabled: true)
    let edited = try session.applying(index: selected.index,bounds: target,rotation: .pi/2,style: style)
    let editedSession = try PDFContentSession(data: edited,pageIndex: 0)
    let changed = editedSession.objects.first { $0.kind == "path" && ($0.fill?.redComponent ?? 0) > 0.9 }!
    expect(abs(changed.bounds.midX-target.midX) < 0.1 && abs(changed.bounds.midY-target.midY) < 0.1,"rotation/movement preserve the intended center")
    expect(abs(changed.opacity-0.4) < 0.01 && abs(changed.lineWidth-3) < 0.01,"stroke, color and opacity persist")
    try expect(try PDFSourceTextReader.pages(data: edited).joined().contains("Untouched"),"unrelated original text survives vector editing")
    expect(editedSession.objects.filter { $0.kind == "path" }.count == 2,"unrelated paths survive")
    let clipboard = try editedSession.clipboard(index: changed.index)
    let pastedSession = try PDFContentSession(data: edited,pageIndex: 0)
    let pasted = try pastedSession.pasting(clipboard,at: CGPoint(x: 50,y: 500))
    let pastedInfo = pastedSession.result!
    expect(pastedInfo.kind == "group" && abs(pastedInfo.bounds.minX-50) < 1 && abs(pastedInfo.bounds.maxY-500) < 1,"vector clipboard paste positions a reusable PDF group")
    try expect(try PDFSourceTextReader.pages(data: pasted).joined().contains("Untouched"),"paste retains page text")
    let deleting = try PDFContentSession(data: edited,pageIndex: 0)
    let deleted = try deleting.applying(index: changed.index,bounds: changed.bounds,rotation: 0,delete: true)
    try expect(try PDFContentSession(data: deleted,pageIndex: 0).objects.filter { $0.kind == "path" }.count == 1,"delete removes only the selected path")
    func image(_ color: CGColor,_ width: Int,_ height: Int) -> CGImage {
        let context = CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color); context.fill(CGRect(x: 0,y: 0,width: width,height: height)); return context.makeImage()!
    }
    let imageData = try PDFSourceSession.insertingImage(data: edited,pageIndex: 0,image: image(CGColor(red: 1,green: 0,blue: 0,alpha: 1),24,16),bounds: CGRect(x: 400,y: 300,width: 60,height: 40))
    let imageSession = try PDFContentSession(data: imageData,pageIndex: 0),info = imageSession.objects.first { $0.kind == "image" }!
    let replaced = try imageSession.applying(index: info.index,bounds: info.bounds,rotation: 0,style: .init(stroke: .black,fill: .black,width: 1,opacity: 0.5,strokeEnabled: false,fillEnabled: true),image: image(CGColor(red: 0,green: 1,blue: 0,alpha: 1),36,12))
    let replacedInfo = try PDFContentSession(data: replaced,pageIndex: 0).objects.first { $0.kind == "image" }!
    expect(replacedInfo.pixelSize == CGSize(width: 36,height: 12),"image replacement keeps placement and changes pixel data")
    expect(abs(replacedInfo.bounds.minX-info.bounds.minX) < 0.01,"image replacement retains its transform")
    let imageStorage = replaced as NSData
    let renderDocument = FPDF_LoadMemDocument64(imageStorage.bytes,imageStorage.length,nil)!,renderPage = FPDF_LoadPage(renderDocument,0)!
    let bitmap = FPDFBitmap_Create(612,792,1)!
    FPDFBitmap_FillRect(bitmap,0,0,612,792,0xffffffff)
    FPDF_RenderPageBitmap(bitmap,renderPage,0,0,612,792,0,0)
    let pixels = FPDFBitmap_GetBuffer(bitmap)!.assumingMemoryBound(to: UInt8.self)
    let offset = (792-320)*Int(FPDFBitmap_GetStride(bitmap))+430*4
    expect(pixels[offset+1] > 245 && pixels[offset] > 110 && pixels[offset] < 145 && pixels[offset+2] > 110 && pixels[offset+2] < 145,"image opacity affects rendered pixels rather than only inspector state")
    FPDFBitmap_Destroy(bitmap); FPDF_ClosePage(renderPage); FPDF_CloseDocument(renderDocument)
    let pdf = PDFDocument(data: replaced)!
    let saveURL = root.appendingPathComponent("content-editor.pdf")
    try PDFDocumentSerializer.save(pdf,to: saveURL)
    if let destination = ProcessInfo.processInfo.environment["BOTPLUS_GUI_FIXTURE"] { try Data(contentsOf: saveURL).write(to: URL(fileURLWithPath: destination)) }
    let saved = try PDFContentSession(data: Data(contentsOf: saveURL),pageIndex: 0)
    expect(saved.objects.contains { $0.kind == "image" },"edited image survives app save/reopen")
    let defaults = UserDefaults(suiteName: "BotPlusContentChecks")!
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults))
    for tab in RibbonTab.allCases {
        for command in RibbonView.groups(for: tab).flatMap(\.commands) {
            if case .tool = command.action { expect(!manager.canPerform(command.action),"tools are disabled without a document") }
        }
    }
    expect(!manager.canPerform(.save) && !manager.canPerform(.print) && !manager.canPerform(.paste),"document commands are disabled")
    expect(manager.canPerform(.open) && manager.canPerform(.feature("blank")) && manager.canPerform(.feature("license")),"start/help commands stay available")
    manager.createBlankDocument()
    expect(!manager.canPerform(.previous) && !manager.canPerform(.next) && !manager.canPerform(.deletePage),"single page navigation/delete boundaries")
    expect(manager.canPerform(.tool(.editContent)),"content editor is enabled for a writable document")
    expect(HoverEventLocation.acceptsWindow(owner: 1,underPointer: 1,modal: nil,hasSheet: false),"pointer ownership accepts a window independent of key-window focus")
    expect(!HoverEventLocation.acceptsWindow(owner: 1,underPointer: 2,modal: nil,hasSheet: false),"floating panel under pointer blocks a covered viewport")
    expect(!HoverEventLocation.acceptsWindow(owner: 1,underPointer: 1,modal: 2,hasSheet: false),"modal dialog blocks viewport input")
    expect(!HoverEventLocation.acceptsWindow(owner: 1,underPointer: 1,modal: nil,hasSheet: true),"attached sheet blocks viewport input")
    let item = PDFDocumentItem(url: saveURL,document: PDFDocument(data: data)!)
    manager.insertDocument(item); manager.tool = .editContent
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 600))
    let window = NSWindow(contentRect: view.frame,styleMask: [.titled],backing: .buffered,defer: false); window.isReleasedWhenClosed = false; window.contentView = view
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(view); coordinator.update(view)
    view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
    func mouse(_ type: NSEvent.EventType,_ point: CGPoint) -> NSEvent {
        let position = view.convert(view.convert(point,from: item.document.page(at: 0)!),to: nil)
        return NSEvent.mouseEvent(with: type,location: position,modifierFlags: [],timestamp: 0,windowNumber: window.windowNumber,context: nil,eventNumber: 0,clickCount: 1,pressure: 1)!
    }
    view.mouseDown(with: mouse(.leftMouseDown,CGPoint(x: 140,y: 130)))
    expect(manager.contentProperties.active && manager.selectedContent?.kind == "path","click activates content inspector")
    view.mouseDragged(with: mouse(.leftMouseDragged,CGPoint(x: 160,y: 145)))
    view.mouseUp(with: mouse(.leftMouseUp,CGPoint(x: 160,y: 145)))
    expect(abs(manager.selectedContent!.bounds.midX-(selected.bounds.midX+20)) < 1,"drag commits source-object movement")
    expect(!item.undoHistory.isEmpty,"content transactions participate in Undo")
    manager.undoDocument(redo: false)
    try expect(try PDFContentSession(data: manager.serializedData(item),pageIndex: 0).select(at: CGPoint(x: 140,y: 130),tolerance: 3) != nil,"Undo restores original object geometry")
    coordinator.update(view)
    for zoom: CGFloat in [0.05,0.1,1,5,20] {
        coordinator.checkCommand(.setZoom(zoom),view: view)
        expect(abs(view.scaleFactor-zoom) < 0.001,"toolbar/slider supports full PDF range")
        expect(abs(CGFloat(exp(log(Double(PDFZoomLimits.clamp(zoom)))))-zoom) < 0.001,"logarithmic status slider doesn't clamp legal PDF zoom")
    }
    coordinator.detach(); view.stopEventMonitoring(); window.close()
    print("PASS: content paths/images, precise hit testing, transform/style/delete/clipboard, inspector/Undo, command availability and full-range PDF zoom")
}

@MainActor
private func checkFormatting(root: URL) async throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("FORMAT CHECK FAILED: \(message)") }
    }
    let emptyPage = PDFPage()
    emptyPage.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
    let freeText = PDFAnnotation(bounds: CGRect(x: 30, y: 550, width: 400, height: 100), forType: .freeText, withProperties: nil)
    freeText.contents = "NEW PAGE"; freeText.font = NSFont.systemFont(ofSize: 40); freeText.fontColor = .black; freeText.color = .clear
    emptyPage.addAnnotation(freeText)
    let thumbnail = PDFThumbnailCache.shared.image(page: emptyPage, documentID: UUID(), index: 0, revision: 1, width: 153, ratio: 792.0/612.0, interactive: false)
    let bitmap = NSBitmapImageRep(data: thumbnail.tiffRepresentation!)!
    var ink = 0
    for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
        if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent < 0.8 { ink += 1 }
    } }
    expect(ink > 0, "blank PDF page without a CGPDFPage still renders text annotations in thumbnails")
    let document = PDFDocument()
    for index in 0..<3 {
        guard let page = PDFRasterizer.textPage("ORIGINAL \(index + 1)"), let copy = page.copy() as? PDFPage else { fatalError("fixture") }
        copy.setBounds(CGRect(x: 12, y: 20, width: 588, height: 752), for: .cropBox)
        if index == 1 { copy.rotation = 90 }
        document.insert(copy, at: index)
    }
    let url = root.appendingPathComponent("formatting.pdf")
    expect(document.write(to: url), "fixture saves")
    let manager = DocumentManager(recent: RecentPDFStore(defaults: UserDefaults(suiteName: "BotPlusFormattingChecks")!))
    manager.open(url)
    let item = manager.selected!
    let view = PDFViewerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    let coordinator = PDFViewer.Coordinator(manager: manager)
    coordinator.attach(view); coordinator.update(view)
    var options = PDFFormattingOptions(); options.range = "1,3"
    options.headerCenter = "{file}"; options.footerCenter = "{page}/{pages}"
    expect(coordinator.applyFormatting(.header, options: options, remove: false, item: item, view: view) == nil, "headers apply")
    expect(item.document.page(at: 1)!.annotations.isEmpty, "range leaves rotated page intact")
    expect(item.document.page(at: 2)!.annotations.contains { $0.contents == "3/3" }, "real page numbers")
    options.headerCenter = "UPDATED {date}"
    expect(coordinator.applyFormatting(.header, options: options, remove: false, item: item, view: view) == nil, "headers replace")
    expect(item.document.page(at: 0)!.annotations.filter { AnnotationMetadata.decoration(of: $0) == "header" }.count == 2, "no duplicate headers")
    let serialized = try manager.serializedData(item)
    let reopened = PDFDocument(data: serialized)!
    AnnotationMetadata.restore(reopened)
    expect(reopened.page(at: 0)!.annotations.contains { AnnotationMetadata.decoration(of: $0) == "header" }, "decoration tags survive save/reopen")
    options.text = "BP-{bates}"; options.batesStart = 90; options.batesDigits = 6
    expect(coordinator.applyFormatting(.bates, options: options, remove: false, item: item, view: view) == nil, "Bates apply")
    expect(item.document.page(at: 2)!.annotations.contains { $0.contents == "BP-000091" }, "Bates sequence follows selected range")
    expect(coordinator.applyFormatting(.header, options: options, remove: true, item: item, view: view) == nil, "headers remove")
    expect(item.document.page(at: 0)!.annotations.allSatisfy { AnnotationMetadata.decoration(of: $0) != "header" }, "only matching decoration removed")
    expect(item.document.page(at: 0)!.annotations.contains { AnnotationMetadata.decoration(of: $0) == "bates" }, "other decoration remains")
    options.left = 900
    let before = item.document.page(at: 0)!.bounds(for: .cropBox)
    expect(coordinator.applyFormatting(.margins, options: options, remove: false, item: item, view: view) != nil, "invalid margins rejected before mutation")
    expect(item.document.page(at: 0)!.bounds(for: .cropBox) == before, "invalid margins preserve bounds")
    let base = try manager.serializedData(item)
    let oldCount = try PDFContentSession(data: base, pageIndex: 0).objects.count
    let red = PDFColorComponents(Color.red)
    let background = try await PDFPageBackgroundEngine.change(data: base, indices: [0, 2], color: red, image: nil, remove: false) { _ in }
    let first = try PDFContentSession(data: background, pageIndex: 0)
    expect(first.objects.count == oldCount + 1, "background adds one object")
    expect(first.objects.first?.kind == "path", "background inserted behind original objects")
    let image = NSImage(size: CGSize(width: 16, height: 16), flipped: false) { rect in NSColor.green.setFill(); rect.fill(); return true }
    let imageBackground = try await PDFPageBackgroundEngine.change(data: background, indices: [0], color: red,
        image: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!, remove: false) { _ in }
    let imageObjects = try PDFContentSession(data: imageBackground, pageIndex: 0).objects
    expect(imageObjects.count == oldCount + 1 && imageObjects.first?.kind == "image", "image replaces color background as one object behind original content")
    let replaced = try await PDFPageBackgroundEngine.change(data: background, indices: [0, 2], color: PDFColorComponents(.blue), image: nil, remove: false) { _ in }
    let replacedCount = try PDFContentSession(data: replaced, pageIndex: 0).objects.count
    expect(replacedCount == oldCount + 1, "background update preserves mark and replaces old fill")
    let removed = try await PDFPageBackgroundEngine.change(data: replaced, indices: [0, 2], color: red, image: nil, remove: true) { _ in }
    let removedCount = try PDFContentSession(data: removed, pageIndex: 0).objects.count
    expect(removedCount == oldCount, "remove background preserves original objects")
    let final = PDFDocument(data: removed)!
    expect(final.page(at: 0)!.string?.contains("ORIGINAL 1") == true, "source text preserved")
    expect(final.page(at: 1)!.rotation == 90, "other page rotation preserved")
    for format in PDFImageFormat.allCases {
        let folder = root.appendingPathComponent("format-" + format.rawValue)
        let export = PDFImageExportOptions(indices: [0, 1], format: format, dpi: 72, transparent: true, quality: 0.9)
        let count = try PDFImageExporter.export(data: removed, to: folder, options: export) { _ in }
        expect(count == 2, "export count")
        let data = try Data(contentsOf: folder.appendingPathComponent("Page-0002." + format.fileExtension))
        let bitmap = NSBitmapImageRep(data: data)!
        expect(bitmap.pixelsWide == 752 && bitmap.pixelsHigh == 588, "rotated CropBox export size")
    }
    let tooLarge = root.appendingPathComponent("too-large")
    do {
        _ = try PDFImageExporter.export(data: removed, to: tooLarge,
            options: PDFImageExportOptions(indices: [0], format: .png, dpi: 3000, transparent: false, quality: 1)) { _ in }
        fatalError("oversized export should fail")
    } catch PDFImageExportError.tooLarge { }
    expect(!FileManager.default.fileExists(atPath: tooLarge.path), "failed export removes only its own partial directory")
    manager.tool = .editContent
    coordinator.checkContentOutlines(view: view)
    for _ in 0..<100 where coordinator.contentOutlineBuildCount == 0 {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let countBeforeZoom = coordinator.contentOutlineBuildCount
    for _ in 0..<100 { coordinator.checkContentOutlines(view: view) }
    try await Task.sleep(nanoseconds: 50_000_000)
    if coordinator.contentOutlineBuildCount != countBeforeZoom || countBeforeZoom == 0 {
        FileHandle.standardError.write(Data("Outline builds before/after: \(countBeforeZoom)/\(coordinator.contentOutlineBuildCount)\n".utf8))
    }
    expect(countBeforeZoom > 0 && coordinator.contentOutlineBuildCount == countBeforeZoom, "pan/zoom keeps content outlines when pages and revision are unchanged")
    coordinator.detach()
    try checkZoomSafety()
    try checkHoverRoutingAndSplitter()
    try checkGraphicMarks(root: root)
    try await checkDocumentWorkflows(root: root)
    print("PASS: decoration templates/ranges/replacement/persistence, margins validation, vector background ordering/update/removal, PNG/JPEG/TIFF export and rotation")
}

@MainActor
private final class FormattingCheckStatus {
    var finished = false
    var error: Error?
}

@MainActor
private func checkZoomSafety() throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("ZOOM CHECK FAILED: \(message)") }
    }
    let original = PDFDocument(); original.insert(PDFRasterizer.textPage("ZOOM ORIGINAL")!, at: 0)
    let other = PDFDocument(); other.insert(PDFRasterizer.textPage("ZOOM OTHER")!, at: 0)
    let view = PDFViewerView(frame: CGRect(x: 0, y: 0, width: 500, height: 500))
    view.installDocument(original); view.autoScales = false; view.scaleFactor = 1
    let anchor = CGPoint(x: 250, y: 250)
    for _ in 0..<100 { view.checkQueuedMagnify(0.002, anchor: anchor) }
    view.checkFlushMagnify()
    expect(abs(view.scaleFactor - exp(0.2)) < 0.001, "100 gesture events are coalesced without lost deltas")
    view.checkQueuedMagnify(0.5, anchor: anchor)
    view.installDocument(other); view.scaleFactor = 1
    view.checkFlushMagnify()
    expect(abs(view.scaleFactor - 1) < 0.001, "old document gesture does not zoom a newly selected document")
    view.checkQueuedMagnify(0.05, anchor: anchor); view.checkQueuedMagnify(-0.05, anchor: anchor); view.checkFlushMagnify()
    expect(abs(view.scaleFactor - 1) < 0.001, "reverse burst restores scale")
    view.checkQueuedMagnify(.nan, anchor: anchor); view.checkFlushMagnify()
    expect(abs(view.scaleFactor - 1) < 0.001, "nonfinite magnification is ignored")
    view.stopEventMonitoring()
    let cache = PDFThumbnailCache()
    let key = UUID()
    let first = cache.image(page: original.page(at: 0)!, documentID: key, index: 0, revision: 1, width: 600, ratio: 792.0/612.0, interactive: true)
    let pixels = NSBitmapImageRep(data: first.tiffRepresentation!)!
    expect(pixels.pixelsWide == 128, "cold thumbnail gesture starts with a cheap raster")
    _ = cache.image(page: original.page(at: 0)!, documentID: key, index: 0, revision: 1, width: 600, ratio: 792.0/612.0, interactive: true)
    expect(cache.renderCount == 1, "gesture reuses the same thumbnail raster")
    _ = cache.image(page: original.page(at: 0)!, documentID: key, index: 0, revision: 1, width: 600, ratio: 792.0/612.0, interactive: false)
    expect(cache.renderCount == 2, "detail is upgraded after the gesture")
    print("PASS: burst gesture zoom, document isolation, reverse/invalid deltas, cold thumbnail zoom and cached outline reuse")
}

@MainActor
private func checkHoverRoutingAndSplitter() throws {
    func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError("HOVER CHECK FAILED: \(message)") } }
    let manager = DocumentManager(); manager.createBlankDocument()
    expect(manager.thumbnailZoom == 1, "thumbnails initially fit the panel width")
    let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 500)); window.contentView = root
    let thumbnails = ThumbnailGestureView(frame: CGRect(x: 0, y: 0, width: 200, height: 500)); thumbnails.manager = manager
    let pdf = PDFViewerView(frame: CGRect(x: 206, y: 0, width: 494, height: 500)); pdf.installDocument(manager.selected!.document); pdf.scaleFactor = 1
    root.addSubview(thumbnails); root.addSubview(pdf); window.orderFront(nil)
    defer { thumbnails.stop(); pdf.stopEventMonitoring(); window.orderOut(nil) }
    let router = HoverGestureRouter.shared
    let overPDF = window.convertPoint(toScreen: CGPoint(x: 450, y: 250)), overThumbs = window.convertPoint(toScreen: CGPoint(x: 100, y: 250))
    let front = window.windowNumber
    let responder = window.firstResponder
    expect(router.target(at: overPDF, frontWindow: front)?.0 === pdf, "pointer over PDF selects PDF despite thumbnail registration order")
    expect(router.zoom(0.2, at: overPDF, frontWindow: front), "PDF gesture is routed without clicking")
    pdf.checkFlushMagnify(); expect(abs(pdf.scaleFactor-exp(0.2)) < 0.001, "routed PDF gesture changes scale")
    expect(manager.thumbnailZoom == 1, "PDF gesture leaves thumbnails alone")
    expect(router.zoom(-0.2, at: overThumbs, frontWindow: front), "moving pointer routes next gesture to thumbnails")
    thumbnails.flush(); expect(manager.thumbnailZoom < 1, "routed thumbnail gesture changes their size")
    expect(abs(pdf.scaleFactor-exp(0.2)) < 0.001, "thumbnail gesture leaves PDF alone")
    expect(window.firstResponder === responder, "routing preserves first responder")
    expect(router.target(at: overPDF, frontWindow: front+100) == nil, "covered window receives no gesture")
    thumbnails.isHidden = true
    expect(router.target(at: overThumbs, frontWindow: front) == nil, "hidden thumbnails receive no gesture")
    let splitter = PanelResizeHandle.SplitterView(frame: CGRect(x: 200,y: 0,width: 6,height: 500)); root.addSubview(splitter)
    splitter.initialWidth = 230; splitter.direction = 1
    var result: CGFloat = 0; splitter.onWidth = { result = $0 }
    func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 200), modifierFlags: [], timestamp: 0, windowNumber: front, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    splitter.mouseDown(with: event(.leftMouseDown,203))
    splitter.mouseDragged(with: event(.leftMouseDragged,253)); splitter.frame.origin.x += 50; splitter.initialWidth = 280
    splitter.mouseUp(with: event(.leftMouseUp,283))
    expect(abs(result-310) < 0.001, "moving splitter frame does not feed back into drag translation")
    splitter.direction = -1; splitter.initialWidth = 310; splitter.mouseDown(with: event(.leftMouseDown,283)); splitter.mouseUp(with: event(.leftMouseUp,233))
    expect(abs(result-360) < 0.001, "right splitter uses reversed screen delta")
    print("PASS: pointer-routed PDF/thumbnail zoom without focus, occlusion/hidden safeguards, maximum thumbnail default and stable screen-coordinate splitters")
}

@MainActor
private func checkGraphicMarks(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError("MARK CHECK FAILED: \(message)") } }
    let request = PDFGraphicMarkRequest(kind: "stamp", russian: true, filename: "Drawing.pdf", page: 2, apply: { _ in nil })
    let model = PDFGraphicMarkModel(request: request)
    model.text = "TEST {file} {page} {date}"
    let text = model.expanded(model.text, date: Date(timeIntervalSince1970: 0))
    expect(text.contains("Drawing.pdf 3") && !text.contains("{date}"), "dynamic stamp tokens expand")
    guard let image = model.rendered() else { fatalError("mark rendered") }
    let bitmap = NSBitmapImageRep(cgImage: image)
    expect(image.width == 1200 && image.height == 400, "graphic mark has bounded raster resolution")
    expect(bitmap.colorAt(x: 0,y: 0)?.alphaComponent == 0, "graphic marks preserve transparent background")
    model.mode = 1; model.strokes = [[CGPoint(x: 0.1,y: 0.2),CGPoint(x: 0.9,y: 0.7)]]
    expect(model.rendered() != nil, "drawn signature renders")
    model.mode = 2; model.image = image; expect(model.rendered() != nil, "imported signature renders")
    let data = try JSONEncoder().encode(PDFGraphicMarkPreset(name: "test", mode: 0, text: "{page}", font: "Helvetica", size: 42, red: 1,green: 0,blue: 0,opacity: 0.7,thickness: 3,border: true,strokes: [],image: nil))
    let restored = try JSONDecoder().decode(PDFGraphicMarkPreset.self,from: data); model.load(restored)
    expect(model.text == "{page}" && model.opacity == 0.7 && model.border, "preset roundtrip retains template/style")
    let document = PDFDocument(); document.insert(PDFRasterizer.textPage("ORIGINAL")!, at: 0)
    let markerContext = CGContext(data: nil, width: 40, height: 40, bitsPerComponent: 8, bytesPerRow: 160, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    markerContext.setFillColor(NSColor.red.cgColor); markerContext.fill(CGRect(x: 0,y: 20,width: 40,height: 20))
    markerContext.setFillColor(NSColor.blue.cgColor); markerContext.fill(CGRect(x: 0,y: 0,width: 40,height: 20))
    let marker = markerContext.makeImage()!
    let markerData = try PDFSourceSession.insertingImage(data: document.dataRepresentation()!,pageIndex: 0,image: marker,bounds: CGRect(x: 0,y: 0,width: 612,height: 792))
    let markerPDF = PDFDocument(data: markerData)!
    let markerPage = markerPDF.page(at: 0)!
    let raster = NSBitmapImageRep(data: markerPage.thumbnail(of: CGSize(width: 612,height: 792),for: .cropBox).tiffRepresentation!)!
    let sourcePixels = NSBitmapImageRep(data: NSBitmapImageRep(cgImage: marker).representation(using: .png, properties: [:])!)!
    let top = raster.colorAt(x: raster.pixelsWide/2,y: raster.pixelsHigh/4)!.usingColorSpace(.sRGB)!
    let expected = sourcePixels.colorAt(x: 20,y: 10)!.usingColorSpace(.sRGB)!
    let bottom = raster.colorAt(x: raster.pixelsWide/2,y: raster.pixelsHigh*3/4)!.usingColorSpace(.sRGB)!
    let expectedBottom = sourcePixels.colorAt(x: 20,y: 30)!.usingColorSpace(.sRGB)!
    // PDFKit applies its display color profile. Compare color dominance to
    // detect inversion without requiring byte-identical color conversion.
    expect((top.redComponent-top.blueComponent)*(expected.redComponent-expected.blueComponent) > 0.1 &&
           (bottom.redComponent-bottom.blueComponent)*(expectedBottom.redComponent-expectedBottom.blueComponent) > 0.1,
           "inserted image preserves top/bottom orientation")
    withExtendedLifetime(markerPDF) {}
    let changed = try PDFSourceSession.insertingImage(data: document.dataRepresentation()!,pageIndex: 0,image: image,bounds: CGRect(x: 50,y: 100,width: 240,height: 80))
    let target = root.appendingPathComponent("graphic-signature.pdf"); try changed.write(to: target)
    let reopened = PDFDocument(url: target)!
    expect(reopened.string?.contains("ORIGINAL") == true, "graphic mark insertion preserves original searchable text")
    let session = try PDFContentSession(data: changed,pageIndex: 0)
    expect(session.objects.contains { $0.kind == "image" && abs($0.bounds.width-240) < 1 }, "saved graphic mark is selectable content")
    print("PASS: typed/drawn/imported transparent signatures, dynamic stamps, preset serialization and PDF save/reopen")
}

@MainActor
private func checkDocumentWorkflows(root: URL) async throws {
    func expect(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { fatalError("WORKFLOW CHECK FAILED: \(message)") } }
    expect(PDFPagePlan.order("3-1, 4",count: 4) == [2,1,0,3], "descending order parser")
    expect(PDFPagePlan.order("1,1",count: 4) == nil && PDFPagePlan.order("0",count: 4) == nil, "duplicate/invalid page order rejected")
    expect(PDFPagePlan.groups(indices: [0,1,2,3,4],size: 2,starts: nil) == [[0,1],[2,3],[4]], "split by page count")
    expect(PDFPagePlan.groups(indices: [0,1,2,3,4],size: 1,starts: [0,3]) == [[0,1,2],[3,4]], "split at top-level bookmarks")
    let document = PDFDocument()
    for label in ["ONE","TWO","THREE"] { document.insert(PDFRasterizer.textPage(label)!,at: document.pageCount) }
    let pages = (0..<3).map { document.page(at: $0)! }
    let link = PDFAnnotation(bounds: CGRect(x: 20,y: 20,width: 100,height: 20),forType: .link,withProperties: nil)
    link.action = PDFActionGoTo(destination: PDFDestination(page: pages[2],at: CGPoint(x: 30,y: 600))); pages[1].addAnnotation(link)
    let outside = PDFAnnotation(bounds: CGRect(x: 20,y: 50,width: 100,height: 20),forType: .link,withProperties: nil)
    outside.action = PDFActionGoTo(destination: PDFDestination(page: pages[0],at: .zero)); pages[1].addAnnotation(outside)
    let url = PDFAnnotation(bounds: CGRect(x: 20,y: 80,width: 100,height: 20),forType: .link,withProperties: nil)
    url.action = PDFActionURL(url: URL(string: "https://botplus.ru")!); pages[1].addAnnotation(url)
    let rootOutline = PDFOutline(), parent = PDFOutline(), child = PDFOutline()
    parent.label = "Section"; parent.destination = PDFDestination(page: pages[1],at: .zero)
    child.label = "Child"; child.destination = PDFDestination(page: pages[2],at: .zero)
    parent.insertChild(child,at: 0); rootOutline.insertChild(parent,at: 0)
    let omitted = PDFOutline(); omitted.label = "Omitted"; omitted.destination = PDFDestination(page: pages[0],at: .zero); rootOutline.insertChild(omitted,at: 1)
    document.outlineRoot = rootOutline
    let mark = PDFAnnotation(bounds: CGRect(x: 10,y: 10,width: 60,height: 20),forType: .square,withProperties: nil)
    AnnotationMetadata.setGroup("kept-group",on: mark); AnnotationMetadata.setOpacity(0.5,on: mark); pages[2].addAnnotation(mark)
    AnnotationMetadata.prepareForSave(document)
    let subset = try PDFSubsetBuilder.build(document,indices: [1,2])
    let exported = PDFDocument(data: subset)!; AnnotationMetadata.restore(exported)
    expect(exported.pageCount == 2 && exported.page(at: 0)!.string!.contains("TWO"), "subset page order and text preserved")
    let exportedLinks = exported.page(at: 0)!.annotations.filter { $0.type == "Link" }
    expect(exportedLinks.compactMap { $0.action as? PDFActionGoTo }.allSatisfy { exported.index(for: $0.destination.page!) == 1 }, "subset internal links remapped")
    expect(exportedLinks.filter { $0.action == nil }.count == 1, "out-of-range destination removed")
    expect(exportedLinks.contains { $0.action is PDFActionURL }, "external link preserved")
    expect(exported.outlineRoot?.numberOfChildren == 1 && exported.outlineRoot?.child(at: 0)?.numberOfChildren == 1, "bookmark hierarchy pruned without flattening")
    expect(exported.page(at: 1)!.annotations.contains { AnnotationMetadata.group(of: $0) == "kept-group" }, "annotation metadata survives extraction")
    let splitFolder = root.appendingPathComponent("workflow-split")
    let splitData = document.dataRepresentation()!
    let exportWorker = Task.detached { try PDFSubsetBuilder.export(data: splitData,groups: [[0,1],[2]],to: splitFolder,split: true,progress: { _ in }) }
    let files = try await exportWorker.value
    expect(files == 2 && PDFDocument(url: splitFolder.appendingPathComponent("Part-001.pdf"))?.pageCount == 2, "split writes correct PDF groups")
    let protectedFolder = root.appendingPathComponent("existing-split"); try FileManager.default.createDirectory(at: protectedFolder,withIntermediateDirectories: false)
    let sentinel = protectedFolder.appendingPathComponent("keep.txt"); try Data("KEEP".utf8).write(to: sentinel)
    do { _ = try PDFSubsetBuilder.export(data: document.dataRepresentation()!,groups: [[0]],to: protectedFolder,split: true,progress: { _ in }); fatalError("Existing folder overwritten") } catch { }
    expect(FileManager.default.fileExists(atPath: sentinel.path), "existing folder never removed on export failure")
    let initial = root.appendingPathComponent("workflow-source.pdf"); try document.dataRepresentation()!.write(to: initial)
    let manager = DocumentManager(); manager.open(initial); let item = manager.selected!
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 500))
    let window = NSWindow(contentRect: view.frame,styleMask: [.titled],backing: .buffered,defer: false); window.isReleasedWhenClosed = false; window.contentView = view
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(view); coordinator.update(view)
    coordinator.checkCommand(.feature("swap"),view: view)
    for _ in 0..<30 { if manager.pageWorkflowRequest != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
    let request = manager.pageWorkflowRequest!
    var options = PDFPageWorkflowOptions(); options.range = "3,1,2"
    expect(request.apply(options) == nil, "page order dialog applies validated permutation")
    manager.pageWorkflowRequest = nil
    expect(item.document.page(at: 0)!.string!.contains("THREE") && item.document.page(at: 1)!.string!.contains("ONE"), "permutation reorders all pages")
    let orderedData = try manager.serializedData(item), ordered = PDFDocument(data: orderedData)!
    expect(ordered.outlineRoot?.child(at: 0)?.destination?.page.map { ordered.index(for: $0) } == 2, "reordered bookmarks follow original page")
    expect(ordered.page(at: 2)?.annotations.compactMap { $0.action as? PDFActionGoTo }.contains { $0.destination.page.map { ordered.index(for: $0) } == 0 } == true, "reordered links follow original target")
    manager.undoDocument(redo: false); coordinator.update(view)
    expect(item.document.page(at: 0)!.string!.contains("ONE"), "page order Undo restores original")
    coordinator.checkCommand(.page(0),view: view); view.scaleFactor = 1.2; coordinator.checkCommand(.page(0),view: view)
    let a = coordinator.navigationLocation(view,item: item)!
    view.scaleFactor = 1.8; coordinator.checkCommand(.page(2),view: view)
    let b = coordinator.navigationLocation(view,item: item)!
    coordinator.navigationWork?.cancel(); item.navigation.reset(); item.navigationPageCount = item.pageCount
    item.navigation.record(a); item.navigation.record(b)
    let serializations = manager.serializationCount
    coordinator.checkCommand(.history(-1),view: view); try await Task.sleep(for: .milliseconds(80))
    expect(item.pageIndex == a.page && abs(view.scaleFactor-a.zoom) < 0.001, "history restores page and zoom")
    let actual = coordinator.navigationLocation(view,item: item)!
    expect(hypot(actual.point.x-a.point.x,actual.point.y-a.point.y) < 2, "history restores viewport center")
    expect(item.navigation.canForward, "history preserves forward branch")
    coordinator.checkCommand(.history(1),view: view); try await Task.sleep(for: .milliseconds(80))
    expect(item.pageIndex == b.page && abs(view.scaleFactor-b.zoom) < 0.001, "history forward restores saved view")
    expect(manager.serializationCount == serializations, "history never serializes the PDF")
    let history = PDFNavigationHistory(); history.record(a); history.record(b); _ = history.move(-1)
    history.record(.init(page: 1,point: CGPoint(x: 10,y: 50),zoom: 1,layout: .single,padding: NSEdgeInsets(top: 8,left: 8,bottom: 8,right: 8)))
    expect(!history.canForward && history.canBack, "new view clears obsolete forward branch")
    let region = CGRect(x: 20,y: 100,width: 120,height: 80)
    let source = item.document
    for angle in [0,90,180,270] {
        source.page(at: 0)!.rotation = angle
        let data = try manager.serializedData(item)
        let snapshotWorker = Task.detached { try PDFSnapshotRenderer.render(data: data,index: 0,region: region,dpi: 144) }
        let png = try await snapshotWorker.value
        let image = NSBitmapImageRep(data: png)!
        expect(image.pixelsWide == (angle%180 == 0 ? 240 : 160) && image.pixelsHigh == (angle%180 == 0 ? 160 : 240), "snapshot DPI and rotation dimensions")
    }
    let blank = PDFDocument(); let blankPage = PDFPage(); blankPage.setBounds(CGRect(x: 0,y: 0,width: 600,height: 600),for: .mediaBox); blank.insert(blankPage,at: 0)
    let blankData = try PDFDocumentSerializer.data(blank,preserveStreams: false)
    let transparent = try await Task.detached { try PDFSnapshotRenderer.render(data: blankData,index: 0,region: CGRect(x: 0,y: 0,width: 600,height: 600),dpi: 150,transparent: true) }.value
    let alpha = NSBitmapImageRep(data: transparent)!.colorAt(x: 10,y: 10)!.alphaComponent
    expect(alpha == 0,"transparent snapshot background")
    let preview = try await Task.detached { try PDFSnapshotRenderer.preview(transparent) }.value
    let pixels = NSBitmapImageRep(data: preview)!
    expect(max(pixels.pixelsWide,pixels.pixelsHigh) <= 500,"snapshot inspector preview is bounded")
    let oldGap = manager.pageGap, scale = view.scaleFactor, currentDocument = view.document
    manager.pageGap = 20; coordinator.requestUpdate(view); try await Task.sleep(for: .milliseconds(80))
    expect(view.configuredPageMargin == 10 && view.pageBreakMargins.top == 10,"page spacing applies natively")
    expect(view.document === currentDocument && abs(view.scaleFactor-scale) < 0.001,"spacing does not rebuild document or reset zoom")
    manager.pageGap = oldGap; coordinator.requestUpdate(view); try await Task.sleep(for: .milliseconds(80))
    view.activeTool = .snapshot; var captured = false; view.onSnapshot = { _, rect in captured = rect.width > 0 }
    let revision = manager.contentRevision, annotations = source.page(at: 0)!.annotations.count
    view.checkDraw(page: source.page(at: 0)!,start: CGPoint(x: 20,y: 100),end: CGPoint(x: 140,y: 180),tool: .snapshot)
    expect(captured && manager.contentRevision == revision && source.page(at: 0)!.annotations.count == annotations, "snapshot tool creates no annotation or content revision")
    coordinator.detach(); view.stopEventMonitoring(); window.orderOut(nil)
    print("PASS: ordered page plans, split groups, extraction links/bookmarks/metadata, reorder/Undo, page/zoom/position history without serialization, rotated DPI snapshots and transient tool safety")
}

@MainActor
private func checkUpdatePolicies(root: URL) throws {
    func expect(_ condition: @autoclosure () -> Bool,_ message: String) { if !condition() { fatalError("CHECK FAILED: \(message)") } }
    let now = Date(timeIntervalSince1970: 1706659200)
    var policy = UpdatePolicy()
    expect(policy.shouldNotify(version: "v1.8",installed: "1.7",now: now),"new release notifies")
    policy.skipped = "v1.8"
    expect(!policy.shouldNotify(version: "1.8.0",installed: "1.7",now: now),"skip normalizes release version")
    expect(policy.shouldNotify(version: "1.9",installed: "1.7",now: now),"skip does not suppress subsequent versions")
    policy.snoozedUntil = UpdatePolicy.month(after: now)
    expect(!policy.shouldNotify(version: "1.9",installed: "1.7",now: now),"month snooze")
    expect(policy.shouldNotify(version: "1.9",installed: "1.7",now: policy.snoozedUntil!),"snooze expires")
    expect(!ReleaseUpdate.isNewer("1.999999999999999999999999999999999",than: "1.7"),"overflow version rejected")
    expect(!ReleaseUpdate.assetURL(URL(string: "https://github.com/other/repo/releases/download/v1.8/archive.zip")!,tag: "v1.8"),"wrong release source rejected")
    expect(!ReleaseUpdate.permittedDownload(URL(string: "http://github.com/a")!),"insecure redirects rejected")
    expect(!ReleaseUpdate.permittedDownload(URL(string: "https://release-assets.githubusercontent.com.evil.example/a")!),"redirect host is exact")
    expect(PDFPageSpacing.clamp(.nan) == 4 && PDFPageSpacing.clamp(-1) == 0 && PDFPageSpacing.clamp(41) == 40,"page spacing clamps invalid settings")
    expect(UpdateArchive.validDigest("sha256:"+String(repeating: "a",count: 64)) != nil,"SHA-256 accepted")
    expect(UpdateArchive.validDigest("md5:"+String(repeating: "a",count: 64)) == nil,"wrong digest rejected")
    expect(UpdateArchive.checksum(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","SHA-256 calculation")
    let source = root.appendingPathComponent("zip-fixture/BotPlus PDF Editor.app")
    try FileManager.default.createDirectory(at: source.appendingPathComponent("Contents"),withIntermediateDirectories: true)
    try Data("fixture".utf8).write(to: source.appendingPathComponent("Contents/Info.plist"))
    func zip(_ name: String) throws -> Data {
        let url = root.appendingPathComponent(name), process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); process.arguments = ["-c","-k","--keepParent","--norsrc",source.path,url.path]
        try process.run(); process.waitUntilExit(); expect(process.terminationStatus == 0,"fixture ZIP created"); return try Data(contentsOf: url)
    }
    let good = try zip("good.zip"); try UpdateArchive.validate(good)
    let truncated = good.dropLast()
    do { try UpdateArchive.validate(Data(truncated)); fatalError("truncated ZIP accepted") } catch { }
    var bad = good
    let needle = Data("BotPlus PDF Editor.app/Contents/Info.plist".utf8)
    let escape = Data("BotPlus PDF Editor.app/../escapeInfo.plist".utf8)
    expect(needle.count == escape.count,"traversal fixture length")
    while let range = bad.range(of: needle) { bad.replaceSubrange(range,with: escape) }
    do { try UpdateArchive.validate(bad); fatalError("ZIP traversal accepted") } catch { }
    try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("Contents/escape"),withDestinationURL: root)
    do { try UpdateArchive.validate(try zip("symlink.zip")); fatalError("ZIP symlink accepted") } catch { }
    let installed = root.appendingPathComponent("swap-current.app"), next = root.appendingPathComponent("swap-next.app"), backup = root.appendingPathComponent("swap-backup.app")
    try Data("old".utf8).write(to: installed); try Data("new".utf8).write(to: next)
    do {
        try UpdateInstaller.swap(next: next,current: installed,backup: backup) { from,to in
            if from == next { throw UpdateFailure.invalid("Simulated installation failure") }
            try FileManager.default.moveItem(at: from,to: to)
        }
        fatalError("simulated failed update succeeded")
    } catch { }
    let oldContents = try String(contentsOf: installed,encoding: .utf8)
    expect(oldContents == "old","rollback preserves old app")
    try UpdateInstaller.swap(next: next,current: installed,backup: backup)
    let newContents = try String(contentsOf: installed,encoding: .utf8)
    expect(newContents == "new","new app installed")
    let backupContents = try String(contentsOf: backup,encoding: .utf8)
    expect(backupContents == "old","old app retained")
    let suite = "BotPlusUpdateChecks-"+UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let controller = AppUpdateController(installed: "1.7",defaults: defaults)
    expect(controller.automaticChecks && !controller.automaticInstall,"automatic install is opt-in")
    controller.automaticChecks = false; controller.automaticInstall = true
    let reloaded = AppUpdateController(installed: "1.7",defaults: defaults)
    expect(!reloaded.automaticChecks && reloaded.automaticInstall,"preferences persist")
    print("PASS: update policy, skip/snooze/expiry, fixed HTTPS release origins, SHA-256, ZIP traversal/symlink/truncation guards and rollback")
}

@MainActor private func checkHeaderTemplates(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let suite = "BotPlusHeaderTemplates-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var options = PDFFormattingOptions(); options.range = "1"; options.headerCenter = "Шаблон {page}/{pages}"; options.footerCenter = "{file}"
    options.left = 12*PageGeometryUnit.mm.factor; options.right = 0.5*PageGeometryUnit.inch.factor; options.top = 21; options.bottom = 15
    options.fontSize = 11; options.color = .blue; options.opacity = 0.6
    let box = CGRect(x: -20,y: 35,width: 600,height: 800)
    let annotations = PDFDecorationEngine.annotations(kind: .header,options: options,box: box,page: 2,count: 5,filename: "CAD.pdf",sequence: 0,russian: true)
    expect(annotations.count == 2 && annotations[0].contents == "Шаблон 3/5","header expands templates with actual page number")
    let column = (box.width-options.left-options.right)/3
    expect(abs(annotations[0].bounds.minX-(box.minX+options.left+column)) < 0.0001 && abs(annotations[0].bounds.maxY-(box.maxY-options.top)) < 0.0001 && abs(annotations[1].bounds.minY-(box.minY+options.bottom)) < 0.0001,"four insets account for nonzero CropBox origin")
    let preset = PDFHeaderPreset(name: "  CAD шаблон  ",options: options)!
    PDFHeaderPresetStore.save([preset,preset],defaults: defaults)
    let loaded = PDFHeaderPresetStore.load(defaults: defaults)
    expect(loaded.count == 1 && loaded[0].name == "CAD шаблон","preset storage preserves Unicode and removes duplicate IDs/names")
    var restored = PDFFormattingOptions(); restored.range = "2-4"; loaded[0].apply(to: &restored)
    expect(restored.range == "2-4" && restored.headerCenter == options.headerCenter && restored.left == options.left && restored.fontSize == 11 && restored.opacity == 0.6,"loading template preserves current range and restores physical dimensions/style")
    let restoredColor = PDFColorComponents(restored.color)
    expect(restoredColor.blue > 0.99 && restoredColor.red < 0.01,"preset restores color components")
    var invalid = options; invalid.left = -.infinity
    expect(PDFHeaderPreset(name: "Bad",options: invalid) == nil && !PDFDecorationEngine.validHeader(invalid,box: box),"nonfinite template offsets rejected")
    invalid = options; invalid.headerCenter = String(repeating: "x",count: 32001)
    expect(PDFHeaderPreset(name: "Long",options: invalid) == nil,"preset rejects oversized text")
    defaults.set(Data("bad json".utf8),forKey: "BotPlus.HeaderFooterPresets.v1")
    expect(PDFHeaderPresetStore.load(defaults: defaults).isEmpty,"malformed template storage falls back without crashing")
    PDFHeaderPresetStore.save([],defaults: defaults)
    expect(PDFHeaderPresetStore.load(defaults: defaults).isEmpty,"deleting final preset persists")
    let document = PDFDocument(),page = PDFPage(),small = PDFPage()
    page.setBounds(box,for: .mediaBox); page.setBounds(box,for: .cropBox); small.setBounds(CGRect(x: 0,y: 0,width: 100,height: 100),for: .mediaBox)
    document.insert(page,at: 0); document.insert(small,at: 1)
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),item = PDFDocumentItem(url: root.appendingPathComponent("header-insets.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    expect(coordinator.applyFormatting(.header,options: options,remove: false,item: item,view: view) == nil,"custom header insets install")
    var bad = options; bad.range = "all"; bad.top = 80
    let history = item.undoHistory.count,originalText = page.annotations.map(\.contents)
    expect(coordinator.applyFormatting(.header,options: bad,remove: false,item: item,view: view) != nil && item.undoHistory.count == history && page.annotations.map(\.contents) == originalText && small.annotations.isEmpty,"mixed-size page validation rejects entire operation before mutation/history")
    item.historyDate = .distantPast; options.top = 42
    expect(coordinator.applyFormatting(.header,options: options,remove: false,item: item,view: view) == nil,"header insets update replaces existing decorations")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!; AnnotationMetadata.restore(reopened)
    let header = reopened.page(at: 0)!.annotations.first { ($0.contents ?? "").hasPrefix("Шаблон") }!
    expect(abs(header.bounds.maxY-(reopened.page(at: 0)!.bounds(for: .cropBox).maxY-42)) < 0.01,"header insets survive save/reopen when PDFKit normalizes the page origin")
    manager.undoDocument(redo: false)
    let undoHeader = item.document.page(at: 0)!.annotations.first { ($0.contents ?? "").hasPrefix("Шаблон") }!
    expect(abs(undoHeader.bounds.maxY-(item.document.page(at: 0)!.bounds(for: .cropBox).maxY-21)) < 0.01,"Undo restores previous header position")
    manager.undoDocument(redo: true)
    let redoHeader = item.document.page(at: 0)!.annotations.first { ($0.contents ?? "").hasPrefix("Шаблон") }!
    expect(abs(redoHeader.bounds.maxY-(item.document.page(at: 0)!.bounds(for: .cropBox).maxY-42)) < 0.01,"Redo restores header placement")
    print("PASS: header/footer insets/units/templates/color, Unicode storage/range isolation, mixed-page atomic validation and save/Undo/Redo")
}

@MainActor private func checkXFDFInkGeometry(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 500,height: 500),for: .mediaBox); document.insert(page,at: 0)
    let ink = PDFAnnotation(bounds: CGRect(x: 30,y: 50,width: 200,height: 160),forType: .ink,withProperties: nil)
    let path = NSBezierPath(); path.move(to: .zero); path.curve(to: CGPoint(x: 100,y: 0),controlPoint1: CGPoint(x: 0,y: 100),controlPoint2: CGPoint(x: 100,y: 100))
    path.move(to: CGPoint(x: 130,y: 20)); path.line(to: CGPoint(x: 170,y: 20)); path.line(to: CGPoint(x: 150,y: 60)); path.close()
    ink.add(path); ink.contents = "Кривой штрих & контур"; page.addAnnotation(ink)
    let oldBox = ink.bounds,oldElements = ink.paths!.map(\.elementCount)
    let data = PDFXFDF.comments(document,include: { $0 === ink }),parsed = try PDFXFDF.read(data)
    expect(parsed.comments.count == 1 && parsed.comments[0].gestures.count == 2,"XFDF keeps independent subpaths as separate gestures")
    let strokes = parsed.comments[0].gestures
    expect(strokes[0].count > 10 && abs(strokes[0].map(\.y).max()!-125) < 0.04,"XFDF adaptively samples cubic shape instead of connecting endpoints")
    expect(strokes[1].first == strokes[1].last && strokes[1].count == 4,"XFDF preserves closed stroke without bridging subpaths")
    expect(ink.bounds == oldBox && ink.paths!.map(\.elementCount) == oldElements && ink.page === page,"export probe preserves source geometry and ownership")
    let imported = PDFXFDF.annotation(parsed.comments[0])!.1
    expect(imported.contents == ink.contents && imported.paths?.count == 2,"XFDF imports sampled strokes and Unicode contents")
    let importedNodes = try PDFInkCurveGeometry.read(imported,record: nil),points = importedNodes.filter { $0.kind != .close }.map(\.point)
    expect(abs(points.map(\.y).max()!-125) < 0.04 && points.contains { hypot($0.x-160,$0.y-70) < 0.001 },"imported XFDF retains absolute curve and contour coordinates")
    let out = root.appendingPathComponent("curved-ink.xfdf"); try data.write(to: out)
    let reopened = try PDFXFDF.read(Data(contentsOf: out))
    expect(reopened.comments[0].gestures == strokes,"XFDF geometry survives file round trip")
    let square = PDFAnnotation(bounds: CGRect(x: 20,y: 20,width: 50,height: 60),forType: .square,withProperties: nil)
    square.userName = "Автор & \"CAD\""; square.color = .blue; square.interiorColor = .green; square.contents = "Filled"
    let flagBits = 4|8|16|64|128|512; square.setValue(NSNumber(value: flagBits),forAnnotationKey: .flags)
    AnnotationMetadata.setOpacity(0.37,on: square); page.addAnnotation(square)
    let styled = try PDFXFDF.read(PDFXFDF.comments(document,include: { $0 === square },opacity: { Double(AnnotationMetadata.alpha(of: $0)) }))
    let importedSquare = PDFXFDF.annotation(styled.comments[0])!.1
    expect(importedSquare.userName == square.userName && (importedSquare.value(forAnnotationKey: .flags) as? NSNumber)?.intValue == flagBits,"XFDF preserves escaped author and native flags")
    expect(abs(importedSquare.color.alphaComponent-0.37) < 0.0001 && (importedSquare.interiorColor?.usingColorSpace(.sRGB)?.greenComponent ?? 0) > 0.99,"XFDF preserves application opacity and interior color")
    print("PASS: XFDF cubic Ink flattening, independent/closed subpaths, absolute coordinates, source preservation and file round trip")
}

@MainActor private func checkMembershipEditing(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let states = [5:true,6:false,7:true],allowed = Set(states.keys)
    for (policy,expected) in [("AllOn",false),("AnyOn",true),("AllOff",false),("AnyOff",true)] {
        expect(PDFMembershipInfo(id: 0,generation: 0,memberIDs: [5,6],policy: policy,expression: nil,editable: true).visible(states: states) == expected,"standard OCMD policy truth table")
        expect(PDFMembershipInfo(id: 0,generation: 0,memberIDs: [],policy: policy,expression: nil,editable: true).visible(states: states) == true,"empty OCMD membership has no effect for every policy")
    }
    let expression = try PDFVisibilityExpression.parse(" Or( #6, And(#5, Not(#6)) ) ",allowed: allowed)
    expect(expression.evaluate(states) && expression.text == "Or(#6, And(#5, Not(#6)))","OCMD boolean grammar parses and evaluates nested expressions")
    expect(tryExpressionRejected("Not(#5,#6)") && tryExpressionRejected("And()") && tryExpressionRejected("#5") && tryExpressionRejected("And(#999)") && tryExpressionRejected("Or(#5) garbage"),"OCMD parser rejects invalid arity, empty/root/unknown references and trailing input")
    func tryExpressionRejected(_ input: String) -> Bool { do { _ = try PDFVisibilityExpression.parse(input,allowed: allowed); return false } catch { return true } }
    expect(tryExpressionRejected(String(repeating: "Not(",count: 70)+"#5"+String(repeating: ")",count: 70)),"OCMD expression depth is bounded")
    let content = "/OC /M BDC 0 0 1 rg 20 20 50 50 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R] /D << /Name (Original) /Order [5 0 R 6 0 R 7 0 R] /ON [5 0 R 7 0 R] /OFF [6 0 R] /Locked [7 0 R] >> >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Properties << /M 8 0 R /N 9 0 R /Bad 10 0 R /Cycle 12 0 R >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>","<< /Type /OCG /Name (C) >>",
        "<< /Type /OCMD /OCGs [5 0 R 6 0 R] /P /AllOn /Private (keep me) >>",
        "<< /Type /OCMD /VE 11 0 R >>",
        "<< /Type /OCMD /OCGs [99 0 R] /P /Unknown >>",
        "[/Or 6 0 R [/Not 5 0 R]]",
        "<< /Type /OCMD /VE 13 0 R >>","[/Not 13 0 R]"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (i,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var trailer = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { trailer += String(format: "%010lld 00000 n \n",Int64(offset)) }
    trailer += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(trailer.utf8))
    let report = try PDFDocumentExtras.membershipConfiguration(data),entry = report.entries.first { $0.id == 8 }!
    expect(report.groups.count == 3 && report.entries.count == 4 && entry.editable && entry.visible(states: states) == false,"OCMD inspector discovers indirect dictionaries and group policies (groups \(report.groups.count), entries \(report.entries.count))")
    expect(report.entries.first { $0.id == 9 }?.expression == "Or(#6, Not(#5))" && report.entries.first { $0.id == 9 }?.visible(states: states) == false,"indirect VE array resolves with group-state precedence")
    expect(report.entries.filter { !$0.editable }.count == 2,"unknown references/policies and cyclic expression remain read-only")
    let changed = try PDFDocumentExtras.setMembership(data,entry: entry,members: [5,6],policy: "AnyOff",expression: nil)
    let changedReport = try PDFDocumentExtras.membershipConfiguration(changed),changedEntry = changedReport.entries.first { $0.id == 8 }!
    expect(changedEntry.visible(states: states) == true && changedReport.groups.first { $0.id == 7 }?.locked == true,"policy update preserves default OCG states and locks")
    let ve = try PDFDocumentExtras.setMembership(changed,entry: changedEntry,members: [7],policy: "AnyOn",expression: "Not(#5)")
    let veEntry = try PDFDocumentExtras.membershipConfiguration(ve).entries.first { $0.id == 8 }!
    expect(veEntry.visible(states: states) == false && veEntry.memberIDs == [7],"VE overrides otherwise-visible membership policy")
    let cleared = try PDFDocumentExtras.setMembership(ve,entry: veEntry,members: [],policy: "AnyOff",expression: nil)
    let clearedEntry = try PDFDocumentExtras.membershipConfiguration(cleared).entries.first { $0.id == 8 }!
    expect(clearedEntry.expression == nil && clearedEntry.visible(states: states) == true,"removing VE and empty membership has no visibility effect")
    do { _ = try PDFDocumentExtras.setMembership(changed,entry: entry,members: [5],policy: "AnyOn",expression: nil); fatalError("stale OCMD accepted") } catch { }
    do { _ = try PDFDocumentExtras.setMembership(data,entry: entry,members: [999],policy: "AnyOn",expression: nil); fatalError("unknown OCG accepted") } catch { }
    do { _ = try PDFDocumentExtras.setMembership(data,entry: entry,members: [5,5],policy: "AnyOn",expression: nil); fatalError("duplicate OCG accepted") } catch { }
    let cg = CGPDFDocument(CGDataProvider(data: ve as CFData)!)!,page = cg.page(at: 1)!
    var resources: CGPDFDictionaryRef?,properties: CGPDFDictionaryRef?,membership: CGPDFDictionaryRef?
    CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources); CGPDFDictionaryGetDictionary(resources!,"Properties",&properties); CGPDFDictionaryGetDictionary(properties!,"M",&membership)
    var opaque: CGPDFStringRef?; CGPDFDictionaryGetString(membership!,"Private",&opaque)
    var stream: CGPDFStreamRef?; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream); var format = CGPDFDataFormat.raw
    expect(CGPDFStringCopyTextString(opaque!)! as String == "keep me" && CGPDFStreamCopyData(stream!,&format)! as Data == Data(content.utf8),"OCMD writer preserves opaque dictionary keys and original content stream")
    let suite = "BotPlusOCMD-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("ocmd.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showMembershipEditor(item: item,view: view)
    let request = manager.membershipRequest!,selected = request.configuration.entries.first { $0.id == 8 }!
    expect(request.apply(selected,[5,6],"AnyOff",nil) == nil,"OCMD editor installs catalog transaction")
    expect(request.apply(selected,[5],"AnyOn",nil) != nil,"stale OCMD editor rejects replaced document")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.membershipConfiguration(Data(contentsOf: item.url))
    expect(saved.entries.first { $0.id == 8 }?.policy == "AnyOff","OCMD policy survives save/reopen")
    manager.undoDocument(redo: false)
    expect(tryPolicy(manager,item) == "AllOn","Undo restores OCMD policy")
    manager.undoDocument(redo: true)
    expect(tryPolicy(manager,item) == "AnyOff","Redo restores OCMD policy")
    func tryPolicy(_ manager: DocumentManager,_ item: PDFDocumentItem) -> String? { try? PDFDocumentExtras.membershipConfiguration(manager.serializedData(item)).entries.first { $0.id == 8 }?.policy }
    print("PASS: OCMD policies/membership/VE grammar, precedence/cycles/depth/unknown references, preserved streams/catalog and save/Undo/Redo")
}

@MainActor private func checkFDFComments(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let source = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 500,height: 500),for: .mediaBox); source.insert(page,at: 0)
    let square = PDFAnnotation(bounds: CGRect(x: 20.5,y: 40.25,width: 60.75,height: 80),forType: .square,withProperties: nil)
    square.contents = "Комментарий (Ёж) \\ ✓"; square.userName = "Автор"; square.color = .blue; square.interiorColor = .green
    let dashed = PDFBorder(); dashed.lineWidth = 2.5; dashed.style = .dashed; dashed.dashPattern = [NSNumber(value: 4.5),NSNumber(value: 2)]; square.border = dashed
    square.setValue(NSNumber(value: 4|128),forAnnotationKey: .flags); page.addAnnotation(square)
    let line = PDFAnnotation(bounds: CGRect(x: 120,y: 40,width: 100,height: 100),forType: .line,withProperties: nil); line.startPoint = CGPoint(x: 5,y: 10); line.endPoint = CGPoint(x: 95,y: 90); line.startLineStyle = .diamond; line.endLineStyle = .openArrow; line.contents = "Line"; page.addAnnotation(line)
    let ink = PDFAnnotation(bounds: CGRect(x: 30,y: 200,width: 150,height: 100),forType: .ink,withProperties: nil),path = NSBezierPath()
    path.move(to: CGPoint(x: 0,y: 0)); path.curve(to: CGPoint(x: 100,y: 0),controlPoint1: CGPoint(x: 0,y: 100),controlPoint2: CGPoint(x: 100,y: 100)); ink.add(path); ink.contents = "Ink"; page.addAnnotation(ink)
    let xml = try PDFXFDF.read(PDFXFDF.comments(source,include: { $0.type != "Popup" },opacity: { _ in 0.42 })),data = try PDFFDF.writeComments(xml.comments),parsed = try PDFFDF.readComments(data)
    expect(parsed.unsupported == 0 && parsed.entries.count == 3 && parsed.entries[0].contents == square.contents,"FDF comments round trip Unicode and supported types")
    let importedSquare = PDFXFDF.annotation(parsed.entries[0])!.1
    expect(importedSquare.bounds == square.bounds && importedSquare.userName == "Автор" && abs(importedSquare.color.alphaComponent-0.42) < 0.0001 && (importedSquare.interiorColor?.usingColorSpace(.sRGB)?.greenComponent ?? 0) > 0.99,"FDF preserves fractional rect, author, alpha and fill")
    expect((importedSquare.value(forAnnotationKey: .flags) as? NSNumber)?.intValue == (4|128),"FDF preserves annotation flags")
    expect(importedSquare.border?.style == .dashed && importedSquare.border?.lineWidth == 2.5 && (importedSquare.border?.dashPattern as? [NSNumber])?.map(\.doubleValue) == [4.5,2],"FDF/XFDF retain border style and dash lengths")
    for style in [PDFBorderStyle.solid,.dashed,.beveled,.inset,.underline] { expect(PDFXFDF.borderStyle(PDFXFDF.borderName(style)) == style,"native border styles map in both directions") }
    expect(PDFXFDF.dashValues("0,0") == nil && PDFXFDF.dashValues("nan,2") == nil && PDFXFDF.dashValues("-1,2") == nil,"invalid dash patterns rejected")
    let importedLine = PDFXFDF.annotation(parsed.entries[1])!.1
    expect(importedLine.startPoint == line.startPoint && importedLine.endPoint == line.endPoint,"FDF line endpoints use absolute coordinates in file and local coordinates in PDFKit")
    expect(importedLine.startLineStyle == .diamond && importedLine.endLineStyle == .openArrow && xml.comments[1].attributes["head"] == "Diamond" && xml.comments[1].attributes["tail"] == "OpenArrow","FDF/XFDF retain start/head and end/tail without reversing arrow endings")
    for style in [PDFLineStyle.none,.square,.circle,.diamond,.openArrow,.closedArrow] { expect(PDFXFDF.lineStyle(PDFXFDF.lineStyleName(style)) == style,"all native line-ending names map in both directions") }
    expect(parsed.entries[2].gestures[0].count > 10 && abs(parsed.entries[2].gestures[0].map(\.y).max()!-275) < 0.04,"FDF Ink retains adaptively sampled curve")
    let external = Data("%FDF-1.3\n1 0 obj << /FDF << /Annots [2 0 R 3 0 R] >> >> endobj\n2 0 obj << /Subtype /Circle /Page 0 /Rect [1.25 2.5 30 40] /C [.2 .4 .6] /Contents (External) /BS << /W 2.5 >> >> endobj\n3 0 obj << /Subtype /Stamp /Page 0 /Rect [0 0 10 10] >> endobj\ntrailer << /Root 1 0 R >>\n%%EOF".utf8)
    let externalParsed = try PDFFDF.readComments(external)
    expect(externalParsed.entries.count == 1 && externalParsed.unsupported == 1 && externalParsed.entries[0].attributes["width"] == "2.5","FDF reads indirect annotations/real numbers and reports unsupported types")
    let encoded = Data("%FDF-1.2\n1 0 obj << /FDF << /Fields [<< /T (Field) /V <8084929395A0E9> >>] >> >> endobj trailer << /Root 1 0 R >>".utf8)
    let encodedFields = try PDFFDF.read(encoded)
    expect(encodedFields["Field"] == .text("•—™ﬁŁ€é"),"FDF default PDFDocEncoding preserves punctuation, ligatures and Euro")
    let utf8 = Data("%FDF-1.2\n1 0 obj << /FDF << /Encoding /utf_8 /Fields [<< /T (Поле) /V (Привет) >>] >> >> endobj trailer << /Root 1 0 R >>".utf8)
    let utf8Fields = try PDFFDF.read(utf8)
    expect(utf8Fields["Поле"] == .text("Привет"),"FDF field Encoding explicitly selects UTF-8")
    let noColor = Data("%FDF-1.3\n1 0 obj << /FDF << /Annots [<< /Subtype /Square /Page 0 /Rect [0 0 20 20] /C [] >>] >> >> endobj trailer << /Root 1 0 R >>".utf8)
    do { _ = try PDFFDF.readComments(noColor); fatalError("no-color annotation replaced by opaque color") } catch { }
    let mixedEncoding = Data("%FDF-1.3\n1 0 obj << /FDF << /Encoding /utf_8 /Annots [<< /Subtype /Text /Page 0 /Rect [0 0 20 20] /Contents <80> >>] >> >> endobj trailer << /Root 1 0 R >>".utf8)
    let mixed = try PDFFDF.readComments(mixedEncoding)
    expect(mixed.entries[0].contents == "•","field Encoding does not alter annotation text decoding")
    let cycle = Data("%FDF-1.3\n1 0 obj << /FDF << /Annots [2 0 R] >> >> endobj 2 0 obj 2 0 R endobj trailer << /Root 1 0 R >>".utf8)
    do { _ = try PDFFDF.readComments(cycle); fatalError("cyclic FDF annotation accepted") } catch { }
    var invalid = parsed.entries[0]; invalid.attributes["rect"] = "0,0,1"
    do { _ = try PDFFDF.writeComments([invalid]); fatalError("malformed FDF rect exported") } catch { }
    let suite = "BotPlusFDFComments-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),targetPage = PDFPage(); targetPage.setBounds(CGRect(x: 0,y: 0,width: 500,height: 500),for: .mediaBox); document.insert(targetPage,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("fdf-comments.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    var badPage = parsed.entries[0]; badPage.attributes["page"] = "9"
    let beforeHistory = item.undoHistory.count
    expect(!coordinator.applyExchangedComments([parsed.entries[0],badPage],item: item,view: view) && targetPage.annotations.isEmpty && item.undoHistory.count == beforeHistory,"comment import validates all page targets before any mutation/history")
    let malformedInk = try PDFXFDF.read(Data("<xfdf><annots><ink page=\"0\" rect=\"0,0,30,30\"><inklist><gesture>bad</gesture></inklist></ink></annots></xfdf>".utf8))
    expect(!coordinator.applyExchangedComments(malformedInk.comments,item: item,view: view) && targetPage.annotations.isEmpty && item.undoHistory.count == beforeHistory,"malformed XFDF stroke rejects import before history")
    let markup = try PDFXFDF.read(Data("<xfdf><annots><highlight page=\"0\" rect=\"20,20,60,40\" coords=\"20,40,60,40,20,20,60,20\"/></annots></xfdf>".utf8))
    expect(markup.comments[0].quads.count == 4 && PDFXFDF.annotation(markup.comments[0])?.1.quadrilateralPoints?.count == 4,"standard XFDF coords attribute imports text markup geometry")
    expect(coordinator.applyExchangedComments(parsed.entries,item: item,view: view) && targetPage.annotations.filter { !AnnotationMetadata.isContainer($0) }.count == 3,"FDF comments install as one transaction")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!; AnnotationMetadata.restore(reopened)
    expect(reopened.page(at: 0)!.annotations.contains { $0.contents == square.contents && abs(AnnotationMetadata.alpha(of: $0)-0.42) < 0.001 },"FDF imported contents and opacity survive save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.filter { !AnnotationMetadata.isContainer($0) }.isEmpty,"Undo removes complete imported batch")
    manager.undoDocument(redo: true)
    expect(item.document.page(at: 0)!.annotations.contains { $0.contents == square.contents },"Redo restores imported comments")
    let file = root.appendingPathComponent("comments.fdf"); try data.write(to: file)
    let fileEntries = try PDFFDF.readComments(Data(contentsOf: file))
    expect(fileEntries.entries.count == 3,"FDF comment file round trip")
    let styledDocument = PDFDocument(),styledPage = PDFPage(); styledPage.setBounds(CGRect(x: 0,y: 0,width: 300,height: 300),for: .mediaBox); styledDocument.insert(styledPage,at: 0)
    let freeText = PDFAnnotation(bounds: CGRect(x: 20,y: 100,width: 200,height: 40),forType: .freeText,withProperties: nil); freeText.contents = "Right aligned"; freeText.font = .systemFont(ofSize: 12); freeText.fontColor = .black; freeText.color = .clear; freeText.alignment = .right; styledPage.addAnnotation(freeText)
    let note = PDFAnnotation(bounds: CGRect(x: 20,y: 20,width: 30,height: 30),forType: .text,withProperties: nil); note.contents = "Help"; note.iconType = .help; styledPage.addAnnotation(note)
    let styleEntries = try PDFXFDF.read(PDFXFDF.comments(styledDocument,include: { $0.type != "Popup" })).comments
    expect(styleEntries.first { $0.kind == "freetext" }?.attributes["justification"] == "right" && styleEntries.first { $0.kind == "text" }?.attributes["icon"] == "Help","XFDF exports native text alignment and note icon")
    let styleData = try PDFFDF.writeComments(styleEntries),styleRoundtrip = try PDFFDF.readComments(styleData)
    let textResult = PDFXFDF.annotation(styleRoundtrip.entries.first { $0.kind == "freetext" }!)!.1,noteResult = PDFXFDF.annotation(styleRoundtrip.entries.first { $0.kind == "text" }!)!.1
    expect(textResult.alignment == .right && noteResult.iconType == .help,"FDF Q/Name retain FreeText alignment and note icon")
    for icon in [PDFTextAnnotationIconType.comment,.key,.note,.help,.newParagraph,.paragraph,.insert] { expect(PDFXFDF.noteIcon(PDFXFDF.noteIconName(icon)) == icon,"all native note icons map in both directions") }
    print("PASS: FDF comment geometry/Ink/Unicode/color/flags/alpha, indirect real values, unsupported counts/cycles and atomic import/save/Undo/Redo")
}

@MainActor private func checkMeasurementTransforms(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let triangle = EngineeringMeasure(kind: .area,points: [CGPoint(x: 100,y: 100),CGPoint(x: 200,y: 100),CGPoint(x: 150,y: 180)],scale: EngineeringScale(unit: .mm),dimensionOffset: nil)
    let rotatedTriangle = triangle.transformed(degrees: 37,mirrorX: true,mirrorY: false)!
    expect(abs(rotatedTriangle.value-triangle.value) < 0.00001,"area remains calibrated after rigid rotation/reflection")
    expect(triangle.transformed(degrees: .nan,mirrorX: false,mirrorY: false) == nil && triangle.transformed(degrees: 361,mirrorX: false,mirrorY: false) == nil,"measurement transform rejects nonfinite/out-of-range angles")
    let suite = "BotPlusMeasureTransform-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 600,height: 600),for: .mediaBox); document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("transformed-measure.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 200,y: 300),CGPoint(x: 400,y: 300)],view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!
    AnnotationMetadata.setOpacity(0.4,on: ink)
    let history = item.undoHistory.count
    expect(coordinator.transformMeasurement(ink,degrees: 0,mirrorX: false,mirrorY: false,item: item,view: view) && item.undoHistory.count == history,"no-op measurement transform keeps history")
    let label = page.annotations.first { $0.type == "FreeText" && AnnotationMetadata.group(of: $0) == group }!
    AnnotationMetadata.setLocked(true,on: label)
    expect(!coordinator.transformMeasurement(ink,degrees: 90,mirrorX: false,mirrorY: false,item: item,view: view) && AnnotationMetadata.measurement(ink)?.points == original.points,"locked dependent label rejects entire transform")
    AnnotationMetadata.setLocked(false,on: label)
    coordinator.showEngineeringTransform(item: item,view: view)
    let request = manager.engineeringTransformRequest!; item.historyDate = .distantPast
    expect(request.apply(90,false,false,100,true) == nil,"measurement dialog rotates points and dependent parts")
    let rotated = AnnotationMetadata.measurement(ink)!
    expect(rotated.points == [CGPoint(x: 300,y: 200),CGPoint(x: 300,y: 400)] && abs(rotated.value-original.value) < 0.000001 && rotated.scale.millimetersPerPoint == original.scale.millimetersPerPoint,"measurement point rotation preserves value and calibration")
    let dimensions = page.annotations.filter { AnnotationMetadata.decoration(of: $0) == "engineeringDimension" }
    expect(dimensions.count == 3 && dimensions.contains { $0.startLineStyle == .closedArrow && $0.endLineStyle == .closedArrow } && dimensions.allSatisfy { abs(AnnotationMetadata.alpha(of: $0)-0.4) < 0.001 },"dimension arrows regenerate with source opacity")
    expect(label.contents == ink.contents && label.bounds.width == 140 && view.selectedAnnotations.count == 5,"label stays upright and regenerated parts remain selected as one group")
    expect(request.apply(90,false,false,100,true) != nil,"old measurement dialog rejects changed geometry")
    item.historyDate = .distantPast
    expect(coordinator.transformMeasurement(ink,degrees: 0,mirrorX: true,mirrorY: false,item: item,view: view) && AnnotationMetadata.measurement(ink)?.dimensionOffset == -original.dimensionOffset!,"reflection flips signed normal offset to preserve dimension side")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedMeasure = saved.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!
    expect(abs(savedMeasure.value-original.value) < 0.000001 && savedMeasure.dimensionOffset == -original.dimensionOffset!,"transformed measurement metadata survives save/reopen")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    let undoMeasure = item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!
    expect(undoMeasure.dimensionOffset == original.dimensionOffset,"Undo restores dimension-side metadata")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first?.dimensionOffset == -original.dimensionOffset!,"Redo restores reflected measurement")
    let small = PDFPage(); small.setBounds(CGRect(x: 0,y: 0,width: 100,height: 100),for: .mediaBox); item.document.insert(small,at: 1)
    coordinator.commitEngineering(page: small,kind: .distance,points: [CGPoint(x: 20,y: 50),CGPoint(x: 80,y: 50)],view: view)
    let smallInk = small.annotations.first { AnnotationMetadata.measurement($0) != nil }!,before = AnnotationMetadata.measurement(smallInk)!.points,beforeFailure = item.undoHistory.count
    expect(!coordinator.transformMeasurement(smallInk,degrees: 90,mirrorX: false,mirrorY: false,item: item,view: view) && AnnotationMetadata.measurement(smallInk)!.points == before && item.undoHistory.count == beforeFailure,"out-of-page label/parts reject measurement transform before history/mutation")
    print("PASS: calibrated measurement rotation/reflection, area invariance, dimension-side/arrow/opacity/label regeneration, locks/bounds/stale guards and save/Undo/Redo")
}

@MainActor private func checkMeasurementBatchScaling(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let triangle = EngineeringMeasure(kind: .area,points: [CGPoint(x: 100,y: 100),CGPoint(x: 160,y: 100),CGPoint(x: 130,y: 150)],scale: EngineeringScale(unit: .mm),dimensionOffset: nil)
    let larger = triangle.transformed(degrees: 17,mirrorX: true,mirrorY: false,factor: 2,preservingValue: false)!
    let calibrated = triangle.transformed(degrees: 17,mirrorX: false,mirrorY: true,factor: 2,preservingValue: true)!
    expect(abs(larger.value-triangle.value*4) < 0.00001 && abs(calibrated.value-triangle.value) < 0.00001 && calibrated.scale.millimetersPerPoint == triangle.scale.millimetersPerPoint/2,"area scale obeys explicit calibration/value policy")
    expect(triangle.transformed(degrees: 0,mirrorX: false,mirrorY: false,factor: 0) == nil && triangle.transformed(degrees: 0,mirrorX: false,mirrorY: false,factor: .nan) == nil,"measurement scale rejects invalid factors")
    let suite = "BotPlusMeasureBatch-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 800,height: 800),for: .mediaBox); document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("batch-measurements.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 150,y: 250),CGPoint(x: 250,y: 250)],view: view)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 450,y: 450),CGPoint(x: 550,y: 450)],view: view)
    let inks = page.annotations.filter { AnnotationMetadata.measurement($0) != nil },old = inks.map { AnnotationMetadata.measurement($0)! }
    let pageCalibration = EngineeringCalibration.read(page)
    view.selectAnnotations(inks); coordinator.showEngineeringTransform(item: item,view: view)
    expect(manager.engineeringTransformRequest?.count == 2,"dialog captures multiple logical measurement groups")
    let request = manager.engineeringTransformRequest!,beforeHistory = item.undoHistory.count
    expect(request.apply(0,false,false,100,false) == nil && item.undoHistory.count == beforeHistory,"batch no-op avoids history")
    AnnotationMetadata.setLocked(true,on: inks[1])
    expect(!coordinator.transformMeasurements(inks,degrees: 0,mirrorX: false,mirrorY: false,factor: 2,preservingValue: false,item: item,view: view) && AnnotationMetadata.measurement(inks[0])!.points == old[0].points && item.undoHistory.count == beforeHistory,"locked member rejects batch before modifying earlier measurement")
    AnnotationMetadata.setLocked(false,on: inks[1]); item.historyDate = .distantPast
    expect(coordinator.transformMeasurements(inks,degrees: 0,mirrorX: false,mirrorY: false,factor: 2,preservingValue: false,item: item,view: view),"batch geometry scale applies")
    expect(item.undoHistory.count == beforeHistory+1 && view.annotationSelectionUnitCount == 2,"whole measurement batch records one Undo and keeps multi-selection")
    for (index,ink) in inks.enumerated() {
        let measure = AnnotationMetadata.measurement(ink)!
        expect(abs(measure.value-old[index].value*2) < 0.00001 && measure.scale.millimetersPerPoint == old[index].scale.millimetersPerPoint && measure.dimensionOffset == old[index].dimensionOffset!*2,"fixed calibration updates length and scales dimension offset")
    }
    expect(EngineeringCalibration.read(page)?.millimetersPerPoint == pageCalibration?.millimetersPerPoint,"selected transform leaves page calibration unchanged")
    expect(request.apply(0,false,false,120,true) != nil,"batch dialog rejects changed document")
    item.historyDate = .distantPast
    expect(coordinator.transformMeasurements(inks,degrees: 30,mirrorX: true,mirrorY: false,factor: 0.5,preservingValue: true,item: item,view: view),"batch scale with value preservation applies")
    for (index,ink) in inks.enumerated() { let measure = AnnotationMetadata.measurement(ink)!; expect(abs(measure.value-old[index].value*2) < 0.00001 && measure.scale.millimetersPerPoint == old[index].scale.millimetersPerPoint*2,"value-preserving scale updates selected calibration only") }
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    expect(saved.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.allSatisfy { abs($0.value-old[0].value*2) < 0.00001 },"batch scale metadata saves/reopens")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    let undone = item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }
    expect(undone.count == 2 && undone.allSatisfy { $0.scale.millimetersPerPoint == old[0].scale.millimetersPerPoint },"Undo restores whole batch calibration")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.allSatisfy { $0.scale.millimetersPerPoint == old[0].scale.millimetersPerPoint*2 },"Redo restores whole batch calibration")
    print("PASS: batch measurement scale/calibration policies, length/area values, one-step atomic history, locks/selection/page isolation and save/Undo/Redo")
}

@MainActor private func checkLayerStateSettings(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let content = "/OC /M BDC 20 20 20 20 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Private (root) /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R] /D << /Name (Default) /BaseState /ON /Intent /View /ON [5 0 R 7 0 R] /OFF [6 0 R] /Locked [7 0 R] /RBGroups [[5 0 R 6 0 R]] /Order [(Sheets) [5 0 R 6 0 R 7 0 R]] >> /Configs [9 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /Properties << /M 8 0 R >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>","<< /Type /OCG /Name (C) /Usage << /Zoom << /min 0 /max 100 >> >> >>",
        "<< /Type /OCMD /VE [/And 5 0 R [/Not 6 0 R]] >>",
        "<< /Name (Alternative) /BaseState /Unchanged /Intent /Design /ON [6 0 R] /OFF [5 0 R] /Locked [7 0 R] /RBGroups [[5 0 R 6 0 R]] /Order [6 0 R 5 0 R] /AS [<< /Event /Print /OCGs [7 0 R] /Category [/Print] >>] /Retain (yes) >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (i,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(i+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8))
    let report = try PDFDocumentExtras.layerStateReport(data),alternative = report.configurations.first { $0.id == 0 }!,primary = report.configurations.first { $0.id == -1 }!
    expect(report.groups.count == 3 && alternative.editable && alternative.base == "Unchanged" && alternative.intents == ["Design"],"configuration inspector reads default/alternative state and intent")
    let lockEdit = try PDFDocumentExtras.setLayerState(data,entry: alternative,base: alternative.base,intents: alternative.intents,on: alternative.on,off: alternative.off,locked: [5])
    let lockReport = try PDFDocumentExtras.layerStateReport(lockEdit),newLocks = lockReport.configurations.first { $0.id == 0 }!
    expect(newLocks.locked == [5] && newLocks.on == alternative.on && newLocks.off == alternative.off && newLocks.intents == alternative.intents,"alternative Locked changes without activating preset or changing state/intent")
    expect(lockReport.configurations.first { $0.id == -1 } == primary && newLocks.radios == alternative.radios,"alternative lock edits preserve default configuration and radio membership")
    do { _ = try PDFDocumentExtras.setLayerState(lockEdit,entry: alternative,base: alternative.base,intents: alternative.intents,on: alternative.on,off: alternative.off,locked: []); fatalError("stale lock configuration accepted") } catch { }
    for invalid in [[5,5],[999]] {
        do { _ = try PDFDocumentExtras.setLayerState(data,entry: alternative,base: alternative.base,intents: alternative.intents,on: alternative.on,off: alternative.off,locked: invalid); fatalError("invalid configuration Locked accepted") } catch { }
    }
    let groupA = report.groups.first { $0.id == 5 }!
    let intentData = try PDFDocumentExtras.setLayerUsage(data,entry: groupA,viewState: nil,printState: nil,intents: ["View","Проект печати"])
    let intentGroup = try PDFDocumentExtras.layers(intentData).first { $0.id == 5 }!
    expect(intentGroup.intent == ["View","Проект печати"],"group Intent edits preserve Unicode PDF names")
    let inheritedIntent = try PDFDocumentExtras.setLayerUsage(intentData,entry: intentGroup,viewState: nil,printState: nil,intents: [])
    let inheritedGroup = try PDFDocumentExtras.layers(inheritedIntent).first { $0.id == 5 }!
    expect(inheritedGroup.intent == ["View"],"removing group Intent restores default View")
    do { _ = try PDFDocumentExtras.setLayerUsage(data,entry: report.groups.first { $0.id == 7 }!,viewState: nil,printState: nil,intents: ["Design"]); fatalError("locked group intent changed") } catch { }
    let changed = try PDFDocumentExtras.setLayerState(data,entry: alternative,base: "OFF",intents: ["View","Проект печати"],on: [6,7],off: [5]),changedReport = try PDFDocumentExtras.layerStateReport(changed)
    let newAlternative = changedReport.configurations.first { $0.id == 0 }!
    expect(newAlternative.base == "OFF" && newAlternative.intents == ["View","Проект печати"] && newAlternative.on == [6,7] && changedReport.groups.first { $0.id == 5 }?.visible == true,"editing alternative settings retains current default visibility and escaped Unicode intents")
    func rejected(_ entry: PDFLayerStateConfiguration,base: String = "ON",intents: [String] = ["View"],on: [Int],off: [Int]) -> Bool {
        do { _ = try PDFDocumentExtras.setLayerState(data,entry: entry,base: base,intents: intents,on: on,off: off); return false } catch { return true }
    }
    expect(rejected(primary,base: "OFF",on: [5,7],off: [6]) && rejected(primary,intents: ["Design"],on: [5,7],off: [6]),"default configuration enforces ON/View")
    expect(rejected(primary,on: [5],off: [6,7]) && rejected(primary,on: [5,6,7],off: []),"locked states and exclusive radio choices are preserved")
    expect(rejected(primary,on: [5,7],off: [5,6]) && rejected(primary,on: [999],off: [6]) && rejected(alternative,intents: ["View","View"],on: [6,7],off: [5]),"configuration input rejects overlap, unknown groups and duplicate intents")
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!
    func dictionary(_ dict: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef { var value: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(dict,key,&value); return value! }
    var configs: CGPDFArrayRef?; CGPDFDictionaryGetArray(dictionary(cg.catalog!,"OCProperties"),"Configs",&configs)
    var config: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(configs!,0,&config)
    var retained: CGPDFStringRef?; CGPDFDictionaryGetString(config!,"Retain",&retained)
    var usage: CGPDFArrayRef?,order: CGPDFArrayRef?; CGPDFDictionaryGetArray(config!,"AS",&usage); CGPDFDictionaryGetArray(config!,"Order",&order)
    expect(CGPDFStringCopyTextString(retained!)! as String == "yes" && CGPDFArrayGetCount(usage!) == 1 && CGPDFArrayGetCount(order!) == 2,"configuration writer preserves opaque keys, AS usage and hierarchy")
    expect(tryMembership(changed) == "And(#5, Not(#6))","configuration edits preserve OCMD expressions")
    func tryMembership(_ data: Data) -> String? { try? PDFDocumentExtras.membershipConfiguration(data).entries.first?.expression }
    let viewOnly = try PDFDocumentExtras.setLayerState(changed,entry: newAlternative,base: "Unchanged",intents: ["View"],on: [6],off: [5])
    let madeDefault = try PDFDocumentExtras.makeLayerPresetDefault(viewOnly,index: 0),active = try PDFDocumentExtras.layerStateReport(madeDefault)
    expect(active.configurations.first { $0.id == -1 }?.base == "ON" && active.groups.first { $0.id == 6 }?.visible == true && active.groups.first { $0.id == 5 }?.visible == false,"edited Unchanged preset activates through canonical default conversion")
    let suite = "BotPlusLayerSettings-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("config-settings.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showLayerStateEditor(item: item,view: view)
    let request = manager.layerStateRequest!,entry = request.report.configurations.first { $0.id == 0 }!
    expect(request.applyWithLocks?(entry,"OFF",["View"],[6,7],[5],[5]) == nil,"configuration settings and alternative locks install in one transaction")
    expect(request.apply(entry,"ON",["View"],[6,7],[5]) != nil,"stale configuration editor rejects replaced document")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.layerStateReport(Data(contentsOf: item.url))
    expect(saved.configurations.first { $0.id == 0 }?.base == "OFF","configuration state survives save/reopen")
    expect(saved.configurations.first { $0.id == 0 }?.locked == [5],"alternative Locked survives save/reopen without default swap")
    manager.undoDocument(redo: false)
    expect(tryBase(manager,item) == "Unchanged","Undo restores complete configuration")
    expect(tryLocks(manager,item) == [7],"Undo restores original alternative Locked")
    manager.undoDocument(redo: true)
    expect(tryBase(manager,item) == "OFF","Redo restores configuration settings")
    expect(tryLocks(manager,item) == [5],"Redo restores alternative Locked with settings")
    func tryBase(_ manager: DocumentManager,_ item: PDFDocumentItem) -> String? { try? PDFDocumentExtras.layerStateReport(manager.serializedData(item)).configurations.first { $0.id == 0 }?.base }
    func tryLocks(_ manager: DocumentManager,_ item: PDFDocumentItem) -> [Int]? { try? PDFDocumentExtras.layerStateReport(manager.serializedData(item)).configurations.first { $0.id == 0 }?.locked }
    print("PASS: configuration BaseState/ON/OFF/Unicode Intent, default constraints, locked/radio guards, retained AS/Order/OCMD and save/Undo/Redo")
}

@MainActor private func checkStructuralGraphics(root: URL) async throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    func object(_ id: String,_ x: CGFloat,geometry: String = "rect",style: String = "red") -> PDFGraphicSnapshot { PDFGraphicSnapshot(id: id,kind: "path",geometry: geometry,style: style,bounds: CGRect(x: x,y: 10,width: 20,height: 30)) }
    let duplicate = PDFGraphicPage(objects: [object("0",10),object("1",10)])
    let equal = try PDFGraphicComparison.compare(left: duplicate,right: duplicate)
    expect(equal.unchanged == 2 && equal.changes.isEmpty,"graphic comparison preserves duplicate multiplicity")
    let moved = try PDFGraphicComparison.compare(left: PDFGraphicPage(objects: [object("0",10)]),right: PDFGraphicPage(objects: [object("0",20)]))
    let styled = try PDFGraphicComparison.compare(left: PDFGraphicPage(objects: [object("0",10)]),right: PDFGraphicPage(objects: [object("0",10,style: "blue")]))
    let modified = try PDFGraphicComparison.compare(left: PDFGraphicPage(objects: [object("0",10)]),right: PDFGraphicPage(objects: [object("0",10,geometry: "triangle")]))
    expect(moved.changes.first?.kind == "moved" && styled.changes.first?.kind == "style" && modified.changes.first?.kind == "modified","graphic classifier distinguishes position, style and unambiguous replacement")
    let removed = try PDFGraphicComparison.compare(left: duplicate,right: PDFGraphicPage(unsupported: 2,truncated: true))
    expect(removed.changes.count == 2 && removed.unsupportedRight == 2 && removed.truncated,"missing graphics and incomplete-source diagnostics remain distinct")
    func fixture(rect: String = "10 10 20 30 re f",color: String = "1 0 0 rg",image: String = "abc") -> Data {
        let content = color+"\n"+rect+"\n0 0 1 RG 1 w 60 10 m 90 40 l S\nq 1 0 0 1 100 100 cm /F Do Q\nq 20 0 0 20 140 140 cm /Im Do Q\n",form = "0 1 0 rg 0 0 5 10 re f\n"
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Resources << /XObject << /F 5 0 R /Im 6 0 R >> >> /Contents 4 0 R >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream","<< /Type /XObject /Subtype /Form /BBox [-100 -100 500 500] /Resources << >> /Length \(form.utf8.count) >>\nstream\n"+form+"endstream","<< /Type /XObject /Subtype /Image /Width 1 /Height 1 /BitsPerComponent 8 /ColorSpace /DeviceRGB /Length 3 >>\nstream\n"+image+"\nendstream"]
        var bytes = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(bytes.count); bytes.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = bytes.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; bytes.append(Data(end.utf8)); return bytes
    }
    let source = fixture(),original = try await PDFSourceGraphicReader.pages(data: source),same = try await PDFSourceGraphicReader.pages(data: source)
    expect(original.count == 1 && original[0].objects.count == 4 && original[0].unsupported == 0,"source reader extracts paths, nested Form and image data")
    expect(original[0].objects.contains { $0.kind == "path" && abs($0.bounds.minX-100) < 0.01 && abs($0.bounds.minY-100) < 0.01 },"nested Form geometry reaches page coordinates")
    let unchanged = try PDFGraphicComparison.compare(left: original[0],right: same[0])
    expect(unchanged.unchanged == 4 && unchanged.changes.isEmpty,"source fingerprints are repeatable without rewriting")
    let translated = try await PDFSourceGraphicReader.pages(data: fixture(rect: "15 10 20 30 re f"))
    let sourceMoved = try PDFGraphicComparison.compare(left: original[0],right: translated[0])
    expect(sourceMoved.changes.count == 1 && sourceMoved.changes[0].kind == "moved","source path translation is distinct from geometry changes")
    let recolored = try await PDFSourceGraphicReader.pages(data: fixture(color: "0 1 0 rg"))
    let sourceStyle = try PDFGraphicComparison.compare(left: original[0],right: recolored[0])
    expect(sourceStyle.changes.count == 1 && sourceStyle.changes[0].kind == "style","source fill-color change appears in structural report")
    let imageData = fixture(image: "abd"),imagePages = try await PDFSourceGraphicReader.pages(data: imageData)
    let imageDiff = try PDFGraphicComparison.compare(left: original[0],right: imagePages[0])
    expect(imageDiff.changes.count == 1 && imageDiff.changes[0].objectKind == "image" && imageDiff.changes[0].kind == "modified","image content is compared independently of its bounds")
    let rows = try PDFVisualComparison.compare(left: source,right: imageData,offset: 0,tolerance: 20,leftGraphics: original,rightGraphics: imagePages) { _ in }
    expect(rows[0].graphics?.changes.count == 1,"structural graphics attach to the same visual page pairs")
    let html = PDFTextComparison.html(rows: rows,leftName: "A",rightName: "B")
    expect(html.contains("Source graphics") && html.contains("modified · image") && html.contains("Unsupported left/right"),"HTML exports source graphic changes and coverage diagnostics")
    let clipped = try await PDFSourceGraphicReader.pages(data: fixture(rect: "q 10 10 5 5 re W n 10 10 20 30 re f Q"))
    expect(clipped[0].unsupported > 0 && clipped[0].objects.count < original[0].objects.count,"clipped source graphics are reported unsupported instead of compared as complete")
    let dense = try await PDFSourceGraphicReader.pages(data: fixture(rect: String(repeating: "10 10 1 1 re f\n",count: 1005)))
    expect(dense[0].truncated && dense[0].objects.count == 1000,"source object cap produces an explicit incomplete report")
    let canceled = Task { @MainActor in try await PDFSourceGraphicReader.pages(data: source) }; canceled.cancel()
    do { _ = try await canceled.value; fatalError("canceled graphic reader completed") } catch is CancellationError { }
    try html.write(to: root.appendingPathComponent("source-graphics.html"),atomically: true,encoding: .utf8)
    print("PASS: structural path/image comparison, duplicate counts, move/style/replacement classification, nested matrices, source preservation and visual/HTML integration")
}

@MainActor private func checkEmptyTagDeletion(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let content = "/P << /MCID 0 >> BDC 10 10 20 20 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /StructTreeRoot 5 0 R /Lang (en) /MarkInfo << /Marked true >> /Private (6 0 R) >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /StructParents 0 /Resources << >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /StructTreeRoot /K [6 0 R 7 0 R] /ParentTree 8 0 R >>",
        "<< /Type /StructElem /S /Div /T (Empty) /P 5 0 R /K [] >>",
        "<< /Type /StructElem /S /P /T (Body) /P 5 0 R /Pg 3 0 R /K 0 >>",
        "<< /Nums [0 [7 0 R]] >>"
    ]
    func fixture(_ objects: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
    }
    let data = fixture(objects),report = try PDFDocumentExtras.structure(data,russian: false),empty = report.nodes.first { $0.title == "Empty" }!
    expect(empty.canDeleteEmpty && !report.nodes.first { $0.title == "Body" }!.canDeleteEmpty,"empty-tag capability excludes marked-content owners")
    let deleted = try PDFDocumentExtras.deleteEmptyStructure(data,node: empty),after = try PDFDocumentExtras.structure(deleted,russian: false)
    expect(after.nodes.map(\.title) == ["Body"],"empty tag detaches without deleting content tag; reference-like strings do not count as links")
    func rejected(_ bodies: [String]) -> Bool {
        do { let bytes = fixture(bodies),node = try PDFDocumentExtras.structure(bytes,russian: false).nodes.first { $0.title == "Empty" }!; _ = try PDFDocumentExtras.deleteEmptyStructure(bytes,node: node); return false } catch { return true }
    }
    var aliased = objects; aliased[6] = "<< /Type /StructElem /S /P /T (Body) /P 5 0 R /Pg 3 0 R /K 0 /Ref [6 0 R] >>"
    expect(rejected(aliased),"other structural references prevent orphaning an empty tag")
    var identified = objects; identified[5] = "<< /Type /StructElem /S /Div /T (Empty) /ID (target) /P 5 0 R /K [] >>"
    expect(rejected(identified),"tag ID prevents deletion even without an IDTree binding")
    var actual = objects; actual[5] = "<< /Type /StructElem /S /Div /T (Empty) /P 5 0 R /K [] /ActualText () >>"
    expect(rejected(actual),"explicit ActualText prevents empty-tag deletion")
    var bound = objects; bound[7] = "<< /Nums [0 [7 0 R 6 0 R]] >>"
    expect(rejected(bound),"ParentTree references prevent deletion")
    let cg = CGPDFDocument(CGDataProvider(data: deleted as CFData)!)!,page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream); var format = CGPDFDataFormat.raw
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data(content.utf8),"empty-tag deletion preserves original marked content stream")
    let suite = "BotPlusEmptyTag-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("empty-tag.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showStructure(item: item,view: view)
    let request = manager.structureRequest!,node = request.report.nodes.first { $0.title == "Empty" }!
    expect(request.deleteEmpty?(node) == nil,"empty-tag command installs atomic structure transaction")
    expect(request.deleteEmpty?(node) != nil,"stale empty-tag dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    let saved = try PDFDocumentExtras.structure(Data(contentsOf: item.url),russian: false)
    expect(saved.nodes.map(\.title) == ["Body"],"empty-tag deletion survives save/reopen")
    manager.undoDocument(redo: false)
    expect(tryTitles(manager,item) == ["Empty","Body"],"Undo restores removed empty tag")
    manager.undoDocument(redo: true)
    expect(tryTitles(manager,item) == ["Body"],"Redo restores tag deletion")
    func tryTitles(_ manager: DocumentManager,_ item: PDFDocumentItem) -> [String]? { try? PDFDocumentExtras.structure(manager.serializedData(item),russian: false).nodes.map(\.title) }
    print("PASS: empty-tag deletion, ID/ActualText/ParentTree/Ref refusal, literal-string distinction, preserved marked content and save/Undo/Redo")
}

@MainActor private func checkAffineMeasurements(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < max(0.00001,abs(b)*1e-8) }
    let scale = EngineeringScale(millimetersPerPoint: 1,unit: .mm)
    let diagonal = EngineeringMeasure(kind: .distance,points: [CGPoint(x: 100,y: 100),CGPoint(x: 200,y: 200)],scale: scale,dimensionOffset: 10)
    var options = EngineeringAffineOptions(); options.scaleX = 2; options.scaleY = 1; options.shearX = 0.5; options.center = .custom; options.preservingValue = false
    let changed = diagonal.transformed(options: options)!
    expect(changed.points == [CGPoint(x: 250,y: 100),CGPoint(x: 500,y: 200)] && close(changed.value,hypot(250,100)),"nonuniform/shear transform uses the declared matrix and PDF pivot")
    expect(close(changed.dimensionOffset!,10*2*hypot(100,100)/hypot(250,100)),"dimension spacing follows signed normal separation")
    options.preservingValue = true
    let preserved = diagonal.transformed(options: options)!
    expect(close(preserved.value,diagonal.value) && close(preserved.scale.millimetersPerPoint,diagonal.value/changed.value),"affine distance preservation adjusts aggregate calibration")
    var translation = EngineeringAffineOptions(); translation.offsetX = 50; translation.offsetY = -20
    let translated = diagonal.transformed(options: translation)!
    expect(!translation.isIdentity && translated.points == [CGPoint(x: 150,y: 80),CGPoint(x: 250,y: 180)] && close(translated.value,diagonal.value),"numeric translation retains calibrated value")
    let triangle = EngineeringMeasure(kind: .area,points: [CGPoint(x: 0,y: 0),CGPoint(x: 30,y: 0),CGPoint(x: 0,y: 20)],scale: scale,dimensionOffset: nil)
    options.preservingValue = false
    expect(close(triangle.transformed(options: options)!.value,triangle.value*2),"area follows affine determinant")
    options.preservingValue = true
    expect(close(triangle.transformed(options: options)!.value,triangle.value),"area preservation uses square-root calibration correction")
    var singular = EngineeringAffineOptions(); singular.shearX = 1; singular.shearY = 1
    expect(singular.linear == nil && triangle.transformed(options: singular) == nil,"singular shear is rejected")
    singular.shearY = 0.99999999
    expect(singular.linear == nil,"near-singular transforms are rejected")
    options.center = .selection
    expect(triangle.transformed(options: options) == nil,"selection center is required explicitly")
    let suite = "BotPlusAffine-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("affine-measure.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 200,y: 300),CGPoint(x: 300,y: 300)],view: view)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 500,y: 300),CGPoint(x: 600,y: 300)],view: view)
    let inks = page.annotations.filter { AnnotationMetadata.measurement($0) != nil },before = inks.map { AnnotationMetadata.measurement($0)! }
    view.selectAnnotations(inks); coordinator.showEngineeringTransform(item: item,view: view)
    let request = manager.engineeringTransformRequest!
    expect(request.selectionCenter == CGPoint(x: 400,y: 300) && request.applyAffine != nil,"affine dialog captures the common geometry center")
    var rotation = EngineeringAffineOptions(); rotation.degrees = 90; rotation.center = .selection
    item.historyDate = .distantPast
    expect(request.applyAffine?(rotation) == nil,"shared-pivot affine batch applies")
    expect(AnnotationMetadata.measurement(inks[0])!.points == [CGPoint(x: 400,y: 100),CGPoint(x: 400,y: 200)] && AnnotationMetadata.measurement(inks[1])!.points == [CGPoint(x: 400,y: 400),CGPoint(x: 400,y: 500)],"common-center rotation moves whole measurement groups together")
    expect(request.applyAffine?(rotation) != nil,"affine dialog rejects changed geometry")
    var affine = EngineeringAffineOptions(); affine.scaleX = 1.5; affine.scaleY = 0.8; affine.shearX = 0.25; affine.preservingValue = true
    item.historyDate = .distantPast
    expect(coordinator.transformMeasurements(inks,options: affine,item: item,view: view),"nonuniform/shear batch builds and validates all dependent parts")
    expect(inks.enumerated().allSatisfy { close(AnnotationMetadata.measurement($0.element)!.value,before[$0.offset].value) },"affine batch preserves chosen measured values")
    let history = item.undoHistory.count,oldPoints = AnnotationMetadata.measurement(inks[0])!.points
    expect(!coordinator.transformMeasurements(inks,options: singular,item: item,view: view) && item.undoHistory.count == history && AnnotationMetadata.measurement(inks[0])!.points == oldPoints,"invalid affine matrix rejects batch before history/mutation")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    expect(saved.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.allSatisfy { close($0.value,before[0].value) },"affine calibration and measurement metadata save/reopen")
    manager.undoDocument(redo: false); view.installDocument(item.document)
    let undone = item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }
    expect(undone.allSatisfy { $0.scale.millimetersPerPoint == before[0].scale.millimetersPerPoint },"Undo restores pre-affine calibration")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.contains { $0.scale.millimetersPerPoint != before[0].scale.millimetersPerPoint },"Redo restores affine calibration")
    print("PASS: affine/nonuniform/shear measurement transforms, common/custom pivots, signed dimension normals, calibration policies, singular guards and save/Undo/Redo")
}

@MainActor private func checkExtendedLayerUsage(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool,_ message: String) { if !value() { fatalError("CHECK FAILED: "+message) } }
    let content = "10 10 30 30 re f\n",objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R] /D << /BaseState /ON /Order [5 0 R 6 0 R] /AS [<< /Event /View /OCGs [5 0 R 6 0 R] /Category [/User] /Private (keep) >>] >> >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (Main) /Usage << /CreatorInfo << /Creator (Test) /Subtype /Technical >> /Export << /ExportState /ON /Private (retain) >> /Zoom << /min 0.25 /max 2 /Private (zoom) >> /Language << /Lang (en-US) /Preferred /OFF /Private (language) >> >> >>",
        "<< /Type /OCG /Name (Russian) /Usage << /Language << /Lang (ru-RU) /Preferred /ON >> >> >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8))
    let entry = try PDFDocumentExtras.layers(data).first { $0.id == 5 }!,initial = try PDFDocumentExtras.layerExtendedUsage(data,entry: entry)
    expect(initial.exportState == true && initial.zoomEnabled && initial.minZoom == 0.25 && initial.maxZoom == 2 && initial.language == "en-US" && initial.preferred == false,"extended usage reader preserves Export/Zoom/Language values")
    let options = PDFLayerExtendedUsage(exportState: false,zoomEnabled: true,minZoom: 0.5,maxZoom: 4,language: "ru",preferred: true,metadata: initial.metadata)
    let changed = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: true,printState: nil,intents: ["View","Design"],extended: options)
    let current = try PDFDocumentExtras.layers(changed).first { $0.id == 5 }!,saved = try PDFDocumentExtras.layerExtendedUsage(changed,entry: current)
    expect(saved == options && current.viewState == true && current.intent == ["View","Design"],"extended rules, intent and View state update together")
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef { var value: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(parent,key,&value); return value! }
    let props = dictionary(cg.catalog!,"OCProperties"),config = dictionary(props,"D")
    var applications: CGPDFArrayRef?; CGPDFDictionaryGetArray(config,"AS",&applications)
    var languageRules = 0,exportRules = 0,zoomRules = 0,preserved = false
    for index in 0..<CGPDFArrayGetCount(applications!) {
        var app: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(applications!,index,&app)
        var category: CGPDFArrayRef?; CGPDFDictionaryGetArray(app!,"Category",&category)
        var name: UnsafePointer<CChar>?; CGPDFArrayGetName(category!,0,&name); let value = String(cString: name!)
        if value == "Language" { languageRules += 1; var groups: CGPDFArrayRef?; CGPDFDictionaryGetArray(app!,"OCGs",&groups); expect(CGPDFArrayGetCount(groups!) == 2,"language AS evaluates all language groups together") }
        if value == "Export" { exportRules += 1 }; if value == "Zoom" { zoomRules += 1 }
        if value == "User" { preserved = true }
    }
    expect(languageRules == 1 && exportRules == 1 && zoomRules == 1 && preserved,"new usage applications preserve other category rules")
    var groups: CGPDFArrayRef?; CGPDFDictionaryGetArray(props,"OCGs",&groups); var group: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(groups!,0,&group)
    let usage = dictionary(group!,"Usage")
    var privateValue: CGPDFStringRef?; CGPDFDictionaryGetString(dictionary(usage,"Zoom"),"Private",&privateValue)
    var creator: CGPDFStringRef?; CGPDFDictionaryGetString(dictionary(usage,"CreatorInfo"),"Creator",&creator)
    expect(CGPDFStringCopyTextString(privateValue!)! as String == "zoom" && CGPDFStringCopyTextString(creator!)! as String == "Test","unknown properties of enabled categories and other Usage survive")
    let repeated = try PDFDocumentExtras.setLayerUsage(changed,entry: current,viewState: true,printState: nil,intents: nil,extended: options)
    let repeatedCG = CGPDFDocument(CGDataProvider(data: repeated as CFData)!)!,repeatedConfig = dictionary(dictionary(repeatedCG.catalog!,"OCProperties"),"D")
    var repeatedApplications: CGPDFArrayRef?; CGPDFDictionaryGetArray(repeatedConfig,"AS",&repeatedApplications)
    expect(CGPDFArrayGetCount(repeatedApplications!) == CGPDFArrayGetCount(applications!),"repeated edits do not duplicate owned AS applications")
    let cleared = try PDFDocumentExtras.setLayerUsage(changed,entry: current,viewState: nil,printState: nil,extended: PDFLayerExtendedUsage())
    let clearEntry = try PDFDocumentExtras.layers(cleared).first { $0.id == 5 }!,clearUsage = try PDFDocumentExtras.layerExtendedUsage(cleared,entry: clearEntry)
    expect(clearUsage == PDFLayerExtendedUsage(metadata: initial.metadata),"disabling rules removes Export/Zoom/Language categories and keeps unspecified metadata")
    var invalid = options; invalid.minZoom = 5; invalid.maxZoom = 4
    do { _ = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: nil,printState: nil,extended: invalid); fatalError("invalid zoom range accepted") } catch { }
    invalid = options; invalid.language = "not a language"
    expect(!invalid.valid,"usage language format validated")
    let suite = "BotPlusExtendedUsage-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("usage.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.layerCommand("layersRefresh",item: item,view: view); coordinator.showLayerPolicy("layerPolicy:5",item: item,view: view)
    let request = manager.layerPolicyRequest!
    expect(request.extended == initial && request.applyExtended != nil,"usage editor loads extended properties")
    expect(request.applyExtended?(true,nil,["View"],options) == nil,"extended usage editor installs atomic update")
    expect(request.applyExtended?(true,nil,["View"],options) != nil,"old extended-usage editor rejected")
    try manager.saveForClosing(item,to: item.url)
    let bytes = try Data(contentsOf: item.url),savedEntry = try PDFDocumentExtras.layers(bytes).first { $0.id == 5 }!
    expect(tryUsage(bytes,savedEntry) == options,"extended usage survives save/reopen")
    manager.undoDocument(redo: false)
    expect(tryCurrent(manager,item) == initial,"Undo restores complete extended Usage")
    manager.undoDocument(redo: true)
    expect(tryCurrent(manager,item) == options,"Redo restores extended Usage")
    func tryUsage(_ bytes: Data,_ entry: PDFLayerInfo) -> PDFLayerExtendedUsage? { try? PDFDocumentExtras.layerExtendedUsage(bytes,entry: entry) }
    func tryCurrent(_ manager: DocumentManager,_ item: PDFDocumentItem) -> PDFLayerExtendedUsage? { guard let bytes = try? manager.serializedData(item),let entry = try? PDFDocumentExtras.layers(bytes).first(where: { $0.id == 5 }) else { return nil }; return tryUsage(bytes,entry) }
    print("PASS: OCG Export/Zoom/Language/Preferred, whole-language AS scope, preserved opaque Usage, no duplicate applications and save/Undo/Redo")
}

@MainActor private func checkLayerUsageMetadata(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let content = "0 0 40 40 re f\n",objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R] /D << /Order [5 0 R] /AS [<< /Event /View /Category [/User] /OCGs [5 0 R] /Private (preserve) >>] >> >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (Metadata) /Usage << /CreatorInfo << /Creator (Original) /Subtype /Artwork /Private (creator) >> /User << /Type /Ind /Name (Alice) /Private (user) >> /PageElement << /Subtype /BG /Private (element) >> /Print << /Subtype /Watermark /PrintState /ON /Private (print) >> /Private (usage) >> >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8))
    func read(_ bytes: Data) throws -> PDFLayerExtendedUsage { try PDFDocumentExtras.layerExtendedUsage(bytes,entry: PDFDocumentExtras.layers(bytes)[0]) }
    let entry = try PDFDocumentExtras.layers(data)[0],initial = try read(data)
    expect(initial.metadata == PDFLayerUsageMetadata(creatorEnabled: true,creator: "Original",creatorSubtype: "Artwork",userType: "Ind",userNames: ["Alice"],pageElement: "BG",printSubtype: "Watermark"),"reads creator, single audience string, page element and Print subtype")
    do { _ = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: nil,printState: true,name: "  "); fatalError("blank layer rename accepted") } catch { }
    let metadata = PDFLayerUsageMetadata(creatorEnabled: true,creator: "BotPlus Δ",creatorSubtype: "Чертёж /1",userType: "Org",userNames: ["Проект (А)","Design\\Studio"],pageElement: "HF",printSubtype: "PrintersMarks")
    var options = initial; options.metadata = metadata
    let changed = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: nil,printState: false,extended: options)
    expect(try read(changed).metadata == metadata,"Unicode creator/subtype and multi-name audience round trip")
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef { var value: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(parent,key,&value); return value! }
    let props = dictionary(cg.catalog!,"OCProperties"),config = dictionary(props,"D")
    var groups: CGPDFArrayRef?; CGPDFDictionaryGetArray(props,"OCGs",&groups); var group: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(groups!,0,&group)
    let usage = dictionary(group!,"Usage")
    let savedPage = cg.page(at: 1)!
    var stream: CGPDFStreamRef?; CGPDFDictionaryGetStream(savedPage.dictionary!,"Contents",&stream); var format = CGPDFDataFormat.raw
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data(content.utf8),"metadata edits preserve decoded page content")
    for (category,expected) in [("CreatorInfo","creator"),("User","user"),("PageElement","element"),("Print","print")] {
        var value: CGPDFStringRef?; CGPDFDictionaryGetString(dictionary(usage,category),"Private",&value)
        expect(value != nil && CGPDFStringCopyTextString(value!)! as String == expected,"preserves opaque keys in enabled descriptive categories")
    }
    var rules: CGPDFArrayRef?; CGPDFDictionaryGetArray(config,"AS",&rules)
    expect(CGPDFArrayGetCount(rules!) == 2,"descriptive fields add no audience/creator auto-state rules")
    let legacy = try PDFDocumentExtras.setLayerUsage(changed,entry: entry,viewState: true,printState: nil)
    expect(try read(legacy).metadata == metadata,"legacy View/Print edits preserve metadata and Print subtype")
    for (type,role) in [("Ind","FG"),("Ttl","BG"),("Org","L")] {
        var alternate = metadata; alternate.userType = type; alternate.userNames = ["Одна запись"]; alternate.pageElement = role
        var value = options; value.metadata = alternate
        let bytes = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: nil,printState: nil,extended: value)
        expect(try read(bytes).metadata == alternate,"supported audience types and page roles survive single-name string encoding")
    }
    var cleared = options; cleared.metadata = PDFLayerUsageMetadata()
    let removed = try PDFDocumentExtras.setLayerUsage(changed,entry: entry,viewState: nil,printState: nil,extended: cleared)
    expect(try read(removed).metadata == PDFLayerUsageMetadata(),"explicitly clears descriptive categories and print subtype")
    var invalid = metadata; invalid.userNames = []; var badOptions = options; badOptions.metadata = invalid
    do { _ = try PDFDocumentExtras.setLayerUsage(data,entry: entry,viewState: nil,printState: nil,extended: badOptions); fatalError("audience without names accepted") } catch { }
    invalid = metadata; invalid.pageElement = "Unknown"; expect(!invalid.valid,"unsupported page role rejected")
    invalid = metadata; invalid.creatorSubtype = "bad\nname"; expect(!invalid.valid,"control characters rejected in PDF names")
    let suite = "BotPlusUsageMetadata-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("metadata.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.layerCommand("layersRefresh",item: item,view: view); coordinator.showLayerPolicy("layerPolicy:5",item: item,view: view)
    let request = manager.layerPolicyRequest!
    expect(request.extended?.metadata == initial.metadata,"metadata is available in layer policy editor")
    expect(request.applyNamed?(nil,false,["View"],options,"План Δ / Основной") == nil,"Unicode layer name and metadata apply in one document change")
    expect(request.applyExtended?(nil,false,["View"],options) != nil,"stale metadata dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try read(Data(contentsOf: item.url)).metadata == metadata,"metadata survives save/reopen")
    expect(try PDFDocumentExtras.layers(Data(contentsOf: item.url))[0].name == "План Δ / Основной","Unicode OCG name survives save/reopen")
    manager.undoDocument(redo: false)
    expect(try read(manager.serializedData(item)).metadata == initial.metadata,"Undo restores all descriptive fields")
    expect(try PDFDocumentExtras.layers(manager.serializedData(item))[0].name == "Metadata","one Undo restores layer name with usage")
    manager.undoDocument(redo: true)
    expect(try read(manager.serializedData(item)).metadata == metadata,"Redo restores all descriptive fields")
    expect(try PDFDocumentExtras.layers(manager.serializedData(item))[0].name == "План Δ / Основной","Redo restores layer name with usage")
    print("PASS: OCG creator/audience/page-role/print metadata, Unicode PDF names, opaque keys, source preservation, legacy compatibility and save/Undo/Redo")
}

@MainActor private func checkMeasurementPageTransfer(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    let suite = "BotPlusMeasureTransfer-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument()
    let source = PDFPage(),target = PDFPage(),small = PDFPage()
    source.setBounds(CGRect(x: 0,y: 0,width: 800,height: 800),for: .mediaBox); source.setBounds(CGRect(x: 20,y: 40,width: 700,height: 700),for: .cropBox)
    target.setBounds(CGRect(x: -60,y: 10,width: 1000,height: 1000),for: .mediaBox); target.setBounds(CGRect(x: -40,y: 30,width: 900,height: 900),for: .cropBox); target.rotation = 90
    small.setBounds(CGRect(x: 0,y: 0,width: 50,height: 50),for: .mediaBox)
    document.insert(source,at: 0); document.insert(target,at: 1); document.insert(small,at: 2)
    try EngineeringCalibration.write(EngineeringScale(millimetersPerPoint: 2,unit: .mm),page: source)
    let item = PDFDocumentItem(url: root.appendingPathComponent("measure-transfer.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: source,kind: .distance,points: [CGPoint(x: 200,y: 250),CGPoint(x: 300,y: 250)],view: view)
    coordinator.commitEngineering(page: source,kind: .area,points: [CGPoint(x: 400,y: 350),CGPoint(x: 450,y: 350),CGPoint(x: 400,y: 400)],view: view)
    let inks = source.annotations.filter { AnnotationMetadata.measurement($0) != nil },before = inks.map { AnnotationMetadata.measurement($0)! },sourceCalibration = EngineeringCalibration.read(source)!
    let history = item.undoHistory.count,parts = source.annotations.filter { AnnotationMetadata.group(of: $0) != nil },boxes = parts.map(\.bounds)
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 1,useTargetScale: true),item: item,view: view),"target calibration policy requires explicit scale")
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 2,centered: true),item: item,view: view),"oversized complete groups rejected atomically")
    AnnotationMetadata.setLocked(true,on: parts.last!)
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 1),item: item,view: view),"locked dependent part rejects entire transfer")
    AnnotationMetadata.setLocked(false,on: parts.last!)
    expect(item.undoHistory.count == history && zip(parts,boxes).allSatisfy { $0.0.page === source && $0.0.bounds == $0.1 },"rejected transfers change neither geometry nor history")
    try EngineeringCalibration.write(EngineeringScale(millimetersPerPoint: 0.5,unit: .mm),page: target)
    view.selectAnnotations(inks); coordinator.showEngineeringTransfer(item: item,view: view)
    let stale = manager.engineeringTransferRequest!
    view.selectAnnotation(inks[0])
    expect(stale.apply(EngineeringTransferOptions(pageIndex: 1)) != nil,"transfer dialog detects selection changes")
    view.selectAnnotations(inks); coordinator.showEngineeringTransfer(item: item,view: view)
    let request = manager.engineeringTransferRequest!,oldHistory = item.undoHistory.count
    expect(request.count == 2 && request.sourcePage == 0 && request.pageCount == 3,"transfer editor captures complete logical measurement selection")
    expect(request.apply(EngineeringTransferOptions(pageIndex: 1,offsetX: 10,offsetY: 5)) == nil,"moves complete selection with CropBox-relative coordinates")
    expect(item.undoHistory.count == oldHistory+1 && source.annotations.filter { AnnotationMetadata.group(of: $0) != nil }.isEmpty,"transfer records one Undo and removes complete source families")
    for (index,ink) in inks.enumerated() {
        let measurement = AnnotationMetadata.measurement(ink)!
        expect(ink.page === target && zip(measurement.points,before[index].points).allSatisfy { close($0.0.x,$0.1.x-50) && close($0.0.y,$0.1.y-5) },"transfer offsets are independent of destination rotation")
        expect(close(measurement.value,before[index].value) && measurement.scale.millimetersPerPoint == before[index].scale.millimetersPerPoint,"default transfer preserves calibration and value")
    }
    expect(zip(parts,boxes).allSatisfy { $0.0.page === target && close($0.0.bounds.minX,$0.1.minX-50) && close($0.0.bounds.minY,$0.1.minY-5) },"labels and dimension lines translate together")
    expect(EngineeringCalibration.read(source)!.millimetersPerPoint == sourceCalibration.millimetersPerPoint && EngineeringCalibration.read(target)!.millimetersPerPoint == 0.5,"page calibrations remain unchanged")
    expect(request.apply(EngineeringTransferOptions(pageIndex: 0)) != nil,"used transfer dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    expect(saved.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.isEmpty && saved.page(at: 1)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.count == 2,"transferred families survive PDF save/reopen")
    let savedTarget = saved.page(at: 1)!,savedCrop = savedTarget.bounds(for: .cropBox)
    for ink in savedTarget.annotations where AnnotationMetadata.measurement(ink) != nil {
        let measure = AnnotationMetadata.measurement(ink)!,old = before.first { $0.kind == measure.kind }!,vertices = try PDFAnnotationVertexGeometry.read(ink).first!.vertices
        expect(close(measure.points[0].x-savedCrop.minX,old.points[0].x-20+10) && close(measure.points[0].y-savedCrop.minY,old.points[0].y-40+5),"saved metadata follows PDFKit MediaBox normalization relative to CropBox")
        expect(vertices.count >= measure.points.count && zip(vertices,measure.points).allSatisfy { close($0.0.point.x,$0.1.x) && close($0.0.point.y,$0.1.y) },"reopened editable measurement points match native Ink geometry")
    }
    manager.undoDocument(redo: false); view.installDocument(item.document)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.count == 2 && item.document.page(at: 1)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.isEmpty,"one Undo restores source page and destination")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let currentTarget = item.document.page(at: 1)!,currentSource = item.document.page(at: 0)!,currentInks = currentTarget.annotations.filter { AnnotationMetadata.measurement($0) != nil }
    expect(currentInks.count == 2,"Redo restores destination families")
    try EngineeringCalibration.write(EngineeringScale(millimetersPerPoint: 3,unit: .mm),page: currentSource)
    expect(coordinator.transferMeasurements(currentInks,options: EngineeringTransferOptions(pageIndex: 0,centered: true,useTargetScale: true),item: item,view: view),"centered transfer can adopt destination scale")
    let combined = currentSource.annotations.filter { AnnotationMetadata.group(of: $0) != nil }.reduce(CGRect.null) { $0.union($1.bounds) },crop = currentSource.bounds(for: .cropBox)
    expect(close(combined.midX,crop.midX) && close(combined.midY,crop.midY),"center mode aligns all measurement parts together")
    expect(currentInks.allSatisfy { ink in let measure = AnnotationMetadata.measurement(ink)!,old = before.first { $0.kind == measure.kind }!; return close(measure.value,old.value*(measure.kind == .area ? 2.25 : 1.5)) },"destination calibration updates distance linearly and area quadratically")
    print("PASS: atomic measurement page transfer, CropBox origins/rotation, complete families, target calibration/center, locks/bounds/stale guards and save/Undo/Redo")
}

@MainActor private func checkLayerLockAuthoring(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let content = "0 0 10 10 re f\n",objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R] /D << /BaseState /ON /ON [5 0 R] /OFF [6 0 R] /Order [5 0 R 6 0 R] /RBGroups [[5 0 R 6 0 R]] /Locked [5 0 R] /AS [<< /Event /Print /Category [/Print] /OCGs [5 0 R] >>] >> /Configs [<< /Name (Alternative) /Locked [6 0 R] >>] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (First) /Usage << /CreatorInfo << /Creator (Test) /Subtype /Technical >> >> >>","<< /Type /OCG /Name (Second) >>"
    ]
    func fixture(_ objects: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
    }
    let data = fixture(objects),entry = try PDFDocumentExtras.layers(data)[0]
    expect(entry.locked,"native Locked reader loads authoring state")
    let unlocked = try PDFDocumentExtras.setLayerLocked(data,entry: entry,locked: false),current = try PDFDocumentExtras.layers(unlocked)[0]
    expect(!current.locked && current.visible == entry.visible,"unlock changes advisory lock without visibility")
    do { _ = try PDFDocumentExtras.setLayerLocked(unlocked,entry: entry,locked: true); fatalError("stale lock state accepted") } catch PDFSourceError.alreadyUsed { }
    let second = try PDFDocumentExtras.layers(unlocked)[1],toggled = try PDFDocumentExtras.setLayer(unlocked,entry: second,visible: true),state = try PDFDocumentExtras.layers(toggled)
    expect(!state[0].visible && state[1].visible,"radio visibility becomes editable after unlocking")
    let relocked = try PDFDocumentExtras.setLayerLocked(toggled,entry: state[1],locked: true),lockedSecond = try PDFDocumentExtras.layers(relocked)[1]
    do { _ = try PDFDocumentExtras.setLayer(relocked,entry: lockedSecond,visible: false); fatalError("authored Locked ignored") } catch PDFSourceError.permission { }
    let cg = CGPDFDocument(CGDataProvider(data: unlocked as CFData)!)!
    func dictionary(_ parent: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef { var value: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(parent,key,&value); return value! }
    let props = dictionary(cg.catalog!,"OCProperties"),config = dictionary(props,"D")
    var alternatives: CGPDFArrayRef?; CGPDFDictionaryGetArray(props,"Configs",&alternatives); var alternate: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(alternatives!,0,&alternate)
    var alternateLocks: CGPDFArrayRef?; CGPDFDictionaryGetArray(alternate!,"Locked",&alternateLocks)
    var radio: CGPDFArrayRef?; CGPDFDictionaryGetArray(config,"RBGroups",&radio); var rules: CGPDFArrayRef?; CGPDFDictionaryGetArray(config,"AS",&rules)
    expect(CGPDFArrayGetCount(alternateLocks!) == 1 && CGPDFArrayGetCount(radio!) == 1 && CGPDFArrayGetCount(rules!) == 1,"editing default Locked retains alternatives, radio groups and usage applications")
    var malformed = objects; malformed[0] = malformed[0].replacingOccurrences(of: "/Locked [5 0 R]",with: "/Locked [5 0 R 99 0 R]")
    do { _ = try PDFDocumentExtras.setLayerLocked(fixture(malformed),entry: entry,locked: false); fatalError("unknown Locked reference dropped") } catch { }
    let suite = "BotPlusLayerLocks-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("layer-lock.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.layerCommand("layersRefresh",item: item,view: view)
    coordinator.layerCommand("layerLock:5:0",item: item,view: view)
    expect(manager.layerError == nil && manager.layerEntries.first { $0.id == 5 }?.locked == false,"layer lock button installs source transaction")
    let history = item.undoHistory.count; coordinator.layerCommand("layerLock:5:0",item: item,view: view)
    expect(item.undoHistory.count == history,"setting current lock state avoids extra history")
    try manager.saveForClosing(item,to: item.url)
    expect(try PDFDocumentExtras.layers(Data(contentsOf: item.url))[0].locked == false,"authored lock survives save/reopen")
    manager.undoDocument(redo: false)
    expect(try PDFDocumentExtras.layers(manager.serializedData(item))[0].locked,"Undo restores default Locked")
    manager.undoDocument(redo: true)
    expect(try PDFDocumentExtras.layers(manager.serializedData(item))[0].locked == false,"Redo restores authored lock")
    print("PASS: default OCG Locked authoring/unlock, radio/AS/preset preservation, malformed and stale guards, no-op history and save/Undo/Redo")
}

@MainActor private func checkWrittenInkOriginRepair() throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let content = "0 0 20 20 re f\n",appearance = "0 0 2 2 re f\n"
    func fixture(_ stroke: String) -> Data {
        let objects = ["<< /Type /Catalog /Pages 2 0 R >>","<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Annots [<< /Type /Annot /Subtype /Ink /Rect [10 20 80 90] /InkList \(stroke) /AP << /N 7 0 R >> >> 6 0 R] >>",
            "<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream","<< /Unrelated (unchanged) >>",
            "<< /Type /Annot /Subtype /Text /Rect [100 100 120 120] /Contents (Keep) >>",
            "<< /Type /XObject /Subtype /Form /BBox [0 0 2 2] /Resources << >> /Length \(appearance.utf8.count) >>\nstream\n"+appearance+"endstream"]
        var bytes = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in objects.enumerated() { offsets.append(bytes.count); bytes.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = bytes.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; bytes.append(Data(end.utf8)); return bytes
    }
    let original = fixture("[[20 30] [40 50 60 70]]"),changed = try PDFDocumentExtras.repairWrittenInk(original,originalOrigins: [0:CGPoint(x: -10,y: 20)])
    expect(changed.prefix(original.count) == original,"Ink repair appends changes to exact writer output")
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!,page = cg.page(at: 1)!
    var annots: CGPDFArrayRef?; CGPDFDictionaryGetArray(page.dictionary!,"Annots",&annots); var ink: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(annots!,0,&ink)
    var strokes: CGPDFArrayRef?; CGPDFDictionaryGetArray(ink!,"InkList",&strokes)
    var actual: [[Double]] = []
    for index in 0..<CGPDFArrayGetCount(strokes!) { var stroke: CGPDFArrayRef?; CGPDFArrayGetArray(strokes!,index,&stroke); actual.append((0..<CGPDFArrayGetCount(stroke!)).map { position in var number: CGPDFReal = 0; CGPDFArrayGetNumber(stroke!,position,&number); return Double(number) }) }
    expect(actual == [[30,10],[50,30,70,50]],"direct annotation InkList supports point strokes and translates absolute coordinates")
    var ap: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(ink!,"AP",&ap); var appearanceStream: CGPDFStreamRef?; CGPDFDictionaryGetStream(ap!,"N",&appearanceStream)
    var format = CGPDFDataFormat.raw,contentStream: CGPDFStreamRef?; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&contentStream)
    expect(CGPDFStreamCopyData(appearanceStream!,&format)! as Data == Data(appearance.utf8) && CGPDFStreamCopyData(contentStream!,&format)! as Data == Data(content.utf8),"Ink repair retains appearance and page content streams")
    var note: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(annots!,1,&note); var text: CGPDFStringRef?; CGPDFDictionaryGetString(note!,"Contents",&text)
    expect(CGPDFStringCopyTextString(text!)! as String == "Keep","Ink repair retains unrelated annotation references")
    expect(try PDFDocumentExtras.repairWrittenInk(changed,originalOrigins: [0:.zero]) == changed,"normalized document is not translated again")
    do { _ = try PDFDocumentExtras.repairWrittenInk(fixture("[[20 30 40]]"),originalOrigins: [0:CGPoint(x: -10,y: 20)]); fatalError("odd InkList coordinates repaired silently") } catch { }
    print("PASS: raw InkList origin repair, direct dictionaries/point strokes, exact source prefix, retained AP/content/other annotations, no repeat shift and malformed input refusal")
}

@MainActor private func checkLayerRadioAuthoring(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let content = "/OC /M BDC 0 0 20 20 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R 8 0 R] /D << /Name (Default) /BaseState /ON /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] /Locked [8 0 R] /RBGroups [[5 0 R 6 0 R]] /Order [(Sheets) [5 0 R 6 0 R 7 0 R 8 0 R]] /AS [<< /Event /Print /Category [/Print] /OCGs [8 0 R] >>] /Private (keep) >> /Configs [9 0 R 10 0 R 11 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Properties << /M 12 0 R >> >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) /Usage << /CreatorInfo << /Creator (Test) /Subtype /Technical >> >> >>","<< /Type /OCG /Name (B) >>","<< /Type /OCG /Name (C) >>","<< /Type /OCG /Name (D) >>",
        "<< /Name (Explicit) /BaseState /OFF /Intent /View /ON [7 0 R] /OFF [5 0 R 6 0 R 8 0 R] /Locked [8 0 R] /RBGroups [[7 0 R 8 0 R]] /Private (alternative) >>",
        "<< /Name (Inherited) /BaseState /OFF /Intent /View /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] >>",
        "<< /Name (Empty) /BaseState /ON /RBGroups [] >>","<< /Type /OCMD /VE [/And 5 0 R [/Not 6 0 R]] >>"
    ]
    func fixture(_ bodies: [String]) -> Data {
        var bytes = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in bodies.enumerated() { offsets.append(bytes.count); bytes.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = bytes.count; var end = "xref\n0 \(bodies.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(bodies.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; bytes.append(Data(end.utf8)); return bytes
    }
    let data = fixture(objects),report = try PDFDocumentExtras.layerStateReport(data),primary = report.configurations.first { $0.id == -1 }!,inherited = report.configurations.first { $0.id == 1 }!
    expect(inherited.radios == [[5,6]] && inherited.radiosInherited && report.configurations.first { $0.id == 2 }?.radios == [],"missing RBGroups inherits default while explicit empty disables inheritance")
    let desired = [[5,7],[6,8]],changed = try PDFDocumentExtras.setLayerRadios(data,entry: primary,radios: desired),changedReport = try PDFDocumentExtras.layerStateReport(changed)
    expect(changedReport.configurations.first { $0.id == -1 }?.radios == desired && changedReport.configurations.first { $0.id == 1 }?.radios == desired,"default radio editing updates effective inherited groups")
    expect(changedReport.groups.map(\.visible) == report.groups.map(\.visible) && changedReport.configurations.first { $0.id == 0 } == report.configurations.first { $0.id == 0 },"radio editing preserves visibility and explicit alternatives")
    for bad in [[[5]],[[5,5]],[[5,999]],[[5,6],[6,5]]] {
        do {
            _ = try PDFDocumentExtras.setLayerRadios(data,entry: primary,radios: bad); fatalError("invalid radio membership accepted")
        } catch { }
    }
    do { _ = try PDFDocumentExtras.setLayerRadios(data,entry: primary,radios: nil); fatalError("default inherits itself") } catch { }
    do { _ = try PDFDocumentExtras.setLayerRadios(changed,entry: primary,radios: []); fatalError("stale radio configuration accepted") } catch { }
    var conflict = objects; conflict[9] = "<< /Name (Inherited) /BaseState /OFF /ON [5 0 R 7 0 R] /OFF [6 0 R 8 0 R] >>"
    let conflictData = fixture(conflict),conflictEntry = try PDFDocumentExtras.layerStateReport(conflictData).configurations.first { $0.id == -1 }!
    do { _ = try PDFDocumentExtras.setLayerRadios(conflictData,entry: conflictEntry,radios: [[5,7]]); fatalError("conflicting inherited ON states accepted") } catch PDFSourceError.permission { }
    let disabled = try PDFDocumentExtras.setLayerRadios(data,entry: inherited,radios: []),disabledEntry = try PDFDocumentExtras.layerStateReport(disabled).configurations.first { $0.id == 1 }!
    expect(!disabledEntry.radiosInherited && disabledEntry.radios.isEmpty,"empty radio list writes explicit opt-out")
    let reset = try PDFDocumentExtras.setLayerRadios(disabled,entry: disabledEntry,radios: nil),resetEntry = try PDFDocumentExtras.layerStateReport(reset).configurations.first { $0.id == 1 }!
    expect(resetEntry.radiosInherited && resetEntry.radios == primary.radios,"inheritance reset removes explicit RBGroups")
    let explicit = report.configurations.first { $0.id == 0 }!,alternativeChange = try PDFDocumentExtras.setLayerRadios(data,entry: explicit,radios: [[5,7],[6,8]])
    expect(try PDFDocumentExtras.layerStateReport(alternativeChange).configurations.first { $0.id == -1 } == primary,"alternative radio edit does not activate or rewrite default")
    let overlap = try PDFDocumentExtras.setLayerRadios(data,entry: primary,radios: [[5,6],[5,7]])
    expect(try PDFDocumentExtras.layerStateReport(overlap).configurations.first { $0.id == -1 }?.radios == [[5,6],[5,7]],"overlapping radio groups are supported")
    let swap = try PDFDocumentExtras.makeLayerPresetDefault(data,index: 0),swapped = try PDFDocumentExtras.layerStateReport(swap)
    expect(swapped.configurations.first { $0.id == -1 }?.radios == [[7,8]] && swapped.configurations.first { $0.id == 1 }?.radios == [[5,6]] && swapped.configurations.first { $0.id == 1 }?.radiosInherited == false,"default swap materializes previous inheritance to preserve alternative relationships")
    let inheritedSwap = try PDFDocumentExtras.makeLayerPresetDefault(data,index: 1)
    expect(try PDFDocumentExtras.layerStateReport(inheritedSwap).configurations.first { $0.id == -1 }?.radios == [[5,6]],"inherited groups are retained when chosen configuration becomes default")
    let c = try PDFDocumentExtras.layers(changed).first { $0.id == 7 }!,toggled = try PDFDocumentExtras.setLayer(changed,entry: c,visible: true),states = try PDFDocumentExtras.layers(toggled)
    expect(states.first { $0.id == 7 }?.visible == true && states.first { $0.id == 5 }?.visible == false,"new radio membership enforces mutual exclusion on layer toggle")
    let cg = CGPDFDocument(CGDataProvider(data: changed as CFData)!)!,page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data(content.utf8),"radio authoring retains original marked content")
    expect(try PDFDocumentExtras.membershipConfiguration(changed).entries.first?.expression == "And(#5, Not(#6))","radio authoring retains OCMD expression")
    let suite = "BotPlusRadioAuthoring-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("radios.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showLayerRadioEditor(item: item,view: view)
    let request = manager.layerRadioRequest!,beforeHistory = item.undoHistory.count
    expect(request.apply(primary,primary.radios) == nil && item.undoHistory.count == beforeHistory,"unchanged radio list creates no history")
    expect(request.apply(primary,desired) == nil && item.undoHistory.count == beforeHistory+1,"radio editor applies one atomic transaction")
    expect(request.apply(primary,[]) != nil,"stale radio editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try PDFDocumentExtras.layerStateReport(Data(contentsOf: item.url)).configurations.first { $0.id == -1 }?.radios == desired,"radio groups survive save/reopen")
    manager.undoDocument(redo: false)
    expect(try PDFDocumentExtras.layerStateReport(manager.serializedData(item)).configurations.first { $0.id == -1 }?.radios == [[5,6]],"Undo restores radio membership")
    manager.undoDocument(redo: true)
    expect(try PDFDocumentExtras.layerStateReport(manager.serializedData(item)).configurations.first { $0.id == -1 }?.radios == desired,"Redo restores radio membership")
    print("PASS: OCG radio authoring/overlap/inheritance/empty opt-out, default swap, conflicting states, stale/invalid guards, toggle semantics and save/Undo/Redo")
}

@MainActor private func checkLayerOrderEditing(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let content = "/OC /M BDC 10 10 20 20 re f EMC\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [5 0 R 6 0 R 7 0 R 8 0 R] /D << /Name (Default) /BaseState /ON /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] /Locked [8 0 R] /RBGroups [[6 0 R 7 0 R]] /Order 13 0 R /Private (keep) /AS [<< /Event /Print /OCGs [8 0 R] /Category [/Print] >>] >> /Configs [9 0 R 10 0 R 11 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Properties << /M 12 0 R >> >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>","<< /Type /OCG /Name (C) >>","<< /Type /OCG /Name (D) >>",
        "<< /Name (Explicit) /BaseState /OFF /Intent /View /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] /Order [8 0 R 5 0 R] >>",
        "<< /Name (Inherited) /BaseState /OFF /Intent /View /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] >>",
        "<< /Name (Empty) /BaseState /OFF /Order [] >>","<< /Type /OCMD /VE [/And 5 0 R [/Not 6 0 R]] >>",
        "[5 0 R [6 0 R 7 0 R] [<FEFF041E044204340435043B> 8 0 R 6 0 R] 7 0 R]"
    ]
    func fixture(_ bodies: [String]) -> Data {
        var data = Data("%PDF-1.7\n".utf8),offsets = [0]
        for (index,body) in bodies.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
        let xref = data.count; var end = "xref\n0 \(bodies.count+1)\n0000000000 65535 f \n"
        for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
        end += "trailer\n<< /Size \(bodies.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
    }
    func configurations(_ data: Data) throws -> [PDFLayerOrderConfiguration] { try PDFDocumentExtras.layerOrderConfigurations(data) }
    func primary(_ data: Data) throws -> PDFLayerOrderConfiguration { try configurations(data).first { $0.id == -1 }! }
    let data = fixture(objects),report = try configurations(data),entry = try primary(data)
    expect(entry.editable && entry.rows.map(\.title) == ["A","B","C","Отдел","D","B","C"],"Order reader preserves heading Unicode, nested arrays and repeated OCG occurrences")
    expect(entry.rows.map(\.path) == [[0],[0,0],[0,1],[1],[1,0],[1,1],[2]] && entry.rows.map(\.depth) == [0,1,1,0,1,1,0],"Order paths address logical parent/child clusters")
    expect(report.first { $0.id == 1 }?.inherited == true && report.first { $0.id == 2 }?.rows.isEmpty == true && report.first { $0.id == 2 }?.inherited == false,"missing Order inherits default, explicit empty remains independent")
    let moved = try PDFDocumentExtras.editLayerOrder(data,entry: entry,operation: .move([0],1)),movedEntry = try primary(moved)
    expect(movedEntry.rows.map(\.title) == ["Отдел","D","B","A","B","C","C"] && movedEntry.rows.first { $0.layerID == 5 }?.path == [1],"moving parent carries its child array and keeps heading separate")
    let nested = try PDFDocumentExtras.editLayerOrder(data,entry: entry,operation: .move([0,0],1)),nestedEntry = try primary(nested)
    expect(nestedEntry.rows.map(\.title) == ["A","C","B","Отдел","D","B","C"],"nested sibling reordering changes one occurrence of a repeated OCG")
    let heading = try PDFDocumentExtras.editLayerOrder(data,entry: entry,operation: .move([1],1)),headingEntry = try primary(heading)
    expect(headingEntry.rows.map(\.title) == ["A","B","C","C","Отдел","D","B"],"heading moves with its complete subtree")
    let inherited = report.first { $0.id == 1 }!,independent = try PDFDocumentExtras.editLayerOrder(data,entry: inherited,operation: .move([0],1)),independentEntry = try configurations(independent).first { $0.id == 1 }!
    let independentPrimary = try primary(independent)
    expect(!independentEntry.inherited && independentEntry.rows.map(\.title) == movedEntry.rows.map(\.title) && independentPrimary == entry,"editing inherited Order creates independent alternative without activating it")
    let reset = try PDFDocumentExtras.editLayerOrder(independent,entry: independentEntry,operation: .inherit),resetEntry = try configurations(reset).first { $0.id == 1 }!
    expect(resetEntry.inherited && resetEntry.rows == inherited.rows,"reset removes explicit Order and restores inheritance")
    for operation in [PDFLayerOrderOperation.move([],1),.move([0],-1),.move([2],1),.move([0],0),.move([99],1),.move([2,0],1),.inherit] {
        do { _ = try PDFDocumentExtras.editLayerOrder(data,entry: entry,operation: operation); fatalError("invalid Order operation accepted") } catch { }
    }
    do { _ = try PDFDocumentExtras.editLayerOrder(moved,entry: entry,operation: .move([0],1)); fatalError("stale Order configuration accepted") } catch { }
    var shared = objects; shared[8] = shared[8].replacingOccurrences(of: "/Order [8 0 R 5 0 R]",with: "/Order 13 0 R")
    let sharedData = fixture(shared),sharedChange = try PDFDocumentExtras.editLayerOrder(sharedData,entry: primary(sharedData),operation: .move([0],1))
    expect(try configurations(sharedChange).first { $0.id == 0 }?.rows.map(\.title) == entry.rows.map(\.title),"shared indirect Order arrays are isolated when selected configuration changes")
    for invalid in ["[13 0 R]","[99 0 R]",String(repeating: "[",count: 65)+"5 0 R"+String(repeating: "]",count: 65)] {
        var bad = objects; bad[12] = invalid
        expect(try primary(fixture(bad)).editable == false,"cyclic, unknown or excessive-depth Order remains read-only")
    }
    let swap = try PDFDocumentExtras.makeLayerPresetDefault(data,index: 0),swapReport = try configurations(swap)
    expect(swapReport.first { $0.id == -1 }?.rows.map(\.title) == ["D","A"] && swapReport.first { $0.id == 1 }?.rows.map(\.title) == entry.rows.map(\.title) && swapReport.first { $0.id == 1 }?.inherited == false,"default swap preserves formerly inherited Order of other configurations")
    let beforeStates = try PDFDocumentExtras.layerStateReport(data),afterStates = try PDFDocumentExtras.layerStateReport(moved)
    expect(beforeStates.configurations == afterStates.configurations && beforeStates.groups.map(\.visible) == afterStates.groups.map(\.visible),"Order editing preserves states, locks, radio groups and configuration activation")
    let cg = CGPDFDocument(CGDataProvider(data: moved as CFData)!)!,page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data(content.utf8),"Order editing preserves original marked page content")
    expect(try PDFDocumentExtras.membershipConfiguration(moved).entries.first?.expression == "And(#5, Not(#6))","Order editing preserves OCMD visibility expression")
    let suite = "BotPlusOrderEditing-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("layer-order.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showLayerOrderEditor(item: item,view: view)
    let request = manager.layerOrderRequest!,history = item.undoHistory.count
    expect(request.apply(entry,.move([1],1)) == nil && item.undoHistory.count == history+1,"Order editor applies one history transaction")
    expect(request.apply(entry,.move([1],1)) != nil,"stale Order dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try primary(Data(contentsOf: item.url)).rows.map(\.title) == headingEntry.rows.map(\.title),"Order hierarchy survives save/reopen")
    manager.undoDocument(redo: false)
    expect(try primary(manager.serializedData(item)).rows == entry.rows,"Undo restores complete Order tree")
    manager.undoDocument(redo: true)
    expect(try primary(manager.serializedData(item)).rows == headingEntry.rows,"Redo restores reordered tree")
    print("PASS: nested OCG Order sibling/subtree moves, Unicode labels, repeats/shared arrays/inheritance, default swap, cycles/limits/stale guards and save/Undo/Redo")
}

private func orderAuthoringFixture(order: String = "[5 0 R [6 0 R] [(Existing) 7 0 R] 8 0 R]",membershipRegistry: String? = nil) -> Data {
    let content = "/OC /M BDC 10 10 20 20 re f EMC\n",objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << \(membershipRegistry.map { "/BotPlusOCMDs "+$0+" " } ?? "")/OCGs [5 0 R 6 0 R 7 0 R 8 0 R] /D << /Name (Default) /BaseState /ON /ON [5 0 R] /OFF [6 0 R 7 0 R 8 0 R] /Locked [8 0 R] /RBGroups [[5 0 R 8 0 R]] /Order 12 0 R /AS [<< /Event /Print /OCGs [8 0 R] /Category [/Print] >>] >> /Configs [9 0 R 10 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents 4 0 R /Resources << /Properties << /M 11 0 R >> >> >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) /Usage << /View << /ViewState /ON >> >> >>","<< /Type /OCG /Name (B) >>","<< /Type /OCG /Name (C) >>","<< /Type /OCG /Name (D) >>",
        "<< /Name (Empty) /BaseState /OFF /Order [] >>","<< /Name (Inherited) /BaseState /OFF >>","<< /Type /OCMD /VE [/And 5 0 R [/Not 6 0 R]] >>",order
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
}

@MainActor private func checkOrderSections(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func entry(_ bytes: Data,_ id: Int = -1) throws -> PDFLayerOrderConfiguration { try PDFDocumentExtras.layerOrderConfigurations(bytes).first { $0.id == id }! }
    let data = orderAuthoringFixture(),original = try entry(data),name = "Новый (Δ) / Раздел"
    let inserted = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .addSection(nil,name)),insertedEntry = try entry(inserted)
    expect(insertedEntry.rows.last?.title == name && insertedEntry.rows.last?.path == [3] && insertedEntry.rows.last?.canRemove == true,"root section stores Unicode and is removable while empty")
    let child = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .addSection([0],name)),childEntry = try entry(child)
    expect(childEntry.rows.first { $0.path == [0,1] }?.title == name && childEntry.rows.first { $0.path == [0,0] }?.layerID == 6,"section insertion preserves existing child array")
    let renamed = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .renameSection([1],name)),renamedEntry = try entry(renamed)
    expect(renamedEntry.rows.first { $0.path == [1] }?.title == name && renamedEntry.rows.first { $0.path == [1,0] }?.layerID == 7,"heading rename preserves children")
    expect(try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .renameSection([1],"Existing")) == data,"unchanged title is a no-op")
    let repeated = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .addLayer([1],6)),repeatedEntry = try entry(repeated)
    expect(repeatedEntry.rows.filter { $0.layerID == 6 }.count == 2 && repeatedEntry.rows.first { $0.path == [1,1] }?.layerID == 6,"existing OCG can have independent occurrences")
    let removedChild = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .removeLeaf([0,0])),removedChildEntry = try entry(removedChild)
    expect(removedChildEntry.rows.first { $0.path == [0] }?.canRemove == true && removedChildEntry.rows.filter { $0.layerID == 6 }.isEmpty,"leaf removal makes empty parent removable")
    let removedParent = try PDFDocumentExtras.editLayerOrder(removedChild,entry: removedChildEntry,operation: .removeLeaf([0]))
    expect(try PDFDocumentExtras.layerCatalogGroups(removedParent).map(\.id) == [5,6,7,8],"removing Order occurrence leaves catalog OCG intact")
    let removedSection = try PDFDocumentExtras.editLayerOrder(inserted,entry: insertedEntry,operation: .removeLeaf([3]))
    expect(try entry(removedSection).rows == original.rows,"removing empty section restores original presentation tree")
    let inherited = try entry(data,1),independent = try PDFDocumentExtras.editLayerOrder(data,entry: inherited,operation: .addSection(nil,name))
    let independentPrimary = try entry(independent),independentAlternative = try entry(independent,1)
    expect(independentPrimary == original && !independentAlternative.inherited && independentAlternative.rows.last?.title == name,"adding to inherited Order isolates the alternative")
    let empty = try entry(data,0),populated = try PDFDocumentExtras.editLayerOrder(data,entry: empty,operation: .addLayer(nil,8))
    expect(try entry(populated,0).rows.map(\.layerID) == [8],"explicit empty Order accepts an existing locked OCG reference without visibility changes")
    for operation in [PDFLayerOrderOperation.addSection(nil,"  "),.addSection(nil,"bad\nname"),.addSection(nil,String(repeating: "a",count: 4097)),.renameSection([0],"Wrong"),.removeLeaf([0]),.removeLeaf([1]),.addLayer(nil,999),.addSection([],name),.addLayer([99],5)] {
        do { _ = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: operation); fatalError("invalid Order authoring accepted") } catch { }
    }
    let ambiguous = orderAuthoringFixture(order: "[[(H)] 5 0 R [(Q)] [6 0 R]]"),ambiguousEntry = try entry(ambiguous)
    do { _ = try PDFDocumentExtras.editLayerOrder(ambiguous,entry: ambiguousEntry,operation: .removeLeaf([2])); fatalError("anonymous array silently attached to another parent") } catch { }
    let deep = orderAuthoringFixture(order: String(repeating: "[",count: 64)+"5 0 R"+String(repeating: "]",count: 64)),deepEntry = try entry(deep)
    expect(deepEntry.editable,"tree at supported depth remains readable")
    do { _ = try PDFDocumentExtras.editLayerOrder(deep,entry: deepEntry,operation: .addSection(deepEntry.rows.last!.path,name)); fatalError("new section exceeds depth budget") } catch { }
    let before = try PDFDocumentExtras.layerStateReport(data),after = try PDFDocumentExtras.layerStateReport(repeated)
    expect(before.configurations == after.configurations && before.groups.map(\.visible) == after.groups.map(\.visible),"authoring leaves visibility, radios, locks and configuration activation unchanged")
    let cg = CGPDFDocument(CGDataProvider(data: removedParent as CFData)!)!,page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data("/OC /M BDC 10 10 20 20 re f EMC\n".utf8),"Order deletion preserves original page content")
    expect(try PDFDocumentExtras.membershipConfiguration(removedParent).entries.first?.expression == "And(#5, Not(#6))","Order deletion preserves OCMD references")
    let suite = "BotPlusOrderSections-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("order-sections.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showLayerOrderEditor(item: item,view: view)
    let request = manager.layerOrderRequest!,history = item.undoHistory.count
    expect(request.layers.count == 4 && request.apply(original,.renameSection([1],"Existing")) == nil && item.undoHistory.count == history,"editor supplies catalog layers and preserves no-op history")
    expect(request.apply(original,.addSection(nil,name)) == nil && item.undoHistory.count == history+1,"section authoring records one transaction")
    expect(request.apply(original,.addSection(nil,"Stale")) != nil,"old section editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try entry(Data(contentsOf: item.url)).rows.last?.title == name,"Unicode section survives save/reopen")
    manager.undoDocument(redo: false)
    expect(try entry(manager.serializedData(item)).rows == original.rows,"Undo restores original Order")
    manager.undoDocument(redo: true)
    expect(try entry(manager.serializedData(item)).rows.last?.title == name,"Redo restores new section")
    print("PASS: Order section creation/rename, repeated OCG insertion, leaf removal, catalog/content/state preservation, grammar/depth/stale guards and save/Undo/Redo")
}

@MainActor private func checkOrderReparenting(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func entry(_ bytes: Data,_ id: Int = -1) throws -> PDFLayerOrderConfiguration { try PDFDocumentExtras.layerOrderConfigurations(bytes).first { $0.id == id }! }
    let data = orderAuthoringFixture(),original = try entry(data)
    let later = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([0],[1])),laterEntry = try entry(later)
    expect(laterEntry.rows.map(\.title) == ["Existing","C","A","B","D"] && laterEntry.rows.first { $0.layerID == 5 }?.path == [0,1] && laterEntry.rows.first { $0.layerID == 6 }?.path == [0,1,0],"moving subtree into later sibling adjusts destination index and keeps descendants")
    let earlier = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([1],[0])),earlierEntry = try entry(earlier)
    expect(earlierEntry.rows.map(\.title) == ["A","B","Existing","C","D"] && earlierEntry.rows.first { $0.title == "Existing" }?.path == [0,1],"heading can move into earlier layer with its children")
    let leaf = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([0,0],[1])),leafEntry = try entry(leaf)
    expect(leafEntry.rows.map(\.title) == ["A","Existing","C","B","D"] && leafEntry.rows.first { $0.layerID == 5 }?.canRemove == true && leafEntry.rows.first { $0.layerID == 6 }?.path == [1,1],"moving last child leaves source parent empty and appends to destination")
    let newParent = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([2],[0,0])),newParentEntry = try entry(newParent)
    expect(newParentEntry.rows.first { $0.layerID == 8 }?.path == [0,0,0],"leaf OCG can acquire its own child array")
    let toRoot = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([1,0],nil)),rootEntry = try entry(toRoot)
    expect(rootEntry.rows.map(\.title) == ["A","B","Existing","D","C"] && rootEntry.rows.last?.path == [3],"moving to root appends after existing root siblings")
    expect(try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([0,0],[0])) == data,"same parent is a no-op")
    expect(try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: .reparent([0],nil)) == data,"root-to-root is a no-op")
    let repeated = orderAuthoringFixture(order: "[5 0 R [6 0 R 7 0 R] [(Left) 6 0 R 8 0 R] [(Right) 7 0 R]]"),repeatedEntry = try entry(repeated)
    let deepSibling = try PDFDocumentExtras.editLayerOrder(repeated,entry: repeatedEntry,operation: .reparent([0,0],[0,1])),deepSiblingEntry = try entry(deepSibling)
    expect(deepSiblingEntry.rows.first { $0.path == [0,0,0] }?.layerID == 6 && deepSiblingEntry.rows.first { $0.path == [1,0] }?.layerID == 6,"nested later-sibling adjustment preserves other occurrences of same OCG")
    let heading = try PDFDocumentExtras.editLayerOrder(repeated,entry: repeatedEntry,operation: .reparent([1],[2])),headingEntry = try entry(heading)
    expect(headingEntry.rows.first { $0.title == "Left" }?.path == [1,1] && headingEntry.rows.first { $0.title == "Right" }?.path == [1],"moving heading to a later heading preserves destination identity")
    let ancestor = orderAuthoringFixture(order: "[5 0 R [6 0 R [7 0 R]] 8 0 R]"),ancestorEntry = try entry(ancestor)
    let ancestorMove = try PDFDocumentExtras.editLayerOrder(ancestor,entry: ancestorEntry,operation: .reparent([0,0,0],[0])),ancestorMoved = try entry(ancestorMove)
    expect(ancestorMoved.rows.first { $0.layerID == 7 }?.path == [0,1] && ancestorMoved.rows.first { $0.layerID == 6 }?.canRemove == true,"subtree can move to ancestor without creating cycle")
    for operation in [PDFLayerOrderOperation.reparent([0],[0]),.reparent([0],[0,0]),.reparent([0],[99]),.reparent([0],[]),.reparent([],nil)] {
        do { _ = try PDFDocumentExtras.editLayerOrder(data,entry: original,operation: operation); fatalError("invalid or cyclic Order parent accepted") } catch { }
    }
    let deep = orderAuthoringFixture(order: "[5 0 R [6 0 R] "+String(repeating: "[",count: 63)+"8 0 R"+String(repeating: "]",count: 63)+"]"),deepEntry = try entry(deep)
    expect(deepEntry.editable,"deep destination fixture is valid before transfer")
    do { _ = try PDFDocumentExtras.editLayerOrder(deep,entry: deepEntry,operation: .reparent([0],deepEntry.rows.last!.path)); fatalError("reparent exceeded maximum tree depth") } catch { }
    let ambiguous = orderAuthoringFixture(order: "[[(H)] 5 0 R [(Q)] [6 0 R]]"),ambiguousEntry = try entry(ambiguous)
    do { _ = try PDFDocumentExtras.editLayerOrder(ambiguous,entry: ambiguousEntry,operation: .reparent([2],[0])); fatalError("reparent silently changed anonymous array attachment") } catch { }
    let inherited = try entry(data,1),isolated = try PDFDocumentExtras.editLayerOrder(data,entry: inherited,operation: .reparent([0],[1])),isolatedEntry = try entry(isolated,1),isolatedPrimary = try entry(isolated)
    expect(!isolatedEntry.inherited && isolatedEntry.rows == laterEntry.rows && isolatedPrimary == original,"inherited alternative reparenting creates isolated Order without activation")
    let before = try PDFDocumentExtras.layerStateReport(data),after = try PDFDocumentExtras.layerStateReport(later)
    expect(before.configurations == after.configurations && before.groups.map(\.visible) == after.groups.map(\.visible),"reparenting preserves configurations, states, locks and radio groups")
    let cg = CGPDFDocument(CGDataProvider(data: later as CFData)!)!,page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data("/OC /M BDC 10 10 20 20 re f EMC\n".utf8),"reparenting does not move or edit original graphics")
    expect(try PDFDocumentExtras.membershipConfiguration(later).entries.first?.expression == "And(#5, Not(#6))","reparenting does not change content visibility condition")
    let suite = "BotPlusOrderParents-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("order-parents.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showLayerOrderEditor(item: item,view: view)
    let request = manager.layerOrderRequest!,history = item.undoHistory.count
    expect(request.apply(original,.reparent([0,0],[0])) == nil && item.undoHistory.count == history,"no-op reparenting does not create Undo")
    expect(request.apply(original,.reparent([0],[1])) == nil && item.undoHistory.count == history+1,"reparenting records one atomic history operation")
    expect(request.apply(original,.reparent([1],nil)) != nil,"stale parent editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try entry(Data(contentsOf: item.url)).rows == laterEntry.rows,"new parent and child subtree survive save/reopen")
    manager.undoDocument(redo: false)
    expect(try entry(manager.serializedData(item)).rows == original.rows,"Undo restores original parents")
    manager.undoDocument(redo: true)
    expect(try entry(manager.serializedData(item)).rows == laterEntry.rows,"Redo restores parent transfer")
    print("PASS: Order subtree reparent/root/ancestor transfers, shifted destination paths, repeated OCG isolation, cycle/depth/grammar guards and save/Undo/Redo")
}

@MainActor private func checkMembershipCreation(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let data = orderAuthoringFixture(),name = "Условие Δ (печать)",before = try PDFDocumentExtras.membershipConfiguration(data)
    let created = try PDFDocumentExtras.createMembership(data,name: name,members: [5,6],policy: "AllOn",expression: nil),report = try PDFDocumentExtras.membershipConfiguration(created),entry = report.entries.first { $0.name == name }!
    expect(report.entries.count == before.entries.count+1 && entry.id > 12 && entry.generation == 0 && entry.memberIDs == [5,6] && entry.policy == "AllOn" && entry.editable,"new named OCMD has standard membership and fresh object identity")
    expect(entry.visible(states: [5:true,6:false]) == false,"created policy evaluates against OCG state")
    let normalized = try PDFDocumentExtras.normalized(created)
    expect(try PDFDocumentExtras.membershipConfiguration(normalized).entries.contains { $0.name == name },"unassigned condition survives PDFium normalization through catalog anchor")
    let expressionData = try PDFDocumentExtras.createMembership(created,name: "Выражение",members: [5],policy: "AnyOn",expression: "Not(#6)"),expressionEntry = try PDFDocumentExtras.membershipConfiguration(expressionData).entries.first { $0.name == "Выражение" }!
    expect(expressionEntry.expression == "Not(#6)" && expressionEntry.visible(states: [5:false,6:false]) == true,"new VE overrides membership policy using known groups")
    let empty = try PDFDocumentExtras.createMembership(expressionData,name: "Без ограничения",members: [],policy: "AnyOff",expression: nil)
    expect(try PDFDocumentExtras.membershipConfiguration(empty).entries.first { $0.name == "Без ограничения" }?.visible(states: [5:false,6:false]) == true,"empty OCMD without VE has no visibility effect")
    let edited = try PDFDocumentExtras.setMembership(created,entry: entry,members: [7],policy: "AllOff",expression: nil)
    expect(try PDFDocumentExtras.membershipConfiguration(edited).entries.first { $0.id == entry.id }?.name == name,"existing OCMD edit retains created condition name")
    do { _ = try PDFDocumentExtras.createMembership(created,name: name.uppercased(),members: [],policy: "AnyOn",expression: nil); fatalError("duplicate condition name accepted") } catch PDFSourceError.alreadyUsed { }
    for invalid in ["", "  ","bad\nname",String(repeating: "a",count: 4097)] {
        do { _ = try PDFDocumentExtras.createMembership(data,name: invalid,members: [5],policy: "AnyOn",expression: nil); fatalError("invalid OCMD name accepted") } catch { }
    }
    for (members,policy,expression) in [([5,5],"AnyOn",nil as String?),([999],"AnyOn",nil),([5],"Bad",nil),([5],"AnyOn","Not(#999)"),([5],"AnyOn","Not(#5, #6)")] {
        do { _ = try PDFDocumentExtras.createMembership(data,name: "Invalid",members: members,policy: policy,expression: expression); fatalError("invalid OCMD creation accepted") } catch { }
    }
    for registry in ["/Bad","[5 0 R]","[999 0 R]","[11 0 R 11 0 R]"] {
        do { _ = try PDFDocumentExtras.createMembership(orderAuthoringFixture(membershipRegistry: registry),name: "Invalid",members: [5],policy: "AnyOn",expression: nil); fatalError("malformed registry silently replaced") } catch { }
    }
    let registered = try PDFDocumentExtras.createMembership(orderAuthoringFixture(membershipRegistry: "[11 0 R]"),name: "Registered",members: [5],policy: "AnyOn",expression: nil)
    expect(try PDFDocumentExtras.membershipConfiguration(registered).entries.count == before.entries.count+1,"valid pre-existing registry retained")
    let cg = CGPDFDocument(CGDataProvider(data: created as CFData)!)!
    var props: CGPDFDictionaryRef?,registry: CGPDFArrayRef?; CGPDFDictionaryGetDictionary(cg.catalog!,"OCProperties",&props); CGPDFDictionaryGetArray(props!,"BotPlusOCMDs",&registry)
    var dictionary: CGPDFDictionaryRef?; CGPDFArrayGetDictionary(registry!,0,&dictionary)
    var type: UnsafePointer<CChar>?,policy: UnsafePointer<CChar>?,members: CGPDFArrayRef?
    CGPDFDictionaryGetName(dictionary!,"Type",&type); CGPDFDictionaryGetName(dictionary!,"P",&policy); CGPDFDictionaryGetArray(dictionary!,"OCGs",&members)
    expect(String(cString: type!) == "OCMD" && String(cString: policy!) == "AllOn" && CGPDFArrayGetCount(members!) == 2,"independent reader sees anchored standard OCMD dictionary")
    let page = cg.page(at: 1)!
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data("/OC /M BDC 10 10 20 20 re f EMC\n".utf8),"condition creation leaves original page content unchanged")
    let oldState = try PDFDocumentExtras.layerStateReport(data),newState = try PDFDocumentExtras.layerStateReport(created)
    expect(oldState.configurations == newState.configurations && oldState.groups.map(\.visible) == newState.groups.map(\.visible),"unassigned condition does not alter layer states or configurations")
    let suite = "BotPlusOCMDCreation-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("created-ocmd.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showMembershipEditor(item: item,view: view)
    let request = manager.membershipRequest!,history = item.undoHistory.count
    expect(request.create?(name,[5,6],"AllOn",nil) == nil && item.undoHistory.count == history+1,"creation editor installs one atomic document transaction")
    expect(request.create?("Stale",[5],"AnyOn",nil) != nil,"old OCMD creator rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try PDFDocumentExtras.membershipConfiguration(Data(contentsOf: item.url)).entries.contains { $0.name == name },"unassigned named OCMD survives PDFKit save/reopen")
    manager.undoDocument(redo: false)
    expect(try PDFDocumentExtras.membershipConfiguration(manager.serializedData(item)).entries.contains { $0.name == name } == false,"Undo removes created condition and registry reference")
    manager.undoDocument(redo: true)
    expect(try PDFDocumentExtras.membershipConfiguration(manager.serializedData(item)).entries.contains { $0.name == name },"Redo restores created condition")
    print("PASS: OCMD creation/Unicode/VE/empty semantics, retained unassigned registry, malformed input protection, unchanged content/state and save/Undo/Redo")
}

private func membershipBindingFixture(secondTail: String? = nil) -> Data {
    let first = "/OC /Existing BDC BI /W 1 /H 1 /CS /RGB /BPC 8 ID EMC EI\n0 0 0 rg 20 20 60 60 re f BT /F1 12 Tf 20 100 Td (Vector EMC BMC) Tj ET\n",last = "EMC\n"
    func stream(_ value: String) -> String { "<< /Length \(value.utf8.count) >>\nstream\n"+value+"endstream" }
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [7 0 R 8 0 R] /D << /BaseState /ON /ON [7 0 R] /OFF [8 0 R] /Order [7 0 R 8 0 R] >> /BotPlusOCMDs [9 0 R 10 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 /Resources 6 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /Contents [11 0 R 12 0 R] /Annots [13 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] /CropBox [10 10 190 190] /Rotate 90 /Resources 6 0 R /Contents [11 0 R \(secondTail == nil ? 12 : 16) 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
        "<< /Font << /F1 14 0 R >> /Properties << /Existing 15 0 R /BP_OCMD0 7 0 R >> >>",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>",
        "<< /Type /OCMD /BotPlusName (Hidden) /OCGs [7 0 R 8 0 R] /P /AllOn >>","<< /Type /OCMD /BotPlusName (Visible) /OCGs [7 0 R] /P /AnyOn >>",
        stream(first),stream(last),"<< /Type /Annot /Subtype /Square /Rect [120 120 160 160] /C [1 0 0] /Border [0 0 1] /Contents (Keep annotation) >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>","<< /Type /OCMD /OCGs [7 0 R] /P /AnyOn >>",stream(secondTail ?? last)
    ]
    var bytes = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(bytes.count); bytes.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = bytes.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; bytes.append(Data(end.utf8)); return bytes
}

@MainActor private func checkMembershipPageBinding(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func content(_ bytes: Data,_ index: Int) -> [Data] {
        let cg = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!,page = cg.page(at: index+1)!
        var array: CGPDFArrayRef?,result: [Data] = [],format = CGPDFDataFormat.raw
        if CGPDFDictionaryGetArray(page.dictionary!,"Contents",&array),let array {
            for at in 0..<CGPDFArrayGetCount(array) { var stream: CGPDFStreamRef?; CGPDFArrayGetStream(array,at,&stream); result.append(CGPDFStreamCopyData(stream!,&format)! as Data) }
        } else { var stream: CGPDFStreamRef?; if CGPDFDictionaryGetStream(page.dictionary!,"Contents",&stream),let stream { result.append(CGPDFStreamCopyData(stream,&format)! as Data) } }
        return result
    }
    func pixels(_ bytes: Data,_ index: Int) -> Data {
        _ = PDFiumRuntime.ready; let storage = bytes as NSData,document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil)!
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        let page = FPDF_LoadPage(document,Int32(index))!,bitmap = FPDFBitmap_Create(96,96,0)!
        defer { FPDF_ClosePage(page); FPDFBitmap_Destroy(bitmap) }
        FPDFBitmap_FillRect(bitmap,0,0,96,96,0xffffffff); FPDF_RenderPageBitmap(bitmap,page,0,0,96,96,0,0)
        return Data(bytes: FPDFBitmap_GetBuffer(bitmap)!,count: 96*Int(FPDFBitmap_GetStride(bitmap)))
    }
    func dark(_ data: Data) -> Int { data.withUnsafeBytes { raw in let bytes = raw.bindMemory(to: UInt8.self); return stride(from: 0,to: bytes.count,by: 4).filter { Int(bytes[$0])+Int(bytes[$0+1])+Int(bytes[$0+2]) < 384 }.count } }
    let data = membershipBindingFixture(),configuration = try PDFDocumentExtras.membershipConfiguration(data),hidden = configuration.entries.first { $0.name == "Hidden" }!,visible = configuration.entries.first { $0.name == "Visible" }!
    let originalContent = content(data,0),originalPixels = pixels(data,0),otherPixels = pixels(data,1)
    expect(dark(originalPixels) > 100,"original vector/text fixture renders visible")
    let bound = try PDFDocumentExtras.bindMembershipPages(data,entry: hidden,indices: [0]),wrapped = content(bound,0)
    expect(wrapped.count == 4 && Array(wrapped.dropFirst().dropLast()) == originalContent && String(data: wrapped[0],encoding: .utf8) == "/OC /BP_OCMD1 BDC\n" && String(data: wrapped.last!,encoding: .utf8) == "\nEMC\n","binding wraps original multi-stream content without rewriting it and avoids resource name collision")
    expect(dark(pixels(bound,0)) == 0 && pixels(bound,1) == otherPixels,"PDFium hides bound page graphics while shared-resource neighbor remains unchanged")
    expect(try PDFDocumentExtras.bindMembershipPages(bound,entry: hidden,indices: [0]) == bound,"assigning same condition is a no-op")
    let reassigned = try PDFDocumentExtras.bindMembershipPages(bound,entry: visible,indices: [0])
    expect(content(reassigned,0).count == 4 && pixels(reassigned,0) == originalPixels,"reassignment changes property target without nested wrappers or appearance changes")
    let cleared = try PDFDocumentExtras.bindMembershipPages(reassigned,entry: nil,indices: [0])
    expect(content(cleared,0) == originalContent && pixels(cleared,0) == originalPixels,"removal restores original content sequence and rendering")
    expect(try PDFDocumentExtras.bindMembershipPages(cleared,entry: nil,indices: [0,1,2]) == cleared,"removal ignores pages without owned assignment")
    let batch = try PDFDocumentExtras.bindMembershipPages(data,entry: hidden,indices: [0,1,2])
    expect(dark(pixels(batch,0)) == 0 && dark(pixels(batch,1)) == 0 && content(batch,2).count == 2,"batch supports rotated, inherited/shared-resource and empty pages")
    let batchClear = try PDFDocumentExtras.bindMembershipPages(batch,entry: nil,indices: [0,1,2])
    expect(content(batchClear,0) == originalContent && content(batchClear,2).isEmpty && pixels(batchClear,1) == otherPixels,"batch removal restores empty and rotated pages")
    let savedByPDFKit = try PDFDocumentSerializer.data(PDFDocument(data: bound)!,preserveStreams: true)
    let removedAfterSave = try PDFDocumentExtras.bindMembershipPages(savedByPDFKit,entry: nil,indices: [0])
    expect(content(removedAfterSave,0) == originalContent,"owned assignment remains removable after native PDFKit serialization")
    let cg = CGPDFDocument(CGDataProvider(data: bound as CFData)!)!,page = cg.page(at: 1)!,neighbor = cg.page(at: 2)!
    var resources: CGPDFDictionaryRef?,properties: CGPDFDictionaryRef?,metadata: CGPDFDictionaryRef?
    CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources); CGPDFDictionaryGetDictionary(resources!,"Properties",&properties); CGPDFDictionaryGetDictionary(page.dictionary!,"BotPlusPageOC",&metadata)
    var property: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(properties!,"BP_OCMD1",&property); var policy: UnsafePointer<CChar>?; CGPDFDictionaryGetName(property!,"P",&policy)
    expect(String(cString: policy!) == "AllOn" && metadata != nil,"standard Properties resource points to assigned OCMD")
    var annotations: CGPDFArrayRef?; CGPDFDictionaryGetArray(page.dictionary!,"Annots",&annotations)
    expect(CGPDFArrayGetCount(annotations!) == 1 && neighbor.rotationAngle == 90 && neighbor.getBoxRect(.cropBox) == CGRect(x: 10,y: 10,width: 180,height: 180),"annotations, rotation and boxes are preserved")
    let oldState = try PDFDocumentExtras.layerStateReport(data),newState = try PDFDocumentExtras.layerStateReport(bound)
    expect(oldState.configurations == newState.configurations && oldState.groups.map(\.visible) == newState.groups.map(\.visible),"page assignment does not change base OCG states")
    for indices in [[],[-1],[3],[0,0],Array(0..<513)] {
        do { _ = try PDFDocumentExtras.bindMembershipPages(data,entry: hidden,indices: indices); fatalError("invalid binding range accepted") } catch { }
    }
    let forged = PDFMembershipInfo(id: 999,generation: 0,memberIDs: [],policy: "AnyOn",expression: nil,editable: true)
    do { _ = try PDFDocumentExtras.bindMembershipPages(data,entry: forged,indices: [0]); fatalError("unknown OCMD assigned") } catch { }
    let invalid = membershipBindingFixture(secondTail: "")
    do { _ = try PDFDocumentExtras.bindMembershipPages(invalid,entry: hidden,indices: [0,1]); fatalError("unbalanced marked content accepted") } catch { }
    var damaged = bound
    let old = Data("/OC /BP_OCMD1 BDC\n".utf8),replacement = Data("/OC /BP_OCMD1 BMC\n".utf8)
    guard let range = damaged.range(of: old) else { fatalError("wrapper fixture") }; damaged.replaceSubrange(range,with: replacement)
    do { _ = try PDFDocumentExtras.bindMembershipPages(damaged,entry: nil,indices: [0]); fatalError("manually changed wrapper removed") } catch { }
    var damagedPresence = bound
    let presence = Data("/HadContents true ".utf8),absent = Data("/HadContents false".utf8)
    guard let presenceRange = damagedPresence.range(of: presence) else { fatalError("presence fixture") }; damagedPresence.replaceSubrange(presenceRange,with: absent)
    do { _ = try PDFDocumentExtras.bindMembershipPages(damagedPresence,entry: nil,indices: [0]); fatalError("tampered absence flag discarded original streams") } catch { }
    let suite = "BotPlusPageBinding-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("page-binding.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item); item.selectedPages = [0,1]
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showMembershipBindingEditor(item: item,view: view)
    let request = manager.membershipBindingRequest!,history = item.undoHistory.count
    expect(request.pageCount == 3 && request.selectedPages == [0,1] && request.apply(hidden,[0,1]) == nil && item.undoHistory.count == history+1,"binding dialog captures page selection and commits whole range as one operation")
    expect(request.apply(nil,[0]) != nil,"stale binding dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(dark(pixels(try Data(contentsOf: item.url),0)) == 0,"assigned condition survives save/reopen")
    manager.undoDocument(redo: false)
    expect(pixels(try manager.serializedData(item),0) == originalPixels,"one Undo restores unbound page content")
    manager.undoDocument(redo: true)
    expect(dark(pixels(try manager.serializedData(item),0)) == 0,"Redo restores assignment")
    let invalidDocument = PDFDocument(data: invalid)!,invalidItem = PDFDocumentItem(url: root.appendingPathComponent("invalid-binding.pdf"),document: invalidDocument,preserveStreams: true)
    manager.insertDocument(invalidItem); manager.seedSerializedData(invalid,item: invalidItem); view.installDocument(invalidDocument)
    coordinator.showMembershipBindingEditor(item: invalidItem,view: view)
    expect(manager.membershipBindingRequest!.apply(hidden,[0,1]) != nil && invalidItem.document === invalidDocument && invalidItem.undoHistory.isEmpty,"failed page in a range leaves document and history intact")
    print("PASS: page OCMD assignment/reassignment/removal, exact original streams, PDFium visibility, shared/inherited resources, inline images/scopes, ownership/range/stale guards and save/Undo/Redo")
}

private func directMembershipFixture() -> Data {
    let pageContent = "/OC /Direct BDC 20 20 30 30 re f EMC q 10 0 0 10 50 50 cm /Im Do Q /Form Do\n",form = "60 60 10 10 re f\n",image = "endobjXYZ"
    func condition(_ name: String,_ policy: String = "AnyOn",_ members: String = "7 0 R",_ extra: String = "") -> String { "<< /Type /OCMD /BotPlusName (\(name)) /OCGs [\(members)] /P /\(policy) /Private (keep \(name)) \(extra) >>" }
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Private 11 0 R /OCProperties << /OCGs [7 0 R 8 0 R] /D << /BaseState /ON /ON [7 0 R] /OFF [8 0 R] /Order [7 0 R 8 0 R] >> /BotPlusOCMDs [12 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /Resources 5 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R /Annots 13 0 R >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R >>",
        "<< /Properties << /Direct \(condition("Resource","AllOn","7 0 R 8 0 R")) >> /XObject << /Im 9 0 R /Form 10 0 R >> /Marker (resources) >>",
        "<< /Length \(pageContent.utf8.count) >>\nstream\n"+pageContent+"endstream","<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>",
        "<< /Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length 14 0 R /OC \(condition("Image")) >>\nstream\n"+image+"\nendstream",
        "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << >> /Length \(form.utf8.count) /OC \(condition("Form")) >>\nstream\n"+form+"endstream",
        "<< /Holder [\(condition("Nested A","AnyOff","7 0 R 8 0 R")) \(condition("Nested B","AnyOff","7 0 R 8 0 R")) \(condition("Unsupported","Unknown","99 0 R"))] /Marker (holder) >>",
        "<< /Type /OCMD /BotPlusName (Indirect) /OCGs [7 0 R] /P /AnyOn >>",
        "[<< /Type /Annot /Subtype /Square /Rect [70 70 90 90] /C [1 0 0] /Contents (Keep annotation) /OC \(condition("Annotation")) >>]",String(image.utf8.count)
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
}

@MainActor private func checkDirectMemberships(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func named(_ data: Data,_ name: String) throws -> PDFMembershipInfo { try PDFDocumentExtras.membershipConfiguration(data).entries.first { $0.name == name }! }
    func dark(_ bytes: Data,_ index: Int) -> Int {
        _ = PDFiumRuntime.ready; let storage = bytes as NSData,document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil)!
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        let page = FPDF_LoadPage(document,Int32(index))!,bitmap = FPDFBitmap_Create(100,100,0)!
        defer { FPDF_ClosePage(page); FPDFBitmap_Destroy(bitmap) }
        FPDFBitmap_FillRect(bitmap,0,0,100,100,0xffffffff); FPDF_RenderPageBitmap(bitmap,page,0,0,100,100,0,0)
        let data = Data(bytes: FPDFBitmap_GetBuffer(bitmap)!,count: 100*Int(FPDFBitmap_GetStride(bitmap)))
        return data.withUnsafeBytes { raw in let bytes = raw.bindMemory(to: UInt8.self); return stride(from: 0,to: bytes.count,by: 4).filter { Int(bytes[$0])+Int(bytes[$0+1])+Int(bytes[$0+2]) < 384 }.count }
    }
    let data = directMembershipFixture(),configuration = try PDFDocumentExtras.membershipConfiguration(data),resource = try named(data,"Resource")
    expect(configuration.entries.count == 8 && configuration.entries.filter { $0.directLocation != nil }.count == 7,"discovery includes dictionary, stream-header and indirect-array embedded OCMD")
    expect(resource.id < 0 && resource.directLocation?.ownerID == 5 && resource.directLocation?.path == [.key("Properties"),.key("Direct")],"direct condition carries stable owner/path identity")
    let annotation = try named(data,"Annotation")
    expect(annotation.directLocation?.ownerID == 13 && annotation.directLocation?.path == [.index(0),.key("OC")],"direct OCMD in annotation array is addressable")
    let changed = try PDFDocumentExtras.setMembership(data,entry: resource,members: [7,8],policy: "AnyOn",expression: nil),changedEntry = try named(changed,"Resource")
    expect(changedEntry.policy == "AnyOn" && changedEntry.directLocation?.ownerID == 5 && changedEntry.directLocation != resource.directLocation,"editing direct condition retains direct storage and changes owner fingerprint")
    expect(dark(changed,0) > dark(data,0) && dark(changed,1) > dark(data,1),"PDFium applies edited shared resource condition to both uses")
    do { _ = try PDFDocumentExtras.setMembership(changed,entry: resource,members: [7],policy: "AllOff",expression: nil); fatalError("stale direct condition accepted") } catch { }
    let image = try named(data,"Image"),imageChanged = try PDFDocumentExtras.setMembership(data,entry: image,members: [7],policy: "AnyOff",expression: nil)
    let cg = CGPDFDocument(CGDataProvider(data: imageChanged as CFData)!)!,page = cg.page(at: 1)!
    func dictionary(_ value: CGPDFDictionaryRef,_ key: String) -> CGPDFDictionaryRef { var result: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(value,key,&result); return result! }
    var pages: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(cg.catalog!,"Pages",&pages)
    let resources = dictionary(pages!,"Resources"),objects = dictionary(resources,"XObject")
    var stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw; CGPDFDictionaryGetStream(objects,"Im",&stream)
    expect(CGPDFStreamCopyData(stream!,&format)! as Data == Data("endobjXYZ".utf8),"image payload containing object-like bytes is retained by Length")
    let imageDictionary = CGPDFStreamGetDictionary(stream!)!,condition = dictionary(imageDictionary,"OC")
    var preserved: CGPDFStringRef?; CGPDFDictionaryGetString(condition,"Private",&preserved)
    expect(CGPDFStringCopyTextString(preserved!)! as String == "keep Image","direct rewrite preserves opaque condition fields")
    let form = try named(data,"Form"),formChanged = try PDFDocumentExtras.setMembership(data,entry: form,members: [],policy: "AnyOn",expression: "Not(#7)")
    expect(try named(formChanged,"Form").expression == "Not(#7)","embedded stream OCMD accepts VE")
    let formCG = CGPDFDocument(CGDataProvider(data: formChanged as CFData)!)!; var formPages: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(formCG.catalog!,"Pages",&formPages)
    let formObjects = dictionary(dictionary(formPages!,"Resources"),"XObject"); var formStream: CGPDFStreamRef?; CGPDFDictionaryGetStream(formObjects,"Form",&formStream)
    expect(CGPDFStreamCopyData(formStream!,&format)! as Data == Data("60 60 10 10 re f\n".utf8),"Form content bytes survive direct condition edit")
    let nested = try named(data,"Nested A"),sibling = try named(data,"Nested B"),nestedChanged = try PDFDocumentExtras.setMembership(data,entry: nested,members: [8],policy: "AllOn",expression: nil)
    expect(try named(nestedChanged,"Nested A").memberIDs == [8],"nested array location is rewritten")
    expect(try named(nestedChanged,"Nested B").memberIDs == sibling.memberIDs,"identical neighboring condition remains independent")
    do { _ = try PDFDocumentExtras.setMembership(nestedChanged,entry: sibling,members: [7],policy: "AllOn",expression: nil); fatalError("stale owner header accepted for another direct child") } catch { }
    let annotationChanged = try PDFDocumentExtras.setMembership(data,entry: annotation,members: [7],policy: "AllOff",expression: nil)
    expect(try named(annotationChanged,"Annotation").policy == "AllOff","direct condition in indirect annotation array can be edited")
    let unsupported = try named(data,"Unsupported")
    expect(!unsupported.editable,"unknown direct policy/membership stays read-only")
    do { _ = try PDFDocumentExtras.setMembership(data,entry: unsupported,members: [7],policy: "AnyOn",expression: nil); fatalError("unsupported direct condition overwritten") } catch { }
    do { _ = try PDFDocumentExtras.bindMembershipPages(data,entry: resource,indices: [0]); fatalError("synthetic direct ID serialized as an indirect PDF reference") } catch { }
    var forged = resource
    forged.directLocation = PDFMembershipLocation(ownerID: 5,generation: 0,path: [.key("Missing")],fingerprint: resource.directLocation!.fingerprint)
    do { _ = try PDFDocumentExtras.setMembership(data,entry: forged,members: [7],policy: "AnyOn",expression: nil); fatalError("forged direct location accepted") } catch { }
    let oldState = try PDFDocumentExtras.layerStateReport(data),newState = try PDFDocumentExtras.layerStateReport(changed)
    expect(oldState.configurations == newState.configurations && oldState.groups.map(\.visible) == newState.groups.map(\.visible),"direct condition edit leaves base OCG state and configurations intact")
    var pageStream: CGPDFStreamRef?; CGPDFDictionaryGetStream(page.dictionary!,"Contents",&pageStream)
    expect(CGPDFStreamCopyData(pageStream!,&format)! as Data == Data("/OC /Direct BDC 20 20 30 30 re f EMC q 10 0 0 10 50 50 cm /Im Do Q /Form Do\n".utf8),"page stream and existing resource names are retained")
    let suite = "BotPlusDirectOCMD-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("direct-ocmd.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showMembershipEditor(item: item,view: view)
    let request = manager.membershipRequest!,history = item.undoHistory.count
    expect(request.configuration.entries.contains { $0.directLocation != nil } && request.apply(resource,[7,8],"AnyOn",nil) == nil && item.undoHistory.count == history+1,"direct editor installs atomic owner rewrite")
    expect(request.apply(resource,[7],"AllOff",nil) != nil,"old direct editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(try named(Data(contentsOf: item.url),"Resource").policy == "AnyOn","direct condition edit survives save/reopen")
    manager.undoDocument(redo: false)
    expect(try named(manager.serializedData(item),"Resource").policy == "AllOn","Undo restores original embedded condition")
    manager.undoDocument(redo: true)
    expect(try named(manager.serializedData(item),"Resource").policy == "AnyOn","Redo restores embedded condition edit")
    print("PASS: direct OCMD discovery/editing in dictionaries/arrays/stream headers, owner fingerprints, shared render effects, retained image/Form bytes, read-only/invalid guards and save/Undo/Redo")
}

private func xObjectConditionFixture(tagged: Bool = false) -> Data {
    let content = "q 10 0 0 10 20 20 cm /Im Do Q q 10 0 0 10 40 20 cm /Im Do Q q 10 0 0 10 80 20 cm /Alias Do Q /Form Do\n",image = "endobjXYZ",form = "60 60 10 10 re f\n"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R \(tagged ? "/StructTreeRoot 13 0 R /MarkInfo << /Marked true >>" : "") /OCProperties << /OCGs [7 0 R 8 0 R] /D << /BaseState /ON /ON [7 0 R] /OFF [8 0 R] /Order [7 0 R 8 0 R] >> /BotPlusOCMDs [11 0 R 12 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /Resources 5 0 R >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R >>",
        "<< /XObject << /Im 9 0 R /Alias 9 0 R /Form 10 0 R >> /Private (resources) >>","<< /Length \(content.utf8.count) >>\nstream\n"+content+"endstream",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>",
        "<< /Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length \(image.utf8.count) /Private (image) >>\nstream\n"+image+"\nendstream",
        "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << >> /Group << /S /Transparency /CS /DeviceRGB >> /Length \(form.utf8.count) /Private (form) >>\nstream\n"+form+"endstream",
        "<< /Type /OCMD /BotPlusName (Hidden) /OCGs [8 0 R] /P /AnyOn >>","<< /Type /OCMD /BotPlusName (Visible) /OCGs [7 0 R] /P /AnyOn >>","<< /Type /StructTreeRoot /K [] >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
}

@MainActor private func checkXObjectConditions(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func target(_ bytes: Data,_ name: String,_ page: Int = 0) throws -> PDFXObjectConditionTarget { try PDFDocumentExtras.xObjectConditionTargets(bytes,pageIndex: page).first { $0.key == name }! }
    func pixels(_ bytes: Data,_ index: Int = 0) -> Data {
        _ = PDFiumRuntime.ready; let storage = bytes as NSData,document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil)!
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        let page = FPDF_LoadPage(document,Int32(index))!,bitmap = FPDFBitmap_Create(100,100,0)!
        defer { FPDF_ClosePage(page); FPDFBitmap_Destroy(bitmap) }
        FPDFBitmap_FillRect(bitmap,0,0,100,100,0xffffffff); FPDF_RenderPageBitmap(bitmap,page,0,0,100,100,0,0)
        return Data(bytes: FPDFBitmap_GetBuffer(bitmap)!,count: 100*Int(FPDFBitmap_GetStride(bitmap)))
    }
    func dark(_ data: Data) -> Int { data.withUnsafeBytes { raw in let bytes = raw.bindMemory(to: UInt8.self); return stride(from: 0,to: bytes.count,by: 4).filter { Int(bytes[$0])+Int(bytes[$0+1])+Int(bytes[$0+2]) < 384 }.count } }
    let data = xObjectConditionFixture(),conditions = try PDFDocumentExtras.membershipConfiguration(data),hidden = conditions.entries.first { $0.name == "Hidden" }!,visible = conditions.entries.first { $0.name == "Visible" }!,image = try target(data,"Im"),form = try target(data,"Form"),alias = try target(data,"Alias")
    expect(image.editable && !image.owned && image.objectID == alias.objectID && form.kind == "Form","root image/Form resources are addressable with shared aliases")
    expect(try PDFDocumentExtras.bindXObjectCondition(data,target: image,entry: nil) == data,"clearing an unassigned resource is a no-op")
    let original = pixels(data),bound = try PDFDocumentExtras.bindXObjectCondition(data,target: image,entry: hidden),boundTarget = try target(bound,"Im")
    let boundAlias = try target(bound,"Alias"),boundNeighbor = try target(bound,"Im",1)
    expect(boundTarget.owned && boundTarget.conditionID == hidden.id && boundTarget.objectID != image.objectID && boundAlias.objectID == image.objectID && boundNeighbor.objectID == image.objectID,"assignment isolates selected resource name and page through a new XObject")
    expect(dark(pixels(bound)) < dark(original) && dark(pixels(bound)) > 0 && pixels(bound,1) == original,"PDFium hides both selected-name uses while preserving alias and shared-resource neighbor")
    expect(try PDFDocumentExtras.bindXObjectCondition(bound,target: boundTarget,entry: hidden) == bound,"same owned assignment has no extra clone/history")
    let reassigned = try PDFDocumentExtras.bindXObjectCondition(bound,target: boundTarget,entry: visible),reassignedTarget = try target(reassigned,"Im")
    expect(reassignedTarget.objectID != boundTarget.objectID && pixels(reassigned) == original,"reassignment isolates existing clone and restores visible rendering")
    let cleared = try PDFDocumentExtras.bindXObjectCondition(reassigned,target: reassignedTarget,entry: nil),clearedTarget = try target(cleared,"Im")
    expect(!clearedTarget.owned && clearedTarget.objectID == image.objectID && pixels(cleared) == original,"clear restores original XObject reference and exact rendering")
    let formBound = try PDFDocumentExtras.bindXObjectCondition(data,target: form,entry: hidden)
    expect(dark(pixels(formBound)) < dark(original) && pixels(formBound,1) == original,"Form condition applies only on selected page")
    let copiedForm = try target(formBound,"Form"),formClear = try PDFDocumentExtras.bindXObjectCondition(formBound,target: copiedForm,entry: nil)
    expect(pixels(formClear) == original,"Form assignment removal restores transparency group and content")
    let combined = try PDFDocumentExtras.bindXObjectCondition(bound,target: target(bound,"Form"),entry: hidden)
    expect(dark(pixels(combined)) > 0 && dark(pixels(combined)) < dark(pixels(bound)),"independent image and Form assignments compose while alias remains visible")
    func objectBytes(_ bytes: Data,_ name: String) -> Data {
        let cg = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!,page = cg.page(at: 1)!
        var resources: CGPDFDictionaryRef?,objects: CGPDFDictionaryRef?,stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw
        CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources); CGPDFDictionaryGetDictionary(resources!,"XObject",&objects); CGPDFDictionaryGetStream(objects!,name,&stream)
        return CGPDFStreamCopyData(stream!,&format)! as Data
    }
    expect(objectBytes(bound,"Im") == Data("endobjXYZ".utf8) && objectBytes(formBound,"Form") == Data("60 60 10 10 re f\n".utf8),"image/Form stream payload is retained byte-for-byte")
    let saved = try PDFDocumentSerializer.data(PDFDocument(data: bound)!,preserveStreams: true),savedTarget = try target(saved,"Im")
    expect(savedTarget.editable && savedTarget.owned,"owned XObject remains valid through PDFKit serialization")
    let nativeClear = try PDFDocumentExtras.bindXObjectCondition(saved,target: savedTarget,entry: nil)
    expect(pixels(nativeClear) == original,"owned assignment remains removable after PDFKit serialization")
    do { _ = try PDFDocumentExtras.bindXObjectCondition(bound,target: image,entry: visible); fatalError("stale original resource accepted") } catch { }
    var damaged = bound
    let objectHeader = Data("\(boundTarget.objectID) \(boundTarget.generation) obj".utf8)
    guard let objectRange = damaged.range(of: objectHeader,options: .backwards),
          let streamRange = damaged.range(of: Data("stream".utf8),in: objectRange.upperBound..<damaged.endIndex) else { fatalError("clone stream fixture") }
    var payloadStart = streamRange.upperBound
    if damaged[payloadStart] == 13 { payloadStart += 1 }
    if damaged[payloadStart] == 10 { payloadStart += 1 }
    // PDFium may compress the payload; corrupt its encoded bytes rather than
    // assuming that the decoded fixture appears literally in the saved file.
    damaged[payloadStart+2] ^= 1
    let damagedTarget = try target(damaged,"Im")
    expect(!damagedTarget.editable,"externally modified clone is protected from automatic restore")
    do { _ = try PDFDocumentExtras.bindXObjectCondition(damaged,target: damagedTarget,entry: nil); fatalError("modified clone content discarded") } catch { }
    let foreignData = directMembershipFixture(),foreign = try target(foreignData,"Im")
    expect(!foreign.editable,"foreign original OC assignment remains read-only")
    do { _ = try PDFDocumentExtras.bindXObjectCondition(foreignData,target: foreign,entry: nil); fatalError("foreign condition removed") } catch { }
    let tagged = xObjectConditionFixture(tagged: true),taggedTarget = try target(tagged,"Im")
    expect(!taggedTarget.editable && taggedTarget.reason.contains("Tagged"),"tagged PDF structure is not cloned without ParentTree rewriting")
    let direct = try PDFDocumentExtras.membershipConfiguration(foreignData).entries.first { $0.directLocation != nil }!
    do { _ = try PDFDocumentExtras.bindXObjectCondition(data,target: image,entry: direct); fatalError("direct synthetic condition serialized as reference") } catch { }
    let before = try PDFDocumentExtras.layerStateReport(data),after = try PDFDocumentExtras.layerStateReport(bound)
    expect(before.configurations == after.configurations && before.groups.map(\.visible) == after.groups.map(\.visible),"resource assignment preserves OCG states/configurations")
    let suite = "BotPlusXObjectCondition-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("xobject-condition.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showXObjectConditionEditor(item: item,view: view)
    let request = manager.xObjectConditionRequest!,history = item.undoHistory.count
    expect(request.targets.count == 3 && request.apply(image,nil) == nil && item.undoHistory.count == history,"resource editor exposes page resources and no-op clear")
    expect(request.apply(image,hidden) == nil && item.undoHistory.count == history+1,"resource assignment is one atomic transaction")
    expect(request.apply(image,visible) != nil,"old resource editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(dark(pixels(try Data(contentsOf: item.url))) < dark(original),"resource condition survives save/reopen")
    manager.undoDocument(redo: false)
    expect(pixels(try manager.serializedData(item)) == original,"Undo restores original resource")
    manager.undoDocument(redo: true)
    expect(dark(pixels(try manager.serializedData(item))) < dark(original),"Redo restores isolated assignment")
    print("PASS: Image/Form OCMD assignment/replace/remove with per-resource/page isolation, original references/bytes, tagged/foreign/tamper guards, PDFium render and save/Undo/Redo")
}


private func nestedXObjectConditionFixture(cycle: Bool = false,foreign: Bool = false) -> Data {
    let page = "/Outer Do q 1 0 0 1 0 45 cm /OuterAlias Do Q\n",leaf = "q 10 0 0 10 5 5 cm /Im Do Q q 10 0 0 10 20 5 cm /Alias Do Q\n",outer = "/Mid Do q 1 0 0 1 40 0 cm /MidAlias Do Q\n",image = "endobjXYZ"
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /OCProperties << /OCGs [7 0 R 8 0 R] /D << /BaseState /ON /ON [7 0 R] /OFF [8 0 R] >> /BotPlusOCMDs [11 0 R 12 0 R] >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /Resources 5 0 R >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Contents 6 0 R >>",
        "<< /XObject << /Outer 14 0 R /OuterAlias 14 0 R >> /Private (page resources) >>",
        "<< /Length \(page.utf8.count) >>\nstream\n"+page+"endstream",
        "<< /Type /OCG /Name (A) >>","<< /Type /OCG /Name (B) >>",
        "<< /Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceRGB /BitsPerComponent 8 /Length \(image.utf8.count) >>\nstream\n"+image+"\nendstream",
        "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Im 9 0 R /Alias 9 0 R >> /Private (mid resources) >> /Group << /S /Transparency /CS /DeviceRGB >> /Length \(leaf.utf8.count) >>\nstream\n"+leaf+"endstream",
        "<< /Type /OCMD /BotPlusName (Hidden) /OCGs [8 0 R] /P /AnyOn >>","<< /Type /OCMD /BotPlusName (Visible) /OCGs [7 0 R] /P /AnyOn >>","<< /Unused true >>",
        "<< /Type /XObject /Subtype /Form /BBox [0 0 100 100] /Resources << /XObject << /Mid 10 0 R /MidAlias 10 0 R \(cycle ? "/Loop 14 0 R" : "") >> /Private (outer resources) >> \(foreign ? "/OC 7 0 R" : "") /Length \(outer.utf8.count) >>\nstream\n"+outer+"endstream"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
}

@MainActor private func checkNestedXObjectConditions(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func target(_ bytes: Data,_ path: [String],_ page: Int = 0) throws -> PDFXObjectConditionTarget { try PDFDocumentExtras.xObjectConditionTargets(bytes,pageIndex: page).first { $0.path == path }! }
    func pixels(_ bytes: Data,_ index: Int = 0) -> Data {
        _ = PDFiumRuntime.ready; let storage = bytes as NSData,document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil)!
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        let page = FPDF_LoadPage(document,Int32(index))!,bitmap = FPDFBitmap_Create(100,100,0)!
        defer { FPDF_ClosePage(page); FPDFBitmap_Destroy(bitmap) }
        FPDFBitmap_FillRect(bitmap,0,0,100,100,0xffffffff); FPDF_RenderPageBitmap(bitmap,page,0,0,100,100,0,0)
        return Data(bytes: FPDFBitmap_GetBuffer(bitmap)!,count: 100*Int(FPDFBitmap_GetStride(bitmap)))
    }
    func dark(_ data: Data) -> Int { data.withUnsafeBytes { raw in let bytes = raw.bindMemory(to: UInt8.self); return stride(from: 0,to: bytes.count,by: 4).filter { Int(bytes[$0])+Int(bytes[$0+1])+Int(bytes[$0+2]) < 384 }.count } }
    func streamBytes(_ bytes: Data,_ path: [String]) -> Data {
        let cg = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!
        var resources: CGPDFDictionaryRef?,objects: CGPDFDictionaryRef?,stream: CGPDFStreamRef?,format = CGPDFDataFormat.raw
        // The edited page has materialized resources; the original inherited
        // dictionary is read from its parent for the comparison below.
        let page = cg.page(at: 1)!,dictionary = page.dictionary!
        if !CGPDFDictionaryGetDictionary(dictionary,"Resources",&resources) {
            var parent: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(dictionary,"Parent",&parent); CGPDFDictionaryGetDictionary(parent!,"Resources",&resources)
        }
        for (index,name) in path.enumerated() {
            CGPDFDictionaryGetDictionary(resources!,"XObject",&objects); CGPDFDictionaryGetStream(objects!,name,&stream)
            if index+1 < path.count { CGPDFDictionaryGetDictionary(CGPDFStreamGetDictionary(stream!)!,"Resources",&resources) }
        }
        return CGPDFStreamCopyData(stream!,&format)! as Data
    }
    let data = nestedXObjectConditionFixture(),config = try PDFDocumentExtras.membershipConfiguration(data),hidden = config.entries.first { $0.name == "Hidden" }!,visible = config.entries.first { $0.name == "Visible" }!,path = ["Outer","Mid","Im"],original = pixels(data)
    let leaf = try target(data,path),outer = try target(data,["Outer"]),mid = try target(data,["Outer","Mid"])
    let all = try PDFDocumentExtras.xObjectConditionTargets(data,pageIndex: 0)
    expect(all.count == 14 && Set(all.map(\.id)).count == all.count && leaf.editable,"nested paths expose repeated shared resources independently")
    let bound = try PDFDocumentExtras.bindXObjectCondition(data,target: leaf,entry: hidden),boundLeaf = try target(bound,path)
    let boundOuter = try target(bound,["Outer"]),boundMid = try target(bound,["Outer","Mid"])
    expect(boundLeaf.owned && boundLeaf.objectID != leaf.objectID && boundOuter.objectID != outer.objectID && boundMid.objectID != mid.objectID,"binding clones the leaf and every containing Form")
    let alias = try target(bound,["Outer","Mid","Alias"]),midAlias = try target(bound,["Outer","MidAlias"]),outerAlias = try target(bound,["OuterAlias"]),neighbor = try target(bound,path,1)
    expect(alias.objectID == leaf.objectID && midAlias.objectID == mid.objectID && outerAlias.objectID == outer.objectID && neighbor.objectID == leaf.objectID,"leaf/sibling/root aliases and neighbor retain original references")
    expect(dark(pixels(bound)) > 0 && dark(pixels(bound)) < dark(original) && pixels(bound,1) == original,"PDFium hides only the selected nested path")
    for streamPath in [["Outer"],["Outer","Mid"],path] { expect(streamBytes(data,streamPath) == streamBytes(bound,streamPath),"every cloned ancestor and leaf retains decoded stream bytes") }
    expect(try PDFDocumentExtras.bindXObjectCondition(bound,target: boundLeaf,entry: hidden) == bound,"same nested condition is a no-op")
    let reassigned = try PDFDocumentExtras.bindXObjectCondition(bound,target: boundLeaf,entry: visible)
    expect(pixels(reassigned) == original && pixels(reassigned,1) == original,"nested reassignment preserves all aliases and restores rendering")
    let cleared = try PDFDocumentExtras.bindXObjectCondition(bound,target: boundLeaf,entry: nil),clearedLeaf = try target(cleared,path)
    expect(!clearedLeaf.owned && clearedLeaf.objectID == leaf.objectID && pixels(cleared) == original,"nested clear restores original leaf reference and pixels")
    let formBound = try PDFDocumentExtras.bindXObjectCondition(data,target: mid,entry: hidden),formTarget = try target(formBound,["Outer","Mid"])
    expect(dark(pixels(formBound)) < dark(pixels(bound)) && pixels(formBound,1) == original,"nested Form assignment affects its subtree on selected root path only")
    let blockedChild = try target(formBound,path)
    expect(!blockedChild.editable,"descendants of owned parents are protected from invalidating restore metadata")
    do { _ = try PDFDocumentExtras.bindXObjectCondition(formBound,target: blockedChild,entry: visible); fatalError("owned parent metadata invalidated") } catch { }
    expect(pixels(try PDFDocumentExtras.bindXObjectCondition(formBound,target: formTarget,entry: nil)) == original,"nested Form removal restores source")
    do { _ = try PDFDocumentExtras.bindXObjectCondition(bound,target: leaf,entry: visible); fatalError("stale nested path accepted") } catch { }
    var forged = boundLeaf; forged.resourcePath = ["OuterAlias","Mid","Im"]
    do { _ = try PDFDocumentExtras.bindXObjectCondition(bound,target: forged,entry: visible); fatalError("forged resource path accepted") } catch { }
    let cyclic = nestedXObjectConditionFixture(cycle: true),cycleTargets = try PDFDocumentExtras.xObjectConditionTargets(cyclic,pageIndex: 0)
    expect(cycleTargets.count < 30 && cycleTargets.contains { $0.path == ["Outer","Loop"] && !$0.editable && $0.reason.contains("Cyclic") },"cyclic resource paths stop with a read-only entry")
    let foreign = nestedXObjectConditionFixture(foreign: true),foreignChild = try target(foreign,path)
    expect(!foreignChild.editable,"foreign parent conditions are preserved without cloning descendants")
    let saved = try PDFDocumentSerializer.data(PDFDocument(data: bound)!,preserveStreams: true),savedTarget = try target(saved,path)
    let savedClear = try PDFDocumentExtras.bindXObjectCondition(saved,target: savedTarget,entry: nil)
    expect(savedTarget.editable && savedTarget.owned && pixels(savedClear) == original,"nested condition remains removable after PDFKit serialization")
    let suite = "BotPlusNestedXObject-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("nested-xobject.pdf"),document: document,preserveStreams: true)
    manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500)); view.installDocument(document)
    coordinator.showXObjectConditionEditor(item: item,view: view)
    let request = manager.xObjectConditionRequest!,history = item.undoHistory.count
    expect(request.targets.contains { $0.path == path } && request.apply(leaf,hidden) == nil && item.undoHistory.count == history+1,"nested resource editor performs one atomic transaction")
    expect(request.apply(leaf,visible) != nil,"stale nested editor rejected")
    try manager.saveForClosing(item,to: item.url)
    expect(dark(pixels(try Data(contentsOf: item.url))) < dark(original),"nested assignment survives save/reopen")
    manager.undoDocument(redo: false); expect(pixels(try manager.serializedData(item)) == original,"nested Undo restores original resources")
    manager.undoDocument(redo: true); expect(dark(pixels(try manager.serializedData(item))) < dark(original),"nested Redo restores isolated resource chain")
    print("PASS: nested Image/Form OCMD paths, ancestor cloning, alias/page isolation, preserved streams, cycle/owned-parent/foreign/stale guards and save/Undo/Redo")
}


@MainActor private func checkMeasurementDocumentCopy(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    let suite = "BotPlusMeasurementCopy-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),source = PDFDocument(),destination = PDFDocument(),page = PDFPage(),target = PDFPage(),tiny = PDFPage()
    page.setBounds(CGRect(x: 0,y: 0,width: 800,height: 800),for: .mediaBox); page.setBounds(CGRect(x: 20,y: 40,width: 700,height: 700),for: .cropBox)
    target.setBounds(CGRect(x: -60,y: 10,width: 1000,height: 1000),for: .mediaBox); target.setBounds(CGRect(x: -40,y: 30,width: 900,height: 900),for: .cropBox); target.rotation = 90
    tiny.setBounds(CGRect(x: 0,y: 0,width: 50,height: 50),for: .mediaBox)
    source.insert(page,at: 0); destination.insert(target,at: 0); destination.insert(tiny,at: 1)
    let item = PDFDocumentItem(url: root.appendingPathComponent("copy-source.pdf"),document: source,preserveStreams: true),output = PDFDocumentItem(url: root.appendingPathComponent("copy-destination.pdf"),document: destination,preserveStreams: true)
    manager.insertDocument(output); manager.insertDocument(item); manager.engineeringUnit = .mm
    let sibling = PDFDocumentItem(shared: output.store,page: 1,zoom: 1); manager.insertDocument(sibling); manager.select(item.id)
    try EngineeringCalibration.write(EngineeringScale(millimetersPerPoint: 2,unit: .mm),page: page)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(source)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 200,y: 250),CGPoint(x: 300,y: 250)],view: view)
    coordinator.commitEngineering(page: page,kind: .area,points: [CGPoint(x: 400,y: 350),CGPoint(x: 450,y: 350),CGPoint(x: 400,y: 400)],view: view)
    let inks = page.annotations.filter { AnnotationMetadata.measurement($0) != nil },measures = inks.map { AnnotationMetadata.measurement($0)! },parts = page.annotations.filter { AnnotationMetadata.group(of: $0) != nil },boxes = parts.map(\.bounds),groups = Set(parts.compactMap { AnnotationMetadata.group(of: $0) })
    let collision = PDFAnnotation(bounds: CGRect(x: 50,y: 80,width: 30,height: 20),forType: .freeText,withProperties: nil); collision.contents = "Existing"; AnnotationMetadata.setGroup(groups.first!,on: collision); target.addAnnotation(collision)
    let sourceHistory = item.undoHistory.count,outputHistory = output.undoHistory.count,targetCount = target.annotations.count
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 0,useTargetScale: true),item: item,view: view,destination: output),"copy requires explicit destination calibration when requested")
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 1,centered: true),item: item,view: view,destination: output),"copy rejects groups too large for destination before changing either document")
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 0),item: item,view: view,destination: item),"cross-document copy excludes the same PDF and its views")
    AnnotationMetadata.setLocked(true,on: parts.last!)
    expect(!coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 0),item: item,view: view,destination: output),"locked dependent part rejects entire copy")
    AnnotationMetadata.setLocked(false,on: parts.last!)
    expect(item.undoHistory.count == sourceHistory && output.undoHistory.count == outputHistory && target.annotations.count == targetCount,"rejected copies do not change either history")
    try EngineeringCalibration.write(EngineeringScale(millimetersPerPoint: 0.5,unit: .mm),page: target)
    view.selectAnnotations(inks); coordinator.showEngineeringDocumentCopy(item: item,view: view)
    let request = manager.engineeringTransferRequest!
    expect(request.destinations.count == 1 && request.destinations[0].id == output.id && request.count == 2,"copy dialog deduplicates shared destination views and supports a one-page source")
    let apply = request.applyToDocument!
    view.selectAnnotation(inks[0]); expect(apply(output.id,EngineeringTransferOptions(pageIndex: 0)) != nil,"copy dialog rejects changed selection")
    view.selectAnnotations(inks); coordinator.showEngineeringDocumentCopy(item: item,view: view)
    let staleTarget = manager.engineeringTransferRequest!
    let note = PDFAnnotation(bounds: CGRect(x: 60,y: 80,width: 20,height: 20),forType: .text,withProperties: nil); note.contents = "New note"; target.addAnnotation(note)
    expect(staleTarget.applyToDocument!(output.id,EngineeringTransferOptions(pageIndex: 0)) != nil,"copy dialog detects destination changes")
    target.removeAnnotation(note)
    coordinator.showEngineeringDocumentCopy(item: item,view: view)
    let valid = manager.engineeringTransferRequest!,history = output.undoHistory.count
    expect(valid.applyToDocument!(output.id,EngineeringTransferOptions(pageIndex: 0,offsetX: 10,offsetY: 5)) == nil,"copies measurement families into selected open PDF")
    expect(manager.selected === output && output.undoHistory.count == history+1 && item.undoHistory.count == sourceHistory,"copy selects destination and adds exactly one destination Undo")
    expect(zip(parts,boxes).allSatisfy { $0.0.page === page && $0.0.bounds == $0.1 } && zip(inks,measures).allSatisfy { AnnotationMetadata.measurement($0.0)!.points == $0.1.points },"source geometry and measurement metadata remain untouched")
    let copies = target.annotations.filter { AnnotationMetadata.measurement($0) != nil },copyGroups = Set(copies.compactMap { AnnotationMetadata.group(of: $0) })
    expect(copies.count == 2 && copyGroups.isDisjoint(with: groups) && target.annotations.contains { $0 === collision },"copied groups receive fresh identities despite existing target group collisions")
    for copy in copies {
        let measure = AnnotationMetadata.measurement(copy)!,old = measures.first { $0.kind == measure.kind }!,group = AnnotationMetadata.group(of: copy)!,family = target.annotations.filter { AnnotationMetadata.group(of: $0) == group }
        expect(family.count == parts.filter { AnnotationMetadata.group(of: $0) == AnnotationMetadata.group(of: inks.first { AnnotationMetadata.measurement($0)!.kind == measure.kind }!) }.count,"complete copied families include label and dimension lines")
        expect(close(measure.value,old.value) && measure.scale.millimetersPerPoint == old.scale.millimetersPerPoint && zip(measure.points,old.points).allSatisfy { close($0.0.x,$0.1.x-50) && close($0.0.y,$0.1.y-5) },"copy preserves values and uses CropBox-relative coordinates independent of page rotation")
        let vertices = try PDFAnnotationVertexGeometry.read(copy).first!.vertices
        expect(zip(vertices,measure.points).allSatisfy { close($0.0.point.x,$0.1.x) && close($0.0.point.y,$0.1.y) },"copied native Ink geometry matches measurement metadata")
    }
    expect(valid.applyToDocument!(output.id,EngineeringTransferOptions(pageIndex: 0)) != nil,"used copy dialog rejected after destination changes")
    try manager.saveForClosing(output,to: output.url); try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: output.url)!; AnnotationMetadata.restore(reopened)
    let savedPage = reopened.page(at: 0)!,savedInks = savedPage.annotations.filter { AnnotationMetadata.measurement($0) != nil }
    expect(savedInks.count == 2 && savedPage.rotation == 90,"copied measurements survive PDF save/reopen")
    for ink in savedInks {
        let measure = AnnotationMetadata.measurement(ink)!,vertices = try PDFAnnotationVertexGeometry.read(ink).first!.vertices
        expect(zip(vertices,measure.points).allSatisfy { close($0.0.point.x,$0.1.x) && close($0.0.point.y,$0.1.y) },"saved metadata and Ink agree after MediaBox origin normalization")
    }
    manager.undoDocument(redo: false)
    expect(output.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.isEmpty && page.annotations.filter { AnnotationMetadata.measurement($0) != nil }.count == 2,"one destination Undo removes copies and leaves original PDF intact")
    manager.undoDocument(redo: true)
    expect(output.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.count == 2 && sibling.document === output.document,"Redo restores copies across shared destination views")
    // A second copy creates independent families and can adopt destination scale.
    manager.select(item.id); view.installDocument(source); view.selectAnnotations(inks)
    let latest = output.document.page(at: 0)!,existingGroups = Set(latest.annotations.compactMap { AnnotationMetadata.group(of: $0) })
    expect(coordinator.transferMeasurements(inks,options: EngineeringTransferOptions(pageIndex: 0,centered: true,useTargetScale: true),item: item,view: view,destination: output),"repeated copy can use destination calibration and centering")
    let newInks = latest.annotations.filter { AnnotationMetadata.measurement($0) != nil && !existingGroups.contains(AnnotationMetadata.group(of: $0) ?? "") }
    expect(newInks.count == 2,"repeat copy never merges prior copied groups")
    for ink in newInks { let measure = AnnotationMetadata.measurement(ink)!,old = measures.first { $0.kind == measure.kind }!; expect(close(measure.value,old.value*(measure.kind == .area ? 0.0625 : 0.25)),"target calibration scales copied distance and area correctly") }
    let newGroups = Set(newInks.compactMap { AnnotationMetadata.group(of: $0) }),union = latest.annotations.filter { newGroups.contains(AnnotationMetadata.group(of: $0) ?? "") }.reduce(CGRect.null) { $0.union($1.bounds) },crop = latest.bounds(for: .cropBox)
    expect(close(union.midX,crop.midX) && close(union.midY,crop.midY),"copy centers the complete selection including dimension parts")
    expect(EngineeringCalibration.read(page)!.millimetersPerPoint == 2 && EngineeringCalibration.read(latest)!.millimetersPerPoint == 0.5,"copy does not overwrite either page calibration")
    manager.select(item.id); view.selectAnnotations(inks); coordinator.showEngineeringDocumentCopy(item: item,view: view)
    let closed = manager.engineeringTransferRequest!; manager.close(output.id)
    expect(closed.applyToDocument!(output.id,EngineeringTransferOptions(pageIndex: 0)) != nil,"closed destination rejects pending copy even if another shared view remains")
    print("PASS: cross-document measurement copy, fresh complete families, CropBox/rotation/calibration/centering, destination Undo/shared views, source preservation, stale/closed/lock/bounds guards and save/reopen")
}


@MainActor private func checkDirectionalMeasurements(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    let old = EngineeringMeasure(kind: .distance,points: [CGPoint(x: 200,y: 250),CGPoint(x: 300,y: 310)],scale: EngineeringScale(millimetersPerPoint: 2,unit: .mm),dimensionOffset: 12)
    let legacy = try JSONDecoder().decode(EngineeringMeasure.self,from: JSONEncoder().encode(old))
    expect(legacy.distanceAxis == nil && legacy.axis == .aligned && close(legacy.value,hypot(100,60)*2),"legacy measurement without axis keeps Euclidean distance")
    var x = old; x.distanceAxis = .horizontal; var y = old; y.distanceAxis = .vertical
    expect(close(x.value,200) && close(y.value,120) && x.label(russian: true).hasSuffix(" · X") && y.label(russian: false).hasSuffix(" · Y"),"axis values are calibrated unsigned projections with explicit labels")
    var rotation = EngineeringAffineOptions(); rotation.degrees = 30; rotation.preservingValue = false
    let rotated = x.transformed(options: rotation)!
    expect(rotated.axis == .horizontal && close(rotated.value,abs(rotated.points[1].x-rotated.points[0].x)*2),"affine transform retains PDF axis and recalculates projection")
    rotation.preservingValue = true
    expect(close(x.transformed(options: rotation)!.value,x.value),"value-preserving rotation recalibrates projected rather than Euclidean length")
    var zero = x; zero.points[1].x = zero.points[0].x
    expect(zero.value == 0 && zero.transformed(options: rotation) == nil,"zero projection cannot preserve its value through a rotation that makes it nonzero")
    let suite = "BotPlusDirectional-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    try EngineeringCalibration.write(old.scale,page: page)
    let item = PDFDocumentItem(url: root.appendingPathComponent("directional.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: old.points,view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,group = AnnotationMetadata.group(of: ink)!,originalBounds = ink.bounds,history = item.undoHistory.count
    expect(coordinator.setMeasurementAxis(ink,axis: .horizontal,item: item,view: view),"horizontal projection applies to existing calibrated measurement")
    expect(item.undoHistory.count == history+1 && ink.bounds == originalBounds && AnnotationMetadata.measurement(ink)!.points == old.points,"axis change is one Undo and retains source points/stroke geometry")
    func dimension(_ page: PDFPage,_ group: String) -> PDFAnnotation { page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "Line" && $0.startLineStyle == .closedArrow }! }
    let horizontal = dimension(page,group)
    expect(close(horizontal.startPoint.y,horizontal.endPoint.y) && close(abs(horizontal.endPoint.x-horizontal.startPoint.x),100),"horizontal dimension arrows match the X projection on a rotated page")
    let noOp = item.undoHistory.count
    expect(coordinator.setMeasurementAxis(ink,axis: .horizontal,item: item,view: view) && item.undoHistory.count == noOp,"same axis produces no extra history")
    let label = page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "FreeText" }!
    AnnotationMetadata.setLocked(true,on: label)
    expect(!coordinator.setMeasurementAxis(ink,axis: .vertical,item: item,view: view) && item.undoHistory.count == noOp,"locked family member rejects axis change without history")
    AnnotationMetadata.setLocked(false,on: label)
    expect(coordinator.setMeasurementAxis(ink,axis: .vertical,item: item,view: view),"vertical projection applies")
    let vertical = dimension(page,group)
    expect(close(vertical.startPoint.x,vertical.endPoint.x) && close(abs(vertical.endPoint.y-vertical.startPoint.y),60) && close(AnnotationMetadata.measurement(ink)!.value,120),"vertical arrows and value match Y projection")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedInk = saved.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedMeasure = AnnotationMetadata.measurement(savedInk)!
    expect(savedMeasure.axis == .vertical && close(savedMeasure.value,120),"axis and value survive save/reopen with normalized MediaBox origin")
    let vertices = try PDFAnnotationVertexGeometry.read(savedInk).first!.vertices
    expect(zip(vertices,savedMeasure.points).allSatisfy { close($0.0.point.x,$0.1.x) && close($0.0.point.y,$0.1.y) },"axis measurement remains editable with matching native Ink coordinates")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.axis == .horizontal,"Undo restores prior axis and dimensions")
    manager.undoDocument(redo: true)
    let currentPage = item.document.page(at: 0)!,current = currentPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!; view.installDocument(item.document)
    expect(AnnotationMetadata.measurement(current)!.axis == .vertical,"Redo restores directional measurement")
    expect(coordinator.setMeasurementAxis(current,axis: .aligned,item: item,view: view) && close(AnnotationMetadata.measurement(current)!.value,old.value),"aligned mode restores original distance")
    let boundaryHistory = item.undoHistory.count,currentGroup = AnnotationMetadata.group(of: current)!
    var outside = AnnotationMetadata.measurement(current)!; outside.dimensionOffset = 10000; AnnotationMetadata.setMeasurement(outside,on: current)
    expect(!coordinator.setMeasurementAxis(current,axis: .horizontal,item: item,view: view) && item.undoHistory.count == boundaryHistory,"out-of-bounds projected dimension rejects atomically")
    expect(currentPage.annotations.contains { AnnotationMetadata.group(of: $0) == currentGroup && $0.type == "Line" },"failed projection retains existing dimension family")
    print("PASS: directional X/Y calibrated distances, legacy decoding, projected dimension arrows, affine value policies, no-op/lock/bounds guards and save/Undo/Redo")
}


@MainActor private func checkCustomDirectionMeasurements(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    var measure = EngineeringMeasure(kind: .distance,points: [CGPoint(x: 200,y: 250),CGPoint(x: 300,y: 310)],scale: EngineeringScale(millimetersPerPoint: 2,unit: .mm),dimensionOffset: 12)
    let old = measure; measure.distanceAxis = .custom; measure.directionDegrees = 45
    let expected = 320/sqrt(2.0)
    expect(close(measure.value,expected) && measure.label(russian: true).hasSuffix("45°"),"arbitrary projection uses dot product and calibrated absolute value")
    measure.directionDegrees = 225; expect(measure.direction == 45 && close(measure.value,expected),"opposite directions normalize to same axis")
    measure.directionDegrees = -45; expect(measure.direction == 135 && close(measure.value,80/sqrt(2.0)),"negative directions normalize and signed projections become absolute")
    measure.directionDegrees = 0; expect(close(measure.value,200),"custom zero agrees with X")
    measure.directionDegrees = 90; expect(close(measure.value,120),"custom right angle agrees with Y")
    var perpendicular = measure; perpendicular.directionDegrees = 135; perpendicular.points[1] = CGPoint(x: 300,y: 350)
    expect(perpendicular.value == 0,"floating-point perpendicular direction resolves to zero projection")
    measure.directionDegrees = .infinity; expect(!measure.value.isFinite && measure.transformed(options: EngineeringAffineOptions()) == nil,"malformed direction is rejected instead of falling back to Euclidean length")
    measure.directionDegrees = 45
    var affine = EngineeringAffineOptions(); affine.degrees = 20; affine.shearX = 0.2; affine.scaleY = 1.4; affine.preservingValue = false
    let transformed = measure.transformed(options: affine)!,points = transformed.points,projection = abs((points[1].x-points[0].x+points[1].y-points[0].y)/sqrt(2.0))*2
    expect(transformed.direction == 45 && close(transformed.value,projection),"affine keeps the direction fixed in PDF coordinates")
    affine.preservingValue = true; expect(close(measure.transformed(options: affine)!.value,measure.value),"value-preserving affine recalibrates arbitrary projection")
    let roundTrip = try JSONDecoder().decode(EngineeringMeasure.self,from: JSONEncoder().encode(measure))
    expect(roundTrip.direction == 45 && close(roundTrip.value,expected),"direction survives Codable round trip")
    let suite = "BotPlusCustomDirection-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    try EngineeringCalibration.write(old.scale,page: page)
    let item = PDFDocumentItem(url: root.appendingPathComponent("custom-direction.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: old.points,view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,group = AnnotationMetadata.group(of: ink)!,box = ink.bounds,history = item.undoHistory.count
    coordinator.showMeasurementDirection(ink,item: item,view: view)
    let stale = manager.engineeringDirectionRequest!; view.selectAnnotations([])
    expect(stale.apply(45) != nil,"direction editor rejects changed selection")
    view.selectAnnotation(ink); coordinator.showMeasurementDirection(ink,item: item,view: view)
    let request = manager.engineeringDirectionRequest!
    expect(request.apply(.nan) != nil && request.apply(361) != nil && item.undoHistory.count == history,"invalid input changes neither measurement nor history")
    expect(request.apply(225) == nil && item.undoHistory.count == history+1,"custom angle editor applies one atomic operation")
    expect(ink.bounds == box && AnnotationMetadata.measurement(ink)!.points == old.points && close(AnnotationMetadata.measurement(ink)!.value,expected),"custom direction preserves source geometry")
    let dimension = page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "Line" && $0.startLineStyle == .closedArrow }!,dx = dimension.endPoint.x-dimension.startPoint.x,dy = dimension.endPoint.y-dimension.startPoint.y
    expect(close(dx,dy) && close(hypot(dx,dy)*2,expected),"dimension arrow baseline is parallel to the specified direction with correct projected length")
    expect(request.apply(30) != nil,"used direction editor detects changed metadata")
    let noOp = item.undoHistory.count
    expect(coordinator.setMeasurementAxis(ink,axis: .custom,item: item,view: view,degrees: -135) && item.undoHistory.count == noOp,"equivalent angle is a no-op")
    let label = page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "FreeText" }!
    AnnotationMetadata.setLocked(true,on: label)
    expect(!coordinator.setMeasurementAxis(ink,axis: .custom,item: item,view: view,degrees: 30) && item.undoHistory.count == noOp,"locked dependent part refuses direction update")
    AnnotationMetadata.setLocked(false,on: label)
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedInk = saved.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedMeasure = AnnotationMetadata.measurement(savedInk)!
    expect(savedMeasure.axis == .custom && savedMeasure.direction == 45 && close(savedMeasure.value,expected),"custom direction survives PDF save/reopen")
    let vertices = try PDFAnnotationVertexGeometry.read(savedInk).first!.vertices
    expect(zip(vertices,savedMeasure.points).allSatisfy { close($0.0.point.x,$0.1.x) && close($0.0.point.y,$0.1.y) },"saved arbitrary projection retains editable native Ink")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.axis == .aligned,"Undo restores original Euclidean metric")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let current = item.document.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!
    expect(AnnotationMetadata.measurement(current)!.direction == 45,"Redo restores angle and projected dimensions")
    let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 900,height: 900),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
    let output = PDFDocumentItem(url: root.appendingPathComponent("custom-copy.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
    expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"arbitrary direction can be copied to another PDF")
    let copied = outputPage.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!
    expect(copied.direction == 45 && close(copied.value,expected),"cross-document copy retains direction and value")
    print("PASS: arbitrary calibrated projection angles, normalization/perpendicular limits, affine policies, angled dimension geometry, stale/lock/no-op guards, cross-PDF copy and save/Undo/Redo")
}


@MainActor private func checkMeasurementLabelLeaders(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    let suite = "BotPlusMeasurementLabel-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("measurement-leader.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 250,y: 300),CGPoint(x: 350,y: 360)],view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!,label = page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "FreeText" }!,originalLabel = label.bounds,history = item.undoHistory.count
    func lines(_ page: PDFPage,_ group: String) -> [PDFAnnotation] { page.annotations.filter { AnnotationMetadata.group(of: $0) == group && AnnotationMetadata.decoration(of: $0) == "engineeringDimension" } }
    expect(original.labelOffset == nil && lines(page,group).count == 3,"legacy automatic label retains three dimension lines")
    coordinator.showMeasurementLabel(ink,item: item,view: view)
    let stale = manager.engineeringLabelRequest!; view.selectAnnotations([])
    expect(stale.apply(EngineeringLabelOptions(x: 100,y: 80)) != nil,"label editor rejects changed selection")
    view.selectAnnotation(ink); coordinator.showMeasurementLabel(ink,item: item,view: view)
    let request = manager.engineeringLabelRequest!
    expect(request.apply(EngineeringLabelOptions(x: .nan,y: 0)) != nil && request.apply(EngineeringLabelOptions(x: 10000,y: 0)) != nil && item.undoHistory.count == history,"invalid or out-of-page leader is rejected before history")
    expect(request.apply(EngineeringLabelOptions(x: 100,y: 80)) == nil && item.undoHistory.count == history+1,"label/leader applies in one transaction")
    expect(close(label.bounds.minX,originalLabel.minX+100) && close(label.bounds.minY,originalLabel.minY+80) && lines(page,group).count == 4,"displaced label creates one standard vector connector")
    let measure = AnnotationMetadata.measurement(ink)!
    expect(measure.points == original.points && close(measure.value,original.value) && measure.scale.millimetersPerPoint == original.scale.millimetersPerPoint,"callout placement leaves measured points/calibration/value unchanged")
    let connector = lines(page,group).last!,end = CGPoint(x: connector.bounds.minX+connector.endPoint.x,y: connector.bounds.minY+connector.endPoint.y)
    expect(close(end.x,label.bounds.minX) && close(end.y,label.bounds.minY),"connector ends on nearest label edge")
    expect(request.apply(EngineeringLabelOptions(x: 0,y: 0)) != nil,"used label dialog is stale")
    let same = item.undoHistory.count
    expect(coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80),item: item,view: view) && item.undoHistory.count == same,"same placement is no-op")
    AnnotationMetadata.setLocked(true,on: connector)
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 50,y: 50),item: item,view: view) && item.undoHistory.count == same,"locked connector protects the complete family")
    AnnotationMetadata.setLocked(false,on: connector)
    expect(coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80,leader: false),item: item,view: view) && lines(page,group).count == 3,"connector can be disabled without resetting label position")
    expect(coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(),item: item,view: view) && label.bounds == originalLabel && AnnotationMetadata.measurement(ink)!.labelOffset == nil,"reset restores automatic position and legacy metadata")
    expect(coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80),item: item,view: view),"leader can be reapplied after reset")
    var affine = EngineeringAffineOptions(); affine.degrees = 90; affine.preservingValue = false
    let rotated = AnnotationMetadata.measurement(ink)!.transformed(options: affine)!
    expect(close(rotated.labelOffset!.x,-80) && close(rotated.labelOffset!.y,100),"affine rotates relative label offset as a vector")
    var shift = EngineeringAffineOptions(); shift.offsetX = 10; shift.offsetY = -20
    expect(AnnotationMetadata.measurement(ink)!.transformed(options: shift)!.labelOffset == CGPoint(x: 100,y: 80),"translation preserves relative offset")
    try manager.saveForClosing(item,to: item.url)
    let reopened = PDFDocument(url: item.url)!; AnnotationMetadata.restore(reopened)
    let savedPage = reopened.page(at: 0)!,savedInk = savedPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedMeasure = AnnotationMetadata.measurement(savedInk)!,savedGroup = AnnotationMetadata.group(of: savedInk)!
    expect(savedMeasure.labelOffset == CGPoint(x: 100,y: 80) && savedMeasure.labelLeader == true && lines(savedPage,savedGroup).count == 4,"leader and relative placement survive normalized-origin PDF save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.labelOffset == nil,"one Undo restores automatic label")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let currentPage = item.document.page(at: 0)!,current = currentPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,currentGroup = AnnotationMetadata.group(of: current)!
    expect(lines(currentPage,currentGroup).count == 4,"Redo restores vector connector")
    let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
    let output = PDFDocumentItem(url: root.appendingPathComponent("copied-leader.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
    expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"leader family can be copied to another PDF")
    let copied = outputPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,copiedGroup = AnnotationMetadata.group(of: copied)!
    expect(AnnotationMetadata.measurement(copied)!.labelOffset == CGPoint(x: 100,y: 80) && copiedGroup != currentGroup && lines(outputPage,copiedGroup).count == 4,"copy retains relative placement/connector in independent group")
    view.installDocument(output.document); view.selectAnnotation(copied)
    var actual = EngineeringAffineOptions(); actual.degrees = 15; actual.preservingValue = false
    expect(coordinator.transformMeasurements([copied],options: actual,item: output,view: view),"complete leader family supports affine transaction")
    let transformed = AnnotationMetadata.measurement(copied)!,expectedOffset = CGPoint(x: 100,y: 80).applying(actual.linear!)
    expect(close(transformed.labelOffset!.x,expectedOffset.x) && close(transformed.labelOffset!.y,expectedOffset.y) && lines(outputPage,copiedGroup).count == 4,"affine rebuild retains connector and transformed offset")
    print("PASS: calibrated dimension label offsets/reset/connector, unchanged source metric, affine vector policy, family bounds/locks/stale/no-op guards, cross-PDF copy and save/Undo/Redo")
}


@MainActor private func checkMeasurementElbowLeaders(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    var model = EngineeringMeasure(kind: .distance,points: [.zero,CGPoint(x: 100,y: 0)],scale: EngineeringScale(),dimensionOffset: 12)
    model.labelOffset = CGPoint(x: 100,y: 80); model.leaderElbow = CGPoint(x: 40,y: 20)
    let rectangle = CGRect(x: 100,y: 80,width: 140,height: 24),route = model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle)
    expect(route == [.zero,CGPoint(x: 40,y: 20),CGPoint(x: 100,y: 80)],"elbow creates two connected segments ending at label edge")
    model.leaderElbow = CGPoint(x: 200,y: 100)
    let clipped = model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle)
    expect(clipped.count == 2 && close(clipped.last!.x,160) && close(clipped.last!.y,80),"first leg clips at label even when knee is inside it")
    model.leaderElbow = CGPoint(x: 300,y: 150)
    let crossing = model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle)
    expect(crossing.count == 2 && close(crossing.last!.x,160),"leg crossing entire label stops at first boundary")
    model.leaderElbow = .zero
    expect(model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle).count == 2,"zero-length first leg is omitted")
    model.leaderElbow = CGPoint(x: CGFloat.infinity,y: 0)
    expect(!model.validLabelPlacement && model.transformed(options: EngineeringAffineOptions()) == nil,"invalid knee cannot enter affine rendering")
    let suite = "BotPlusElbow-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("elbow-leader.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 250,y: 300),CGPoint(x: 350,y: 360)],view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!
    func lines(_ page: PDFPage,_ group: String) -> [PDFAnnotation] { page.annotations.filter { AnnotationMetadata.group(of: $0) == group && AnnotationMetadata.decoration(of: $0) == "engineeringDimension" } }
    let options = EngineeringLabelOptions(x: 100,y: 80,leader: true,elbow: true,elbowX: 40,elbowY: 20),history = item.undoHistory.count
    coordinator.showMeasurementLabel(ink,item: item,view: view)
    let request = manager.engineeringLabelRequest!
    expect(request.apply(options) == nil && item.undoHistory.count == history+1,"elbow editor applies one atomic transaction")
    expect(lines(page,group).count == 5 && AnnotationMetadata.measurement(ink)!.leaderElbow == CGPoint(x: 40,y: 20),"elbow produces two standard vector Lines in measurement family")
    let legs = Array(lines(page,group).suffix(2)),jointA = CGPoint(x: legs[0].bounds.minX+legs[0].endPoint.x,y: legs[0].bounds.minY+legs[0].endPoint.y),jointB = CGPoint(x: legs[1].bounds.minX+legs[1].startPoint.x,y: legs[1].bounds.minY+legs[1].startPoint.y)
    expect(close(jointA.x,jointB.x) && close(jointA.y,jointB.y),"vector legs meet exactly at the knee")
    expect(AnnotationMetadata.measurement(ink)!.points == original.points && close(AnnotationMetadata.measurement(ink)!.value,original.value),"elbow does not change calibration or measured geometry")
    expect(request.apply(EngineeringLabelOptions(x: 100,y: 80)) != nil,"old editor detects changed elbow")
    let unchanged = item.undoHistory.count
    expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view) && item.undoHistory.count == unchanged,"same elbow is a no-op")
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80,elbow: true,elbowX: -1000,elbowY: -1000),item: item,view: view) && item.undoHistory.count == unchanged,"out-of-page leg rejects before history")
    AnnotationMetadata.setLocked(true,on: legs[1])
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80),item: item,view: view),"locked knee leg protects family")
    AnnotationMetadata.setLocked(false,on: legs[1])
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedPage = saved.page(at: 0)!,savedInk = savedPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedMeasure = AnnotationMetadata.measurement(savedInk)!,savedGroup = AnnotationMetadata.group(of: savedInk)!
    expect(savedMeasure.leaderElbow == CGPoint(x: 40,y: 20) && lines(savedPage,savedGroup).count == 5,"relative knee and vector legs survive PDF save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.leaderElbow == nil,"one Undo removes knee and displaced label")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let current = item.document.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!
    expect(AnnotationMetadata.measurement(current)!.leaderElbow == CGPoint(x: 40,y: 20),"Redo restores knee")
    let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
    let output = PDFDocumentItem(url: root.appendingPathComponent("copied-elbow.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
    expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"elbow family copies across PDF documents")
    let copied = outputPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,copiedGroup = AnnotationMetadata.group(of: copied)!
    expect(lines(outputPage,copiedGroup).count == 5 && AnnotationMetadata.measurement(copied)!.leaderElbow == CGPoint(x: 40,y: 20),"copy retains independent knee metadata and both legs")
    view.installDocument(output.document); view.selectAnnotation(copied)
    var affine = EngineeringAffineOptions(); affine.degrees = 90; affine.preservingValue = false
    expect(coordinator.transformMeasurements([copied],options: affine,item: output,view: view),"full elbow family supports affine operation")
    let transformed = AnnotationMetadata.measurement(copied)!
    expect(close(transformed.leaderElbow!.x,-20) && close(transformed.leaderElbow!.y,40) && lines(outputPage,copiedGroup).count == 5,"affine rotates knee vector and rebuilds connected legs")
    expect(coordinator.setMeasurementLabel(copied,options: EngineeringLabelOptions(x: -80,y: 100),item: output,view: view) && AnnotationMetadata.measurement(copied)!.leaderElbow == nil && lines(outputPage,copiedGroup).count == 4,"turning elbow off returns to straight connector")
    print("PASS: elbow measurement leaders, label-boundary clipping, connected vector legs, affine/copy policies, no-op/bounds/lock/stale guards and save/Undo/Redo")
}


@MainActor private func checkMeasurementPolylineLeaders(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: Double,_ b: Double) -> Bool { abs(a-b) < 0.00001 }
    let waypoints = [CGPoint(x: 40,y: 20),CGPoint(x: 80,y: 20),CGPoint(x: 80,y: 60)]
    var model = EngineeringMeasure(kind: .distance,points: [.zero,CGPoint(x: 100,y: 0)],scale: EngineeringScale(),dimensionOffset: 12)
    model.labelOffset = CGPoint(x: 100,y: 80); model.leaderWaypoints = waypoints
    let rectangle = CGRect(x: 100,y: 80,width: 140,height: 24),route = model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle)
    expect(route == [.zero]+waypoints+[CGPoint(x: 100,y: 80)],"multi-knee route preserves vertex order and reaches label boundary")
    model.leaderWaypoints = [.zero,.zero]+waypoints
    expect(model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle) == route,"repeated/zero vertices create no degenerate segments")
    model.leaderWaypoints = [CGPoint(x: 200,y: 100),CGPoint(x: -500,y: -500)]
    expect(model.labelLeaderPoints(midpoint: .zero,labelBounds: rectangle).count == 2,"crossing label terminates route before later vertices")
    model.leaderWaypoints = Array(repeating: .zero,count: 33)
    expect(!model.validLabelPlacement && model.transformed(options: EngineeringAffineOptions()) == nil,"waypoint limit protects render and affine paths")
    let suite = "BotPlusPolylineLeader-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("polyline-leader.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 250,y: 300),CGPoint(x: 350,y: 360)],view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!,history = item.undoHistory.count
    func lines(_ page: PDFPage,_ group: String) -> [PDFAnnotation] { page.annotations.filter { AnnotationMetadata.group(of: $0) == group && AnnotationMetadata.decoration(of: $0) == "engineeringDimension" } }
    let options = EngineeringLabelOptions(x: 100,y: 80,waypoints: waypoints)
    coordinator.showMeasurementLabel(ink,item: item,view: view)
    let request = manager.engineeringLabelRequest!
    expect(request.apply(options) == nil && item.undoHistory.count == history+1,"polyline editor installs one atomic route change")
    expect(AnnotationMetadata.measurement(ink)!.leaderWaypoints == waypoints && lines(page,group).count == 7,"three waypoints generate four standard vector connector legs")
    let legs = Array(lines(page,group).suffix(4))
    for index in 0..<legs.count-1 {
        let a = legs[index],b = legs[index+1],end = CGPoint(x: a.bounds.minX+a.endPoint.x,y: a.bounds.minY+a.endPoint.y),start = CGPoint(x: b.bounds.minX+b.startPoint.x,y: b.bounds.minY+b.startPoint.y)
        expect(close(end.x,start.x) && close(end.y,start.y),"adjacent polyline legs share exact joint coordinates")
    }
    expect(AnnotationMetadata.measurement(ink)!.points == original.points && close(AnnotationMetadata.measurement(ink)!.value,original.value),"multi-knee placement preserves measured geometry/value")
    let same = item.undoHistory.count
    expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view) && item.undoHistory.count == same,"identical route is a no-op")
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80,waypoints: Array(repeating: .zero,count: 33)),item: item,view: view),"too many vertices are rejected atomically")
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80,waypoints: [CGPoint(x: CGFloat.nan,y: 0)]),item: item,view: view),"nonfinite vertex rejected")
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80,waypoints: [CGPoint(x: -1000,y: -1000)]),item: item,view: view) && item.undoHistory.count == same,"out-of-page visible leg rejected before history")
    AnnotationMetadata.setLocked(true,on: legs[1])
    expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 100,y: 80),item: item,view: view),"locked intermediate leg protects route")
    AnnotationMetadata.setLocked(false,on: legs[1])
    coordinator.showMeasurementLabel(ink,item: item,view: view)
    let ordered = manager.engineeringLabelRequest!,reordered = [waypoints[1],waypoints[0],waypoints[2]]
    expect(ordered.initial.waypoints == waypoints && ordered.apply(EngineeringLabelOptions(x: 100,y: 80,waypoints: reordered)) == nil && AnnotationMetadata.measurement(ink)!.leaderWaypoints == reordered,"editor reopens ordered vertices and applies reordering")
    expect(ordered.apply(options) != nil,"reordered route invalidates old editor")
    expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view),"original order can be restored")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedPage = saved.page(at: 0)!,savedInk = savedPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedGroup = AnnotationMetadata.group(of: savedInk)!
    expect(AnnotationMetadata.measurement(savedInk)!.leaderWaypoints == waypoints && lines(savedPage,savedGroup).count == 7,"ordered relative vertices and vector legs survive PDF save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.leaderWaypoints == reordered,"Undo restores previous vertex order")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let current = item.document.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!
    expect(AnnotationMetadata.measurement(current)!.leaderWaypoints == waypoints,"Redo restores route")
    let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
    let output = PDFDocumentItem(url: root.appendingPathComponent("copied-polyline.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
    expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"complete polyline family copies across documents")
    let copied = outputPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,copiedGroup = AnnotationMetadata.group(of: copied)!
    expect(AnnotationMetadata.measurement(copied)!.leaderWaypoints == waypoints && lines(outputPage,copiedGroup).count == 7,"copy retains independent route geometry and metadata")
    view.installDocument(output.document); view.selectAnnotation(copied)
    var affine = EngineeringAffineOptions(); affine.degrees = 90; affine.preservingValue = false
    expect(coordinator.transformMeasurements([copied],options: affine,item: output,view: view),"complete polyline family transforms atomically")
    let transformed = AnnotationMetadata.measurement(copied)!
    expect(transformed.leaderWaypoints == waypoints.map { $0.applying(affine.linear!) } && lines(outputPage,copiedGroup).count == 7,"affine transforms every relative waypoint and rebuilds route")
    expect(coordinator.setMeasurementLabel(copied,options: EngineeringLabelOptions(x: -80,y: 100,waypoints: [CGPoint(x: -20,y: 40)]),item: output,view: view) && AnnotationMetadata.measurement(copied)!.leaderElbow == CGPoint(x: -20,y: 40) && AnnotationMetadata.measurement(copied)!.leaderWaypoints == nil,"one waypoint canonicalizes to compatible single elbow")
    expect(coordinator.setMeasurementLabel(copied,options: EngineeringLabelOptions(x: -80,y: 100,waypoints: []),item: output,view: view) && AnnotationMetadata.measurement(copied)!.effectiveLeaderWaypoints.isEmpty && lines(outputPage,copiedGroup).count == 4,"removing all waypoints restores straight leader")
    print("PASS: multi-knee measurement leaders, ordered joints/editing, clipping/duplicates/limits, affine/copy policies, stale/lock/bounds/no-op guards and save/Undo/Redo")
}


@MainActor private func checkMeasurementLeaderAnchors(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: CGPoint,_ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y) < 0.00001 }
    var model = EngineeringMeasure(kind: .distance,points: [CGPoint(x: 10,y: 20),CGPoint(x: 100,y: 70)],scale: EngineeringScale(),dimensionOffset: 12)
    let p = CGPoint(x: 0,y: 30),q = CGPoint(x: 100,y: 80),mid = CGPoint(x: 50,y: 55)
    let expected = [mid,p,q,model.points[0],model.points[1]]
    for (index,anchor) in EngineeringLeaderAnchor.allCases.enumerated() {
        model.leaderAnchor = anchor
        expect(model.leaderAnchorPoint(dimensionStart: p,dimensionEnd: q) == expected[index],"anchor resolves to requested dimension/measured point")
    }
    model.labelOffset = CGPoint(x: 100,y: 80); model.leaderElbow = CGPoint(x: 40,y: 20)
    let route = model.labelLeaderPoints(midpoint: mid,labelBounds: CGRect(x: 150,y: 150,width: 100,height: 30),anchor: p)
    expect(route.first == p && route[1] == CGPoint(x: 90,y: 75),"anchor changes start while elbow stays relative to dimension midpoint")
    expect(model.labelLeaderPoints(midpoint: mid,labelBounds: CGRect(x: 0,y: 0,width: 20,height: 40),anchor: model.points[0]).isEmpty,"anchor inside label creates no connector through text")
    let legacy = EngineeringMeasure(kind: .distance,points: model.points,scale: model.scale,dimensionOffset: 12)
    expect(try JSONDecoder().decode(EngineeringMeasure.self,from: JSONEncoder().encode(legacy)).effectiveLeaderAnchor == .midpoint,"legacy metadata defaults to midpoint")
    let suite = "BotPlusLeaderAnchors-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
    page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("leader-anchor.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.commitEngineering(page: page,kind: .distance,points: [CGPoint(x: 250,y: 300),CGPoint(x: 350,y: 360)],view: view)
    let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!
    func lines(_ page: PDFPage,_ group: String) -> [PDFAnnotation] { page.annotations.filter { AnnotationMetadata.group(of: $0) == group && AnnotationMetadata.decoration(of: $0) == "engineeringDimension" } }
    func endpoints(_ line: PDFAnnotation) -> (CGPoint,CGPoint) { (CGPoint(x: line.bounds.minX+line.startPoint.x,y: line.bounds.minY+line.startPoint.y),CGPoint(x: line.bounds.minX+line.endPoint.x,y: line.bounds.minY+line.endPoint.y)) }
    let waypoints = [CGPoint(x: 40,y: 20),CGPoint(x: 80,y: 20),CGPoint(x: 80,y: 60)]
    var options = EngineeringLabelOptions(x: 100,y: 80,waypoints: waypoints,anchor: .dimensionStart)
    let history = item.undoHistory.count
    coordinator.showMeasurementLabel(ink,item: item,view: view)
    let request = manager.engineeringLabelRequest!
    expect(request.initial.anchor == .midpoint && request.apply(options) == nil && item.undoHistory.count == history+1,"anchor editor changes family in one transaction")
    expect(request.apply(EngineeringLabelOptions(x: 100,y: 80)) != nil,"anchor change invalidates old editor")
    for anchor in [EngineeringLeaderAnchor.dimensionStart,.dimensionEnd,.measuredStart,.measuredEnd] {
        options.anchor = anchor
        expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view),"all dimension/measured anchors can be selected")
        let parts = lines(page,group),measure = AnnotationMetadata.measurement(ink)!,dimension = parts.first { $0.startLineStyle == .closedArrow }!,base = endpoints(dimension),start = endpoints(parts[3]).0,expectedStart = measure.leaderAnchorPoint(dimensionStart: base.0,dimensionEnd: base.1),midpoint = CGPoint(x: (base.0.x+base.1.x)/2,y: (base.0.y+base.1.y)/2)
        expect(parts.count == 7 && close(start,expectedStart) && close(endpoints(parts[3]).1,CGPoint(x: midpoint.x+40,y: midpoint.y+20)),"renderer uses selected anchor without shifting waypoint frame")
        expect(measure.points == original.points && measure.value == original.value,"changing attachment preserves measured geometry and calibration")
    }
    let noOp = item.undoHistory.count
    expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view) && item.undoHistory.count == noOp,"same anchor/route is a no-op")
    let connector = lines(page,group).last!; AnnotationMetadata.setLocked(true,on: connector)
    var other = options; other.anchor = .dimensionStart
    expect(!coordinator.setMeasurementLabel(ink,options: other,item: item,view: view) && item.undoHistory.count == noOp,"locked route member protects anchor")
    AnnotationMetadata.setLocked(false,on: connector)
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    let savedPage = saved.page(at: 0)!,savedInk = savedPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedGroup = AnnotationMetadata.group(of: savedInk)!,savedMeasure = AnnotationMetadata.measurement(savedInk)!
    expect(savedMeasure.effectiveLeaderAnchor == .measuredEnd && close(endpoints(lines(savedPage,savedGroup)[3]).0,savedMeasure.points.last!),"anchor survives normalized-origin PDF save/reopen with exact native start point")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.effectiveLeaderAnchor == .measuredStart,"Undo restores previous attachment")
    manager.undoDocument(redo: true); view.installDocument(item.document)
    let current = item.document.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!
    expect(AnnotationMetadata.measurement(current)!.effectiveLeaderAnchor == .measuredEnd,"Redo restores selected anchor")
    let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
    let output = PDFDocumentItem(url: root.appendingPathComponent("copied-anchor.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
    expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"anchored route copies across PDF documents")
    let copied = outputPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,copiedGroup = AnnotationMetadata.group(of: copied)!
    expect(AnnotationMetadata.measurement(copied)!.effectiveLeaderAnchor == .measuredEnd,"copy preserves anchor semantics")
    view.installDocument(output.document); view.selectAnnotation(copied)
    var affine = EngineeringAffineOptions(); affine.degrees = 90; affine.preservingValue = false
    expect(coordinator.transformMeasurements([copied],options: affine,item: output,view: view),"anchored route supports full affine transaction")
    let transformed = AnnotationMetadata.measurement(copied)!
    expect(transformed.effectiveLeaderAnchor == .measuredEnd && close(endpoints(lines(outputPage,copiedGroup)[3]).0,transformed.points.last!),"transformed anchor follows its measured point")
    options.anchor = .midpoint; options.waypoints = nil
    expect(coordinator.setMeasurementLabel(copied,options: options,item: output,view: view) && AnnotationMetadata.measurement(copied)!.leaderAnchor == nil,"midpoint canonicalizes to legacy metadata")
    print("PASS: dimension/measured leader anchors, stable waypoint frame, renderer geometry, legacy/stale/lock/no-op guards, affine/copy and save/Undo/Redo")
}


@MainActor private func checkContourMeasurementLeaders(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func close(_ a: CGPoint,_ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y) < 0.00001 }
    let points = [CGPoint(x: 220,y: 250),CGPoint(x: 340,y: 250),CGPoint(x: 340,y: 370)]
    let perimeter = EngineeringMeasure(kind: .perimeter,points: points,scale: EngineeringScale(),dimensionOffset: nil),area = EngineeringMeasure(kind: .area,points: points,scale: EngineeringScale(),dimensionOffset: nil)
    expect(close(perimeter.contourLeaderMidpoint!,points[1]),"perimeter anchor is halfway along open polyline")
    let closedLength = 240+hypot(120.0,120.0),expectedArea = CGPoint(x: 340,y: 250+closedLength/2-120)
    expect(close(area.contourLeaderMidpoint!,expectedArea),"area anchor includes closing edge in arc midpoint")
    var degenerate = perimeter; degenerate.points = [.zero,.zero]
    expect(degenerate.contourLeaderMidpoint == nil,"degenerate contour has no leader origin")
    for kind in [EngineeringKind.perimeter,.area] {
        let suite = "BotPlusContourLeader-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage()
        page.setBounds(CGRect(x: -20,y: 10,width: 800,height: 800),for: .mediaBox); page.rotation = 90; document.insert(page,at: 0)
        let item = PDFDocumentItem(url: root.appendingPathComponent(kind.rawValue+"-leader.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.engineeringUnit = .mm
        let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
        coordinator.commitEngineering(page: page,kind: kind,points: points,view: view)
        let ink = page.annotations.first { AnnotationMetadata.measurement($0) != nil }!,original = AnnotationMetadata.measurement(ink)!,group = AnnotationMetadata.group(of: ink)!,label = page.annotations.first { AnnotationMetadata.group(of: $0) == group && $0.type == "FreeText" }!,originalBox = label.bounds
        func lines(_ page: PDFPage,_ group: String) -> [PDFAnnotation] { page.annotations.filter { AnnotationMetadata.group(of: $0) == group && AnnotationMetadata.decoration(of: $0) == "engineeringDimension" } }
        func start(_ line: PDFAnnotation) -> CGPoint { CGPoint(x: line.bounds.minX+line.startPoint.x,y: line.bounds.minY+line.startPoint.y) }
        expect(lines(page,group).isEmpty,"legacy contour measurements have no dimension arrows")
        let options = EngineeringLabelOptions(x: 100,y: 80,waypoints: [CGPoint(x: 40,y: 20),CGPoint(x: 80,y: 20),CGPoint(x: 80,y: 60)]),history = item.undoHistory.count
        coordinator.showMeasurementLabel(ink,item: item,view: view)
        let request = manager.engineeringLabelRequest!
        expect(request.contour && request.apply(options) == nil && item.undoHistory.count == history+1,"contour editor installs leader in one transaction")
        let actual = AnnotationMetadata.measurement(ink)!,parts = lines(page,group)
        expect(parts.count == 4 && close(start(parts[0]),actual.contourLeaderMidpoint!) && parts.allSatisfy { $0.startLineStyle == .none && $0.endLineStyle == .none },"contour leader follows arc midpoint with no distance arrows")
        expect(close(label.bounds.origin,CGPoint(x: originalBox.minX+100,y: originalBox.minY+80)) && actual.points == original.points && actual.value == original.value && actual.scale.millimetersPerPoint == original.scale.millimetersPerPoint,"label offsets preserve contour metric and calibration")
        expect(request.apply(options) != nil,"used contour editor is stale")
        let noOp = item.undoHistory.count
        expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view) && item.undoHistory.count == noOp,"same contour label is no-op")
        expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(x: 10000,y: 0),item: item,view: view) && item.undoHistory.count == noOp,"out-of-page contour label rejected before history")
        AnnotationMetadata.setLocked(true,on: parts.last!)
        expect(!coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(),item: item,view: view),"locked contour connector protects family")
        AnnotationMetadata.setLocked(false,on: parts.last!)
        var anchored = options; anchored.anchor = .measuredEnd
        expect(coordinator.setMeasurementLabel(ink,options: anchored,item: item,view: view) && close(start(lines(page,group)[0]),points.last!),"contour leader can attach to last measured vertex")
        expect(coordinator.setMeasurementLabel(ink,options: EngineeringLabelOptions(),item: item,view: view) && label.bounds == originalBox && lines(page,group).isEmpty,"reset restores automatic contour label without connector")
        expect(coordinator.setMeasurementLabel(ink,options: options,item: item,view: view),"contour route can be reapplied")
        try manager.saveForClosing(item,to: item.url)
        let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
        let savedPage = saved.page(at: 0)!,savedInk = savedPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,savedMeasure = AnnotationMetadata.measurement(savedInk)!,savedGroup = AnnotationMetadata.group(of: savedInk)!
        // PDFKit serializes native Line coordinates with limited decimal precision.
        expect(savedMeasure.kind == kind && savedMeasure.labelOffset == CGPoint(x: 100,y: 80) && lines(savedPage,savedGroup).count == 4 && hypot(start(lines(savedPage,savedGroup)[0]).x-savedMeasure.contourLeaderMidpoint!.x,start(lines(savedPage,savedGroup)[0]).y-savedMeasure.contourLeaderMidpoint!.y) < 0.0001,"contour anchor and route survive normalized-origin PDF save/reopen")
        manager.undoDocument(redo: false)
        expect(item.document.page(at: 0)!.annotations.compactMap { AnnotationMetadata.measurement($0) }.first!.labelOffset == nil,"one Undo restores original contour label")
        manager.undoDocument(redo: true); view.installDocument(item.document)
        let current = item.document.page(at: 0)!.annotations.first { AnnotationMetadata.measurement($0) != nil }!
        expect(AnnotationMetadata.measurement(current)!.labelOffset == CGPoint(x: 100,y: 80),"Redo restores contour leader")
        let outputDocument = PDFDocument(),outputPage = PDFPage(); outputPage.setBounds(CGRect(x: 0,y: 0,width: 1000,height: 1000),for: .mediaBox); outputDocument.insert(outputPage,at: 0)
        let output = PDFDocumentItem(url: root.appendingPathComponent(kind.rawValue+"-copy.pdf"),document: outputDocument,preserveStreams: true); manager.insertDocument(output); manager.select(item.id)
        expect(coordinator.transferMeasurements([current],options: EngineeringTransferOptions(pageIndex: 0,centered: true),item: item,view: view,destination: output),"contour leader copies between PDFs")
        let copied = outputPage.annotations.first { AnnotationMetadata.measurement($0) != nil }!,copiedGroup = AnnotationMetadata.group(of: copied)!
        expect(lines(outputPage,copiedGroup).count == 4,"copied contour family includes all leader legs")
        view.installDocument(output.document); view.selectAnnotation(copied)
        var affine = EngineeringAffineOptions(); affine.degrees = 90; affine.preservingValue = false
        expect(coordinator.transformMeasurements([copied],options: affine,item: output,view: view),"contour family supports full affine operation")
        let transformed = AnnotationMetadata.measurement(copied)!
        expect(close(transformed.labelOffset!,CGPoint(x: -80,y: 100)) && close(start(lines(outputPage,copiedGroup)[0]),transformed.contourLeaderMidpoint!) && abs(transformed.value-original.value) < 0.00001,"transformed connector uses recomputed contour midpoint and preserves metric under rotation")
    }
    print("PASS: perimeter/area label leaders, open/closed arc midpoint, native geometry/no arrows, calibration/bounds/locks/stale/reset guards, affine/copy and save/Undo/Redo")
}


private func bookmarkChainFixture(mode: String = "normal") -> Data {
    let stream = "0 0 20 20 re f\n"
    let next = mode == "direct" ? "<< /S /URI /URI (https://example.test/direct) /Next 14 0 R >>" : mode == "scalar" ? "42" : "[10 0 R 11 0 R 13 0 R 14 0 R]"
    let reset = mode == "cycle" ? "/Next 9 0 R" : ""
    let objects = [
        "<< /Type /Catalog /Pages 2 0 R /Outlines 7 0 R /Names << /Dests 15 0 R >> >>",
        "<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 5 0 R >>","<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 6 0 R >>",
        "<< /Length \(stream.utf8.count) >>\nstream\n"+stream+"endstream","<< /Length \(stream.utf8.count) >>\nstream\n"+stream+"endstream",
        "<< /Type /Outlines /First 8 0 R /Last 8 0 R /Count 1 >>","<< /Title (Chain) /Parent 7 0 R /A 9 0 R >>",
        "<< /Type /Action /S /GoTo /D [4 0 R /FitH null] /Next \(next) >>",
        "<< /S /Named /N /NextPage /Next 12 0 R >>",
        mode == "unsupported" ? "<< /S /JavaScript /JS (unsupported) >>" : "<< /S /URI /URI (https://example.test/a) >>",
        "<< /S /ResetForm /Fields [(A)] /Flags 1 \(reset) >>",
        "<< /S /GoToR /F (other.pdf) /D [2 /Fit] /NewWindow true >>","<< /S /GoTo /D (Local) >>","<< /Names [(Local) [3 0 R /FitV null]] >>"
    ]
    var data = Data("%PDF-1.7\n".utf8),offsets = [0]
    for (index,body) in objects.enumerated() { offsets.append(data.count); data.append(Data("\(index+1) 0 obj\n\(body)\nendobj\n".utf8)) }
    let xref = data.count; var end = "xref\n0 \(objects.count+1)\n0000000000 65535 f \n"
    for offset in offsets.dropFirst() { end += String(format: "%010lld 00000 n \n",Int64(offset)) }
    end += "trailer\n<< /Size \(objects.count+1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"; data.append(Data(end.utf8)); return data
}

@MainActor private func checkBookmarkActionChains(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func encoded(_ value: [PDFBookmarkExchange]) throws -> Data { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value) }
    let data = bookmarkChainFixture(),records = try PDFDocumentExtras.bookmarkExchange(data),record = records[0],next = record.nextActions!
    expect(record.page == 2 && record.view == "/FitH null" && next.count == 4,"exports primary GoTo and ordered Next array")
    expect(next[0].action?.kind == "named" && next[0].nextActions?.first?.action?.kind == "resetForm" && next[1].url == "https://example.test/a" && next[2].action?.newWindow == true && next[3].destinationName == "Local","nested Named/ResetForm, URI, remote and named local targets retained")
    let decoded = try JSONDecoder().decode([PDFBookmarkExchange].self,from: encoded(records))
    expect(decoded[0].valid(pageCount: 2) && decoded[0].outline(document: PDFDocument(data: data)!) == nil,"JSON valid and PDFKit fallback refuses to drop chained actions")
    let appended = try PDFDocumentExtras.appendBookmarkExchange(data,records: decoded),again = try PDFDocumentExtras.bookmarkExchange(appended)
    expect(try encoded([again.last!]) == encoded(records),"PDF JSON PDF preserves full action tree semantics and order")
    let targetDocument = PDFDocument(); targetDocument.insert(PDFPage(),at: 0); targetDocument.insert(PDFPage(),at: 1)
    let empty = try PDFDocumentSerializer.data(targetDocument,preserveStreams: false),fresh = try PDFDocumentExtras.appendBookmarkExchange(empty,records: decoded),freshRows = try PDFDocumentExtras.bookmarkExchange(fresh)
    expect(try encoded(freshRows) == encoded(records),"named destinations referenced only by Next are created on import")
    let direct = try PDFDocumentExtras.bookmarkExchange(bookmarkChainFixture(mode: "direct"))
    expect(direct[0].nextActions?.count == 1 && direct[0].nextActions?[0].nextActions?[0].destinationName == "Local","direct dictionary Next and nested indirect action read")
    for mode in ["cycle","scalar","unsupported"] {
        do { _ = try PDFDocumentExtras.bookmarkExchange(bookmarkChainFixture(mode: mode)); fatalError("invalid action chain exported: "+mode) } catch { }
    }
    var deep = PDFBookmarkExchange(title: "",url: "https://example.test",children: [])
    for _ in 0..<16 { var parent = PDFBookmarkExchange(title: "",url: "https://example.test",children: []); parent.nextActions = [deep]; deep = parent }
    expect(!deep.valid(pageCount: 2),"action depth limit enforced before import")
    var invalid = record; invalid.nextActions = [PDFBookmarkExchange(title: "Not an action",page: 1,children: [])]
    expect(!invalid.valid(pageCount: 2),"outline metadata cannot be smuggled into action-only entries")
    invalid = record; invalid.nextActions = Array(repeating: next[1],count: 257)
    expect(!invalid.valid(pageCount: 2),"per-array action limit enforced")
    let suite = "BotPlusActionChains-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),item = PDFDocumentItem(url: root.appendingPathComponent("bookmark-chains.pdf"),document: PDFDocument(data: data)!,preserveStreams: true); manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(item.document)
    let history = item.undoHistory.count
    do { try coordinator.applyBookmarkExchange([invalid],item: item,view: view); fatalError("invalid chain installed") } catch { }
    expect(item.undoHistory.count == history,"invalid chain rejected before Undo")
    try coordinator.applyBookmarkExchange(decoded,item: item,view: view)
    expect(item.undoHistory.count == history+1,"chained bookmark import is one source transaction")
    try manager.saveForClosing(item,to: item.url)
    expect(try PDFDocumentExtras.bookmarkExchange(Data(contentsOf: item.url)).count == 2,"action chains survive app save/reopen")
    manager.undoDocument(redo: false)
    expect(try PDFDocumentExtras.bookmarkExchange(manager.serializedData(item)).count == 1,"Undo removes imported tree")
    manager.undoDocument(redo: true)
    let restored = try PDFDocumentExtras.bookmarkExchange(manager.serializedData(item))
    expect(try encoded([restored.last!]) == encoded(records),"Redo restores full Next action tree")
    print("PASS: bookmark JSON Next action trees/order, local/named/remote/URI/ResetForm targets, direct/indirect values, cycle/depth/array/unsupported guards and save/Undo/Redo")
}


@MainActor private func checkCommentModificationDates(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    let raw = "D:20261029123045+03'00'",date = PDFXFDF.modificationDate(raw)!,utc = "D:20261029093045Z"
    expect(PDFXFDF.modificationDateText(date) == utc && PDFXFDF.modificationDate("D:20261029063045-03'00'") == date,"positive/negative timezone offsets resolve to identical timestamp")
    expect(PDFXFDF.modificationDate("D:20240229Z") != nil && PDFXFDF.modificationDate("D:2026Z") != nil && PDFXFDF.modificationDate("20261029093045Z") == date,"partial dates, optional prefix and leap dates supported")
    for invalid in ["D:20260229Z","D:20261301Z","D:20261029243045Z","D:20261029126145Z","D:20261029123045+03'99'","D:20261029123045Zjunk","D:00000101Z"] { expect(PDFXFDF.modificationDate(invalid) == nil,"malformed or normalized calendar date rejected") }
    let entries = [PDFXFDF.Comment(kind: "text",attributes: ["page":"0","rect":"20,20,60,60","date":raw,"color":"#123456"],contents: "Dated note",gestures: [],quads: []),PDFXFDF.Comment(kind: "freetext",attributes: ["page":"0","rect":"80,80,220,140","date":utc],contents: "Текст с датой",gestures: [],quads: [])]
    let fdf = try PDFFDF.writeComments(entries),read = try PDFFDF.readComments(fdf)
    expect(read.unsupported == 0 && read.entries.map { $0.attributes["date"] } == entries.map { $0.attributes["date"] },"FDF M field retained through data round trip")
    var invalid = entries[0]; invalid.attributes["date"] = "D:20260230Z"
    expect(PDFXFDF.annotation(invalid) == nil,"invalid date rejects annotation before creation")
    do { _ = try PDFFDF.writeComments([invalid]); fatalError("invalid FDF date written") } catch { }
    let suite = "BotPlusCommentDates-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(),page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 300,height: 300),for: .mediaBox); document.insert(page,at: 0)
    let item = PDFDocumentItem(url: root.appendingPathComponent("comment-dates.pdf"),document: document,preserveStreams: true); manager.insertDocument(item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    let history = item.undoHistory.count
    expect(!coordinator.applyExchangedComments([entries[0],invalid],item: item,view: view) && page.annotations.isEmpty && item.undoHistory.count == history,"invalid date cancels complete import before mutation/history")
    expect(coordinator.applyExchangedComments(read.entries,item: item,view: view) && item.undoHistory.count == history+1,"dated annotations imported in one transaction")
    let visible = page.annotations.filter { !AnnotationMetadata.isContainer($0) && $0.type != "Popup" }
    expect(visible.count == 2 && visible.allSatisfy { $0.modificationDate == date },"native note and FreeText receive original modification timestamp")
    let xml = PDFXFDF.comments(document,include: { !AnnotationMetadata.isContainer($0) && $0.type != "Popup" }),xmlEntries = try PDFXFDF.read(xml).comments
    expect(xmlEntries.count == 2 && xmlEntries.allSatisfy { $0.attributes["date"] == utc },"XFDF exports canonical UTC dates for all supported comments")
    let native = xmlEntries.compactMap { PDFXFDF.annotation($0)?.1 }
    expect(native.count == 2 && native.allSatisfy { $0.modificationDate == date },"XFDF import restores same timestamp")
    let fdfAgain = try PDFFDF.readComments(PDFFDF.writeComments(xmlEntries))
    expect(fdfAgain.entries.allSatisfy { PDFXFDF.modificationDate($0.attributes["date"]!) == date },"XFDF to FDF retains timestamp across timezone normalization")
    try manager.saveForClosing(item,to: item.url)
    let saved = PDFDocument(url: item.url)!; AnnotationMetadata.restore(saved)
    expect(saved.page(at: 0)!.annotations.filter { !AnnotationMetadata.isContainer($0) && $0.type != "Popup" }.allSatisfy { $0.modificationDate == date },"timestamps survive PDF save/reopen")
    manager.undoDocument(redo: false)
    expect(item.document.page(at: 0)!.annotations.filter { !AnnotationMetadata.isContainer($0) && $0.type != "Popup" }.isEmpty,"Undo removes dated import")
    manager.undoDocument(redo: true)
    let restored = item.document.page(at: 0)!.annotations.filter { !AnnotationMetadata.isContainer($0) && $0.type != "Popup" }
    expect(restored.count == 2 && restored.allSatisfy { $0.modificationDate == date },"Redo restores timestamps")
    print("PASS: FDF/XFDF annotation modification dates, timezones/calendar validation, native note/FreeText, atomic import, canonical exchange and save/Undo/Redo")
}


@MainActor private func checkIndependentFormTransforms(root: URL) throws {
    func expect(_ value: Bool,_ message: String) { if !value { fatalError("CHECK FAILED: "+message) } }
    func target(_ bytes: Data,_ path: [String],_ page: Int = 0) throws -> PDFXObjectConditionTarget { try PDFDocumentExtras.xObjectConditionTargets(bytes,pageIndex: page).first { $0.path == path }! }
    func pixels(_ bytes: Data,_ index: Int = 0) -> Data {
        _ = PDFiumRuntime.ready; let storage = bytes as NSData,document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil)!
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        let page = FPDF_LoadPage(document,Int32(index))!,bitmap = FPDFBitmap_Create(100,100,0)!
        defer { FPDF_ClosePage(page); FPDFBitmap_Destroy(bitmap) }
        FPDFBitmap_FillRect(bitmap,0,0,100,100,0xffffffff); FPDF_RenderPageBitmap(bitmap,page,0,0,100,100,0,0)
        return Data(bytes: FPDFBitmap_GetBuffer(bitmap)!,count: 100*Int(FPDFBitmap_GetStride(bitmap)))
    }
    func inspect(_ bytes: Data,_ path: [String]) -> ([Double],Data,Bool) {
        let document = CGPDFDocument(CGDataProvider(data: bytes as CFData)!)!,page = document.page(at: 1)!
        var resources: CGPDFDictionaryRef?,objects: CGPDFDictionaryRef?,stream: CGPDFStreamRef?
        if !CGPDFDictionaryGetDictionary(page.dictionary!,"Resources",&resources) { var parent: CGPDFDictionaryRef?; CGPDFDictionaryGetDictionary(page.dictionary!,"Parent",&parent); CGPDFDictionaryGetDictionary(parent!,"Resources",&resources) }
        for (index,key) in path.enumerated() { CGPDFDictionaryGetDictionary(resources!,"XObject",&objects); CGPDFDictionaryGetStream(objects!,key,&stream); if index+1 < path.count { CGPDFDictionaryGetDictionary(CGPDFStreamGetDictionary(stream!)!,"Resources",&resources) } }
        let header = CGPDFStreamGetDictionary(stream!)!; var matrix: CGPDFArrayRef?,group: CGPDFDictionaryRef?,format = CGPDFDataFormat.raw
        let hasMatrix = CGPDFDictionaryGetArray(header,"Matrix",&matrix),hasGroup = CGPDFDictionaryGetDictionary(header,"Group",&group)
        let values: [Double] = hasMatrix ? (0..<6).map { index in var value: CGPDFReal = 0; CGPDFArrayGetNumber(matrix!,index,&value); return Double(value) } : [1,0,0,1,0,0]
        return (values,CGPDFStreamCopyData(stream!,&format)! as Data,hasGroup)
    }
    let data = nestedXObjectConditionFixture(),path = ["Outer","Mid"],selected = try target(data,path),outer = try target(data,["Outer"]),original = pixels(data)
    expect(try PDFDocumentExtras.transformFormResource(data,target: selected,options: PDFFormResourceTransformOptions()) == data,"identity Form transform is no-op")
    let moved = try PDFDocumentExtras.transformFormResource(data,target: selected,options: PDFFormResourceTransformOptions(x: 5)),current = try target(moved,path)
    expect(current.objectID != selected.objectID && pixels(moved) != original && pixels(moved,1) == original,"nested transform affects selected page and path only")
    let alias = try target(moved,["OuterAlias"]),sibling = try target(moved,["Outer","MidAlias"]),newOuter = try target(moved,["Outer"])
    expect(alias.objectID == outer.objectID && sibling.objectID == selected.objectID && newOuter.objectID != outer.objectID,"ancestor copies isolate root/sibling aliases of shared Forms")
    let before = inspect(data,path),after = inspect(moved,path)
    expect(after.0 == [1,0,0,1,5,0] && before.1 == after.1 && after.2 && inspect(data,["Outer"]).1 == inspect(moved,["Outer"]).1,"matrix changes while leaf/ancestor streams and transparency group are retained")
    let scaled = try PDFDocumentExtras.transformFormResource(moved,target: current,options: PDFFormResourceTransformOptions(scaleX: 2,centered: false))
    expect(inspect(scaled,path).0 == [2,0,0,1,10,0],"delta matrix composes before existing Form transform")
    let rotated = try PDFDocumentExtras.transformFormResource(data,target: selected,options: PDFFormResourceTransformOptions(degrees: 90))
    expect(inspect(rotated,path).0 == [0,1,-1,0,100,0],"rotation about transformed BBox center is exact for quarter turns")
    do { _ = try PDFDocumentExtras.transformFormResource(moved,target: selected,options: PDFFormResourceTransformOptions(x: 1)); fatalError("stale Form path accepted") } catch { }
    for options in [PDFFormResourceTransformOptions(scaleX: 0),PDFFormResourceTransformOptions(x: .nan),PDFFormResourceTransformOptions(degrees: 361)] {
        do { _ = try PDFDocumentExtras.transformFormResource(data,target: selected,options: options); fatalError("invalid Form matrix accepted") } catch { }
    }
    let image = try target(data,["Outer","Mid","Im"])
    do { _ = try PDFDocumentExtras.transformFormResource(data,target: image,options: PDFFormResourceTransformOptions(x: 5)); fatalError("image treated as Form") } catch { }
    let foreignData = nestedXObjectConditionFixture(foreign: true),foreign = try target(foreignData,path)
    do { _ = try PDFDocumentExtras.transformFormResource(foreignData,target: foreign,options: PDFFormResourceTransformOptions(x: 5)); fatalError("foreign OC parent changed") } catch { }
    let conditions = try PDFDocumentExtras.membershipConfiguration(data),hidden = conditions.entries.first { $0.name == "Hidden" }!,bound = try PDFDocumentExtras.bindXObjectCondition(data,target: selected,entry: hidden),owned = try target(bound,path)
    do { _ = try PDFDocumentExtras.transformFormResource(bound,target: owned,options: PDFFormResourceTransformOptions(x: 5)); fatalError("owned OC restore metadata invalidated") } catch { }
    let suite = "BotPlusFormTransform-"+UUID().uuidString,defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let manager = DocumentManager(recent: RecentPDFStore(defaults: defaults)),document = PDFDocument(data: data)!,item = PDFDocumentItem(url: root.appendingPathComponent("form-transform.pdf"),document: document,preserveStreams: true); manager.insertDocument(item); manager.seedSerializedData(data,item: item)
    let coordinator = PDFViewer.Coordinator(manager: manager),view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600)); view.installDocument(document)
    coordinator.showFormResourceTransform(item: item,view: view)
    let request = manager.formResourceTransformRequest!,history = item.undoHistory.count
    expect(request.targets.allSatisfy { $0.kind == "Form" } && request.apply(selected,PDFFormResourceTransformOptions()) == nil && item.undoHistory.count == history,"Form dialog exposes nested groups and no-op history")
    expect(request.apply(selected,PDFFormResourceTransformOptions(x: 5)) == nil && item.undoHistory.count == history+1,"isolated Form transform is one source transaction")
    expect(request.apply(selected,PDFFormResourceTransformOptions(x: 1)) != nil,"used Form dialog rejected")
    try manager.saveForClosing(item,to: item.url)
    let saved = try Data(contentsOf: item.url)
    expect(pixels(saved) == pixels(moved) && pixels(saved,1) == original,"independent transform survives app save/reopen")
    manager.undoDocument(redo: false)
    expect(pixels(try manager.serializedData(item)) == original,"Undo restores original shared Forms")
    manager.undoDocument(redo: true)
    expect(pixels(try manager.serializedData(item)) == pixels(moved),"Redo restores isolated transformed path")
    print("PASS: independent nested Form transforms, matrix composition/BBox pivots, alias/page isolation, preserved streams/transparency, stale/OC/invalid guards and save/Undo/Redo")
}


@MainActor
private func checkSearchPanel(root: URL) async throws {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError("SEARCH CHECK FAILED: \(message)") }
    }
    let document = PDFDocument()
    for _ in 0..<2 {
        let page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); document.insert(page,at: document.pageCount)
    }
    var data = document.dataRepresentation()!
    for (index,text) in ["Alpha alpha ALPHA", "Other alpha text / Поиск поиск"].enumerated() {
        data = try PDFSourceSession.adding(data: data,pageIndex: index,point: CGPoint(x: 72,y: 700),fontSize: 16,color: .black).applying(text: text,fontSize: 16,color: .black)
    }
    let url = root.appendingPathComponent("search-panel.pdf"); try data.write(to: url)
    let manager = DocumentManager(); manager.open(url)
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 600,height: 600))
    let coordinator = PDFViewer.Coordinator(manager: manager); coordinator.attach(view); coordinator.update(view)
    defer { coordinator.detach(); view.stopEventMonitoring(); manager.clearSearch() }
    func finish() async throws {
        for _ in 0..<500 where manager.searchRunning { try await Task.sleep(for: .milliseconds(10)) }
        expect(!manager.searchRunning && manager.searchCompleted,"search finishes")
    }
    manager.searchText = "alpha"; manager.runSearch(); try await finish()
    expect(manager.searchMatches.count == 4,"all repeated case-insensitive matches on both pages")
    expect(manager.searchMatches.map(\.page) == [0,0,0,1],"ordered page and text positions")
    expect(manager.panels.configuration(for: .search).isVisible,"search opens its panel")
    expect(manager.searchMatches.allSatisfy { $0.selection.string?.lowercased() == "alpha" && !$0.snippet.isEmpty },"native selections and context")
    manager.selectSearchMatch(3); coordinator.update(view)
    expect(view.currentSelection?.pages.first === manager.selected?.document.page(at: 1),"click goes to selected match on page two")
    manager.stepSearch(1); expect(manager.searchMatchID == 0,"next wraps")
    manager.stepSearch(-1); expect(manager.searchMatchID == 3,"previous wraps")
    manager.searchText = "поиск"; manager.runSearch(); try await finish()
    expect(manager.searchMatches.count == 2,"Cyrillic case-insensitive search")
    manager.searchText = "absent"; manager.runSearch(); try await finish()
    expect(manager.searchMatches.isEmpty && manager.currentSearchSelection == nil,"no results clears selection target")
    manager.searchText = "alpha"; manager.runSearch(); manager.searchText = "поиск"; manager.runSearch(); try await finish()
    expect(manager.searchMatches.count == 2 && manager.searchMatches.allSatisfy { $0.page == 1 },"superseded query cannot publish stale matches")
    manager.selected!.store.revision += 1; manager.invalidateStaleSearch()
    expect(manager.searchMatches.isEmpty && !manager.searchCompleted,"edits invalidate old page selections")
    manager.searchText = "alpha"; manager.runSearch(); manager.clearSearch(); await Task.yield()
    expect(!manager.searchRunning && manager.searchMatches.isEmpty,"canceled search stays empty")
    manager.runSearch(); try await finish(); manager.open(url.deletingLastPathComponent().appendingPathComponent("native-checks.pdf"))
    expect(manager.searchMatches.isEmpty,"tab change clears matches")
    print("PASS: search panel, all matches/snippets, native navigation, next/previous, Cyrillic, cancellation and stale query/document/revision protection")
}


private final class BackgroundPDFViewRead: @unchecked Sendable {
    let view: PDFView
    let expected: PDFDocument
    init(view: PDFView, expected: PDFDocument) { self.view = view; self.expected = expected }
}

@MainActor
private func checkPDFKitBackgroundGetter() async throws {
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError("BACKGROUND PDFKIT CHECK FAILED: \(message)") }
    }
    let selector = NSSelectorFromString("document")
    let inherited = class_getInstanceMethod(PDFView.self, selector)!
    let actual = class_getInstanceMethod(PDFViewerView.self, selector)!
    expect(unsafeBitCast(method_getImplementation(inherited),to: UInt.self) == unsafeBitCast(method_getImplementation(actual),to: UInt.self),"PDFKit getter has no Swift actor thunk")
    let view = PDFViewerView(frame: CGRect(x: 0,y: 0,width: 500,height: 500))
    defer { view.installDocument(nil); view.stopEventMonitoring() }
    let first = PDFDocument(); let page = PDFPage(); first.insert(page,at: 0)
    let note = PDFAnnotation(bounds: CGRect(x: 20,y: 20,width: 50,height: 30),forType: .text,withProperties: nil); page.addAnnotation(note)
    view.installDocument(first); view.selectAnnotation(note)
    expect(view.selectedAnnotation === note,"selection fixture")
    let second = PDFDocument(); second.insert(PDFPage(),at: 0)
    view.installDocument(second)
    expect(view.selectedAnnotation == nil && view.selectedAnnotations.isEmpty,"document replacement resets selection")
    let read = BackgroundPDFViewRead(view: view,expected: second)
    let matches = await Task.detached {
        for _ in 0..<200 {
            guard read.view.value(forKey: "document") as? PDFDocument === read.expected else { return false }
        }
        return true
    }.value
    expect(matches,"background Objective-C document getter survives formFillingQueue call pattern")
    print("PASS: PDFKit background document getter without actor trap and main-thread document replacement/selection reset")
}

private func checkAppDiagnostics(root: URL) throws {
    func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError("DIAGNOSTICS CHECK FAILED: \(message)") }
    }
    let directory = root.appendingPathComponent("diagnostics",isDirectory: true)
    let logger = try AppDiagnostics(directory: directory,maximumBytes: 1024,retainedFiles: 3)
    try Data("old run".utf8).write(to: directory.appendingPathComponent(".active-2147483647"))
    logger.startSession()
    func logs() throws -> [URL] { try FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: nil).filter { $0.pathExtension == "log" } }
    var bytes = try logs().map { try Data(contentsOf: $0) }.reduce(Data(),+)
    expect(String(decoding: bytes,as: UTF8.self).contains("previous_session_ended_without_clean_shutdown"),"unclean prior run recorded")
    logger.record("newline\nforged-event")
    bytes = try logs().map { try Data(contentsOf: $0) }.reduce(Data(),+)
    expect(String(decoding: bytes,as: UTF8.self).contains("newline forged-event"),"app events cannot inject log lines")
    logger.captureStandardError()
    FileHandle.standardError.write(Data("diagnostic-stderr-probe\n".utf8))
    var captured = false
    for _ in 0..<200 {
        bytes = try logs().map { try Data(contentsOf: $0) }.reduce(Data(),+)
        if String(decoding: bytes,as: UTF8.self).contains("diagnostic-stderr-probe") { captured = true; break }
        Thread.sleep(forTimeInterval: 0.01)
    }
    logger.stopCapturingStandardError()
    expect(captured,"runtime stderr captured without a main-thread dependency")
    DispatchQueue.concurrentPerform(iterations: 200) { index in logger.record("concurrent-event \(index) " + String(repeating: "x",count: 100)) }
    logger.append(Data(repeating: 65,count: 7000)); logger.record("final-event"); logger.finishSession()
    let files = try logs()
    expect(files.count <= 3,"bounded retained file count")
    let sizesValid = try files.allSatisfy { try Data(contentsOf: $0).count <= 1024 }
    expect(sizesValid,"file size bounded, including oversized writes")
    bytes = try files.map { try Data(contentsOf: $0) }.reduce(Data(),+)
    expect(String(decoding: bytes,as: UTF8.self).contains("final-event"),"latest event retained after rotation")
    expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".active-\(getpid())").path),"clean exit removes run marker")
    let mode = try FileManager.default.attributesOfItem(atPath: files[0].path)[.posixPermissions] as! NSNumber
    expect(mode.intValue & 0o077 == 0,"logs readable only by their user")
    print("PASS: local diagnostics, concurrent writes, size/count rotation, oversized writes, private permissions and session markers")
}
