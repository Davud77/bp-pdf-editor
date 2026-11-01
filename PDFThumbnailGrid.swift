// SPDX-License-Identifier: AGPL-3.0-only
import AppKit
import SwiftUI

@MainActor protocol PDFThumbnailCommandTarget: AnyObject {
    var thumbnailDocumentID: UUID? { get }
    func canPerformThumbnailCommand(_ action: String) -> Bool
    func performThumbnailCommand(_ action: String)
}

/// Native selection, rubber-band tracking, scrolling and drag destinations share
/// a single responder. No gesture recognizer competes with the scroll view.
@MainActor struct PDFThumbnailGrid: NSViewRepresentable {
    static let dragType = NSPasteboard.PasteboardType("com.botplus.pdf.page-drag")
    let documentID: UUID
    let revision: Int
    let pageCount: Int
    let currentPage: Int
    let selected: Set<Int>
    let zoom: Double
    let interactive: Bool
    let logicalLabels: Bool
    let russian: Bool
    let aspect: (Int) -> CGFloat
    let label: (Int) -> String
    let image: (Int, CGFloat) -> NSImage
    let canCommand: (String) -> Bool
    let command: (String, Int) -> Void
    let selectionChanged: (Set<Int>, Int?) -> Void
    let focus: (NSWindow?) -> Void
    let acceptDrop: (String, Int) -> Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let grid = GridView()
        grid.frame = scroll.contentView.bounds
        grid.autoresizingMask = [.width]
        grid.backgroundColors = [.clear]
        grid.isSelectable = true
        grid.allowsMultipleSelection = true
        grid.allowsEmptySelection = true
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 40, right: 8)
        grid.collectionViewLayout = layout
        grid.register(ThumbnailItem.self, forItemWithIdentifier: Coordinator.itemID)
        grid.dataSource = context.coordinator
        grid.delegate = context.coordinator
        grid.owner = context.coordinator
        grid.registerForDraggedTypes([Self.dragType])
        grid.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        grid.setDraggingSourceOperationMask([], forLocal: false)
        scroll.documentView = grid
        context.coordinator.grid = grid
        context.coordinator.update(self)
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) { context.coordinator.update(self) }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.grid?.owner = nil
        coordinator.grid?.dataSource = nil
        coordinator.grid?.delegate = nil
        coordinator.grid = nil
    }

    @MainActor final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        static let itemID = NSUserInterfaceItemIdentifier("BotPlusThumbnail")
        var configuration: PDFThumbnailGrid
        weak var grid: GridView?
        private var updating = false
        private var selectionScheduled = false
        private var hasLoaded = false
        private var ratios: [Int: CGFloat] = [:]
        init(_ configuration: PDFThumbnailGrid) { self.configuration = configuration }

        func update(_ value: PDFThumbnailGrid) {
            let previous = configuration
            configuration = value
            guard let grid else { return }
            updating = true
            defer { updating = false }
            let changedDocument = previous.documentID != value.documentID
            let changedContent = changedDocument || previous.revision != value.revision || previous.pageCount != value.pageCount
            if changedContent { ratios.removeAll(); grid.rangeAnchor = nil; grid.rangeBase = nil }
            grid.columns = columnCount
            if changedContent || !hasLoaded { grid.reloadData(); hasLoaded = true }
            if changedDocument { grid.focusIndex = value.currentPage }
            if let focus = grid.focusIndex, !(0..<value.pageCount).contains(focus) { grid.focusIndex = value.currentPage }
            let selection = Set(value.selected.filter { (0..<value.pageCount).contains($0) }.map { IndexPath(item: $0, section: 0) })
            if (!selectionScheduled || value.selected != previous.selected || changedContent), grid.selectionIndexPaths != selection {
                grid.selectionIndexPaths = selection
            }
            if changedContent || previous.zoom != value.zoom { grid.collectionViewLayout?.invalidateLayout() }
            // Reconfigure visible items only. AppKit owns reuse and offscreen items.
            if changedContent || previous.zoom != value.zoom || previous.interactive != value.interactive ||
                previous.currentPage != value.currentPage || previous.logicalLabels != value.logicalLabels || previous.russian != value.russian {
                refreshVisible()
            }
            if changedDocument || previous.currentPage != value.currentPage {
                let identity = value.documentID, index = value.currentPage
                DispatchQueue.main.async { [weak self, weak grid] in
                    guard let self, let grid, self.configuration.documentID == identity,
                          (0..<self.configuration.pageCount).contains(index) else { return }
                    grid.scrollToItems(at: [IndexPath(item: index, section: 0)], scrollPosition: .nearestHorizontalEdge)
                }
            }
        }
        var itemWidth: CGFloat {
            let available = max(44, (grid?.enclosingScrollView?.contentSize.width ?? 220) - 16)
            return max(44, floor((available - CGFloat(columnCount - 1) * 8) / CGFloat(columnCount)))
        }
        var columnCount: Int {
            let available = max(44, (grid?.enclosingScrollView?.contentSize.width ?? 220) - 16)
            let target = 44 + (available - 44) * CGFloat(min(1, max(0, configuration.zoom)))
            return max(1, Int((available + 8) / (target + 8)))
        }
        func refreshVisible() {
            guard let grid else { return }
            for path in grid.indexPathsForVisibleItems() {
                if let item = grid.item(at: path) as? ThumbnailItem { configure(item, index: path.item) }
            }
        }
        private func configure(_ item: ThumbnailItem, index: Int) {
            guard (0..<configuration.pageCount).contains(index) else { return }
            item.preview.image = configuration.image(index, itemWidth)
            item.caption.stringValue = configuration.label(index)
            item.view.toolTip = configuration.russian
                ? "Страница \(index + 1) · \(configuration.label(index))"
                : "Page \(index + 1) · \(configuration.label(index))"
            item.preview.setAccessibilityLabel(item.view.toolTip)
            item.isCurrent = index == configuration.currentPage
            item.updateAppearance()
        }
        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { configuration.pageCount }
        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: Self.itemID, for: indexPath)
            if let thumbnail = item as? ThumbnailItem { configure(thumbnail, index: indexPath.item) }
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
            let index = indexPath.item
            let ratio: CGFloat
            if let cached = ratios[index] { ratio = cached }
            else {
                let value = configuration.aspect(index)
                ratio = value.isFinite ? min(12, max(0.1, value)) : 1.414
                ratios[index] = ratio
            }
            return NSSize(width: itemWidth, height: itemWidth * ratio + 22)
        }
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { scheduleSelection() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { scheduleSelection() }
        func scheduleSelection() {
            guard !updating, !selectionScheduled else { return }
            selectionScheduled = true
            let identity = configuration.documentID
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.selectionScheduled = false
                guard self.configuration.documentID == identity, let grid = self.grid else { return }
                let indices = Set(grid.selectionIndexPaths.map(\.item))
                let focus = grid.focusIndex.flatMap { indices.contains($0) ? $0 : nil }
                self.configuration.selectionChanged(indices, focus)
            }
        }
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> (any NSPasteboardWriting)? {
            let selected = collectionView.selectionIndexPaths.map(\.item).sorted()
            let indices = selected.contains(indexPath.item) ? selected : [indexPath.item]
            guard !indices.isEmpty, configuration.canCommand("copy") else { return nil }
            let data = "\(configuration.documentID.uuidString)|\(indices.map(String.init).joined(separator: ","))|\(configuration.revision)"
            let item = NSPasteboardItem()
            item.setString(data, forType: PDFThumbnailGrid.dragType)
            return item
        }
        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: any NSDraggingInfo,
                            proposedIndexPath proposedDropIndexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
                            dropOperation proposedDropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            guard draggingInfo.draggingPasteboard.string(forType: PDFThumbnailGrid.dragType) != nil,
                  configuration.canCommand("insert") else { return [] }
            proposedDropOperation.pointee = .before
            let proposed = proposedDropIndexPath.pointee as IndexPath
            proposedDropIndexPath.pointee = IndexPath(item: min(configuration.pageCount, max(0, proposed.item)), section: 0) as NSIndexPath
            return (draggingInfo.draggingSource as? NSCollectionView) === collectionView ? .move : .copy
        }
        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: any NSDraggingInfo,
                            indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
            guard let payload = draggingInfo.draggingPasteboard.string(forType: PDFThumbnailGrid.dragType), payload.utf8.count < 100_000 else { return false }
            return configuration.acceptDrop(payload, min(configuration.pageCount, max(0, indexPath.item)))
        }
        func invoke(_ action: String, at index: Int) {
            guard let grid, configuration.canCommand(action), (0..<configuration.pageCount).contains(index) else { return }
            // Selection is flushed before the command, including a right-click
            // that did not change first responder through the usual delegate.
            let indices = Set(grid.selectionIndexPaths.map(\.item))
            configuration.selectionChanged(indices, nil)
            configuration.command(action, index)
        }
    }

    @MainActor final class GridView: NSCollectionView, PDFThumbnailCommandTarget, NSMenuItemValidation {
        weak var owner: Coordinator?
        var focusIndex: Int?
        var columns = 1
        var rangeAnchor: Int?
        var rangeBase: Set<IndexPath>?
        private var previousWidth: CGFloat = 0
        private var refreshScheduled = false
        var thumbnailDocumentID: UUID? { owner?.configuration.documentID }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { owner?.configuration.focus(window) }
            return accepted
        }
        override func selectAll(_ sender: Any?) {
            rangeAnchor = nil; rangeBase = nil
            super.selectAll(sender); owner?.scheduleSelection()
        }
        override func deselectAll(_ sender: Any?) {
            rangeAnchor = nil; rangeBase = nil
            super.deselectAll(sender); owner?.scheduleSelection()
        }
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            guard abs(previousWidth - newSize.width) > 0.5 else { return }
            previousWidth = newSize.width
            columns = owner?.columnCount ?? 1
            collectionViewLayout?.invalidateLayout()
            // Rendering never runs inside a layout callback.
            guard !refreshScheduled else { return }
            refreshScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshScheduled = false
                self.owner?.refreshVisible()
            }
        }
        override func mouseDown(with event: NSEvent) {
            let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item
            if event.modifierFlags.contains(.shift) {
                if rangeAnchor == nil { rangeAnchor = focusIndex ?? selectionIndexPaths.map(\.item).min() }
            } else { rangeAnchor = index; rangeBase = nil }
            focusIndex = index
            window?.makeFirstResponder(self)
            super.mouseDown(with: event)
            owner?.scheduleSelection()
        }
        override func keyDown(with event: NSEvent) {
            guard let owner, owner.configuration.pageCount > 0 else { super.keyDown(with: event); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased() {
                let action = ["c": "copy", "x": "cut", "v": "paste", "a": "selectAll"][key]
                if let action { performThumbnailCommand(action); return }
            }
            if event.keyCode == 51 || event.keyCode == 117 { performThumbnailCommand("delete"); return }
            if event.keyCode == 53 { deselectAll(nil); rangeAnchor = nil; rangeBase = nil; owner.scheduleSelection(); return }
            let count = owner.configuration.pageCount
            let current = focusIndex ?? selectionIndexPaths.map(\.item).min() ?? owner.configuration.currentPage
            let visibleCount = max(columns, indexPathsForVisibleItems().count - columns)
            let next: Int
            switch event.keyCode {
            case 123: next = flags.contains(.command) ? 0 : current - 1
            case 124: next = flags.contains(.command) ? count - 1 : current + 1
            case 125: next = flags.contains(.command) ? count - 1 : current + columns
            case 126: next = flags.contains(.command) ? 0 : current - columns
            case 115: next = 0
            case 119: next = count - 1
            case 116: next = current - visibleCount
            case 121: next = current + visibleCount
            case 36, 76, 49: owner.configuration.selectionChanged(Set(selectionIndexPaths.map(\.item)), current); return
            default: super.keyDown(with: event); return
            }
            let destination = min(count - 1, max(0, next))
            if flags.contains(.shift) {
                if rangeAnchor == nil { rangeAnchor = current }
                if rangeBase == nil { rangeBase = flags.contains(.command) ? selectionIndexPaths : [] }
                let anchor = rangeAnchor ?? current
                let range = Set((min(anchor, destination)...max(anchor, destination)).map { IndexPath(item: $0, section: 0) })
                selectionIndexPaths = (rangeBase ?? []).union(range)
            } else {
                rangeAnchor = nil; rangeBase = nil
                selectionIndexPaths = [IndexPath(item: destination, section: 0)]
            }
            focusIndex = destination
            scrollToItems(at: [IndexPath(item: destination, section: 0)], scrollPosition: .nearestHorizontalEdge)
            owner.scheduleSelection()
        }
        func canPerformThumbnailCommand(_ action: String) -> Bool {
            guard let owner else { return false }
            if action == "selectAll" { return owner.configuration.pageCount > 0 }
            if action == "selectNone" { return !selectionIndexPaths.isEmpty }
            if ["delete", "cut"].contains(action), selectionIndexPaths.count >= owner.configuration.pageCount { return false }
            return (!selectionIndexPaths.isEmpty || action == "paste" || action == "insert") && owner.configuration.canCommand(action)
        }
        func performThumbnailCommand(_ action: String) {
            guard canPerformThumbnailCommand(action), let owner else { return }
            if action == "selectAll" { selectAll(nil); owner.scheduleSelection(); return }
            if action == "selectNone" { deselectAll(nil); owner.scheduleSelection(); return }
            let indices = Set(selectionIndexPaths.map(\.item))
            let focus = focusIndex.flatMap { indices.contains($0) ? $0 : nil }
            owner.invoke(action, at: focus ?? indices.min() ?? owner.configuration.currentPage)
        }
        override func menu(for event: NSEvent) -> NSMenu? {
            guard let owner else { return nil }
            window?.makeFirstResponder(self)
            if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item {
                focusIndex = index
                if !selectionIndexPaths.contains(IndexPath(item: index, section: 0)) { selectionIndexPaths = [IndexPath(item: index, section: 0)] }
                owner.scheduleSelection()
            }
            let menu = NSMenu()
            let entries = [
                ("selectAll", "Выделить все", "Select all"), ("selectNone", "Снять выделение", "Clear selection"),
                ("", "", ""), ("cut", "Вырезать", "Cut"), ("copy", "Копировать", "Copy"), ("paste", "Вставить после", "Paste after"),
                ("delete", "Удалить выбранные", "Delete selected"), ("duplicate", "Дублировать выбранные", "Duplicate selected"), ("", "", ""),
                ("rotateLeft", "Повернуть влево", "Rotate left"), ("rotateRight", "Повернуть вправо", "Rotate right"),
                ("crop", "Обрезать…", "Crop…"), ("extract", "Извлечь…", "Extract…"), ("new", "Новый PDF из выбранных", "New PDF from selection"),
                ("exportImages", "Экспорт изображений…", "Export images…"), ("print", "Печать выбранных…", "Print selected…"), ("", "", ""),
                ("insert", "Вставить из файла…", "Insert from file…"), ("replace", "Заменить страницы…", "Replace pages…"),
                ("blankBefore", "Пустая перед", "Blank before"), ("blankAfter", "Пустая после", "Blank after")]
            for entry in entries {
                if entry.0.isEmpty { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: owner.configuration.russian ? entry.1 : entry.2, action: #selector(menuCommand(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = entry.0; menu.addItem(item)
            }
            return menu
        }
        @objc private func menuCommand(_ sender: NSMenuItem) {
            if let action = sender.representedObject as? String { performThumbnailCommand(action) }
        }
        func validateMenuItem(_ item: NSMenuItem) -> Bool {
            guard let action = item.representedObject as? String else { return true }
            return canPerformThumbnailCommand(action)
        }
    }

    @MainActor final class ThumbnailItem: NSCollectionViewItem {
        let preview = NSImageView()
        let caption = NSTextField(labelWithString: "")
        var isCurrent = false
        override var isSelected: Bool { didSet { updateAppearance() } }
        override func loadView() {
            view = NSView()
            view.wantsLayer = true
            preview.translatesAutoresizingMaskIntoConstraints = false
            caption.translatesAutoresizingMaskIntoConstraints = false
            preview.imageScaling = .scaleProportionallyUpOrDown
            preview.wantsLayer = true
            caption.font = .systemFont(ofSize: 10)
            caption.alignment = .center
            caption.lineBreakMode = .byTruncatingMiddle
            view.addSubview(preview); view.addSubview(caption)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                preview.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                preview.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
                preview.bottomAnchor.constraint(equalTo: caption.topAnchor, constant: -4),
                caption.leadingAnchor.constraint(equalTo: view.leadingAnchor), caption.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                caption.heightAnchor.constraint(equalToConstant: 14), caption.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2)])
            updateAppearance()
        }
        func updateAppearance() {
            guard isViewLoaded else { return }
            preview.layer?.borderWidth = isSelected ? 2 : 1
            preview.layer?.borderColor = (isSelected ? NSColor.controlAccentColor : (isCurrent ? .secondaryLabelColor : .separatorColor)).cgColor
            caption.textColor = isSelected ? .controlAccentColor : .secondaryLabelColor
            view.layer?.backgroundColor = isSelected ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor : NSColor.clear.cgColor
        }
    }
}
