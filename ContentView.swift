// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus

import SwiftUI
import AppKit
import PDFKit
import AVFoundation
import CoreText
import UniformTypeIdentifiers
import Combine

private enum BotPlusBrand {
    static let name = "BotPlus PDF Editor"
    static let version = "1.9.1"
    static let copyright = "© 2026 BotPlus"
    static let supportURL = URL(string: "https://github.com/Davud77/BotPlus-PDF-Editor")!
    static let telegramURL = URL(string: "https://t.me/botplus_pdf")!
}

// Native macOS PDF workspace. Source-content editing is implemented in PDFiumSourceEditor.swift.
// When App Sandbox is enabled, grant User Selected File Read/Write in Signing & Capabilities.

private struct Bilingual {
    let en: String
    let ru: String
    func value(_ language: AppLanguage) -> String { language == .ru ? ru : en }
}

private enum AppLanguage: String, CaseIterable, Identifiable {
    case ru, en
    var id: String { rawValue }
    var displayName: String { self == .ru ? "Русский" : "English" }
}

private enum AppTheme: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .dark: Bilingual(en: "Dark", ru: "Тёмная")
        case .light: Bilingual(en: "Light", ru: "Светлая")
        case .system: Bilingual(en: "System", ru: "Системная")
        }
    }
    var colorScheme: ColorScheme? { self == .system ? nil : (self == .dark ? .dark : .light) }
    var appearance: NSAppearance? { self == .system ? nil : NSAppearance(named: self == .dark ? .darkAqua : .aqua) }
    @MainActor var isDark: Bool {
        self == .dark || (self == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
    }
}
private enum Palette {
    private static func grey(_ dark: CGFloat, _ light: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(calibratedWhite: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light, alpha: 1)
        })
    }
    static let ribbon = grey(0.17, 0.95)
    static let chrome = grey(0.125, 0.91)
    static let raised = grey(0.205, 0.98)
    static let panel = grey(0.20, 0.97)
    static let workspace = grey(0.12, 0.82)
    static let ruler = grey(0.125, 0.94)
    static let rulerTicks = grey(0.533, 0.45)
    static let rulerText = grey(0.8, 0.25)
    static let separator = grey(0.25, 0.76)
    static let selected = grey(0.29, 0.83)
    static let file = Color(red: 0.65, green: 0.18, blue: 0.20)
    static let text = grey(0.88, 0.12)
    static let muted = grey(0.68, 0.40)
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.30, green: 0.62, blue: 0.90, alpha: 1)
            : NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.72, alpha: 1)
    })
}

private enum RibbonTab: CaseIterable, Identifiable {
    case file, home, view, comment, protect, form, organize, convert, mailings, review, accessibility, bookmarks, help
    var id: Self { self }
    var title: Bilingual {
        switch self {
        case .file: Bilingual(en: "File", ru: "Файл")
        case .home: Bilingual(en: "Home", ru: "Главная")
        case .view: Bilingual(en: "View", ru: "Вид")
        case .comment: Bilingual(en: "Comment", ru: "Комментарий")
        case .protect: Bilingual(en: "Protect", ru: "Защита")
        case .form: Bilingual(en: "Form", ru: "Форма")
        case .organize: Bilingual(en: "Organize", ru: "Организация")
        case .convert: Bilingual(en: "Convert", ru: "Преобразование")
        case .mailings: Bilingual(en: "Mailings", ru: "Рассылки")
        case .review: Bilingual(en: "Review", ru: "Рецензирование")
        case .accessibility: Bilingual(en: "Accessibility", ru: "Спец. возможности")
        case .bookmarks: Bilingual(en: "Bookmarks", ru: "Закладки")
        case .help: Bilingual(en: "Help", ru: "Помощь")
        }
    }
}

private enum PDFTool: Equatable {
    case distance, perimeter, area, calibration
    case hand, textSelection, selectComments, highlight, underline, strike, typewriter, rectangle, ellipse, cloud, pencil, eraser, line, arrow, callout, note, stamp, link, marquee, snapshot, formText, formCheckbox, formRadio, formChoice, formButton, addText, editText, editContent
    var title: Bilingual {
        switch self {
        case .distance: Bilingual(en: "Distance",ru: "Расстояние")
        case .perimeter: Bilingual(en: "Perimeter",ru: "Периметр")
        case .area: Bilingual(en: "Area",ru: "Площадь")
        case .calibration: Bilingual(en: "Calibrate scale",ru: "Калибровать масштаб")
        case .hand: Bilingual(en: "Hand", ru: "Рука")
        case .textSelection: Bilingual(en: "Text Selection", ru: "Выделить текст")
        case .selectComments: Bilingual(en: "Select Comments", ru: "Выделить комментарии")
        case .highlight: Bilingual(en: "Highlight Text", ru: "Подсветить текст")
        case .underline: Bilingual(en: "Underline", ru: "Подчёркивание")
        case .strike: Bilingual(en: "Strikethrough", ru: "Зачёркивание")
        case .ellipse: Bilingual(en: "Ellipse", ru: "Эллипс")
        case .cloud: Bilingual(en: "Cloud", ru: "Облако")
        case .pencil: Bilingual(en: "Pencil", ru: "Карандаш")
        case .eraser: Bilingual(en: "Eraser", ru: "Ластик")
        case .note: Bilingual(en: "Sticky Note", ru: "Заметка")
        case .stamp: Bilingual(en: "Stamp", ru: "Штамп")
        case .link: Bilingual(en: "Link", ru: "Ссылка")
        case .marquee: Bilingual(en: "Marquee Zoom", ru: "Масштаб области")
        case .snapshot: Bilingual(en: "Snapshot", ru: "Снимок области")
        case .formText: Bilingual(en: "Text Field",ru: "Поле формы")
        case .formCheckbox: Bilingual(en: "Checkbox",ru: "Флажок")
        case .formRadio: Bilingual(en: "Radio Button",ru: "Переключатель")
        case .formChoice: Bilingual(en: "Dropdown",ru: "Список")
        case .formButton: Bilingual(en: "Button",ru: "Кнопка")
        case .typewriter: Bilingual(en: "Text Box", ru: "Текстовое поле")
        case .rectangle: Bilingual(en: "Rectangle", ru: "Прямоугольник")
        case .line: Bilingual(en: "Line", ru: "Линия")
        case .arrow: Bilingual(en: "Arrow", ru: "Стрелка")
        case .callout: Bilingual(en: "Callout", ru: "Выноска")
        case .addText: Bilingual(en: "Add PDF Text", ru: "Добавить текст PDF")
        case .editText: Bilingual(en: "Edit PDF Text", ru: "Редактировать текст PDF")
        case .editContent: Bilingual(en: "Content Editor",ru: "Редактор содержимого")
        }
    }
}

private enum PDFZoomLimits {
    static let minimum: CGFloat = 0.05
    static let maximum: CGFloat = 20
    static func clamp(_ value: CGFloat) -> CGFloat { min(maximum,max(minimum,value.isFinite ? value : 1)) }
}

private enum PageLayout: CaseIterable, Identifiable {
    case single, continuous, spread
    var id: Self { self }
    var title: Bilingual {
        switch self {
        case .single: Bilingual(en: "Single Page", ru: "Одна страница")
        case .continuous: Bilingual(en: "Continuous", ru: "Непрерывно")
        case .spread: Bilingual(en: "Two Pages", ru: "Две страницы")
        }
    }
    var pdfMode: PDFDisplayMode {
        switch self {
        case .single: .singlePage
        case .continuous: .singlePageContinuous
        case .spread: .twoUpContinuous
        }
    }
}

private enum WorkspacePanel: String, CaseIterable, Identifiable, Codable {
    case thumbnails, bookmarks, search, properties, comments, layers, attachments
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .thumbnails: Bilingual(en: "Thumbnails", ru: "Миниатюры страниц")
        case .bookmarks: Bilingual(en: "Bookmarks", ru: "Закладки")
        case .search: Bilingual(en: "Search", ru: "Поиск")
        case .properties: Bilingual(en: "Properties", ru: "Свойства")
        case .comments: Bilingual(en: "Comments / Annotations", ru: "Комментарии")
        case .layers: Bilingual(en: "Layers", ru: "Слои")
        case .attachments: Bilingual(en: "Attachments", ru: "Вложения")
        }
    }
    var symbol: String {
        switch self {
        case .thumbnails: "square.grid.2x2"
        case .bookmarks: "bookmark"
        case .search: "magnifyingglass"
        case .properties: "slider.horizontal.3"
        case .comments: "text.bubble"
        case .layers: "square.3.layers.3d"
        case .attachments: "paperclip"
        }
    }
}

private enum PanelDock: String, Codable, CaseIterable, Identifiable {
    case left, right, floating
    var id: String { rawValue }
    var title: Bilingual {
        switch self {
        case .left: Bilingual(en: "Dock Left", ru: "Закрепить слева")
        case .right: Bilingual(en: "Dock Right", ru: "Закрепить справа")
        case .floating: Bilingual(en: "Float", ru: "Плавающее окно")
        }
    }
}

private struct PanelConfiguration: Codable, Equatable {
    var isVisible: Bool
    var dock: PanelDock
    var width: Double
    var isPinned = true
    var isExpanded = true
    var lastDock: PanelDock = .left
    enum CodingKeys: String, CodingKey { case isVisible, dock, width, isPinned, isExpanded, lastDock }
    init(isVisible: Bool, dock: PanelDock, width: Double) {
        self.isVisible = isVisible; self.dock = dock; self.width = min(600, max(200, width))
        lastDock = dock == .floating ? .left : dock
    }
    init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        isVisible = try v.decode(Bool.self, forKey: .isVisible)
        dock = try v.decode(PanelDock.self, forKey: .dock)
        width = min(600, max(200, try v.decode(Double.self, forKey: .width)))
        isPinned = try v.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        isExpanded = try v.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        lastDock = try v.decodeIfPresent(PanelDock.self, forKey: .lastDock) ?? (dock == .floating ? .left : dock)
    }
}
private enum RulerUnit: String, CaseIterable, Identifiable {
    case points = "pt", millimeters = "mm", inches = "in"
    var id: String { rawValue }
    var pointsPerUnit: CGFloat { switch self { case .points: 1; case .millimeters: 72 / 25.4; case .inches: 72 } }
}
private struct RulerMetrics: Equatable {
    var horizontalOrigin: CGFloat = 0
    var horizontalPointsPerPixel: CGFloat = 1
    var verticalOrigin: CGFloat = 0
    var verticalPointsPerPixel: CGFloat = -1
    var valid = false
}
@MainActor
private final class ViewportState: ObservableObject {
    @Published var metrics = RulerMetrics()
    @Published var cursorViewport: CGPoint?
    @Published var cursorPage: CGPoint?
}

@MainActor
private final class PanelWorkspaceModel: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var configurations: [WorkspacePanel: PanelConfiguration]
    @Published private(set) var activeLeft: WorkspacePanel = .thumbnails
    @Published private(set) var activeRight: WorkspacePanel = .properties
    @Published private(set) var isResizing = false
    private var floatingWindows: [WorkspacePanel: NSPanel] = [:]
    private var suppressedClose = Set<ObjectIdentifier>()
    private var floatingSyncPending = false
    private var resizeStarts: [WorkspacePanel: CGFloat] = [:]
    private var persistenceWork: DispatchWorkItem?
    private let persistenceKey = "BotPlusPDFEditor.panelConfigurations.v1"
    override init() {
        let defaults: [WorkspacePanel: PanelConfiguration] = [
            .thumbnails: .init(isVisible: true, dock: .left, width: 230),
            .bookmarks: .init(isVisible: true, dock: .left, width: 240),
            .search: .init(isVisible: false, dock: .left, width: 300),
            .properties: .init(isVisible: true, dock: .right, width: 250),
            .comments: .init(isVisible: false, dock: .right, width: 260),
            .layers: .init(isVisible: false, dock: .left, width: 220),
            .attachments: .init(isVisible: false, dock: .right, width: 220)
        ]
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let saved = try? JSONDecoder().decode([WorkspacePanel: PanelConfiguration].self, from: data) {
            configurations = defaults.merging(saved) { _, value in value }
        } else { configurations = defaults }
        super.init()
        if let panel = activePanel(on: .left) { select(panel) }
        if let panel = activePanel(on: .right) { select(panel) }
    }
    func configuration(for panel: WorkspacePanel) -> PanelConfiguration {
        configurations[panel] ?? .init(isVisible: false, dock: .left, width: 230)
    }
    func panels(on side: PanelDock) -> [WorkspacePanel] {
        WorkspacePanel.allCases.filter { configuration(for: $0).dock == side && configuration(for: $0).isVisible }
    }
    func activePanel(on side: PanelDock) -> WorkspacePanel? {
        let candidates = panels(on: side).filter { configuration(for: $0).isExpanded }
        let preferred = side == .left ? activeLeft : activeRight
        return candidates.contains(preferred) ? preferred : candidates.first
    }
    func select(_ panel: WorkspacePanel) {
        let config = configuration(for: panel)
        if config.dock == .left { activeLeft = panel }
        if config.dock == .right { activeRight = panel }
        var next = configurations
        let sharedWidth = activePanel(on: config.dock).map { configuration(for: $0).width } ?? config.width
        for candidate in WorkspacePanel.allCases where configuration(for: candidate).dock == config.dock && config.dock != .floating {
            next[candidate]?.width = sharedWidth
            next[candidate]?.isExpanded = candidate == panel
        }
        next[panel]?.isVisible = true; next[panel]?.isExpanded = true
        publish(next)
    }
    func toggleDrawer(_ panel: WorkspacePanel) {
        let config = configuration(for: panel)
        if config.dock == .floating { floatingWindows[panel]?.makeKeyAndOrderFront(nil); return }
        if activePanel(on: config.dock) == panel && config.isExpanded {
            update(panel) { $0.isExpanded = false }
        } else { select(panel) }
    }
    func collapseAutoHiddenPanels() {
        var next = configurations
        for panel in WorkspacePanel.allCases {
            if var config = next[panel], !config.isPinned, config.dock != .floating {
                config.isExpanded = false; next[panel] = config
            }
        }
        publish(next)
    }
    func setPinned(_ pinned: Bool, for panel: WorkspacePanel) { update(panel) { $0.isPinned = pinned; $0.isExpanded = true } }
    func setVisible(_ visible: Bool, for panel: WorkspacePanel) {
        update(panel) { $0.isVisible = visible; $0.isExpanded = visible }
        if visible { select(panel) }
    }
    func setDock(_ dock: PanelDock, for panel: WorkspacePanel) {
        update(panel) {
            if dock == .floating && $0.dock != .floating { $0.lastDock = $0.dock }
            if dock != .floating { $0.lastDock = dock }
            $0.dock = dock; $0.isExpanded = true; $0.isVisible = true
        }
        select(panel)
    }
    func setWidth(_ width: CGFloat, for panel: WorkspacePanel) {
        let dock = configuration(for: panel).dock
        var next = configurations
        for candidate in WorkspacePanel.allCases where candidate == panel || (dock != .floating && configuration(for: candidate).dock == dock) {
            next[candidate]?.width = Double(min(600,max(200,width)))
        }
        publish(next)
    }
    func beginResize() { isResizing = true }
    func resize(_ panel: WorkspacePanel, translation: CGFloat, initialWidth: CGFloat? = nil) {
        let start = resizeStarts[panel] ?? initialWidth ?? CGFloat(configuration(for: panel).width)
        resizeStarts[panel] = start
        setWidth(start + translation, for: panel)
    }
    func endResize(_ panel: WorkspacePanel) { resizeStarts[panel] = nil; isResizing = false; persist() }
    private func update(_ panel: WorkspacePanel, change: (inout PanelConfiguration) -> Void) {
        var next = configurations; var config = configuration(for: panel)
        change(&config); next[panel] = config; publish(next)
    }
    private func publish(_ next: [WorkspacePanel: PanelConfiguration]) {
        guard next != configurations else { return }
        configurations = next
        persistenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persist() }
        persistenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3, execute: work)
    }
    private func persist() {
        persistenceWork?.cancel(); persistenceWork = nil
        if let data = try? JSONEncoder().encode(configurations) { UserDefaults.standard.set(data, forKey: persistenceKey) }
    }
    func synchronizeFloatingWindows(manager: DocumentManager) {
        guard !floatingSyncPending else { return }; floatingSyncPending = true
        DispatchQueue.main.async { [weak self,weak manager] in
            guard let self else { return }; self.floatingSyncPending = false
            guard let manager else { return }; self.applyFloatingWindows(manager: manager)
        }
    }
    private func applyFloatingWindows(manager: DocumentManager) {
        for panel in WorkspacePanel.allCases {
            let config = configuration(for: panel)
            if config.isVisible && config.dock == .floating {
                if let window = floatingWindows[panel] {
                    if window.title != manager.text(panel.title) { window.title = manager.text(panel.title) }
                    if window.appearance?.name != manager.theme.appearance?.name { window.appearance = manager.theme.appearance }
                    continue
                }
                let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: config.width, height: 420),
                                     styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
                window.title = manager.text(panel.title)
                window.appearance = manager.theme.appearance
                window.isReleasedWhenClosed = false; window.isFloatingPanel = true; window.level = .floating
                window.minSize = NSSize(width: 200, height: 180); window.maxSize = NSSize(width: 600, height: 1600)
                window.delegate = self
                window.contentView = NSHostingView(rootView: FloatingPanelContents(panel: panel, panels: self, manager: manager))
                window.setFrameAutosaveName("BotPlusPDFEditor.\(panel.rawValue).floating")
                floatingWindows[panel] = window; window.makeKeyAndOrderFront(nil)
            } else if let window = floatingWindows[panel] {
                suppressedClose.insert(ObjectIdentifier(window)); floatingWindows[panel] = nil; window.close()
            }
        }
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if suppressedClose.remove(ObjectIdentifier(window)) != nil { return }
        guard let panel = floatingWindows.first(where: { $0.value === window })?.key else { return }
        floatingWindows[panel] = nil
        DispatchQueue.main.async { [weak self] in
            guard let self,self.configuration(for: panel).dock == .floating else { return }
            self.setDock(self.configuration(for: panel).lastDock,for: panel)
        }
    }
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = floatingWindows.first(where: { $0.value === window })?.key else { return }
        DispatchQueue.main.async { [weak self,weak window] in
            guard let self,let window,self.floatingWindows[panel] === window else { return }
            self.setWidth(window.frame.width,for: panel)
        }
    }
}

@MainActor
private final class SharedPDFDocument: ObservableObject {
    let id = UUID()
    @Published var url: URL { didSet { accessLease = FileAccessLease(url) } }
    private var accessLease: FileAccessLease
    @Published var document: PDFDocument
    @Published var isUntitled = false
    @Published var revision = 0
    var savedRevision = 0
    var savedStamp: Int
    var undoHistory: [PDFDocumentItem.Snapshot] = [], redoHistory: [PDFDocumentItem.Snapshot] = []
    var historyGroup = "", historyDate = Date.distantPast
    var recoveredFilename: String?, rootSourceData: Data?
    var streamIdentity: ObjectIdentifier?, streamPages: [ObjectIdentifier] = [], streamRoot: Int?
    init(url: URL,document: PDFDocument) { self.url = url; self.document = document; accessLease = FileAccessLease(url); savedStamp = PDFDocumentState.stamp(document) }
    var hasChanges: Bool { isUntitled || revision != savedRevision || savedStamp != PDFDocumentState.stamp(document) }
}
@MainActor
private final class PDFDocumentItem: ObservableObject, Identifiable {
    let id = UUID(), store: SharedPDFDocument
    private var storeObservation: AnyCancellable?
    @Published var pageIndex = 0
    @Published var zoom: CGFloat = 1
    @Published var selectedPages = Set<Int>()
    var thumbnailAnchor: Int?
    struct Snapshot { let data: Data; let page: Int; let zoom: CGFloat; let bookmarks: [PDFBookmarkStore.Record]? }
    var url: URL { get { store.url } set { store.url = newValue } }
    var document: PDFDocument { get { store.document } set { store.document = newValue } }
    var isUntitled: Bool { get { store.isUntitled } set { store.isUntitled = newValue } }
    var undoHistory: [Snapshot] { get { store.undoHistory } set { store.undoHistory = newValue } }
    var redoHistory: [Snapshot] { get { store.redoHistory } set { store.redoHistory = newValue } }
    var historyGroup: String { get { store.historyGroup } set { store.historyGroup = newValue } }
    var historyDate: Date { get { store.historyDate } set { store.historyDate = newValue } }
    var rootSourceData: Data? { get { store.rootSourceData } set { store.rootSourceData = newValue } }
    var recoveredFilename: String? { get { store.recoveredFilename } set { store.recoveredFilename = newValue } }
    let navigation = PDFNavigationHistory()
    var navigationPageCount = 0
    init(url: URL,document: PDFDocument,preserveStreams: Bool = false) {
        store = SharedPDFDocument(url: url,document: document)
        observeStore(); if preserveStreams { enableStreamPreservation() }
    }
    init(shared: SharedPDFDocument,page: Int,zoom: CGFloat) { store = shared; pageIndex = page; self.zoom = zoom; observeStore() }
    private func observeStore() { storeObservation = store.objectWillChange.sink { [weak self] _ in MainActor.assumeIsolated { self?.objectWillChange.send() } } }
    func enableStreamPreservation() {
        store.streamIdentity = ObjectIdentifier(document)
        store.streamPages = (0..<pageCount).compactMap { document.page(at: $0).map(ObjectIdentifier.init) }
        store.streamRoot = PDFDocumentState.rootStamp(document)
    }
    var canPreserveStreams: Bool { store.streamIdentity == ObjectIdentifier(document) && store.streamRoot == PDFDocumentState.rootStamp(document) && store.streamPages == (0..<pageCount).compactMap { document.page(at: $0).map(ObjectIdentifier.init) } }
    var filename: String { isUntitled ? recoveredFilename ?? "Untitled.pdf" : url.lastPathComponent }
    var pageCount: Int { document.pageCount }
}

@MainActor
private final class DocumentManager: ObservableObject {
    let panels: PanelWorkspaceModel
    let recent: RecentPDFStore
    init(recent: RecentPDFStore = .shared,panels: PanelWorkspaceModel = PanelWorkspaceModel()) { self.recent = recent; self.panels = panels }
    @Published var splitManager: DocumentManager?
    @Published var splitHorizontal = true
    @Published var splitFocused = false
    weak var parentManager: DocumentManager?
    var activePane: DocumentManager { splitFocused ? splitManager ?? self : self }
    private var documentObservations: [AnyCancellable] = []
    private func observeDocuments() {
        documentObservations = documents.map { item in item.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.refreshPresentation() }
        } }
    }
    @Published var formattingRequest: PDFFormattingRequest?
    @Published var graphicMarkRequest: PDFGraphicMarkRequest?
    @Published var pageWorkflowRequest: PDFPageWorkflowRequest?
    var afterPageWorkflowDismiss: (() -> Void)?
    @Published var snapshotDPI = 150
    @Published var snapshotTransparent = false
    @Published var snapshotImage: NSImage?
    var snapshotPNG: Data?
    @Published var isSpacingPresented = false
    @Published var isRibbonCustomizationPresented = false
    @Published var geometryRequest: PageGeometryRequest?
    @Published var regionRequest: PDFRegionRequest?
    @Published var printRequest: PDFPrintRequest?
    @Published var spellRequest: PDFSpellRequest?
    @Published var securityRequest: PDFSecurityRequest?
    @Published var headingRequest: PDFHeadingRequest?
    @Published var bookmarkTextRequest: PDFBookmarkTextRequest?
    @Published var bookmarkValidationRequest: PDFBookmarkValidationRequest?
    @Published var tocRequest: PDFTOCRequest?
    @Published var formOrderRequest: PDFFormOrderRequest?
    @Published var tabTraversalRequest: PDFTabTraversalRequest?
    @Published var engineeringScaleRequest: EngineeringScaleRequest?
    @Published var annotationVertexRequest: PDFAnnotationVertexRequest?
    @Published var annotationScaleRequest: PDFAnnotationScaleRequest?
    @Published var annotationRotationRequest: PDFAnnotationRotationRequest?
    @Published var formValuesRequest: PDFFormValuesRequest?
    @Published var formRuleRequest: PDFFormRuleRequest?
    @Published var formValidationRequest: PDFFormValidationRequest?
    @Published var ocrReviewRequest: PDFOCRReviewRequest?
    @Published var scannerRequest: PDFScannerRequest?
    @Published var rasterRequest: PDFRasterRequest?
    @Published var comparisonRequest: PDFComparisonRequest?
    @Published var officeRequest: PDFOfficeRequest?
    @Published var structureRequest: PDFStructureRequest?
    @Published var pathRequest: PDFPathRequest?
    @Published var namedRequest: PDFNamedRequest?
    @Published var layerEntries: [PDFLayerInfo] = []
    @Published var layerOutline: [PDFLayerRow] = []
    @Published var layerHasOrder = false
    @Published var layerPresets: [PDFLayerPreset] = []
    @Published var layerPresetRequest: PDFLayerPresetRequest?
    @Published var layerStateRequest: PDFLayerStateRequest?
    @Published var layerRadioRequest: PDFLayerRadioRequest?
    @Published var layerOrderRequest: PDFLayerOrderRequest?
    @Published var layerPolicyRequest: PDFLayerPolicyRequest?
    @Published var membershipRequest: PDFMembershipRequest?
    @Published var membershipBindingRequest: PDFMembershipBindingRequest?
    @Published var xObjectConditionRequest: PDFXObjectConditionRequest?
    @Published var formResourceTransformRequest: PDFFormResourceTransformRequest?
    @Published var engineeringTransformRequest: EngineeringTransformRequest?
    @Published var engineeringTransferRequest: EngineeringTransferRequest?
    @Published var engineeringDirectionRequest: EngineeringDirectionRequest?
    @Published var engineeringLabelRequest: EngineeringLabelRequest?
    @Published var layerError: String?
    var layerSnapshot: (data: Data,document: ObjectIdentifier,stamp: Int)?
    var afterFeatureDismiss: (() -> Void)?
    @Published var attachments: [PDFAttachmentEntry] = []
    @Published var attachmentError: String?
    @Published var snapshotSource: (id: UUID, page: Int, region: CGRect)?
    @Published var pageGap = PDFPageSpacing.clamp(UserDefaults.standard.object(forKey: "BotPlus.pageGap") as? Double ?? 4) {
        didSet { UserDefaults.standard.set(pageGap,forKey: "BotPlus.pageGap") }
    }
    @Published var navigationRevision = 0
    @Published var operationProgress: Double?
    @Published var operationTitle = ""
    var operationTask: Task<Void, Never>?
    var activeOperationID: UUID?
    @Published var loadingFiles = 0
    private var openingPaths = Set<String>()
    @Published var isLicensePresented = false
    @Published var isUpdatePresented = false
    private var serializedIdentity: ObjectIdentifier?
    private var serializedRevision = -1
    private var serializedStamp: Int?
    private var serializedBytes: Data?
    private(set) var serializationCount = 0

    @Published private(set) var documents: [PDFDocumentItem] = [] { didSet { observeDocuments() } }
    @Published var selectedID: UUID?
    @Published var language: AppLanguage = .ru {
        didSet {
            if let parentManager,parentManager.language != language { parentManager.language = language }
            if let splitManager,splitManager.language != language { splitManager.language = language }
        }
    }
    @Published var theme: AppTheme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "BotPlusPDFEditor.theme") ?? "dark") ?? .dark {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "BotPlusPDFEditor.theme")
            if let parentManager,parentManager.theme != theme { parentManager.theme = theme }
            if let splitManager,splitManager.theme != theme { splitManager.theme = theme }
        }
    }
    @Published var thumbnailZoom = 1.0
    @Published var thumbnailGestureActive = false
    var thumbnailGestureOwner: UUID?
    private var embeddedTextDocument: ObjectIdentifier?
    private var embeddedTextRevision = -1
    private var embeddedTextData: Data?
    private var embeddedTextCache: [Int:String] = [:]
    private var localRevision = 0
    var contentRevision: Int { get { selected?.store.revision ?? localRevision } set { if let selected { selected.store.revision = newValue } else { localRevision = newValue } } }
    @Published var selectedOutline: PDFOutline?
    @Published var stampText = "СОГЛАСОВАНО"
    @Published var annotationFill = false
    lazy var speech = AVSpeechSynthesizer()
    @Published var tab: RibbonTab = .home
    @Published var tool: PDFTool = .hand
    @Published var layout: PageLayout = .continuous
    @Published var rulersVisible = false
    @Published var engineeringSnap = true
    @Published var engineeringUnit = EngineeringUnit.m
    @Published var rulerUnit: RulerUnit = .millimeters
    let viewport = ViewportState()
    let textProperties = PDFTextPropertiesModel()
    let contentProperties = PDFContentPropertiesModel()
    @Published var hasTextSelection = false
    @Published var clipboardAvailable = false
    var cursorViewport: CGPoint? { get { viewport.cursorViewport } set { viewport.cursorViewport = newValue } }
    var cursorPage: CGPoint? { get { viewport.cursorPage } set { viewport.cursorPage = newValue } }
    @Published var annotationColor: Color = .red
    @Published var annotationStrokeWidth: Double = 2
    @Published var annotationOpacity: Double = 1
    @Published var textFontSize: Double = 18
    @Published var textBorderEnabled = true
    @Published var selectedAnnotation: PDFAnnotation?
    @Published var selectedAnnotationCount = 0
    @Published var selectedContent: PDFSourceSession.ContentObject?
    @Published var pageText = "1"
    @Published var searchText = "" { didSet { if searchText != oldValue { clearSearch() } } }
    @Published var searchRequestID = 0
    struct SearchMatch: Identifiable {
        let id: Int
        let page: Int
        let snippet: String
        let selection: PDFSelection
    }
    @Published var searchMatches: [SearchMatch] = []
    @Published var searchMatchID: Int?
    @Published var searchRunning = false
    @Published var searchCompleted = false
    @Published var searchNavigationID = 0
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var searchDocument: PDFDocument?
    private var searchRevision = -1
    var currentSearchSelection: PDFSelection? {
        guard let item = selected, item.document === searchDocument, item.store.revision == searchRevision else { return nil }
        return searchMatches.first { $0.id == searchMatchID }?.selection
    }
    func clearSearch() {
        searchGeneration &+= 1; searchTask?.cancel(); searchTask = nil
        searchMatches = []; searchMatchID = nil; searchRunning = false; searchCompleted = false
        searchDocument = nil; searchRevision = -1
        searchNavigationID &+= 1
    }
    func invalidateStaleSearch() {
        if let searchDocument, selected?.document !== searchDocument || selected?.store.revision != searchRevision { clearSearch() }
    }
    func runSearch() {
        clearSearch(); panels.select(.search)
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, let item = selected else { return }
        let document = item.document, revision = item.store.revision, generation = searchGeneration
        searchDocument = document; searchRevision = revision; searchRunning = true
        searchTask = Task { @MainActor [weak self] in
            for index in 0..<document.pageCount {
                await Task.yield()
                guard let self, !Task.isCancelled, self.searchGeneration == generation else { return }
                guard self.selected?.document === document, item.store.revision == revision else { self.clearSearch(); return }
                guard let page = document.page(at: index), let text = page.string else { continue }
                let source = text as NSString
                var cursor = 0
                var batch: [SearchMatch] = []
                while cursor < source.length {
                    let range = source.range(of: query, options: .caseInsensitive, range: NSRange(location: cursor, length: source.length - cursor))
                    guard range.location != NSNotFound, range.length > 0 else { break }
                    if let selection = page.selection(for: range) {
                        let start = max(0, range.location - 45), end = min(source.length, NSMaxRange(range) + 65)
                        let context = source.rangeOfComposedCharacterSequences(for: NSRange(location: start, length: end - start))
                        let snippet = source.substring(with: context).components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                        batch.append(SearchMatch(id: self.searchMatches.count + batch.count, page: index, snippet: (start > 0 ? "…" : "") + snippet + (end < source.length ? "…" : ""), selection: selection))
                    }
                    cursor = NSMaxRange(range)
                    if batch.count.isMultiple(of: 200) {
                        await Task.yield()
                        guard !Task.isCancelled, self.searchGeneration == generation else { return }
                        guard self.selected?.document === document, item.store.revision == revision else { self.clearSearch(); return }
                    }
                }
                self.searchMatches.append(contentsOf: batch)
                if self.searchMatchID == nil, let first = self.searchMatches.first { self.selectSearchMatch(first.id) }
            }
            guard let self, self.searchGeneration == generation, !Task.isCancelled else { return }
            self.searchRunning = false; self.searchCompleted = true; self.searchTask = nil
        }
    }
    func selectSearchMatch(_ id: Int) {
        invalidateStaleSearch()
        guard searchMatches.contains(where: { $0.id == id }) else { return }
        searchMatchID = id; searchNavigationID &+= 1; refreshPresentation()
    }
    func stepSearch(_ delta: Int) {
        guard !searchMatches.isEmpty else { return }
        let index = searchMatches.firstIndex { $0.id == searchMatchID } ?? 0
        selectSearchMatch(searchMatches[(index + delta % searchMatches.count + searchMatches.count) % searchMatches.count].id)
    }
    @Published var notice: String?
    @Published var commandIndex = 0
    @Published var command: ViewerCommand = .refresh
    var rulerMetrics: RulerMetrics { get { viewport.metrics } set { viewport.metrics = newValue } }
    var finishSourceEditing: (() -> Bool)?
    var isClosingTabs = false
    var captureNavigation: (() -> Void)?
    @Published var isAboutPresented = false

    var selected: PDFDocumentItem? { documents.first(where: { $0.id == selectedID }) }
    var title: String {
        guard let selected else { return BotPlusBrand.name }
        return "\(selected.filename) - \(BotPlusBrand.name)"
    }
    func restoreRecovered(_ item: PDFDocumentItem) { documents.append(item); select(item.id) }
    func text(_ value: Bilingual) -> String { value.value(language) }
    func say(_ en: String, _ ru: String) { notice = language == .ru ? ru : en }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            DispatchQueue.main.async { for url in panel.urls { self?.openAsync(url) } }
        }
    }

    func openAsync(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { say("Please choose a PDF file.","Выберите файл PDF."); return }
        if let existing = documents.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { recent.remember(url); select(existing.id); return }
        guard finishSourceEditing?() != false else { return }
        let path = url.standardizedFileURL.path
        guard openingPaths.insert(path).inserted else { return }
        loadingFiles += 1
        Task { @MainActor [weak self] in
            guard let self else { return }
            let lease = FileAccessLease(url)
            defer { _ = lease; openingPaths.remove(path); loadingFiles -= 1 }
            do {
                let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url,options: .mappedIfSafe) }.value
                guard let document = PDFDocument(data: data) else { throw PDFSourceError.document }
                AnnotationMetadata.restore(document)
                let item = PDFDocumentItem(url: url,document: document,preserveStreams: true)
                documents.append(item); recent.remember(url); select(item.id)
                seedSerializedData(data,item: item)
                AppDiagnostics.record("document_open pages=\(document.pageCount)")
            } catch { AppDiagnostics.error("document_open", error); say("The PDF could not be opened. Select the file again if access expired.","Не удалось открыть PDF. Если доступ истёк, выберите файл снова.") }
        }
    }

    func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { say("Please choose a PDF file.", "Выберите файл PDF."); return }
        if let existing = documents.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            recent.remember(url); select(existing.id); return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let document = PDFDocument(url: url) else { say("The PDF could not be opened.", "Не удалось открыть PDF-файл."); return }
        AnnotationMetadata.restore(document)
        let item = PDFDocumentItem(url: url, document: document,preserveStreams: true)
        documents.append(item)
        AppDiagnostics.record("document_open pages=\(document.pageCount)")
        recent.remember(url)
        select(item.id)
        if let data = try? Data(contentsOf: url,options: .mappedIfSafe) { seedSerializedData(data,item: item) }
    }

    func select(_ id: UUID) {
        parentManager?.splitFocused = true
        guard selectedID == id || finishSourceEditing?() != false else { return }
        if selectedID != id { selectedOutline = nil; selectedContent = nil; selectedAnnotation = nil; hasTextSelection = false; contentProperties.reset(); textProperties.reset() }
        if selectedID != id { captureNavigation?(); clearSearch() }
        selectedID = id
        pageText = String((documents.first(where: { $0.id == id })?.pageIndex ?? 0) + 1)
        refreshPresentation()
    }

    func close(_ id: UUID) {
        guard selectedID != id || finishSourceEditing?() != false else { return }
        let wasSelected = selectedID == id
        documents.removeAll(where: { $0.id == id })
        if wasSelected {
            selectedContent = nil; selectedAnnotation = nil; hasTextSelection = false; contentProperties.reset(); textProperties.reset()
            selectedID = documents.last?.id
            pageText = String((selected?.pageIndex ?? 0) + 1)
            send(.refresh)
        }
    }

    func serializedData(_ item: PDFDocumentItem) throws -> Data {
        let identity = ObjectIdentifier(item.document)
        let stamp = PDFDocumentState.stamp(item.document)
        if serializedIdentity == identity,serializedRevision == item.store.revision,serializedStamp == stamp,let data = serializedBytes { return data }
        var data = try PDFDocumentSerializer.data(item.document,preserveStreams: item.canPreserveStreams)
        if let root = item.rootSourceData {
            if PDFDocument(data: root)?.isEncrypted == true {
                guard item.canPreserveStreams else { throw PDFSourceError.permission }
            } else { data = try PDFDocumentExtras.preserveAttachments(from: root,in: data) }
        }
        serializationCount += 1; serializedIdentity = identity; serializedRevision = item.store.revision
        serializedStamp = stamp
        serializedBytes = data.count <= 64*1024*1024 ? data : nil
        return data
    }
    func seedSerializedData(_ data: Data,item: PDFDocumentItem) {
        item.rootSourceData = data
        serializedIdentity = ObjectIdentifier(item.document); serializedRevision = item.store.revision
        serializedStamp = PDFDocumentState.stamp(item.document)
        serializedBytes = data.count <= 64*1024*1024 ? data : nil
    }
    func refreshPresentation() { command = .refresh; commandIndex &+= 1 }
    func send(_ next: ViewerCommand) { if next == .refresh { contentRevision &+= 1 }; command = next; commandIndex &+= 1 }
    func navigate(to index: Int) {
        guard finishSourceEditing?() != false else { return }
        guard let selected, selected.pageCount > 0 else { return }
        let safeIndex = min(max(index, 0), selected.pageCount - 1)
        selected.pageIndex = safeIndex
        pageText = String(safeIndex + 1)
        send(.page(safeIndex))
    }
    func commitPageField() {
        guard let number = Int(pageText) else { pageText = String((selected?.pageIndex ?? 0) + 1); return }
        navigate(to: number - 1)
    }

    func saveDocument() {
        guard finishSourceEditing?() != false else { return }
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        if selected.isUntitled { saveDocumentAs(); return }
        do { try PDFDocumentSerializer.write(try serializedData(selected),to: selected.url); selected.store.savedRevision = selected.store.revision; selected.store.savedStamp = PDFDocumentState.stamp(selected.document); recent.remember(selected.url) }
        catch { AppDiagnostics.error("document_save", error); say("Could not save the PDF.","Не удалось сохранить PDF-файл.") }
    }
    func saveDocumentAs() {
        guard finishSourceEditing?() != false else { return }
        guard let selected else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = selected.filename
        panel.begin { [weak self] response in
            guard response == .OK,let url = panel.url else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                do { try PDFDocumentSerializer.write(try self.serializedData(selected),to: url) }
                catch { AppDiagnostics.error("document_save_as", error); self.say("Could not save the PDF.","Не удалось сохранить PDF-файл."); return }
                selected.url = url; selected.isUntitled = false; selected.store.savedRevision = selected.store.revision; selected.store.savedStamp = PDFDocumentState.stamp(selected.document); self.recent.remember(url); self.refreshPresentation()
            }
        }
    }
    func printDocument() {
        guard selected?.document != nil else { say("Open a PDF first.", "Сначала откройте PDF-файл."); return }
        send(.print)
    }
    func perform(_ action: RibbonAction) {
        guard canPerform(action) else { return }
        if let (target, command) = thumbnailTarget(for: action) { target.performThumbnailCommand(command); return }
        if case .feature(let id) = action {
            AppDiagnostics.record("command feature=\(id)")
            if id == "logs" {
                if FileManager.default.fileExists(atPath: AppDiagnostics.directory.path) {
                    NSWorkspace.shared.open(AppDiagnostics.directory)
                } else { say("Could not create the logs folder.","Не удалось создать папку логов.") }
                return
            }
            if id == "search" { panels.select(.search); return }
            if id == "license" { isLicensePresented = true; return }
            if id == "updates" { checkUpdates(); return }
            if id == "spacing" { isSpacingPresented = true; return }
            if id == "undo" || id == "redo" { undoDocument(redo: id == "redo"); return }
            if id == "blank" { createBlankDocument(); return }
            if id == "newWindow" { PDFWindowPool.shared.open(); return }
            if id == "customize" { isRibbonCustomizationPresented = true; return }
            if id == "scanner" { openScanner(); return }
            if id == "fromFiles" { createFromFiles(); return }
        }
        if selected == nil {
            switch action {
            case .open, .settings, .toggleLanguage, .toggleRulers, .panels, .languagePicker, .about, .support, .telegram, .themePicker, .development: break
            default: say("Open a PDF first.", "Сначала откройте PDF-файл."); return
            }
        }
        switch action {
        case .open: openPanel()
        case .save: saveDocument()
        case .saveAs: saveDocumentAs()
        case .close: if let selected { closeTabs([selected.id]) }
        case .print: printDocument()
        case .settings: tab = .help
        case .tool(let next):
            guard finishSourceEditing?() != false else { return }
            if next == .snapshot {
                selectedAnnotation = nil; selectedContent = nil; contentProperties.reset(); textProperties.reset(); panels.select(.properties)
            }
            tool = next; refreshPresentation()
        case .layout(let next): captureNavigation?(); layout = next; refreshPresentation()
        case .zoomIn: send(.zoomIn)
        case .zoomOut: send(.zoomOut)
        case .actualSize: send(.actualSize)
        case .fitPage: send(.fitPage)
        case .fitWidth: send(.fitWidth)
        case .rotateLeft: send(.rotate(-90))
        case .rotateRight: send(.rotate(90))
        case .previous: navigate(to: (selected?.pageIndex ?? 0) - 1)
        case .next: navigate(to: (selected?.pageIndex ?? 0) + 1)
        case .first: navigate(to: 0)
        case .last: navigate(to: (selected?.pageCount ?? 1) - 1)
        case .highlight: activateMarkup(.highlight)
        case .underline: activateMarkup(.underline)
        case .feature("historyBack"): send(.history(-1))
        case .feature("historyForward"): send(.history(1))
        case .feature(let id): send(.feature(id))
        case .insertBlankPage: send(.insertBlankPage)
        case .deletePage: send(.deletePage)
        case .duplicatePage: send(.duplicatePage)
        case .toggleLanguage: language = language == .ru ? .en : .ru
        case .toggleRulers: rulersVisible.toggle()
        case .panels: break
        case .languagePicker: break
        case .about: isAboutPresented = true
        case .support: openExternalLink(BotPlusBrand.supportURL)
        case .telegram: openExternalLink(BotPlusBrand.telegramURL)
        case .themePicker: break
        case .copy: send(.copy)
        case .cut: send(.cut)
        case .paste: send(.paste)
        case .deleteSelection: send(.deleteSelection)
        case .development: say("Feature in development", "Функция в разработке")
        }
    }

    private func openExternalLink(_ url: URL) {
        if !NSWorkspace.shared.open(url) {
            say("Could not open the link.", "Не удалось открыть ссылку.")
        }
    }
}

@MainActor
private enum AnnotationMetadata {
    static func isLocked(_ annotation: PDFAnnotation) -> Bool {
        let flags = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
        return flags & ((1 << 6) | (1 << 7) | (1 << 9)) != 0
    }
    static func setLocked(_ value: Bool,on annotation: PDFAnnotation) {
        var flags = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
        let mask = (1 << 6) | (1 << 7) | (1 << 9)
        if value { flags |= mask } else { flags &= ~mask }
        annotation.setValue(NSNumber(value: flags),forAnnotationKey: .flags)
    }
    struct Record: Codable {
        var id = UUID().uuidString
        var opacity: Double
        var group: String?
        var decoration: String?
        var measurement: EngineeringMeasure?
        var formSelections: [String]?
        var formRule: PDFFormRule?
        var inkCurves: PDFInkCurveRecord?
    }
    private struct Entry: Codable {
        let index: Int
        let subtype: String
        let center: CGPoint
        let record: Record
        // PDFKit may normalize MediaBox to (0, 0) and translate annotations.
        // Optional so files written before coordinate-origin tracking still open.
        let mediaOrigin: CGPoint?
    }
    private final class Box: NSObject {
        var record: Record
        init(_ record: Record) { self.record = record }
    }
    private static let records = NSMapTable<PDFAnnotation, Box>.weakToStrongObjects()
    private static let prefix = "BotPlus PDF Editor metadata v1:"
    static func measurement(_ annotation: PDFAnnotation) -> EngineeringMeasure? { records.object(forKey: annotation)?.record.measurement }
    static func inkCurves(_ annotation: PDFAnnotation) -> PDFInkCurveRecord? { records.object(forKey: annotation)?.record.inkCurves }
    static func setInkCurves(_ value: PDFInkCurveRecord?,on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.inkCurves = value; records.setObject(Box(record),forKey: annotation)
    }
    static func formRule(_ annotation: PDFAnnotation) -> PDFFormRule? { records.object(forKey: annotation)?.record.formRule }
    static func setFormRule(_ rule: PDFFormRule,on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.formRule = rule; records.setObject(Box(record),forKey: annotation)
    }
    static func formSelections(_ annotation: PDFAnnotation) -> [String]? {
        guard let values = records.object(forKey: annotation)?.record.formSelections,
              (annotation.value(forAnnotationKey: .widgetValue) as? String ?? "") == values.first ?? "" else { return nil }
        return values
    }
    static func setFormSelections(_ values: [String],on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.formSelections = values; records.setObject(Box(record),forKey: annotation)
        annotation.widgetStringValue = values.first ?? ""
    }
    static func clearFormSelections(_ annotation: PDFAnnotation) {
        guard var record = records.object(forKey: annotation)?.record else { return }
        record.formSelections = nil; records.setObject(Box(record),forKey: annotation)
    }
    static func setMeasurement(_ value: EngineeringMeasure,on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.measurement = value; records.setObject(Box(record),forKey: annotation)
    }
    static func alpha(of annotation: PDFAnnotation) -> CGFloat {
        if let record = records.object(forKey: annotation)?.record { return CGFloat(record.opacity) }
        return annotation.color.alphaComponent
    }
    static func decoration(of annotation: PDFAnnotation) -> String? { records.object(forKey: annotation)?.record.decoration }
    static func setDecoration(_ kind: String, on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: 1)
        record.decoration = kind; records.setObject(Box(record), forKey: annotation)
    }
    static func group(of annotation: PDFAnnotation) -> String? { records.object(forKey: annotation)?.record.group }
    static func setOpacity(_ opacity: Double, on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: opacity)
        record.opacity = min(1, max(0, opacity)); records.setObject(Box(record), forKey: annotation)
    }
    static func setGroup(_ group: String, on annotation: PDFAnnotation) {
        var record = records.object(forKey: annotation)?.record ?? Record(opacity: Double(annotation.color.alphaComponent))
        record.group = group; records.setObject(Box(record), forKey: annotation)
    }
    private static func isOpacityContainer(_ annotation: PDFAnnotation) -> Bool {
        ["Text", "FreeText", "Popup"].contains(annotation.type ?? "") && (annotation.contents ?? "").hasPrefix(prefix)
    }
    static func isContainer(_ annotation: PDFAnnotation) -> Bool {
        isOpacityContainer(annotation) || (annotation.contents ?? "").hasPrefix("BotPlus engineering calibration v1:") || (!annotation.shouldDisplay && !annotation.shouldPrint && PDFSourceSession.isLayoutMetadata(annotation.contents ?? ""))
    }
    // PDFKit's writer omits custom dictionary keys. A hidden, non-printing FreeText
    // annotation carries editor settings while standard visible annotations stay editable.
    static func prepareForSave(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isOpacityContainer(annotation) { removeContainer(annotation, from: page) }
            let entries = page.annotations.filter { !isContainer($0) }.enumerated().compactMap { index, annotation -> Entry? in
                guard let record = records.object(forKey: annotation)?.record else { return nil }
                return Entry(index: index, subtype: annotation.type ?? "", center: CGPoint(x: annotation.bounds.midX, y: annotation.bounds.midY), record: record,mediaOrigin: page.bounds(for: .mediaBox).origin)
            }
            guard !entries.isEmpty, let data = try? JSONEncoder().encode(entries) else { continue }
            let marker = PDFAnnotation(bounds: CGRect(x: page.bounds(for: .cropBox).minX, y: page.bounds(for: .cropBox).minY, width: 1, height: 1), forType: .freeText, withProperties: nil)
            marker.contents = prefix + data.base64EncodedString()
            marker.shouldDisplay = false; marker.shouldPrint = false
            marker.userName = BotPlusBrand.name
            page.addAnnotation(marker)
        }
    }
    private static func removeContainer(_ marker: PDFAnnotation, from page: PDFPage) {
        if let popup = marker.popup { page.removeAnnotation(popup) }
        marker.popup = nil
        page.removeAnnotation(marker)
    }
    static func removeContainers(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            for annotation in page.annotations where isOpacityContainer(annotation) { removeContainer(annotation, from: page) }
        }
    }
    static func restore(_ document: PDFDocument) {
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let annotations = page.annotations.filter { !isContainer($0) }
            let containers = page.annotations.filter(isOpacityContainer)
            var used = Set<Int>()
            for marker in containers where marker.type != "Popup" {
                guard let contents = marker.contents,
                      let data = Data(base64Encoded: String(contents.dropFirst(prefix.count))),
                      let entries = try? JSONDecoder().decode([Entry].self, from: data) else { continue }
                for entry in entries {
                    let currentOrigin = page.bounds(for: .mediaBox).origin,oldOrigin = entry.mediaOrigin ?? currentOrigin
                    let dx = currentOrigin.x-oldOrigin.x,dy = currentOrigin.y-oldOrigin.y
                    func matches(_ i: Int) -> Bool {
                        guard annotations.indices.contains(i), !used.contains(i), annotations[i].type == entry.subtype else { return false }
                        let bounds = annotations[i].bounds
                        return hypot(bounds.midX - entry.center.x-dx, bounds.midY - entry.center.y-dy) < 8
                    }
                    guard let match = matches(entry.index) ? entry.index : annotations.indices.first(where: matches) else { continue }
                    let annotation = annotations[match]; used.insert(match)
                    var record = entry.record
                    if var measure = record.measurement { measure.points = measure.points.map { CGPoint(x: $0.x+dx,y: $0.y+dy) }; record.measurement = measure }
                    records.setObject(Box(record), forKey: annotation)
                    if annotation.type != "Stamp" { annotation.removeValue(forAnnotationKey: .appearanceDictionary) }
                    if annotation.type == "FreeText" {
                        annotation.color = .clear
                        annotation.fontColor = (annotation.fontColor ?? .black).withAlphaComponent(CGFloat(entry.record.opacity))
                    } else { annotation.color = annotation.color.withAlphaComponent(CGFloat(entry.record.opacity)) }
                }
            }
            for marker in containers { removeContainer(marker, from: page) }
        }
    }
    static func transfer(from originals: [PDFAnnotation], to copies: [PDFAnnotation]) {
        var groups: [String: String] = [:]
        for (original, duplicate) in zip(originals, copies) {
            guard var record = records.object(forKey: original)?.record else { continue }
            record.id = UUID().uuidString
            if let group = record.group {
                let copied = groups[group] ?? UUID().uuidString; groups[group] = copied; record.group = copied
            }
            records.setObject(Box(record), forKey: duplicate)
        }
    }
    static func copy(from source: PDFPage, to destination: PDFPage) {
        let old = source.annotations.filter { !isContainer($0) }
        for marker in destination.annotations where isOpacityContainer(marker) { removeContainer(marker, from: destination) }
        transfer(from: old, to: destination.annotations.filter { !isContainer($0) })
    }

}

private enum ViewerCommand: Equatable {
    case refresh, zoomIn, zoomOut, actualSize, fitPage, fitWidth, rotate(Int), page(Int), highlight, underline, insertBlankPage, deletePage, duplicatePage, print, applyAnnotationStyle
    case strike, destination(PDFDestination), feature(String), history(Int)
    case setZoom(CGFloat)
    case copy, cut, paste, deleteSelection
    case deletePageAt(Int), duplicatePageAt(Int), copyPageAt(Int), pastePagesAt(Int), blankPageAt(Int), rotatePageAt(Int,Int)
}

private enum RibbonAction {
    case feature(String)
    case open, save, saveAs, close, print, settings
    case tool(PDFTool), layout(PageLayout), zoomIn, zoomOut, actualSize, fitPage, fitWidth
    case rotateLeft, rotateRight, previous, next, first, last, highlight, toggleLanguage, toggleRulers
    case panels, languagePicker, themePicker, about, support, telegram, underline, insertBlankPage, deletePage, duplicatePage, copy, cut, paste, deleteSelection, development
}

@MainActor
private extension DocumentManager {
    func thumbnailTarget(for action: RibbonAction) -> ((any PDFThumbnailCommandTarget), String)? {
        guard let target = NSApp.keyWindow?.firstResponder as? any PDFThumbnailCommandTarget,
              target.thumbnailDocumentID == selected?.id else { return nil }
        let command: String
        switch action {
        case .copy: command = "copy"
        case .cut: command = "cut"
        case .paste: command = "paste"
        case .deleteSelection: command = "delete"
        default: return nil
        }
        return (target, command)
    }
    func canPerform(_ action: RibbonAction) -> Bool {
        if let (target, command) = thumbnailTarget(for: action) { return target.canPerformThumbnailCommand(command) }
        switch action {
        case .open,.settings,.toggleLanguage,.toggleRulers,.panels,.languagePicker,.themePicker,.about,.support,.telegram: return true
        case .feature(let id) where ["license","updates","blank","fromFiles","scanner","newWindow","customize","spacing","logs"].contains(id): return true
        default: break
        }
        guard let item = selected,!item.document.isLocked else { return false }
        let editable = item.document.allowsDocumentChanges
        let commenting = item.document.allowsCommenting
        switch action {
        case .feature("background"), .feature("margins"): return editable
        case .feature("header"), .feature("watermark"), .feature("bates"): return editable && commenting
        case .feature("images"): return item.document.allowsCopying
        case .feature("signature"), .feature("initials"), .feature("stamp"): return editable
        case .feature("historyBack"): return item.navigation.canBack
        case .feature("historyForward"): return item.navigation.canForward
        case .feature("extract"), .feature("split"): return item.document.allowsCopying && operationTask == nil
        case .feature("swap"): return editable && item.pageCount > 1 && operationTask == nil
        case .previous,.first: return item.pageIndex > 0
        case .next,.last: return item.pageIndex+1 < item.pageCount
        case .deletePage: return editable && item.pageCount > 1
        case .print: return item.document.allowsPrinting
        case .copy: return item.document.allowsCopying && (selectedAnnotation != nil || contentProperties.active || hasTextSelection || textProperties.active)
        case .cut,.deleteSelection: return (editable && (contentProperties.active || textProperties.active)) || (commenting && selectedAnnotation != nil)
        case .paste: return editable && clipboardAvailable
        case .highlight,.underline: return commenting
        case .tool(let tool):
            if [.hand,.textSelection].contains(tool) { return true }
            if tool == .snapshot { return item.document.allowsCopying && operationTask == nil }
            if [.editText,.editContent,.addText].contains(tool) { return editable }
            return commenting
        case .insertBlankPage,.duplicatePage,.rotateLeft,.rotateRight: return editable
        case .feature("undo"): return !item.undoHistory.isEmpty || (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canUndo == true
        case .feature("redo"): return !item.redoHistory.isEmpty || (NSApp.keyWindow?.firstResponder as? NSTextView)?.undoManager?.canRedo == true
        default: return true
        }
    }
    func refreshClipboard() {
        let board = NSPasteboard.general
        let available = board.availableType(from: [ObjectClipboard.contentObject,ObjectClipboard.annotations,ObjectClipboard.sourceText,.string]) != nil
        if clipboardAvailable != available { clipboardAvailable = available }
    }
}

private struct RibbonCommand: Identifiable {
    let id: String
    let title: Bilingual
    let symbol: String
    let action: RibbonAction
    init(_ id: String, _ en: String, _ ru: String, _ symbol: String, _ action: RibbonAction = .development) {
        self.id = id; title = Bilingual(en: en, ru: ru); self.symbol = symbol; self.action = action
    }
}

private struct RibbonGroupSpec: Identifiable {
    let id: String
    let title: Bilingual
    let commands: [RibbonCommand]
    init(_ id: String, _ en: String, _ ru: String, _ commands: [RibbonCommand]) {
        self.id = id; title = Bilingual(en: en, ru: ru); self.commands = commands
    }
}

// AppKit owns the application lifecycle and Finder Apple Events. SwiftUI is
// used exclusively for the hosted workspace, without SwiftUI App discovery.
@main
@MainActor
struct BotPlusPDFEditorApp {
    static func main() {
        AppDiagnostics.shared?.startSession()
        AppDiagnostics.shared?.captureStandardError()
        let application = NSApplication.shared
        let delegate = BotPlusAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class BotPlusAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let manager = DocumentManager()
    private var workspace: NSWindow?
    private var pendingURLs: [URL] = []
    private var launched = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDiagnostics.record("application_did_finish_launching")
        launched = true
        rebuildMenus()
        showWorkspace()
        let urls = pendingURLs
        pendingURLs.removeAll()
        receive(urls)
        restoreUpdateRecovery()
        if let bookmarks = UserDefaults.standard.array(forKey: "BotPlus.update.pendingFiles") as? [Data] {
            let files = bookmarks.compactMap { data -> URL? in
                var stale = false
                return try? URL(resolvingBookmarkData: data,options: .withSecurityScope,relativeTo: nil,bookmarkDataIsStale: &stale)
            }
            UserDefaults.standard.removeObject(forKey: "BotPlus.update.pendingFiles"); receive(files)
        }
        AppUpdateController.shared.onAvailable = { [weak self] in
            guard let self, self.workspace?.isVisible == true, self.workspace?.attachedSheet == nil else { return false }
            self.manager.isUpdatePresented = true
            return true
        }
        AppUpdateController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppDiagnostics.shared?.finishSession()
        AppDiagnostics.shared?.stopCapturingStandardError()
    }

    // Finder double-click, Open With, multiple-file selection and Dock drops
    // all arrive here, including before applicationDidFinishLaunching.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard launched else { pendingURLs.append(contentsOf: urls); return }
        receive(urls)
    }

    private func receive(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        if AppUpdateController.shared.installing { pendingURLs.append(contentsOf: urls); return }
        showWorkspace()
        // Defer model publication until after Apple Event/window processing.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for url in urls where url.isFileURL { self.manager.openAsync(url) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !AppUpdateController.shared.installing else { return false }
        showWorkspace()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let updater = AppUpdateController.shared
        guard updater.installationArmed else {
            let owners = [manager]+(manager.splitManager.map { [$0] } ?? [])+PDFWindowPool.shared.allManagers
            guard owners.allSatisfy({ $0.loadingFiles == 0 && $0.operationTask == nil && $0.finishSourceEditing?() != false }) else { manager.say("Finish or cancel document operations before quitting.","Завершите или отмените операции перед выходом."); return .terminateCancel }
            var seen = Set<UUID>()
            let dirty = owners.flatMap(\.documents).filter { seen.insert($0.store.id).inserted && $0.store.hasChanges }
            guard !dirty.isEmpty else { return .terminateNow }
            let alert = NSAlert(); alert.messageText = manager.language == .ru ? "Выйти без сохранения изменений?" : "Quit without saving changes?"
            alert.informativeText = dirty.map(\.filename).joined(separator: "\n")
            alert.addButton(withTitle: manager.language == .ru ? "Отмена" : "Cancel"); alert.addButton(withTitle: manager.language == .ru ? "Выйти без сохранения" : "Quit without saving")
            guard let window = NSApp.keyWindow ?? workspace,window.attachedSheet == nil else { return .terminateCancel }
            alert.beginSheetModal(for: window) { response in sender.reply(toApplicationShouldTerminate: response == .alertSecondButtonReturn) }
            return .terminateLater
        }
        guard !updater.installing else { return .terminateCancel }
        let owners = [manager] + (manager.splitManager.map { [$0] } ?? []) + PDFWindowPool.shared.allManagers
        guard owners.allSatisfy({ $0.loadingFiles == 0 && $0.operationTask == nil && $0.finishSourceEditing?() != false }) else {
            manager.say("Finish or cancel document operations before installing an update.","Завершите или отмените операции с документами перед установкой обновления.")
            return .terminateCancel
        }
        let hidden = sender.windows.filter { $0.isVisible }
        hidden.forEach { $0.orderOut(nil) }
        Task { @MainActor in
            var recoveryPrepared = false
            do {
                try preserveUpdateRecovery(owners)
                recoveryPrepared = true
                try await updater.installOnQuit()
                if !pendingURLs.isEmpty {
                    let bookmarks = pendingURLs.compactMap { try? $0.bookmarkData(options: .withSecurityScope,includingResourceValuesForKeys: nil,relativeTo: nil) }
                    UserDefaults.standard.set(bookmarks,forKey: "BotPlus.update.pendingFiles")
                }
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                if recoveryPrepared { try? FileManager.default.removeItem(at: recoveryRoot.appendingPathComponent("pending.txt")); UserDefaults.standard.removeObject(forKey: "BotPlus.update.recovery") }
                updater.installationFailed(error.localizedDescription)
                sender.reply(toApplicationShouldTerminate: false)
                hidden.forEach { $0.makeKeyAndOrderFront(nil) }
                DispatchQueue.main.async { self.manager.isUpdatePresented = true; let urls = self.pendingURLs; self.pendingURLs.removeAll(); self.receive(urls) }
            }
        }
        return .terminateLater
    }

    private struct RecoveredPDF: Codable {
        var file: String; var original: URL; var name: String?; var source: UUID?; var untitled: Bool; var page: Int; var zoom: CGFloat
    }
    private var recoveryRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory,in: .userDomainMask)[0].appendingPathComponent("BotPlusUpdateRecovery",isDirectory: true)
    }
    private func preserveUpdateRecovery(_ owners: [DocumentManager]) throws {
        guard owners.reduce(0,{ $0+$1.documents.count }) <= 1000 else { throw UpdateFailure.invalid("Слишком много открытых документов для обновления / Too many open documents for update recovery") }
        let fm = FileManager.default, root = recoveryRoot
        try fm.createDirectory(at: root,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        let batch = root.appendingPathComponent(UUID().uuidString,isDirectory: true)
        try fm.createDirectory(at: batch,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
        var records: [RecoveredPDF] = [], committed = false
        defer { if !committed { try? fm.removeItem(at: batch) } }
        for owner in owners { for item in owner.documents {
            let name = UUID().uuidString+".pdf"
            try owner.serializedData(item).write(to: batch.appendingPathComponent(name),options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600],ofItemAtPath: batch.appendingPathComponent(name).path)
            records.append(.init(file: name,original: item.url,name: item.filename,source: item.store.id,untitled: item.isUntitled,page: item.pageIndex,zoom: item.zoom))
        } }
        try JSONEncoder().encode(records).write(to: batch.appendingPathComponent("documents.json"),options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600],ofItemAtPath: batch.appendingPathComponent("documents.json").path)
        try Data(batch.lastPathComponent.utf8).write(to: root.appendingPathComponent("pending.txt"),options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600],ofItemAtPath: root.appendingPathComponent("pending.txt").path)
        committed = true
    }
    private func restoreUpdateRecovery() {
        guard let name = (try? String(contentsOf: recoveryRoot.appendingPathComponent("pending.txt"),encoding: .utf8)) ?? UserDefaults.standard.string(forKey: "BotPlus.update.recovery"), UUID(uuidString: name) != nil else { return }
        let batch = recoveryRoot.appendingPathComponent(name,isDirectory: true)
        do {
            let records = try JSONDecoder().decode([RecoveredPDF].self,from: Data(contentsOf: batch.appendingPathComponent("documents.json")))
            guard records.count <= 1000 else { return }
            var recovered: [PDFDocumentItem] = []
            var shared: [UUID:SharedPDFDocument] = [:]
            for record in records {
                guard record.file.range(of: "^[A-Fa-f0-9-]{36}\\.pdf$",options: .regularExpression) != nil,
                      let document = PDFDocument(url: batch.appendingPathComponent(record.file)) else { throw PDFSourceError.document }
                AnnotationMetadata.restore(document)
                // Recovery becomes an untitled copy: saving cannot overwrite an original silently.
                let item: PDFDocumentItem
                if let id = record.source,let store = shared[id] { item = PDFDocumentItem(shared: store,page: record.page,zoom: record.zoom) }
                else {
                    item = PDFDocumentItem(url: record.original,document: document,preserveStreams: true)
                    item.rootSourceData = try Data(contentsOf: batch.appendingPathComponent(record.file))
                    if let id = record.source { shared[id] = item.store }
                }
                item.isUntitled = true; item.recoveredFilename = record.name ?? record.original.lastPathComponent; item.pageIndex = min(max(0,record.page),max(0,document.pageCount-1)); item.zoom = record.zoom.isFinite ? record.zoom : 1
                recovered.append(item)
            }
            for item in recovered { manager.restoreRecovered(item) }
            try? FileManager.default.removeItem(at: recoveryRoot.appendingPathComponent("pending.txt"))
            UserDefaults.standard.removeObject(forKey: "BotPlus.update.recovery")
            if !records.isEmpty { DispatchQueue.main.async { [weak self] in self?.manager.say("Open PDFs restored as unsaved copies. Save As keeps your originals intact.","Открытые PDF восстановлены как несохранённые копии. Сохраните их через «Сохранить как».") } }
        } catch { DispatchQueue.main.async { [weak self] in self?.manager.say("Recovery files remain in Application Support/BotPlusUpdateRecovery.","Файлы восстановления сохранены в Application Support/BotPlusUpdateRecovery.") } }
    }

    private func showWorkspace() {
        if workspace == nil {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1380, height: 880),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = BotPlusBrand.name
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 1060, height: 700)
            window.contentView = NSHostingView(rootView: ContentView(manager: manager)
                .frame(minWidth: 1060, minHeight: 700))
            window.center()
            window.setFrameAutosaveName("BotPlusWorkspace")
            workspace = window
        }
        if workspace?.isMiniaturized == true { workspace?.deminiaturize(nil) }
        workspace?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func rebuildMenus() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: title)
            item.submenu = submenu; main.addItem(item)
            return submenu
        }
        func text(_ en: String, _ ru: String) -> String { manager.language == .ru ? ru : en }
        func command(_ menu: NSMenu, _ en: String, _ ru: String, _ key: String,
                     _ action: RibbonAction, shift: Bool = false) {
            let item = NSMenuItem(title: text(en, ru), action: #selector(runCommand(_:)), keyEquivalent: key)
            item.target = self; item.representedObject = action
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : [.command]
            menu.addItem(item)
        }
        func responder(_ menu: NSMenu, _ en: String, _ ru: String, _ key: String, _ selector: Selector) {
            menu.addItem(NSMenuItem(title: text(en, ru), action: selector, keyEquivalent: key))
        }
        let app = menu(BotPlusBrand.name)
        command(app, "About BotPlus PDF Editor", "О программе BotPlus PDF Editor", "", .about)
        command(app, "Settings…", "Настройки…", ",", .settings)
        command(app, "Customize Ribbon…", "Настроить ленту…", "", .feature("customize"))
        command(app, "Updates…", "Обновления…", "", .feature("updates"))
        app.addItem(.separator())
        let services = NSMenu(title: text("Services", "Службы"))
        let servicesItem = NSMenuItem(title: services.title, action: nil, keyEquivalent: "")
        servicesItem.submenu = services; app.addItem(servicesItem); NSApp.servicesMenu = services
        app.addItem(.separator())
        responder(app, "Hide BotPlus PDF Editor", "Скрыть BotPlus PDF Editor", "h", #selector(NSApplication.hide(_:)))
        let hideOthers = NSMenuItem(title: text("Hide Others", "Скрыть остальные"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]; app.addItem(hideOthers)
        responder(app, "Show All", "Показать все", "", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        responder(app, "Quit BotPlus PDF Editor", "Завершить BotPlus PDF Editor", "q", #selector(NSApplication.terminate(_:)))
        let file = menu(text("File", "Файл"))
        command(file, "New Blank PDF", "Создать пустой PDF", "n", .feature("blank"))
        command(file, "Open PDF…", "Открыть PDF…", "o", .open)
        file.addItem(.separator())
        command(file, "Save", "Сохранить", "s", .save)
        command(file, "Save As…", "Сохранить как…", "s", .saveAs, shift: true)
        command(file, "Print…", "Печать…", "p", .print)
        responder(file, "Close Window", "Закрыть окно", "w", #selector(NSWindow.performClose(_:)))
        let edit = menu(text("Edit", "Правка"))
        command(edit, "Undo", "Отменить", "z", .feature("undo"))
        command(edit, "Redo", "Повторить", "z", .feature("redo"), shift: true)
        edit.addItem(.separator())
        command(edit, "Cut", "Вырезать", "x", .cut)
        command(edit, "Copy", "Копировать", "c", .copy)
        command(edit, "Paste", "Вставить", "v", .paste)
        responder(edit, "Select All", "Выделить всё", "a", #selector(NSText.selectAll(_:)))
        edit.addItem(.separator())
        command(edit, "Find in PDF…", "Найти в PDF…", "f", .feature("search"))
        let window = menu(text("Window", "Окно"))
        responder(window, "Minimize", "Свернуть", "m", #selector(NSWindow.performMiniaturize(_:)))
        responder(window, "Zoom", "Развернуть", "", #selector(NSWindow.performZoom(_:)))
        window.addItem(.separator())
        responder(window, "Bring All to Front", "Все окна на передний план", "", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
        let help = menu(text("Help", "Помощь"))
        command(help, "Open Logs Folder", "Открыть папку логов", "", .feature("logs"))
        command(help, "Support", "Поддержка", "", .support)
        command(help, "Telegram", "Телеграм", "", .telegram)
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }

    private var commandManager: DocumentManager {
        PDFWindowPool.shared.manager(for: NSApp.keyWindow) ?? manager
    }

    @objc private func runCommand(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? RibbonAction else { return }
        if let thumbnails = NSApp.keyWindow?.firstResponder as? any PDFThumbnailCommandTarget {
            switch action {
            case .copy: thumbnails.performThumbnailCommand("copy"); return
            case .cut: thumbnails.performThumbnailCommand("cut"); return
            case .paste: thumbnails.performThumbnailCommand("paste"); return
            default: break
            }
        }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            switch action {
            case .copy: editor.copy(sender); return
            case .cut: editor.cut(sender); return
            case .paste: editor.paste(sender); return
            case .feature("undo") where editor.undoManager?.canUndo == true: editor.undoManager?.undo(); return
            case .feature("redo") where editor.undoManager?.canRedo == true: editor.undoManager?.redo(); return
            default: break
            }
        }
        let active = commandManager
        active.refreshClipboard()
        active.perform(action)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if AppUpdateController.shared.installing { return false }
        guard let action = item.representedObject as? RibbonAction else { return true }
        if let thumbnails = NSApp.keyWindow?.firstResponder as? any PDFThumbnailCommandTarget {
            switch action {
            case .copy: return thumbnails.canPerformThumbnailCommand("copy")
            case .cut: return thumbnails.canPerformThumbnailCommand("cut")
            case .paste: return thumbnails.canPerformThumbnailCommand("paste")
            default: break
            }
        }
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
            switch action {
            case .copy: return editor.selectedRange().length > 0
            case .cut: return editor.isEditable && editor.selectedRange().length > 0
            case .paste: return editor.isEditable && NSPasteboard.general.canReadItem(withDataConformingToTypes: [UTType.text.identifier])
            case .feature("undo") where editor.undoManager?.canUndo == true: return true
            case .feature("redo") where editor.undoManager?.canRedo == true: return true
            default: break
            }
        }
        return commandManager.canPerform(action)
    }
}

@MainActor
private struct ContentView: View {
    @StateObject private var manager: DocumentManager
    init(manager: DocumentManager = DocumentManager()) { _manager = StateObject(wrappedValue: manager) }

    var body: some View {
        VStack(spacing: 0) {
            QuickBar(manager: manager.activePane)
            RibbonView(manager: manager.activePane)
            DocumentTabs(manager: manager)
            WorkspaceArea(manager: manager).onDrop(of: [UTType.fileURL], isTargeted: nil, perform: receivePDFs)
            StatusBar(manager: manager.activePane)
        }
        .overlay(alignment: .bottomTrailing) {
            if let progress = manager.operationProgress {
                HStack(spacing: 10) {
                    VStack(alignment: .leading) {
                        Text(manager.operationTitle).font(.caption)
                        ProgressView(value: progress).frame(width: 170)
                    }
                    Button(manager.language == .ru ? "Отменить" : "Cancel") { manager.operationTask?.cancel() }
                }.padding(12).background(Palette.panel, in: RoundedRectangle(cornerRadius: 6)).padding(30)
            } else if manager.loadingFiles > 0 { HStack { ProgressView().controlSize(.small); Text(manager.language == .ru ? "Открытие PDF…" : "Opening PDF…").font(.system(size: 11)) }.padding(9).background(Palette.panel,in: RoundedRectangle(cornerRadius: 5)).padding(30) }
        }
        .background(Palette.ribbon)
        .background(WindowTitleSynchronizer(title: manager.title).frame(width: 0, height: 0))
        .background(WindowChromeConfigurator(theme: manager.theme).frame(width: 0, height: 0))
        .foregroundStyle(Palette.text)
        .preferredColorScheme(manager.theme.colorScheme)
        .environment(\.locale,Locale(identifier: manager.language == .ru ? "ru_RU" : "en_US"))
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { manager.refreshClipboard() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in manager.refreshClipboard() }
        .onReceive(manager.panels.$configurations) { _ in
            manager.panels.synchronizeFloatingWindows(manager: manager)
        }
        .onChange(of: manager.language) { _, _ in
            manager.panels.synchronizeFloatingWindows(manager: manager)
            DispatchQueue.main.async { (NSApp.delegate as? BotPlusAppDelegate)?.rebuildMenus() }
        }
        .onChange(of: manager.theme) { _, _ in manager.panels.synchronizeFloatingWindows(manager: manager) }
        .modifier(WorkspaceSheets(manager: manager))
    }

    private func receivePDFs(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in manager.openAsync(url) }
            }
        }
        return accepted
    }
}

private struct WindowTitleSynchronizer: NSViewRepresentable {
    let title: String
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let nextTitle = title
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, window.title != nextTitle else { return }
            window.title = nextTitle
        }
    }
}

private struct WindowChromeConfigurator: NSViewRepresentable {
    let theme: AppTheme
    func makeNSView(context: Context) -> WindowChromeView {
        let view = WindowChromeView(frame: .zero); view.theme = theme; return view
    }
    func updateNSView(_ view: WindowChromeView, context: Context) { view.theme = theme; DispatchQueue.main.async { [weak view] in view?.configureWindow() } }

    @MainActor
    final class WindowChromeView: NSView {
        var theme: AppTheme = .dark
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in self?.configureWindow() }
        }
        private var configuredWindow: ObjectIdentifier?
        private var configuredTheme: AppTheme?
        func configureWindow() {
            guard let window else { return }
            guard configuredWindow != ObjectIdentifier(window) || configuredTheme != theme else { return }
            configuredWindow = ObjectIdentifier(window); configuredTheme = theme
            window.appearance = theme.appearance
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.backgroundColor = NSColor(calibratedWhite: theme.isDark ? 0.125 : 0.91, alpha: 1)
        }
    }
}

/// Uses the same artwork as the Dock/Finder icon from the bundled asset catalog.
struct AppIconPreviewView: View {
    var body: some View {
        Image("BrandIcon")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .accessibilityLabel("BotPlus PDF Editor app icon")
    }
}

private struct AboutDialog: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 14) {
            AppIconPreviewView().frame(width: 112, height: 112)
            Text(BotPlusBrand.name).font(.system(size: 20, weight: .semibold))
            Text("\(manager.language == .ru ? "Версия" : "Version") \(BotPlusBrand.version)").font(.system(size: 12)).foregroundStyle(Palette.muted)
            Text(BotPlusBrand.copyright).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Button(manager.language == .ru ? "Закрыть" : "Close") { manager.isAboutPresented = false }
                .keyboardShortcut(.defaultAction)
        }
        .padding(26).frame(width: 360).background(Palette.ribbon)
        .preferredColorScheme(manager.theme.colorScheme)
    }
}

private struct QuickBar: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        ZStack {
            Text(manager.title).font(.system(size: 12, weight: .medium)).lineLimit(1).frame(maxWidth: 440).frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                Color.clear.frame(width: 78, height: 1)
                AppIconPreviewView().frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 4)).padding(.horizontal, 2)
                quick("Open", "Открыть", "folder", .open)
                quick("Save", "Сохранить", "botplus.floppy", .save)
                quick("Print", "Печать", "printer", .print)
                Hairline(height: 20)
                quick("Undo", "Отменить", "arrow.uturn.backward", .feature("undo"))
                quick("Redo", "Повторить", "arrow.uturn.forward", .feature("redo"))
                quick("Back", "Назад", "chevron.left", .feature("historyBack"))
                quick("Forward", "Вперёд", "chevron.right", .feature("historyForward"))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    SystemSymbolImage(name: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField(manager.language == .ru ? "Поиск / Быстрый поиск…" : "Search / Quick Search…", text: $manager.searchText, onCommit: { manager.runSearch() })
                        .textFieldStyle(.plain).frame(width: 158).disabled(manager.selected == nil)
                }.padding(.horizontal, 8).frame(height: 25).background(Palette.raised, in: RoundedRectangle(cornerRadius: 4)).padding(.trailing, 10)
            }
        }
        .frame(height: 40).background(Palette.chrome)
        .overlay(alignment: .bottom) { Palette.separator.frame(height: 1) }
    }

    private func quick(_ en: String, _ ru: String, _ symbol: String, _ action: RibbonAction) -> some View {
        QuickIcon(en, ru, symbol, language: manager.language) { manager.perform(action) }.disabled(!manager.canPerform(action)).opacity(manager.canPerform(action) ? 1 : 0.35)
    }
}

private struct QuickIcon: View {
    let en: String; let ru: String; let symbol: String; let action: () -> Void
    let language: AppLanguage
    init(_ en: String, _ ru: String, _ symbol: String, language: AppLanguage, action: @escaping () -> Void) {
        self.en = en; self.ru = ru; self.symbol = symbol; self.language = language; self.action = action
    }
    var body: some View {
        Button(action: action) {
            Group {
                if symbol == "botplus.floppy" { FloppyDiskSymbol().stroke(style: StrokeStyle(lineWidth: 1.3, lineJoin: .round)).frame(width: 14, height: 14) }
                else { SystemSymbolImage(name: symbol).font(.system(size: 12)) }
            }.frame(width: 24, height: 24)
        }
            .buttonStyle(.plain).foregroundStyle(Palette.text).help(language == .ru ? ru : en).accessibilityLabel(language == .ru ? ru : en)
    }
}

// Resolve once per symbol on this OS before SwiftUI renders it. This avoids
// blank icons and repeated SwiftUI warnings on older supported macOS versions.
@MainActor
private enum SystemSymbolCatalog {
    private static var resolved: [String: String] = [:]
    static func name(_ requested: String) -> String {
        if let cached = resolved[requested] { return cached }
        let available = NSImage(systemSymbolName: requested, accessibilityDescription: nil) != nil
        let result = available ? requested : "questionmark.square"
        resolved[requested] = result
        return result
    }
}

private struct SystemSymbolImage: View {
    let name: String
    var body: some View { Image(systemName: SystemSymbolCatalog.name(name)) }
}

private struct BookmarkAddSymbol: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: SystemSymbolCatalog.name("bookmark")).resizable().scaledToFit().frame(width: 15, height: 21)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Image(systemName: SystemSymbolCatalog.name("plus.circle.fill")).resizable().scaledToFit().frame(width: 11, height: 11)
                .background(Palette.ribbon, in: Circle())
        }.accessibilityHidden(true)
    }
}

private struct FloppyDiskSymbol: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.width / 16, y = rect.height / 16
        func point(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: rect.minX + px * x, y: rect.minY + py * y) }
        var path = Path(); path.move(to: point(1, 1)); path.addLine(to: point(11, 1))
        path.addLine(to: point(15, 5)); path.addLine(to: point(15, 15)); path.addLine(to: point(1, 15)); path.closeSubpath()
        path.addRect(CGRect(x: rect.minX + 4*x, y: rect.minY + y, width: 6*x, height: 5*y))
        path.addRect(CGRect(x: rect.minX + 4*x, y: rect.minY + 9*y, width: 8*x, height: 6*y))
        return path
    }
}

private struct RibbonView: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var profile = RibbonProfile.shared
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(RibbonTab.allCases) { tab in
                        Button { manager.tab = tab } label: {
                            Text(manager.text(tab.title)).font(.system(size: 12, weight: manager.tab == tab ? .semibold : .regular))
                                .foregroundStyle(tab == .file ? Color.white : Palette.text)
                                .lineLimit(1).frame(width: tabWidth(tab), height: 33)
                                .background(tab == .file ? Palette.file : (manager.tab == tab ? Palette.selected : .clear))
                                .overlay(alignment: .bottom) { if manager.tab == tab && tab != .file { Palette.accent.frame(height: 2) } }
                        }.buttonStyle(.plain).help(manager.text(tab.title))
                    }
                }.padding(.horizontal, 5)
            }.frame(height: 34)
            Palette.separator.frame(height: 1)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(displayGroups, id: \.id) { group in RibbonGroupView(group: group, manager: manager) }
                }.padding(.horizontal, 6)
            }.frame(height: 91)
            Palette.separator.frame(height: 1)
        }.background(Palette.ribbon)
    }

    private var displayGroups: [RibbonGroupSpec] {
        let all = Self.groups(for: manager.tab), key = String(describing: manager.tab)
        return profile.ordered(all.map(\.id),scope: key).compactMap { id in
            guard let group = all.first(where: { $0.id == id }), profile.visible(key+"/"+id) else { return nil }
            let commands = profile.ordered(group.commands.map(\.id),scope: key+"/"+id).compactMap { commandID in
                group.commands.first { $0.id == commandID && profile.visible(key+"/"+id+"/"+commandID) }
            }
            return commands.isEmpty ? nil : RibbonGroupSpec(group.id,group.title.en,group.title.ru,commands)
        }
    }

    private func tabWidth(_ tab: RibbonTab) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let width = (manager.text(tab.title) as NSString).size(withAttributes: [.font: font]).width
        return max(50, ceil(width) + (tab == .file ? 28 : 20))
    }

    fileprivate static func groups(for tab: RibbonTab) -> [RibbonGroupSpec] {
                let tool = { (id: String, en: String, ru: String, icon: String, value: PDFTool) in RibbonCommand(id, en, ru, icon, .tool(value)) }
        let cmd = { (id: String, en: String, ru: String, icon: String) in RibbonCommand(id, en, ru, icon, .feature(id)) }
        switch tab {
        case .file:
            return [RibbonGroupSpec("file", "Document", "Документ", [
                RibbonCommand("open", "Open", "Открыть", "folder", .open), RibbonCommand("save", "Save", "Сохранить", "botplus.floppy", .save),
                RibbonCommand("saveAs", "Save As", "Сохранить как", "square.and.arrow.up", .saveAs), RibbonCommand("close", "Close", "Закрыть", "xmark", .close),
                RibbonCommand("print", "Print", "Печать", "printer", .print), RibbonCommand("settings", "Settings", "Настройки", "gearshape", .settings)
            ])]
        case .home:
            return [
                RibbonGroupSpec("tools", "Tools", "Инструменты", [tool("hand", "Hand", "Рука", "hand.raised", .hand), tool("text", "Select Text", "Выделить текст", "text.cursor", .textSelection), tool("selectComments", "Select Comments", "Выделить комментарии", "cursorarrow", .selectComments), tool("snapshot", "Snapshot", "Снимок", "camera.viewfinder", .snapshot)]),
                RibbonGroupSpec("view", "View", "Вид", [RibbonCommand("zoomOut", "Zoom Out", "Уменьшить", "minus.magnifyingglass", .zoomOut), RibbonCommand("actual", "Actual Size 1:1", "Реальный размер 1:1", "1.magnifyingglass", .actualSize), RibbonCommand("zoomIn", "Zoom In", "Увеличить", "plus.magnifyingglass", .zoomIn), RibbonCommand("fitWidth", "Fit Width", "По ширине", "arrow.left.and.right", .fitWidth), RibbonCommand("rotateLeft", "Rotate 90° CCW", "Повернуть на 90° влево", "rotate.left", .rotateLeft), RibbonCommand("rotateRight", "Rotate 90° CW", "Повернуть на 90° вправо", "rotate.right", .rotateRight)]),
                RibbonGroupSpec("objects", "Objects", "Объекты", [tool("addText", "Add Text", "Добавить текст", "text.badge.plus", .addText), tool("editText", "Edit PDF Text", "Редактировать текст", "character.cursor.ibeam", .editText), tool("editContent", "Content Editor", "Редактор содержимого", "cursorarrow.square", .editContent), RibbonCommand("pasteObject", "Paste", "Вставить", "doc.on.clipboard", .paste), RibbonCommand("copyObject", "Copy", "Копировать", "doc.on.doc", .copy), RibbonCommand("cutObject", "Cut", "Вырезать", "scissors", .cut), RibbonCommand("deleteObject", "Delete", "Удалить", "trash", .deleteSelection), cmd("addImage", "Add Image", "Добавить изображение", "photo.badge.plus")]),
                RibbonGroupSpec("comment", "Comment", "Комментарий", [tool("typewriter", "Text Box", "Текстовое поле", "character.cursor.ibeam", .typewriter), RibbonCommand("highlight", "Highlight Text", "Подсветить текст", "highlighter", .highlight), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline), cmd("stamp", "Stamp", "Штамп", "seal"), cmd("sticky", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("links", "Links", "Ссылки", [cmd("addLink", "Add Link", "Добавить ссылку", "link"), cmd("editLink", "Edit Links", "Изменить ссылки", "link.badge.plus")]),
                RibbonGroupSpec("security", "Security", "Защита", [cmd("sign", "Sign Document", "Подписать документ", "signature"), cmd("protect", "Protect", "Защитить", "lock.shield")])
            ]
        case .view:
            return [
                RibbonGroupSpec("navigation", "Navigation", "Навигация", [cmd("historyBack", "Previous View", "Предыдущий вид", "arrow.uturn.backward"), cmd("historyForward", "Next View", "Следующий вид", "arrow.uturn.forward"), RibbonCommand("prev", "Previous Page", "Предыдущая страница", "chevron.left", .previous), RibbonCommand("next", "Next Page", "Следующая страница", "chevron.right", .next), RibbonCommand("first", "First Page", "Первая страница", "backward.end", .first), RibbonCommand("last", "Last Page", "Последняя страница", "forward.end", .last)]),
                RibbonGroupSpec("zoom", "Zoom", "Масштаб", [RibbonCommand("actual", "1:1", "1:1", "1.magnifyingglass", .actualSize), RibbonCommand("zoomOut", "Zoom Out", "Уменьшить", "minus.magnifyingglass", .zoomOut), RibbonCommand("zoomIn", "Zoom In", "Увеличить", "plus.magnifyingglass", .zoomIn), RibbonCommand("fitPage", "Fit Page", "Вся страница", "arrow.down.right.and.arrow.up.left", .fitPage), RibbonCommand("fitWidth", "Fit Width", "По ширине", "arrow.left.and.right", .fitWidth), cmd("marquee", "Marquee Zoom", "Масштаб области", "viewfinder"), tool("snapshot", "Snapshot", "Снимок области", "camera.viewfinder", .snapshot)]),
                RibbonGroupSpec("display", "Page Display", "Отображение страниц", layoutCommands() + [cmd("spacing", "Page Spacing", "Зазор страниц", "rectangle.split.2x1"), RibbonCommand("rulers", "Rulers", "Линейки", "ruler", .toggleRulers)]),
                RibbonGroupSpec("window", "Window", "Окно", [RibbonCommand("panels", "Panels", "Панели", "sidebar.left", .panels), cmd("newWindow", "New Window", "Новое окно", "macwindow.badge.plus"), cmd("cascade", "Cascade", "Каскадом", "square.stack")]),
                RibbonGroupSpec("read", "Read Out Loud", "Чтение вслух", [cmd("read", "Read", "Читать", "speaker.wave.2"), cmd("pauseRead", "Pause", "Пауза", "pause.fill")])
            ]
        case .comment:
            return [
                RibbonGroupSpec("tools", "Tools", "Инструменты", [tool("hand", "Hand", "Рука", "hand.raised", .hand), tool("selectComments", "Select Comments", "Выбрать комментарии", "cursorarrow", .selectComments)]),
                RibbonGroupSpec("text", "Text", "Текст", [tool("textBox", "Text Box", "Текстовое поле", "text.alignleft", .typewriter), tool("callout", "Callout", "Выноска", "text.bubble", .callout)]),
                RibbonGroupSpec("note", "Note", "Заметка", [cmd("note", "Sticky Note", "Заметка", "note.text")]),
                RibbonGroupSpec("markup", "Text Markup", "Разметка текста", [RibbonCommand("highlight", "Highlight", "Подсветка", "highlighter", .highlight), cmd("strike", "Strikethrough", "Зачёркивание", "strikethrough"), RibbonCommand("underline", "Underline", "Подчёркивание", "underline", .underline)]),
                RibbonGroupSpec("drawing", "Drawing", "Рисование", [tool("line", "Line", "Линия", "line.diagonal", .line), tool("arrow", "Arrow", "Стрелка", "arrow.up.right", .arrow), tool("rect", "Rectangle", "Прямоугольник", "rectangle", .rectangle), tool("ellipse", "Ellipse", "Эллипс", "oval", .ellipse), cmd("cloud", "Cloud", "Облако", "cloud"), cmd("pencil", "Pencil", "Карандаш", "pencil.tip"), cmd("eraser", "Eraser", "Ластик", "eraser")]),
                RibbonGroupSpec("measure", "Measurement", "Измерение", [cmd("distance", "Distance", "Расстояние", "ruler"), cmd("perimeter", "Perimeter", "Периметр", "point.topleft.down.to.point.bottomright.curvepath"), cmd("area", "Area", "Площадь", "square.dashed"), cmd("scale", "Calibrate Scale", "Калибровать масштаб", "scale.3d"), cmd("measurementScale", "Measurement Scale", "Масштаб измерений", "slider.horizontal.3")]),
                RibbonGroupSpec("media", "Media", "Медиа", [cmd("audio", "Audio", "Аудио", "waveform"), cmd("video", "Video", "Видео", "video"), cmd("3d", "3D", "3D", "cube")]),
                RibbonGroupSpec("manage", "Comment Management", "Управление комментариями", [cmd("list", "Comments List", "Список комментариев", "list.bullet"), cmd("selectAllAnnotations", "Select on Page", "Выделить на странице", "square.dashed"), cmd("importComments", "Import", "Импорт", "square.and.arrow.down"), cmd("exportComments", "Export PDF", "Экспорт PDF", "square.and.arrow.up"), cmd("importCommentsXFDF", "Import XFDF", "Импорт XFDF", "arrow.down.doc"), cmd("exportCommentsXFDF", "Export XFDF", "Экспорт XFDF", "arrow.up.doc"), cmd("importCommentsFDF", "Import FDF", "Импорт FDF", "arrow.down.doc"), cmd("exportCommentsFDF", "Export FDF", "Экспорт FDF", "arrow.up.doc")])
            ]
        case .protect:
            return [RibbonGroupSpec("signatures", "Digital Signatures", "Цифровые подписи", [cmd("sign", "Sign Document", "Подписать документ", "signature"), cmd("verify", "Verify", "Проверить", "checkmark.seal")]),
                    RibbonGroupSpec("privacy", "Privacy (MS RMS)", "Конфиденциальность (MS RMS)", [cmd("rms", "Rights Management", "Управление правами", "lock.shield")]),
                    RibbonGroupSpec("initials", "Signatures & Initials", "Подписи и инициалы", [cmd("signature", "Signatures", "Подписи", "signature"), cmd("initials", "Initials", "Инициалы", "pencil.tip.crop.circle")]),
                    RibbonGroupSpec("redaction", "Redaction", "Редакция", [cmd("markRedact", "Mark for Redaction", "Пометить для удаления", "eye.slash"), cmd("applyRedact", "Apply All", "Применить всё", "checkmark.shield")]),
                    RibbonGroupSpec("security", "Document Security", "Безопасность документа", [cmd("password", "Password", "Пароль", "key.horizontal"), cmd("certificates", "Certificates", "Сертификаты", "checkmark.seal")]),
                    RibbonGroupSpec("docusign", "DocuSign", "DocuSign", [cmd("docusign", "Send for Signature", "Отправить на подпись", "paperplane")])]
        case .form:
            return [RibbonGroupSpec("fields", "Form Fields", "Поля формы", [cmd("textField", "Text Field", "Текстовое поле", "character.textbox"), cmd("checkbox", "Checkbox", "Флажок", "checkmark.square"), cmd("radio", "Radio Button", "Переключатель", "circle.inset.filled"), cmd("dropdown", "Dropdown", "Список", "chevron.down.square"), cmd("button", "Button", "Кнопка", "button.horizontal")]),
                    RibbonGroupSpec("field", "Fields", "Поля", [cmd("selectFields", "Select Fields", "Выбрать поля", "cursorarrow"), cmd("alignFields", "Align", "Выровнять", "align.horizontal.left"), cmd("formOrder", "Tab Order", "Порядок Tab", "list.number"), cmd("tabTraversal", "Tab Rule", "Правило Tab", "arrow.right.to.line"), cmd("validateForm", "Validate Form", "Проверить форму", "checkmark.seal")]),
                    RibbonGroupSpec("data", "Form Data", "Данные формы", [cmd("import", "Import", "Импорт", "square.and.arrow.down"), cmd("export", "Export", "Экспорт", "square.and.arrow.up"), cmd("clear", "Clear", "Очистить", "eraser"), cmd("importXFDF", "Import XFDF", "Импорт XFDF", "arrow.down.doc"), cmd("exportXFDF", "Export XFDF", "Экспорт XFDF", "arrow.up.doc"), cmd("importFDF", "Import FDF", "Импорт FDF", "arrow.down.doc"), cmd("exportFDF", "Export FDF", "Экспорт FDF", "arrow.up.doc")]),
                    RibbonGroupSpec("fill", "Fill Forms", "Заполнение форм", [cmd("fill", "Fill Form", "Заполнить форму", "pencil.line")]),
                    RibbonGroupSpec("javascript", "JavaScript Console", "Консоль JavaScript", [cmd("js", "JavaScript", "JavaScript", "curlybraces")])]
        case .organize:
            return [RibbonGroupSpec("pages", "Pages", "Страницы", [RibbonCommand("insert", "Insert Blank Page", "Вставить пустую страницу", "doc.badge.plus", .insertBlankPage), RibbonCommand("delete", "Delete Page", "Удалить страницу", "trash", .deletePage), RibbonCommand("duplicate", "Duplicate Page", "Дублировать страницу", "doc.on.doc", .duplicatePage), cmd("extract", "Extract", "Извлечь", "doc.zipper"), cmd("replace", "Replace", "Заменить", "arrow.2.squarepath"), cmd("split", "Split", "Разделить", "scissors"), cmd("swap", "Page Order", "Порядок страниц", "arrow.left.arrow.right")]),
                    RibbonGroupSpec("operations", "Page Operations", "Операции со страницей", [RibbonCommand("rotateLeft", "Rotate Left", "Повернуть влево", "rotate.left", .rotateLeft), RibbonCommand("rotateRight", "Rotate Right", "Повернуть вправо", "rotate.right", .rotateRight), cmd("crop", "Crop", "Обрезать", "crop.rotate"), cmd("resize", "Resize", "Изменить размер", "arrow.up.left.and.arrow.down.right"), cmd("margins", "Margins", "Поля", "rectangle.inset.filled")]),
                    RibbonGroupSpec("labeling", "Page Labeling", "Оформление страниц", [cmd("watermark", "Watermark", "Водяной знак", "drop"), cmd("background", "Background", "Фон", "rectangle.fill"), cmd("header", "Header/Footer", "Колонтитулы", "text.aligncenter"), cmd("bates", "Bates Numbering", "Нумерация Бейтса", "number")])]
        case .convert:
            return [RibbonGroupSpec("create", "Create", "Создать", [cmd("scanner", "From Scanner", "Со сканера", "scanner"), cmd("fromFiles", "From Files", "Из файлов", "doc.on.doc"), cmd("blank", "Blank", "Пустой документ", "doc.badge.plus")]),
                    RibbonGroupSpec("edit", "Edit", "Изменить", [cmd("edit", "Edit PDF", "Изменить PDF", "square.and.pencil")]),
                    RibbonGroupSpec("export", "Export", "Экспорт", [cmd("word", "To Word", "В Word", "doc.text"), cmd("excel", "To Excel", "В Excel", "tablecells"), cmd("powerpoint", "To PowerPoint", "В PowerPoint", "rectangle.on.rectangle"), cmd("images", "To Images", "В изображения", "photo")]),
                    RibbonGroupSpec("ocr", "OCR", "OCR", [cmd("ocr", "Recognize Text", "Распознать текст", "text.viewfinder")]),
                    RibbonGroupSpec("enhance", "Enhanced Pages", "Улучшение страниц", [cmd("enhance", "Enhance", "Улучшить", "wand.and.stars")]),
                    RibbonGroupSpec("color", "Color Conversion", "Преобразование цвета", [cmd("colors", "Convert Colors", "Преобразовать цвета", "circle.lefthalf.filled")])]
        case .mailings:
            return [RibbonGroupSpec("send", "Send", "Отправить", [cmd("emailCurrent", "Email Current Page", "Отправить страницу", "envelope"), cmd("emailAll", "Email All Pages", "Отправить все страницы", "envelope.badge")]),
                    RibbonGroupSpec("sharepoint", "SharePoint", "SharePoint", [cmd("sharepoint", "SharePoint", "SharePoint", "square.and.arrow.up.on.square")])]
        case .review:
            return [RibbonGroupSpec("proofing", "Proofing", "Проверка", [cmd("spell", "Spell Check", "Проверка орфографии", "textformat.abc"), cmd("wordCount", "Word Count", "Подсчёт слов", "number")]),
                    RibbonGroupSpec("comments", "Comments", "Комментарии", [cmd("addComment", "Add", "Добавить", "plus.bubble"), cmd("deleteComment", "Delete", "Удалить", "trash"), cmd("showComments", "Show/Hide", "Показать/скрыть", "eye")]),
                    RibbonGroupSpec("compare", "Compare Documents", "Сравнить документы", [cmd("compare", "Compare", "Сравнить", "rectangle.split.2x1")])]
        case .accessibility:
            return [RibbonGroupSpec("checker", "Accessibility Checker", "Проверка доступности", [cmd("check", "Check Document", "Проверить документ", "accessibility")]),
                    RibbonGroupSpec("order", "Reading Order", "Порядок чтения", [cmd("order", "Reading Order", "Порядок чтения", "list.number")]),
                    RibbonGroupSpec("alt", "Alternative Text", "Альтернативный текст", [cmd("alt", "Alt Text", "Описание изображения", "text.quote")])]
        case .bookmarks:
            return [RibbonGroupSpec("create", "Create", "Создать", [cmd("bookmarkAdd", "Add Bookmark", "Добавить закладку", "botplus.bookmark.plus"), cmd("bookmarkDelete", "Delete Bookmark", "Удалить закладку", "bookmark.slash"), cmd("bookmarkFromPageText", "From Page Text", "Из текста на странице", "text.viewfinder"), cmd("bookmarkEveryN", "Every N-th Page", "Закладка для каждой N-й стр.", "book.pages"), cmd("bookmarkFromTOC", "From TOC", "Из Содержания", "list.bullet.rectangle"), cmd("bookmarkFromFile", "From Text File", "Из текстового файла", "doc.text")]),
                    RibbonGroupSpec("modify", "Modify", "Изменить", [cmd("bookmarkAddText", "Add Text", "Добавить текст", "text.badge.plus"), cmd("bookmarkCase", "Change Case", "Изменить регистр", "textformat"), cmd("bookmarkZoom", "Change Zoom", "Изменить масштаб", "magnifyingglass"), cmd("bookmarkDestination", "Named Destination to Link", "Имен. назначение в ссылку", "link"), cmd("bookmarkFind", "Find & Replace", "Найти и заменить", "text.magnifyingglass"), cmd("bookmarkActions", "Delete Actions", "Удалить действия", "trash"), cmd("bookmarkSort", "Sort", "Сортировать", "arrow.up.arrow.down"), cmd("bookmarkValidate", "Validate", "Утвердить", "checkmark.seal"), cmd("bookmarkMerge", "Merge Duplicates", "Объединить дубликаты", "arrow.triangle.merge")]),
                    RibbonGroupSpec("convert", "Convert", "Преобразовать", [cmd("bookmarkTOC", "Create Table of Contents", "Создать Содержание", "list.bullet.indent"), cmd("bookmarkLinks", "Link for Bookmarks", "Ссылка для закладок", "link.badge.plus"), cmd("bookmarkSortPages", "Sort Pages", "Сортировка страниц", "doc.text.magnifyingglass"), cmd("namedDestinations", "Named Destinations", "Именованные назначения", "list.bullet.rectangle"), cmd("bookmarkNamed", "Convert to Named Destinations", "Преобр. в им. назначения", "bookmark.fill"), cmd("bookmarkJSON", "Export Tree JSON", "Экспорт дерева JSON", "curlybraces"), cmd("bookmarkHTML", "Export to HTML", "Экспорт в HTML", "chevron.left.forwardslash.chevron.right"), cmd("bookmarkText", "Export to Text File", "Экспортировать в текстовый файл", "doc.text")])]
        case .help:
            return [RibbonGroupSpec("ui", "UI Settings", "Настройки интерфейса", [RibbonCommand("theme", "Theme", "Тема", "circle.lefthalf.filled", .themePicker), cmd("customize", "Customize Ribbon", "Настроить ленту", "slider.horizontal.3"), RibbonCommand("language", "Language", "Язык", "globe", .languagePicker)]),
                    RibbonGroupSpec("help", "Contact", "Контакты", [RibbonCommand("support", "Support", "Поддержка", "person.crop.circle.badge.questionmark", .support), RibbonCommand("telegram", "Telegram", "Телеграм", "paperplane", .telegram)]),
                    RibbonGroupSpec("product", "Product", "Программа", [RibbonCommand("about", "About", "О программе", "info.circle", .about), cmd("updates", "Check Updates", "Проверить обновления", "arrow.clockwise"), cmd("license", "License", "Лицензия", "key")])]
        }
    }

    private static func layoutCommands() -> [RibbonCommand] {
        PageLayout.allCases.map { layout in
            RibbonCommand("layout-\(layout.id)", layout.title.en, layout.title.ru, layout == .spread ? "book.pages" : (layout == .single ? "doc" : "scroll"), .layout(layout))
        }
    }
}

private struct RibbonGroupView: View {
    let group: RibbonGroupSpec
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 3) {
                ForEach(group.commands) { command in
                    Group {
                        switch command.action {
                        case .panels: PanelsMenuButton(manager: manager, command: command)
                        case .languagePicker: LanguageMenuButton(manager: manager, command: command)
                        case .themePicker: ThemeMenuButton(manager: manager, command: command)
                        case .tool(.snapshot):
                            Menu {
                                Button(manager.language == .ru ? "Выделить область" : "Select region") { manager.perform(.tool(.snapshot)) }
                                Button(manager.language == .ru ? "Изменить область…" : "Edit region…") { manager.send(.feature("snapshotRegion")) }.disabled(manager.snapshotSource?.id != manager.selectedID)
                                Button(manager.language == .ru ? "Повторить снимок" : "Capture again") { manager.send(.feature("snapshotAgain")) }.disabled(manager.snapshotSource?.id != manager.selectedID)
                                Button(manager.language == .ru ? "Снимок выбранного объекта" : "Capture selected object") { manager.send(.feature("snapshotObject")) }.disabled(manager.selectedAnnotation == nil && manager.selectedContent == nil)
                                Button(manager.language == .ru ? "Печать снимка" : "Print snapshot") { manager.send(.feature("snapshotPrint")) }.disabled(manager.snapshotPNG == nil)
                            } label: { commandLabel(command,manager: manager) }.menuStyle(.borderlessButton)
                        default:
                            Button { manager.perform(command.action) } label: {
                                commandLabel(command, manager: manager)
                            }.buttonStyle(.plain)
                        }
                    }.disabled(!manager.canPerform(command.action)).opacity(manager.canPerform(command.action) ? 1 : 0.35)
                }
            }.frame(maxHeight: .infinity, alignment: .center)
            Text(manager.text(group.title)).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1).padding(.bottom, 3)
        }
        .padding(.horizontal, 7).frame(height: 88)
        .overlay(alignment: .trailing) { Palette.separator.frame(width: 1, height: 68).padding(.bottom, 12) }
    }
}

@MainActor
private func commandLabel(_ command: RibbonCommand, manager: DocumentManager) -> some View {
    let selected: Bool
    if case .toggleRulers = command.action { selected = manager.rulersVisible }
    else if case .tool(let tool) = command.action { selected = manager.tool == tool }
    else { selected = false }
    return VStack(spacing: 5) {
        Group {
            if command.symbol == "botplus.floppy" { FloppyDiskSymbol().stroke(style: StrokeStyle(lineWidth: 1.7, lineJoin: .round)).frame(width: 22, height: 22) }
            else if command.symbol == "botplus.bookmark.plus" { BookmarkAddSymbol().frame(width: 22, height: 22) }
            else { SystemSymbolImage(name: command.symbol).font(.system(size: 20, weight: .regular)) }
        }.frame(height: 24)
        Text(manager.text(command.title)).font(.system(size: 9)).lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.75).frame(height: 23)
    }
    .foregroundStyle(selected ? Palette.accent : Palette.text)
    .frame(width: 59, height: 60)
    .background(selected ? Palette.selected : Palette.raised.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
    .help(manager.text(command.title))
}

private struct PanelsMenuButton: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var panels: PanelWorkspaceModel
    let command: RibbonCommand
    init(manager: DocumentManager, command: RibbonCommand) { self.manager = manager; self.panels = manager.panels; self.command = command }
    var body: some View {
        Menu {
            ForEach(WorkspacePanel.allCases) { panel in
                Toggle(manager.text(panel.title), isOn: Binding(
                    get: { manager.panels.configuration(for: panel).isVisible },
                    set: { manager.panels.setVisible($0, for: panel) }
                ))
            }
        } label: { commandLabel(command, manager: manager) }
            .menuStyle(.borderlessButton).help(manager.text(command.title))
    }
}

private struct ThemeMenuButton: View {
    @ObservedObject var manager: DocumentManager
    let command: RibbonCommand
    var body: some View {
        Menu {
            ForEach(AppTheme.allCases) { theme in
                Button { manager.theme = theme } label: {
                    if manager.theme == theme { Label(manager.text(theme.title), systemImage: "checkmark") }
                    else { Text(manager.text(theme.title)) }
                }
            }
        } label: { commandLabel(command, manager: manager) }
        .menuStyle(.borderlessButton).help(manager.text(command.title))
    }
}

private struct LanguageMenuButton: View {
    @ObservedObject var manager: DocumentManager
    let command: RibbonCommand
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button { manager.language = language } label: {
                    if manager.language == language { Label(language.displayName, systemImage: "checkmark") }
                    else { Text(language.displayName) }
                }
            }
        } label: { commandLabel(command, manager: manager) }
            .menuStyle(.borderlessButton).help(manager.text(command.title))
    }
}

private struct DocumentTabs: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal,showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(manager.documents) { item in tab(item) }
                    Button { manager.openPanel() } label: { Image(systemName: "plus").frame(width: 35,height: 32) }.buttonStyle(.plain)
                }
            }
        }.frame(height: 33).background(Palette.ribbon).overlay(alignment: .bottom) { Palette.separator.frame(height: 1) }
    }
    private func tab(_ item: PDFDocumentItem) -> some View {
        HStack(spacing: 0) {
            Button { manager.select(item.id) } label: {
                HStack(spacing: 6) { Image(systemName: "doc.text"); Text(item.filename).lineLimit(1); if item.isUntitled || item.store.revision != item.store.savedRevision { Circle().fill(Palette.accent).frame(width: 5,height: 5) } }
                    .font(.system(size: 11)).padding(.horizontal,10).frame(width: 210,height: 32)
            }.buttonStyle(.plain)
            Button { manager.closeTabs([item.id]) } label: { Image(systemName: "xmark").font(.system(size: 9)).frame(width: 24,height: 28) }.buttonStyle(.plain)
        }.background(manager.selectedID == item.id ? Palette.selected : .clear)
        .help(item.url.path)
        .onDrag { NSItemProvider(item: Data(item.id.uuidString.utf8) as NSData,typeIdentifier: "com.botplus.pdf.tab-drag") }
        .onDrop(of: ["com.botplus.pdf.tab-drag"],isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadDataRepresentation(forTypeIdentifier: "com.botplus.pdf.tab-drag") { data,_ in
                guard let data,let value = String(data: data,encoding: .utf8),let id = UUID(uuidString: value) else { return }
                Task { @MainActor in manager.moveTab(id,before: item.id) }
            }; return true
        }
        .contextMenu {
            Button(manager.language == .ru ? "Дублировать вид" : "Duplicate view") { manager.duplicateView(item.id) }
            Button(manager.language == .ru ? "Открепить в новое окно" : "Move to new window") { manager.detachTab(item.id) }
            Button(manager.language == .ru ? "Второй вид в новом окне" : "Duplicate in new window") { manager.duplicateView(item.id,detached: true) }
            Button(manager.language == .ru ? "Разделить по вертикали" : "Split side by side") { manager.splitView(item.id,horizontal: true) }
            Button(manager.language == .ru ? "Разделить по горизонтали" : "Split top and bottom") { manager.splitView(item.id,horizontal: false) }
            Divider()
            Button(manager.language == .ru ? "Показать в Finder" : "Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.disabled(item.isUntitled)
            Button(manager.language == .ru ? "Копировать путь" : "Copy path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.url.path,forType: .string) }
            Button(manager.language == .ru ? "Свойства документа" : "Document properties") { manager.select(item.id); manager.panels.select(.properties) }
            Divider()
            Button(manager.language == .ru ? "Закрыть другие" : "Close others") { manager.closeTabs(manager.documents.filter { $0.id != item.id }.map(\.id)) }
            Button(manager.language == .ru ? "Закрыть справа" : "Close tabs to right") { if let index = manager.documents.firstIndex(where: { $0.id == item.id }) { manager.closeTabs(Array(manager.documents.dropFirst(index+1)).map(\.id)) } }
            Button(manager.language == .ru ? "Закрыть всё" : "Close all") { manager.closeTabs(manager.documents.map(\.id)) }
        }
    }
}

private struct EmptyWorkspace: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 13) {
                    SystemSymbolImage(name: "doc.text.viewfinder").font(.system(size: 44,weight: .ultraLight)).foregroundStyle(Palette.muted)
                    Text(manager.language == .ru ? "Документ не открыт" : "No document open").font(.system(size: 17,weight: .medium))
                    Text(manager.language == .ru ? "Дважды щёлкните здесь или перетащите PDF-файл" : "Double-click here or drop a PDF file to open").font(.system(size: 12)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity).contentShape(Rectangle()).onTapGesture(count: 2) { manager.openPanel() }
                HStack(spacing: 12) {
                    Button { manager.openPanel() } label: { Label(manager.language == .ru ? "Открыть PDF" : "Open PDF",systemImage: "folder") }.buttonStyle(.borderedProminent).tint(Palette.accent)
                    Button { manager.createBlankDocument() } label: { Label(manager.language == .ru ? "Создать пустой" : "Create blank",systemImage: "doc.badge.plus") }.buttonStyle(.bordered)
                }
                RecentPDFList(store: manager.recent,manager: manager)
            }.padding(.vertical,32).frame(maxWidth: .infinity)
        }.frame(maxWidth: .infinity,maxHeight: .infinity)
    }
}

private struct WorkspaceArea: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var panels: PanelWorkspaceModel
    init(manager: DocumentManager) { self.manager = manager; self.panels = manager.panels }
    var body: some View {
        GeometryReader { geometry in
            let count = (panels.activePanel(on: .left) == nil ? 0 : 1) + (panels.activePanel(on: .right) == nil ? 0 : 1)
            let maximum = min(600, max(200, (geometry.size.width - 300) / CGFloat(max(1, count))))
            HStack(spacing: 0) {
                PanelIconStrip(side: .left, manager: manager, panels: panels)
                DockedPanelContainer(side: .left, manager: manager, panels: panels, maximumWidth: maximum)
                if manager.selected != nil { viewer } else { EmptyWorkspace(manager: manager) }
                DockedPanelContainer(side: .right, manager: manager, panels: panels, maximumWidth: maximum)
                PanelIconStrip(side: .right, manager: manager, panels: panels)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder private var viewer: some View {
        if let second = manager.splitManager {
            if manager.splitHorizontal {
                HSplitView { PDFViewportPane(manager: manager); SecondaryPDFPane(manager: second,owner: manager) }
            } else { VSplitView { PDFViewportPane(manager: manager); SecondaryPDFPane(manager: second,owner: manager) } }
        } else { PDFViewportPane(manager: manager) }
    }
}
private struct SecondaryPDFPane: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject var owner: DocumentManager
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(manager.title).font(.caption).lineLimit(1); Spacer(); Button { owner.closeSplit() } label: { Image(systemName: "xmark") } }.padding(6)
            DocumentTabs(manager: manager)
            PDFViewportPane(manager: manager)
        }.frame(minWidth: 180,minHeight: 180).modifier(WorkspaceSheets(manager: manager))
    }
}
private struct PDFViewportPane: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 0) {
            if manager.rulersVisible {
                HStack(spacing: 0) {
                    Menu {
                        ForEach(RulerUnit.allCases) { unit in Button(unit.rawValue) { manager.rulerUnit = unit } }
                    } label: { Text(manager.rulerUnit.rawValue).font(.system(size: 8)) }
                    .menuStyle(.borderlessButton).frame(width: 30, height: 25).background(Palette.ruler)
                    RulerBar(axis: .horizontal, manager: manager).frame(height: 25)
                }
            }
            HStack(spacing: 0) {
                if manager.rulersVisible { RulerBar(axis: .vertical, manager: manager).frame(width: 30) }
                PDFViewer(manager: manager).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
        }.background(Palette.workspace).frame(minWidth: 180)
    }
}
private struct PanelIconStrip: View {
    let side: PanelDock
    @ObservedObject var manager: DocumentManager
    @ObservedObject var panels: PanelWorkspaceModel
    var body: some View {
        VStack(spacing: 4) {
            ForEach(WorkspacePanel.allCases.filter {
                let config = panels.configuration(for: $0)
                return (config.dock == .floating ? config.lastDock : config.dock) == side
            }) { panel in
                let config = panels.configuration(for: panel)
                Button { panels.toggleDrawer(panel) } label: {
                    SystemSymbolImage(name: panel.symbol).font(.system(size: 14))
                        .foregroundStyle(config.isVisible && config.isExpanded ? Palette.accent : Palette.muted)
                        .frame(width: 29, height: 32)
                        .background(config.isVisible && config.isExpanded ? Palette.selected : .clear, in: RoundedRectangle(cornerRadius: 3))
                }.buttonStyle(.plain).help(manager.text(panel.title))
            }
            Spacer(minLength: 0)
        }.padding(.top, 5).frame(width: 33).frame(maxHeight: .infinity).background(Palette.ribbon)
    }
}
private struct DockedPanelContainer: View {
    let side: PanelDock
    let maximumWidth: CGFloat
    @ObservedObject var manager: DocumentManager
    @ObservedObject var panels: PanelWorkspaceModel
    init(side: PanelDock, manager: DocumentManager, panels: PanelWorkspaceModel, maximumWidth: CGFloat) {
        self.side = side; self.manager = manager; self.panels = panels; self.maximumWidth = maximumWidth
    }
    var body: some View {
        if let panel = panels.activePanel(on: side) {
            let width = min(CGFloat(panels.configuration(for: panel).width), maximumWidth)
            HStack(spacing: 0) {
                if side == .right { PanelResizeHandle(panel: panel, manager: manager, direction: -1, initialWidth: width).frame(width: 6) }
                VStack(spacing: 0) {
                    PanelHeader(panel: panel, manager: manager)
                    ActivePanelBody(panel: panel, manager: manager)
                }.frame(width: width).frame(maxHeight: .infinity).background(Palette.panel)
                if side == .left { PanelResizeHandle(panel: panel, manager: manager, direction: 1, initialWidth: width).frame(width: 6) }
            }
        }
    }
}

private struct PanelResizeHandle: NSViewRepresentable {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    let direction: CGFloat
    var initialWidth: CGFloat? = nil
    func makeNSView(context: Context) -> SplitterView { let view = SplitterView(); configure(view); return view }
    func updateNSView(_ view: SplitterView, context: Context) { configure(view) }
    private func configure(_ view: SplitterView) {
        view.initialWidth = initialWidth ?? CGFloat(manager.panels.configuration(for: panel).width)
        view.direction = direction
        view.onWidth = { [weak panels = manager.panels] width in panels?.setWidth(width, for: panel) }
        view.onBegin = { [weak panels = manager.panels] in panels?.beginResize() }
        view.onEnd = { [weak panels = manager.panels] in panels?.endResize(panel) }
        view.toolTip = manager.language == .ru ? "Перетащите, чтобы изменить ширину" : "Drag to resize panel"
    }
    static func dismantleNSView(_ view: SplitterView, coordinator: ()) { DispatchQueue.main.async { view.finish() } }
    @MainActor final class SplitterView: NSView {
        var initialWidth: CGFloat = 230
        var direction: CGFloat = 1
        var onWidth: ((CGFloat) -> Void)?
        var onBegin: (() -> Void)?
        var onEnd: (() -> Void)?
        private var startX: CGFloat?
        private var startWidth: CGFloat = 0
        private var pendingWidth: CGFloat?
        private var work: DispatchWorkItem?
        override var intrinsicContentSize: NSSize { NSSize(width: 6, height: NSView.noIntrinsicMetric) }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.separatorColor.setFill(); NSRect(x: bounds.midX, y: bounds.minY, width: 1, height: bounds.height).fill()
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            startX = window.convertPoint(toScreen: event.locationInWindow).x; startWidth = initialWidth
            onBegin?(); NSCursor.resizeLeftRight.set()
        }
        override func mouseDragged(with event: NSEvent) {
            guard let startX, let window else { return }
            pendingWidth = min(600, max(200, startWidth + direction * (window.convertPoint(toScreen: event.locationInWindow).x-startX)))
            guard work == nil else { return }
            let next = DispatchWorkItem { [weak self] in self?.flush() }; work = next
            DispatchQueue.main.asyncAfter(deadline: .now()+1.0/60.0, execute: next)
        }
        private func flush() { work = nil; if let width = pendingWidth { pendingWidth = nil; onWidth?(width) } }
        override func mouseUp(with event: NSEvent) { mouseDragged(with: event); finish() }
        func finish() { work?.cancel(); work = nil; flush(); if startX != nil { startX = nil; onEnd?() } }
    }
}

private struct PanelHeader: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        let config = manager.panels.configuration(for: panel)
        HStack(spacing: 3) {
            Text(manager.text(panel.title)).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 0)
            Button { manager.panels.setDock(config.dock == .floating ? config.lastDock : .floating, for: panel) } label: {
                SystemSymbolImage(name: config.dock == .floating ? "rectangle.inset.filled" : "macwindow").frame(width: 20, height: 23)
            }.buttonStyle(.plain).help(manager.language == .ru ? "Отсоединить / закрепить" : "Detach / Re-dock")
            Button { manager.panels.setDock(.left, for: panel) } label: {
                SystemSymbolImage(name: "arrow.left").frame(width: 20, height: 23)
            }.buttonStyle(.plain).disabled(config.dock == .left).help(manager.language == .ru ? "Переместить влево" : "Dock Left")
            Button { manager.panels.setDock(.right, for: panel) } label: {
                SystemSymbolImage(name: "arrow.right").frame(width: 20, height: 23)
            }.buttonStyle(.plain).disabled(config.dock == .right).help(manager.language == .ru ? "Переместить вправо" : "Dock Right")
            Button { manager.panels.setVisible(false, for: panel) } label: {
                SystemSymbolImage(name: "xmark").frame(width: 20, height: 23)
            }.buttonStyle(.plain).help(manager.language == .ru ? "Закрыть панель" : "Close panel")
        }.font(.system(size: 10)).padding(.horizontal, 6).frame(height: 30).background(Palette.raised)
    }
}

private struct PanelBody: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var panels: PanelWorkspaceModel
    @AppStorage("BotPlus.thumbnailLogicalLabels") private var thumbnailLogicalLabels = true
    init(panel: WorkspacePanel, manager: DocumentManager) { self.panel = panel; self.manager = manager; self.panels = manager.panels }
    var body: some View {
        Group {
            switch panel {
            case .thumbnails: thumbnailList
            case .bookmarks: bookmarkList
            case .search: searchList
            case .properties: properties
            case .comments: comments
            case .layers: layerList
            case .attachments: attachmentList
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var searchList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(manager.language == .ru ? "Текст в PDF" : "Text in PDF", text: $manager.searchText)
                    .onSubmit { manager.runSearch() }
                Button { manager.runSearch() } label: { SystemSymbolImage(name: "magnifyingglass") }
                    .help(manager.language == .ru ? "Найти" : "Find")
            }.disabled(manager.selected == nil)
            HStack {
                if manager.searchRunning { ProgressView().controlSize(.small) }
                Text(manager.language == .ru ? "Совпадений: \(manager.searchMatches.count)" : "Matches: \(manager.searchMatches.count)")
                    .font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button { manager.stepSearch(-1) } label: { SystemSymbolImage(name: "chevron.up") }
                    .help(manager.language == .ru ? "Предыдущее совпадение" : "Previous match")
                Button { manager.stepSearch(1) } label: { SystemSymbolImage(name: "chevron.down") }
                    .help(manager.language == .ru ? "Следующее совпадение" : "Next match")
                Button { manager.clearSearch() } label: { SystemSymbolImage(name: "xmark") }
                    .help(manager.language == .ru ? "Очистить результаты" : "Clear results")
            }.buttonStyle(.plain)
            if manager.searchMatches.isEmpty {
                Text(manager.language == .ru
                     ? (manager.searchCompleted ? "Совпадений нет. Для сканов сначала выполните OCR." : "Введите текст и нажмите Enter.")
                     : (manager.searchCompleted ? "No matches. Run OCR first for scans." : "Enter text and press Return."))
                    .font(.caption).foregroundStyle(Palette.muted).padding(.top, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(manager.searchMatches) { match in
                            Button { manager.selectSearchMatch(match.id) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(manager.language == .ru ? "\(match.id + 1). Страница \(match.page + 1)" : "\(match.id + 1). Page \(match.page + 1)")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(match.snippet).font(.system(size: 12)).lineLimit(4)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(7)
                                    .background(manager.searchMatchID == match.id ? Color.accentColor.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                            }.buttonStyle(.plain).id(match.id)
                        }
                    }
                }.onChange(of: manager.searchMatchID) { _, id in if let id { proxy.scrollTo(id, anchor: .center) } }
            }
        }.padding(10)
    }

    @ViewBuilder private var thumbnailList: some View {
        Group {
            if let item = manager.selected {
                let document = item.document
                VStack(spacing: 4) {
                    HStack {
                        Button { manager.thumbnailZoom = max(0, manager.thumbnailZoom-0.1) } label: { SystemSymbolImage(name: "minus.magnifyingglass") }
                            .disabled(manager.thumbnailZoom <= 0)
                        Spacer()
                        Button { manager.thumbnailZoom = 1 } label: { SystemSymbolImage(name: "arrow.left.and.right") }
                            .help(manager.language == .ru ? "По ширине панели" : "Fit panel width")
                        Spacer()
                        Button { manager.thumbnailZoom = min(1, manager.thumbnailZoom+0.1) } label: { SystemSymbolImage(name: "plus.magnifyingglass") }
                            .disabled(manager.thumbnailZoom >= 1)
                        Menu {
                            Toggle(manager.language == .ru ? "Номера страниц из PDF" : "PDF page labels", isOn: $thumbnailLogicalLabels)
                        } label: { SystemSymbolImage(name: "number") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .help(manager.language == .ru ? "Нумерация миниатюр" : "Thumbnail numbering")
                    }.buttonStyle(.plain).padding(.horizontal,10).help(manager.language == .ru ? "Размер миниатюр" : "Thumbnail size")
                    PDFThumbnailGrid(documentID: item.id, revision: item.store.revision,
                        pageCount: item.pageCount, currentPage: item.pageIndex, selected: item.selectedPages,
                        zoom: manager.thumbnailZoom, interactive: manager.thumbnailGestureActive || panels.isResizing,
                        logicalLabels: thumbnailLogicalLabels, russian: manager.language == .ru,
                        aspect: { index in thumbnailRatio(document.page(at: index)) },
                        label: { index in thumbnailLogicalLabels ? (document.page(at: index)?.label ?? String(index + 1)) : String(index + 1) },
                        image: { index, width in
                            guard let page = document.page(at: index) else { return NSImage(size: .zero) }
                            return PDFThumbnailCache.shared.image(page: page, documentID: item.id, index: index,
                                revision: item.store.revision, width: width, ratio: thumbnailRatio(page),
                                interactive: manager.thumbnailGestureActive || panels.isResizing)
                        },
                        // Native selection may precede SwiftUI publication by one
                        // event cycle; GridView checks its own current count.
                        canCommand: { manager.canThumbnailCommand($0, selectionCount: 0) },
                        command: { action, index in manager.thumbnailCommand(action, index: index) },
                        selectionChanged: { values, focus in
                            guard manager.selected?.id == item.id else { return }
                            item.selectedPages = values.filter { (0..<item.pageCount).contains($0) }
                            if let focus, (0..<item.pageCount).contains(focus) { item.thumbnailAnchor = focus; manager.navigate(to: focus) }
                            else { manager.refreshPresentation() }
                        },
                        focus: { window in
                            if let parent = manager.parentManager { parent.splitFocused = true } else { manager.splitFocused = false }
                            PDFWindowPool.shared.focus(manager, window: window)
                            manager.refreshPresentation()
                        },
                        acceptDrop: { payload, index in receivePageDrop(payload, before: index, item: item) })
                }.background(ThumbnailGestureRegion(manager: manager))
            } else { empty(manager.language == .ru ? "Откройте PDF" : "Open a PDF",symbol: "doc.text") }
        }
    }

    private func thumbnailRatio(_ page: PDFPage?) -> CGFloat {
        guard let page else { return 1.414 }
        let box = page.bounds(for: .cropBox)
        let ratio = page.rotation % 180 != 0 ? box.width / max(1, box.height) : box.height / max(1, box.width)
        return ratio.isFinite ? min(12, max(0.1, ratio)) : 1.414
    }
    private func receivePageDrop(_ payload: String, before index: Int, item: PDFDocumentItem) -> Bool {
        let parts = payload.split(separator: "|")
        guard parts.count == 3, UUID(uuidString: String(parts[0])) != nil,
              Int(parts[2]) != nil, manager.selected?.id == item.id else { return false }
        manager.send(.feature("pages-drop:\(parts[0]):\(parts[1]):\(index):\(parts[2])"))
        return true
    }

    private var attachmentList: some View {
        VStack(alignment: .leading) {
            HStack {
                Button(manager.language == .ru ? "Добавить…" : "Add…") { manager.send(.feature("attachmentAdd")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                Button { manager.send(.feature("attachmentRefresh")) } label: { Image(systemName: "arrow.clockwise") }.disabled(manager.selected == nil)
            }.padding(8)
            if let error = manager.attachmentError { Text(error).font(.caption).foregroundStyle(.orange).padding(8) }
            if manager.attachments.isEmpty && manager.attachmentError == nil { Text(manager.language == .ru ? "Вложений нет" : "No attachments").font(.caption).padding(8) }
            List(manager.attachments) { entry in
                VStack(alignment: .leading) {
                    Text(entry.name).lineLimit(2)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size),countStyle: .file)).font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle()).onTapGesture(count: 2) {
                    if manager.selected?.document.allowsCopying == true { manager.send(.feature("attachmentOpen:\(entry.index)")) }
                }.contextMenu {
                    Button(manager.language == .ru ? "Открыть…" : "Open…") { manager.send(.feature("attachmentOpen:\(entry.index)")) }.disabled(manager.selected?.document.allowsCopying != true)
                    Button(manager.language == .ru ? "Извлечь…" : "Extract…") { manager.send(.feature("attachmentExtract:\(entry.index)")) }.disabled(manager.selected?.document.allowsCopying != true)
                    Button(manager.language == .ru ? "Удалить" : "Delete") { manager.send(.feature("attachmentDelete:\(entry.index)")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                }
            }.listStyle(.plain)
        }.onAppear { DispatchQueue.main.async { manager.send(.feature("attachmentRefresh")) } }
        .onChange(of: manager.selectedID) { _,_ in manager.attachments = []; manager.send(.feature("attachmentRefresh")) }
    }

    private var bookmarkList: some View {
        Group {
            if let root = manager.selected?.document.outlineRoot {
                let rows = makeBookmarkRows(root: root, document: manager.selected?.document)
                if rows.isEmpty { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
                else {
                    List {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            Button {
                                guard manager.finishSourceEditing?() != false else { return }
                                manager.selectedOutline = row.node
                                if row.pageIndex >= 0,let destination = row.node.destination { manager.send(.destination(destination)) }
                            } label: {
                                Text(row.title).font(.system(size: 11)).lineLimit(2).padding(.leading, CGFloat(row.depth * 10)).foregroundStyle(manager.selectedOutline === row.node ? Palette.accent : Palette.text)
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button(manager.language == .ru ? "Добавить дочернюю" : "Add child") { manager.addBookmarkPrompt(parent: row.node) }
                                Button(manager.language == .ru ? "Переименовать" : "Rename") { manager.renameBookmark(row.node) }
                                Button(manager.language == .ru ? "Удалить" : "Delete") { manager.deleteBookmark(row.node) }
                            }
                        }
                    }.listStyle(.plain)
                }
            } else { empty(manager.language == .ru ? "Закладок нет" : "No bookmarks", symbol: "bookmark") }
        }
    }

    private var layerList: some View {
        VStack(alignment: .leading,spacing: 10) {
            HStack { Text(manager.language == .ru ? "Слои исходного PDF" : "PDF optional content").font(.headline); Spacer(); Button { manager.send(.feature("layersRefresh")) } label: { Image(systemName: "arrow.clockwise") }.disabled(manager.selected == nil) }
            if !manager.layerPresets.isEmpty {
                let current = manager.layerPresets.first { $0.id == -1 }
                Text((manager.language == .ru ? "Основная: " : "Default: ")+(current?.name.isEmpty == false ? current!.name : (manager.language == .ru ? "Без имени" : "Unnamed"))).font(.caption)
                Menu(manager.language == .ru ? "Сделать конфигурацию основной…" : "Make configuration default…") {
                    ForEach(manager.layerPresets.filter { $0.id >= 0 }) { preset in
                        Button(preset.name.isEmpty ? "#\(preset.id+1)" : preset.name) { manager.send(.feature("layerPreset:\(preset.id)")) }.disabled(!preset.canMakeDefault)
                    }
                }.disabled(manager.layerPresets.count < 2 || manager.selected?.document.allowsDocumentChanges != true)
                Button(manager.language == .ru ? "Управление конфигурациями…" : "Manage configurations…") { manager.send(.feature("manageLayerPresets")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                Button(manager.language == .ru ? "Видимость и Intent конфигураций…" : "Configuration visibility and intent…") { manager.send(.feature("layerStateEditor")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                Button(manager.language == .ru ? "Радиогруппы слоёв…" : "Layer radio groups…") { manager.send(.feature("layerRadioEditor")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                Button(manager.language == .ru ? "Порядок слоёв…" : "Layer order…") { manager.send(.feature("layerOrderEditor")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
                Text(manager.language == .ru ? "Прежняя основная сохраняется в списке. Конфигурации с Intent, отличным от View, нельзя сделать основной." : "Keeps the previous default in the list. Configurations with an intent other than View cannot become the default.").font(.caption2).foregroundStyle(.secondary)
            }
            if let error = manager.layerError { Text(error).foregroundStyle(.orange).font(.caption) }
            else if manager.layerEntries.isEmpty { Text(manager.language == .ru ? "Группы OCG в каталоге не найдены." : "No OCG groups found in the catalog.").font(.caption).foregroundStyle(.secondary) }
            else { ScrollView { VStack(alignment: .leading,spacing: 8) {
                if manager.layerOutline.isEmpty { Text(manager.language == .ru ? (manager.layerHasOrder ? "Order не содержит отображаемых групп." : "В конфигурации отсутствует Order.") : (manager.layerHasOrder ? "Order has no groups to display." : "This configuration has no Order entry.")).font(.caption).foregroundStyle(.secondary) }
                ForEach(manager.layerOutline) { row in
                    if let id = row.layerID,let entry = manager.layerEntries.first(where: { $0.id == id }) { layerToggle(entry).padding(.leading,CGFloat(min(12,row.depth)*12)) }
                    else { Text(row.title).font(.headline).padding(.leading,CGFloat(min(12,row.depth)*12)) }
                }
                let listed = Set(manager.layerOutline.compactMap(\.layerID)),unlisted = manager.layerEntries.filter { !listed.contains($0.id) }
                if !unlisted.isEmpty {
                    DisclosureGroup(manager.language == .ru ? "Группы каталога вне Order (\(unlisted.count))" : "Catalog groups outside Order (\(unlisted.count))") {
                        ForEach(unlisted) { entry in layerToggle(entry) }
                    }
                }
            } } }
            Text(manager.language == .ru ? "Изменяется конфигурация видимости OCG в PDF. Условия OCMD и правила View/Print сохраняются; отображение зависит от поддержки слоёв движком просмотра." : "Changes the PDF OCG visibility configuration. OCMD and View/Print rules are retained; rendering depends on the viewer’s layer support.").font(.caption).foregroundStyle(.secondary)
            Button(manager.language == .ru ? "Условия видимости OCMD…" : "OCMD visibility conditions…") { manager.send(.feature("membershipEditor")) }
            Button(manager.language == .ru ? "Назначить условие страницам…" : "Assign condition to pages…") { manager.send(.feature("membershipBindingEditor")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
            Button(manager.language == .ru ? "Условия изображений и Form…" : "Image and Form conditions…") { manager.send(.feature("xObjectConditionEditor")) }.disabled(manager.selected?.document.allowsDocumentChanges != true)
            Spacer(minLength: 0)
        }.padding(10)
        .onAppear { DispatchQueue.main.async { manager.send(.feature("layersRefresh")) } }
        .onChange(of: manager.selectedID) { _,_ in manager.layerEntries = []; manager.layerOutline = []; manager.layerHasOrder = false; manager.layerPresets = []; manager.layerSnapshot = nil; manager.send(.feature("layersRefresh")) }
    }
    private func layerToggle(_ entry: PDFLayerInfo) -> some View {
        VStack(alignment: .leading,spacing: 3) {
            HStack {
                Toggle(isOn: Binding(get: { entry.visible },set: { manager.send(.feature("layerToggle:\(entry.id):\($0 ? 1 : 0)")) })) {
                    Text(entry.name.isEmpty ? "OCG #\(entry.id)" : entry.name)
                }.disabled(entry.locked)
                Button { manager.send(.feature("layerPolicy:\(entry.id)")) } label: { Image(systemName: "slider.horizontal.3") }.help(manager.language == .ru ? "Свойства и Usage слоя" : "Layer properties and usage").disabled(entry.locked)
                Button { manager.send(.feature("layerLock:\(entry.id):\(entry.locked ? 0 : 1)")) } label: { Image(systemName: entry.locked ? "lock.fill" : "lock.open") }
                    .help(manager.language == .ru ? "Блокировка слоя в основной конфигурации (не защита доступа)" : "Layer lock in the default configuration (not access control)")
            }.disabled(manager.selected?.document.allowsDocumentChanges != true)
            if entry.viewState != nil || entry.printState != nil {
                Text("View: \(entry.viewState.map { $0 ? "ON" : "OFF" } ?? "—") · Print: \(entry.printState.map { $0 ? "ON" : "OFF" } ?? "—")").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var properties: some View { WorkspacePropertiesContent(manager: manager) }

    private var comments: some View {
        Group {
            if let item = manager.selected {
                let annotations = (0..<item.pageCount).flatMap { index -> [(Int, PDFAnnotation)] in
                    guard let page = item.document.page(at: index) else { return [] }
                    return page.annotations.filter { $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }.map { (index, $0) }
                }
                if annotations.isEmpty { empty(manager.language == .ru ? "Аннотаций нет" : "No annotations", symbol: "text.bubble") }
                else {
                    List {
                        ForEach(Array(annotations.enumerated()), id: \.offset) { _, entry in
                            Button { manager.send(.feature("annotationSelect:\(entry.0):\(item.document.page(at: entry.0)?.annotations.firstIndex(where: { $0 === entry.1 }) ?? -1)")) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.1.contents ?? entry.1.type ?? (manager.language == .ru ? "Аннотация" : "Annotation"))
                                    Text("\(manager.language == .ru ? "Страница" : "Page") \(entry.0 + 1)").font(.system(size: 9)).foregroundStyle(Palette.muted)
                                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }.listStyle(.plain)
                }
            } else { empty(manager.language == .ru ? "Откройте PDF" : "Open a PDF", symbol: "text.bubble") }
        }
    }

    private func property(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 11)).textSelection(.enabled)
        }
    }
    private func empty(_ message: String, symbol: String) -> some View {
        VStack(spacing: 8) { SystemSymbolImage(name: symbol).font(.title3).foregroundStyle(Palette.muted); Text(message).font(.system(size: 10)).foregroundStyle(Palette.muted).multilineTextAlignment(.center) }
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding(14)
    }
}

private struct WorkspacePropertiesContent: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var source: PDFTextPropertiesModel
    init(manager: DocumentManager) { self.manager = manager; source = manager.textProperties }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 12) {
                if let annotation = manager.selectedAnnotation,let measure = AnnotationMetadata.measurement(annotation) {
                    Text(measure.label(russian: manager.language == .ru)).font(.headline)
                    if measure.kind == .distance {
                        Picker(manager.language == .ru ? "Расстояние" : "Distance",selection: Binding(get: { measure.axis },set: { axis in manager.send(.feature("measurementAxis:"+axis.rawValue)) })) {
                            ForEach(EngineeringDistanceAxis.allCases) { Text($0.title(russian: manager.language == .ru)).tag($0) }
                        }
                        if measure.axis == .custom { Button(manager.language == .ru ? "Изменить угол…" : "Change angle…") { manager.send(.feature("measurementAxis:custom")) } }
                        Text(manager.language == .ru ? "Направления заданы в координатах PDF, независимо от поворота страницы." : "Directions use PDF coordinates, independent of page rotation.").font(.caption)
                    }
                    if measure.kind == .perimeter || measure.kind == .area || (measure.kind == .distance && measure.dimensionOffset != nil) {
                        Button(manager.language == .ru ? "Подпись размера и выноска…" : "Dimension label and leader…") { manager.send(.feature("measurementLabel")) }
                    }
                    Button(manager.language == .ru ? "Масштаб и размерные линии…" : "Scale and dimension lines…") { manager.send(.feature("measurementScale")) }
                    Button(manager.language == .ru ? "Преобразовать измерения…" : "Transform measurements…") { manager.send(.feature("measurementTransform")) }
                    Button(manager.language == .ru ? "Перенести на страницу…" : "Move to page…") { manager.send(.feature("measurementTransfer")) }.disabled((manager.selected?.pageCount ?? 0) < 2)
                    Button(manager.language == .ru ? "Копировать в другой PDF…" : "Copy to another PDF…") { manager.send(.feature("measurementCopyDocument")) }.disabled(!manager.documents.contains { $0.document !== manager.selected?.document && $0.document.allowsCommenting })
                    Picker(manager.language == .ru ? "Единицы измерения" : "Measurement units",selection: Binding(get: { measure.scale.unit },set: { unit in
                        guard let item = manager.selected else { return }; manager.recordUndo(item,group: "measureUnit")
                        var value = measure; value.scale.unit = unit; AnnotationMetadata.setMeasurement(value,on: annotation); manager.send(.feature("measureRefresh"))
                    })) { ForEach(EngineeringUnit.allCases) { Text($0.rawValue).tag($0) } }
                }
                if manager.selectedContent?.kind == "group" || (manager.selected != nil && manager.tool == .editContent) {
                    Button(manager.language == .ru ? "Вложенные Form: независимое преобразование…" : "Nested Forms: independent transform…") { manager.send(.feature("formResourceTransform")) }
                }
                if source.active || manager.selectedAnnotation != nil || manager.selectedContent != nil {
                    SourceOrAnnotationProperties(manager: manager)
                } else if let item = manager.selected {
                    if [.distance,.perimeter,.area,.calibration].contains(manager.tool) {
                        Text(manager.language == .ru ? "Щёлкайте вершины. Enter или двойной щелчок — завершить; Esc — отменить." : "Click vertices. Enter or double-click finishes; Esc cancels.").font(.caption)
                        Toggle(manager.language == .ru ? "Привязка к концам, серединам и пересечениям отрезков" : "Snap to endpoints, midpoints and line intersections",isOn: $manager.engineeringSnap)
                        Picker(manager.language == .ru ? "Единицы" : "Units",selection: $manager.engineeringUnit) { ForEach(EngineeringUnit.allCases) { Text($0.rawValue).tag($0) } }
                    }
                    if manager.tool == .snapshot {
                        Toggle(manager.language == .ru ? "Прозрачный фон" : "Transparent background",isOn: $manager.snapshotTransparent)
                        if let image = manager.snapshotImage { Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 160) }
                        Button(manager.language == .ru ? "Изменить область снимка…" : "Edit snapshot region…") { manager.send(.feature("snapshotRegion")) }.disabled(manager.snapshotSource?.id != manager.selectedID)
                        Button(manager.language == .ru ? "Сохранить снимок…" : "Save snapshot…") {
                            guard let png = manager.snapshotPNG else { return }
                            let panel = NSSavePanel(); panel.allowedContentTypes = [.png]; panel.nameFieldStringValue = "Snapshot.png"
                            panel.begin { response in guard response == .OK, let url = panel.url else { return }; DispatchQueue.main.async { do { try png.write(to: url,options: .atomic) } catch { manager.say("Cannot save snapshot","Не удалось сохранить снимок") } } }
                        }.disabled(manager.snapshotPNG == nil)
                        Picker("DPI", selection: $manager.snapshotDPI) { ForEach([72,96,150,200,300,600], id: \.self) { Text(String($0)).tag($0) } }
                        Text(manager.language == .ru ? "Выделите прямоугольную область. PNG будет скопирован в буфер обмена." : "Drag a rectangular region to copy a PNG to the clipboard.").font(.caption)
                    } else if ![PDFTool.hand,.textSelection,.editText,.editContent,.selectComments,.marquee].contains(manager.tool) { AnnotationStyleControls(manager: manager) }
                    DocumentPropertiesView(item: item,russian: manager.language == .ru)
                } else { Text(manager.language == .ru ? "Нет выбранного документа" : "No active document") }
            }.frame(maxWidth: .infinity,alignment: .leading).padding(10)
        }
    }
    private func row(_ title: String,_ value: String) -> some View {
        VStack(alignment: .leading,spacing: 3) { Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 11)).textSelection(.enabled) }
    }
}

private struct DocumentPropertiesView: View {
    @ObservedObject var item: PDFDocumentItem
    let russian: Bool
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
                    Text(russian ? "Свойства документа" : "Document properties").font(.headline)
                    row(russian ? "Файл" : "File",item.filename)
                    row(russian ? "Страниц" : "Pages",String(item.pageCount))
                    if let page = item.document.page(at: item.pageIndex) {
                        let size = page.bounds(for: .cropBox).size
                        row(russian ? "Размер страницы" : "Page size",String(format: "%.1f × %.1f pt",size.width,size.height))
                        row(russian ? "Поворот" : "Rotation","\(page.rotation)°")
                    }
                    row(russian ? "Масштаб" : "Zoom",String(format: "%.0f%%",Double(item.zoom*100)))
                    if let title = item.document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String { row(russian ? "Название" : "Title",title) }
                    if let author = item.document.documentAttributes?[PDFDocumentAttribute.authorAttribute] as? String { row(russian ? "Автор" : "Author",author) }
        }
    }
    private func row(_ title: String,_ value: String) -> some View {
        VStack(alignment: .leading,spacing: 3) { Text(title).font(.system(size: 9)).foregroundStyle(Palette.muted); Text(value).font(.system(size: 11)).textSelection(.enabled) }
    }
}

private struct SourceOrAnnotationProperties: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var source: PDFTextPropertiesModel
    init(manager: DocumentManager) { self.manager = manager; source = manager.textProperties }
    var body: some View {
        Group {
            if source.active { PDFTextPropertiesView(model: source,russian: manager.language == .ru) }
            else if manager.contentProperties.active { PDFContentPropertiesView(model: manager.contentProperties,russian: manager.language == .ru) }
            else if let object = manager.selectedContent {
                VStack(alignment: .leading,spacing: 8) {
                    Text(manager.language == .ru ? (object.kind == "image" ? "Изображение" : "Векторный объект") : (object.kind == "image" ? "Image" : "Vector object")).font(.headline)
                    Text(String(format: "%.1f × %.1f pt",object.bounds.width,object.bounds.height))
                    Text(String(format: "X %.1f  Y %.1f pt",object.bounds.minX,object.bounds.minY))
                    if let pixels = object.pixelSize { Text("\(Int(pixels.width)) × \(Int(pixels.height)) px") }
                }.font(.system(size: 11))
            } else if let annotation = manager.selectedAnnotation {
                VStack(alignment: .leading,spacing: 8) {
                    Text(manager.language == .ru ? "Свойства комментария" : "Comment properties").font(.headline)
                    if manager.selectedAnnotationCount > 1 {
                        Text(manager.language == .ru ? "Выбрано объектов: \(manager.selectedAnnotationCount)" : "Selected annotations: \(manager.selectedAnnotationCount)")
                        Text(manager.language == .ru ? "Cmd/Shift-клик или рамка — несколько объектов. Стрелки — перенос, Shift — шаг 10 пт. Связанные части выбираются вместе." : "Cmd/Shift-click or drag a rectangle to select multiple objects. Arrow keys move; Shift uses 10 pt. Linked parts are selected together.").font(.caption)
                        HStack { Button(manager.language == .ru ? "Блокировать все" : "Lock all") { manager.send(.feature("annotationBatchLock:1")) }; Button(manager.language == .ru ? "Разблокировать" : "Unlock all") { manager.send(.feature("annotationBatchLock:0")) } }
                        HStack { Button(manager.language == .ru ? "Показать все" : "Show all") { manager.send(.feature("annotationBatchVisible:1")) }; Button(manager.language == .ru ? "Скрыть все" : "Hide all") { manager.send(.feature("annotationBatchVisible:0")) } }
                        HStack { Button(manager.language == .ru ? "Печатать все" : "Print all") { manager.send(.feature("annotationBatchPrint:1")) }; Button(manager.language == .ru ? "Не печатать" : "Do not print") { manager.send(.feature("annotationBatchPrint:0")) } }
                    }
                    Button(manager.language == .ru ? "Масштаб выбранной геометрии…" : "Scale selected geometry…") { manager.send(.feature("annotationScale")) }
                    Button(manager.language == .ru ? "Поворот на заданный угол…" : "Rotate by angle…") { manager.send(.feature("annotationRotate")) }
                    Menu(manager.language == .ru ? "Отражение в координатах PDF" : "Flip in PDF coordinates") {
                        Button(manager.language == .ru ? "Слева ↔ справа" : "Left ↔ right") { manager.send(.feature("annotationFlip:horizontal")) }
                        Button(manager.language == .ru ? "Сверху ↔ снизу" : "Top ↔ bottom") { manager.send(.feature("annotationFlip:vertical")) }
                    }
                    HStack {
                        Button(manager.language == .ru ? "Повернуть влево 90°" : "Rotate left 90°") { manager.send(.feature("annotationRotate:left")) }
                        Button(manager.language == .ru ? "Вправо 90°" : "Right 90°") { manager.send(.feature("annotationRotate:right")) }
                    }
                    Text(manager.language == .ru ? "Поворот: Line, Ink, Square и Circle без измерений. Остальные типы требуют сохранения собственного appearance." : "Rotation supports Line, Ink, Square and Circle without measurements. Other types require their own appearance handling.").font(.caption)
                    Text(annotation.type ?? "Annotation")
                    if manager.selectedAnnotationCount <= 1 && (["Line","Ink"].contains(annotation.type ?? "") || (AnnotationMetadata.group(of: annotation) != nil && annotation.page?.annotations.contains(where: { $0.type == "Line" && AnnotationMetadata.group(of: $0) == AnnotationMetadata.group(of: annotation) }) == true)) {
                        Button(manager.language == .ru ? "Редактировать вершины…" : "Edit vertices…") { manager.send(.feature("annotationVertices")) }
                    }
                    if manager.selectedAnnotationCount <= 1 {
                    Toggle(manager.language == .ru ? "Заблокировать" : "Lock annotation",isOn: Binding(get: { AnnotationMetadata.isLocked(annotation) },set: { manager.changeAnnotation(annotation,lock: $0) }))
                    Toggle(manager.language == .ru ? "Показывать" : "Visible",isOn: Binding(get: { annotation.shouldDisplay },set: { manager.changeAnnotation(annotation,visible: $0) }))
                    Toggle(manager.language == .ru ? "Печатать" : "Print",isOn: Binding(get: { annotation.shouldPrint },set: { manager.changeAnnotation(annotation,printable: $0) }))
                    }
                    if annotation.type == "Text" {
                        TextEditor(text: Binding(get: { annotation.contents ?? "" },set: { annotation.contents = $0; manager.send(.refresh) })).frame(minHeight: 80)
                    } else if let contents = annotation.contents,!contents.isEmpty { Text(contents).textSelection(.enabled) }
                    if annotation.type == "Link" {
                        Text((annotation.action as? PDFActionURL)?.url?.absoluteString ?? "Page link").font(.system(size: 10))
                        Button(manager.language == .ru ? "Изменить ссылку" : "Edit link") { manager.editLink(annotation) }
                    }
                    if annotation.type == "Widget" {
                        TextField("Field name / Имя поля",text: Binding(get: { annotation.fieldName ?? "" },set: { manager.recordFieldChange(); annotation.fieldName = $0; manager.send(.refresh) }))
                        Toggle(manager.language == .ru ? "Только чтение" : "Read only",isOn: Binding(get: { annotation.isReadOnly },set: { manager.recordFieldChange(); annotation.isReadOnly = $0; manager.send(.refresh) }))
                        Toggle(manager.language == .ru ? "Обязательное" : "Required",isOn: Binding(get: { ((annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0)&2 != 0 },set: { value in
                            manager.recordFieldChange(); let flags = (annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
                            annotation.setValue(NSNumber(value: value ? flags|2 : flags & ~2),forAnnotationKey: .widgetFieldFlags); manager.send(.refresh)
                        }))
                        if annotation.widgetFieldType == .text {
                            Button(manager.language == .ru ? "Правило проверки значения…" : "Value validation rule…") { manager.send(.feature("formRule")) }
                            Toggle(manager.language == .ru ? "Несколько строк" : "Multiline",isOn: Binding(get: { annotation.isMultiline },set: { manager.recordFieldChange(); annotation.isMultiline = $0; manager.send(.refresh) }))
                            TextField(manager.language == .ru ? "Максимум символов (0 — без ограничения)" : "Maximum length (0 = unlimited)",value: Binding(get: { annotation.maximumLength },set: { manager.recordFieldChange(); annotation.maximumLength = min(100000,max(0,$0)); manager.send(.refresh) }),format: .number)
                            Toggle(manager.language == .ru ? "Ячейки для символов (Comb)" : "Character cells (Comb)",isOn: Binding(get: { annotation.hasComb },set: { value in
                                manager.recordFieldChange(); if value { annotation.isMultiline = false; if annotation.maximumLength == 0 { annotation.maximumLength = 10 } }; annotation.hasComb = value; manager.send(.refresh)
                            }))
                        }
                        if annotation.widgetFieldType == .choice {
                            Button(manager.language == .ru ? "Выбрать значения…" : "Select values…") { manager.send(.feature("formValues")) }
                            Toggle(manager.language == .ru ? "Список вместо выпадающего меню" : "List instead of popup",isOn: Binding(get: { annotation.isListChoice },set: { manager.recordFieldChange(); annotation.isListChoice = $0; manager.send(.refresh) }))
                            Toggle(manager.language == .ru ? "Множественный выбор" : "Multiple selection",isOn: Binding(get: { ((annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0)&(1<<21) != 0 },set: { value in
                                manager.recordFieldChange(); let flags = (annotation.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
                                annotation.setValue(NSNumber(value: value ? flags|(1<<21) : flags & ~(1<<21)),forAnnotationKey: .widgetFieldFlags); if value { annotation.isListChoice = true }; manager.send(.refresh)
                            }))
                            Text(manager.language == .ru ? "Варианты, по одному в строке" : "One choice per line").font(.caption)
                            TextEditor(text: Binding(get: { (annotation.choices ?? []).joined(separator: "\n") },set: { manager.recordFieldChange(); annotation.choices = Array($0.components(separatedBy: .newlines).prefix(1000)); manager.send(.refresh) })).frame(height: 110)
                            Text(manager.language == .ru ? "Экспортные значения по порядку (пропуски = подписи)" : "Export values in order (missing = labels)").font(.caption)
                            TextEditor(text: Binding(get: { (annotation.values ?? annotation.choices ?? []).joined(separator: "\n") },set: { value in
                                manager.recordFieldChange(); let labels = annotation.choices ?? [],values = value.components(separatedBy: .newlines)
                                annotation.values = labels.enumerated().map { index,label in index < values.count ? values[index] : label }; manager.send(.refresh)
                            })).frame(height: 90)
                        }
                        if annotation.widgetFieldType == .button {
                            TextField(manager.language == .ru ? "Экспортное значение / группа определяется именем поля" : "Export value / field name defines the group",text: Binding(get: { annotation.buttonWidgetStateString },set: { manager.recordFieldChange(); annotation.buttonWidgetStateString = $0; manager.send(.refresh) }))
                            if annotation.widgetControlType == .radioButtonControl {
                                Toggle(manager.language == .ru ? "Разрешить снять выбор" : "Allow toggle off",isOn: Binding(get: { annotation.allowsToggleToOff },set: { manager.recordFieldChange(); annotation.allowsToggleToOff = $0; manager.send(.refresh) }))
                                Toggle(manager.language == .ru ? "Одинаковые значения включаются вместе" : "Equal values turn on in unison",isOn: Binding(get: { annotation.radiosInUnison },set: { manager.recordFieldChange(); annotation.radiosInUnison = $0; manager.send(.refresh) }))
                            }
                        }
                    } else if annotation.type != "Stamp" { AnnotationStyleControls(manager: manager) }
                }
            }

        }
    }
}

private struct AnnotationStyleControls: View {
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(manager.language == .ru ? "Оформление аннотации" : "Annotation appearance").font(.system(size: 11, weight: .semibold))
            ColorPicker(manager.language == .ru ? "Цвет" : "Color", selection: $manager.annotationColor, supportsOpacity: false)
            HStack {
                Text(manager.language == .ru ? "Толщина" : "Stroke")
                Slider(value: $manager.annotationStrokeWidth, in: 0.5...12)
                Text(String(format: "%.1f", manager.annotationStrokeWidth)).frame(width: 30)
            }
            HStack { Text(manager.language == .ru ? "Непрозр." : "Opacity"); Slider(value: $manager.annotationOpacity, in: 0...1) }
            Stepper("\(manager.language == .ru ? "Шрифт" : "Font"): \(Int(manager.textFontSize))", value: $manager.textFontSize, in: 6...72)
            Toggle(manager.language == .ru ? "Заливка фигуры" : "Shape fill",isOn: $manager.annotationFill)
            Toggle(manager.language == .ru ? "Рамка текста" : "Text border", isOn: $manager.textBorderEnabled)
            if manager.selectedAnnotation != nil {
                Button(manager.language == .ru ? "Применить к выбранной" : "Apply to selected") { manager.send(.applyAnnotationStyle) }
            }
        }.font(.system(size: 10))
        .onChange(of: manager.annotationColor) { _,_ in apply() }
        .onChange(of: manager.annotationOpacity) { _,_ in apply() }
        .onChange(of: manager.annotationStrokeWidth) { _,_ in apply() }
        .onChange(of: manager.annotationFill) { _,_ in apply() }
    }
    private func apply() { if manager.selectedAnnotation != nil { manager.send(.applyAnnotationStyle) } }
}

private struct BookmarkRow { let title: String; let pageIndex: Int; let depth: Int; let node: PDFOutline }
private func makeBookmarkRows(root: PDFOutline, document: PDFDocument?, depth: Int = 0) -> [BookmarkRow] {
    var rows: [BookmarkRow] = []
    for index in 0..<root.numberOfChildren {
        guard let child = root.child(at: index) else { continue }
        let proposed = child.destination?.page.flatMap { document?.index(for: $0) } ?? -1
        let pageIndex = proposed >= 0 && proposed < (document?.pageCount ?? 0) ? proposed : -1
        rows.append(BookmarkRow(title: child.label ?? "Bookmark",pageIndex: pageIndex,depth: depth,node: child))
        rows.append(contentsOf: makeBookmarkRows(root: child, document: document, depth: depth + 1))
    }
    return rows
}

private struct FloatingPanelContents: View {
    let panel: WorkspacePanel
    @ObservedObject var panels: PanelWorkspaceModel
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(panel: panel, manager: manager)
            ActivePanelBody(panel: panel, manager: manager)
        }.frame(minWidth: 200, minHeight: 180)
            .background(Palette.panel).foregroundStyle(Palette.text).preferredColorScheme(manager.theme.colorScheme)
    }
}

private struct StatusBar: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var viewport: ViewportState
    init(manager: DocumentManager) { self.manager = manager; self.viewport = manager.viewport }
    var body: some View {
        HStack(spacing: 8) {
            StatusIcon(manager: manager, title: Bilingual(en: "Previous Page", ru: "Предыдущая страница"), symbol: "chevron.left", action: .previous)
            TextField("1", text: $manager.pageText, onCommit: manager.commitPageField)
                .textFieldStyle(.roundedBorder).frame(width: 44).multilineTextAlignment(.center).disabled(manager.selected == nil)
            Text("/ \(manager.selected?.pageCount ?? 0)").font(.system(size: 10)).foregroundStyle(Palette.muted)
            StatusIcon(manager: manager, title: Bilingual(en: "Next Page", ru: "Следующая страница"), symbol: "chevron.right", action: .next)
            Hairline(height: 17)
            Text(manager.selected == nil ? (manager.language == .ru ? "Готово" : "Ready") : manager.text(manager.tool.title))
                .font(.system(size: 10)).foregroundStyle(Palette.muted)
            Spacer()
            if let point = manager.cursorPage {
                Text(String(format: "X %.2f  Y %.2f %@", point.x / manager.rulerUnit.pointsPerUnit, point.y / manager.rulerUnit.pointsPerUnit, manager.rulerUnit.rawValue))
                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.muted)
            }
            Picker("Units", selection: $manager.rulerUnit) { ForEach(RulerUnit.allCases) { unit in Text(unit.rawValue).tag(unit) } }.labelsHidden().frame(width: 62)
            SystemSymbolImage(name: "minus.magnifyingglass").font(.system(size: 10))
            Slider(value: Binding(get: { log(Double(PDFZoomLimits.clamp(manager.selected?.zoom ?? 1))) }, set: { manager.send(.setZoom(CGFloat(exp($0)))) }), in: log(Double(PDFZoomLimits.minimum))...log(Double(PDFZoomLimits.maximum)))
                .frame(width: 120).disabled(manager.selected == nil)
            SystemSymbolImage(name: "plus.magnifyingglass").font(.system(size: 10))
            Text(String(format: "%.0f%%", Double(manager.selected?.zoom ?? 1) * 100)).font(.system(size: 10, design: .monospaced)).frame(width: 42, alignment: .trailing)
            Hairline(height: 17)
            ForEach(PageLayout.allCases) { layout in
                Button { manager.perform(.layout(layout)) } label: {
                    SystemSymbolImage(name: layout == .continuous ? "scroll" : (layout == .single ? "doc" : "book.pages"))
                        .font(.system(size: 11)).foregroundStyle(manager.layout == layout ? Palette.accent : Palette.muted).frame(width: 22, height: 22)
                }.buttonStyle(.plain).disabled(!manager.canPerform(.layout(layout))).opacity(manager.canPerform(.layout(layout)) ? 1 : 0.35).help(manager.text(layout.title))
            }
        }.padding(.horizontal, 10).frame(height: 31).background(Palette.ribbon)
            .overlay(alignment: .top) { Palette.separator.frame(height: 1) }
    }
}

private struct StatusIcon: View {
    @ObservedObject var manager: DocumentManager
    let title: Bilingual
    let symbol: String
    let action: RibbonAction
    var body: some View {
        Button { manager.perform(action) } label: { SystemSymbolImage(name: symbol).font(.system(size: 11)).frame(width: 23, height: 23) }
            .buttonStyle(.plain).disabled(!manager.canPerform(action)).opacity(manager.canPerform(action) ? 1 : 0.35).help(manager.text(title))
    }
}

private struct Hairline: View {
    let height: CGFloat
    var body: some View { Palette.separator.frame(width: 1, height: height).padding(.horizontal, 3) }
}

private enum RulerAxis { case horizontal, vertical }

private struct RulerBar: View {
    let axis: RulerAxis
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var viewport: ViewportState
    init(axis: RulerAxis, manager: DocumentManager) { self.axis = axis; self.manager = manager; self.viewport = manager.viewport }
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.ruler))
            let metrics = manager.rulerMetrics
            guard metrics.valid else { return }
            let horizontal = axis == .horizontal
            let origin = horizontal ? metrics.horizontalOrigin : metrics.verticalOrigin
            let step = horizontal ? metrics.horizontalPointsPerPixel : metrics.verticalPointsPerPixel
            let length = horizontal ? size.width : size.height
            guard abs(step) > 0.000001 else { return }
            let unitsPerPixel = step / manager.rulerUnit.pointsPerUnit
            let start = origin / manager.rulerUnit.pointsPerUnit
            let end = start + length * unitsPerPixel
            let major = rulerInterval(for: 80 * abs(unitsPerPixel)); let minor = major / 10
            var value = floor(min(start, end) / minor) * minor; var count = 0
            while value <= max(start, end) + minor && count < 2500 {
                let pixel = (value - start) / unitsPerPixel
                if pixel >= 0 && pixel <= length {
                    let majorTick = abs(value / major - (value / major).rounded()) < 0.00001
                    let mediumTick = abs(value / (major / 2) - (value / (major / 2)).rounded()) < 0.00001
                    let tickLength: CGFloat = majorTick ? 15 : (mediumTick ? 10 : 5)
                    var tick = Path()
                    if horizontal { tick.move(to: CGPoint(x: pixel, y: size.height)); tick.addLine(to: CGPoint(x: pixel, y: size.height - tickLength)) }
                    else { tick.move(to: CGPoint(x: size.width, y: pixel)); tick.addLine(to: CGPoint(x: size.width - tickLength, y: pixel)) }
                    context.stroke(tick, with: .color(Palette.rulerTicks), lineWidth: 1)
                    if majorTick {
                        let digits = major >= 1 ? 0 : (major >= 0.1 ? 1 : 2)
                        let label = Text(verbatim: RulerLabelFormatter.label(value: value,minorInterval: minor,digits: digits,language: manager.language)).font(.system(size: 8)).foregroundColor(Palette.rulerText)
                        if horizontal { context.draw(label, at: CGPoint(x: pixel + 3, y: 2), anchor: .topLeading) }
                        else {
                            var rotated = context; rotated.translateBy(x: 8, y: pixel + 3); rotated.rotate(by: .degrees(90))
                            rotated.draw(label, at: .zero, anchor: .topLeading)
                        }
                    }
                }
                count += 1; value += minor
            }
            if let cursor = manager.cursorViewport {
                let pixel = horizontal ? cursor.x : cursor.y; var marker = Path()
                if horizontal { marker.move(to: CGPoint(x: pixel, y: 0)); marker.addLine(to: CGPoint(x: pixel, y: size.height)) }
                else { marker.move(to: CGPoint(x: 0, y: pixel)); marker.addLine(to: CGPoint(x: size.width, y: pixel)) }
                context.stroke(marker, with: .color(Palette.accent), lineWidth: 1)
            }
        }.accessibilityLabel("\(manager.language == .ru ? "Линейка" : "Ruler") \(manager.rulerUnit.rawValue)")
    }
}

private enum RulerLabelFormatter {
    static func label(value: CGFloat,minorInterval: CGFloat,digits: Int,language: AppLanguage) -> String {
        guard value.isFinite,minorInterval.isFinite else { return "" }
        let number: Double = abs(value) < abs(minorInterval)/2 ? 0 : Double(value)
        return number.formatted(.number.grouping(.never)
            .precision(.fractionLength(min(6,max(0,digits))))
            .locale(Locale(identifier: language == .ru ? "ru_RU" : "en_US_POSIX")))
    }
}

private func rulerInterval(for target: CGFloat) -> CGFloat {
    let safeTarget = max(0.01, target)
    let power = pow(10, floor(log10(Double(safeTarget))))
    for multiplier in [1.0, 2.0, 5.0, 10.0] where multiplier * power >= Double(safeTarget) {
        return CGFloat(multiplier * power)
    }
    return CGFloat(10 * power)
}

private enum ObjectClipboard {
    static let pages = NSPasteboard.PasteboardType("com.botplus.pdfeditor.pages")
    static let annotations = NSPasteboard.PasteboardType("com.botplus.pdfeditor.annotation-objects")
    static let contentObject = NSPasteboard.PasteboardType("com.botplus.pdfeditor.content-object")
    static let sourceText = NSPasteboard.PasteboardType("com.botplus.pdfeditor.source-text")
    struct TextStyle: Codable {
        let text: String
        let fontSize: Double
        let fontName: String
        let rgba: [Double]
        init(text: String, size: CGFloat, name: String, color: NSColor) {
            self.text = text; fontSize = Double(size); fontName = name
            let c = color.usingColorSpace(.deviceRGB) ?? .black
            rgba = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        }
        var color: NSColor {
            guard rgba.count == 4 else { return .black }
            return NSColor(calibratedRed: min(1,max(0,rgba[0])), green: min(1,max(0,rgba[1])), blue: min(1,max(0,rgba[2])), alpha: min(1,max(0,rgba[3])))
        }
    }
}

private struct PDFViewer: NSViewRepresentable {
    @ObservedObject var manager: DocumentManager
    func makeCoordinator() -> Coordinator { Coordinator(manager: manager) }
    func makeNSView(context: Context) -> PDFViewerView {
        let view = PDFViewerView(frame: .zero)
        view.clipsToBounds = true
        view.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
        view.displaysPageBreaks = true
        view.pageBreakMargins = NSEdgeInsets(top: 2,left: 2,bottom: 2,right: 2)
        view.displayBox = .cropBox
        view.pageShadowsEnabled = true
        view.autoScales = false
        view.configureZoomLimits()
        view.enableDataDetectors = false
        context.coordinator.attach(view)
        return view
    }
    func updateNSView(_ view: PDFViewerView, context: Context) {
        context.coordinator.manager = manager
        context.coordinator.requestUpdate(view)
    }

    static func dismantleNSView(_ nsView: PDFViewerView, coordinator: Coordinator) {
        coordinator.detach()
        nsView.stopEventMonitoring()
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        var manager: DocumentManager
        weak var view: PDFViewerView?
        var activeDocumentID: UUID?
        var lastCommand = -1
        var observationTokens: [NSObjectProtocol] = []
        var clipToken: NSObjectProtocol?
        weak var observedClip: NSClipView?
        var syncScheduled = false
        var navigationWork: DispatchWorkItem?
        var navigationRestoring = false
        var navigationGeneration = 0
        var textPopover: NSPopover?
        var sourceDocument: ObjectIdentifier?
        var fontDocument: ObjectIdentifier?
        var fontNames: [String] = []
        var sourceOutlineData: Data?
        var sourceOutlineCache: [Int:[PDFSourceSession.BlockDescriptor]] = [:]
        var outlinePending = false
        var outlineGeneration = 0
        var sourceAnchor: (index: Int, point: CGPoint)?
        var lastSearchRequestID = -1
        var lastSearchNavigationID = -1

        init(manager: DocumentManager) { self.manager = manager }
        func attach(_ view: PDFViewerView) {
            self.view = view; view.delegate = self
            view.onFocus = { [weak manager = manager,weak view] in
                guard let manager else { return }
                if let parent = manager.parentManager { parent.splitFocused = true } else { manager.splitFocused = false }
                PDFWindowPool.shared.focus(manager,window: view?.window)
            }
            manager.finishSourceEditing = { [weak self] in self?.finishSourceEditor() ?? true }
            manager.captureNavigation = { [weak self, weak view] in if let self, let view, let item = self.manager.selected { self.recordNavigation(view, item: item) } }
            view.engineeringSnapper = { [weak self,weak view] page,point in
                view?.engineeringSnapIndicator = nil
                guard let self,let view,self.manager.engineeringSnap,let item = self.manager.selected else { return point }
                let index = item.document.index(for: page)
                guard let session = try? self.contentSession(item: item,index: index) else { return point }
                let threshold = 8/max(0.05,view.scaleFactor)
                guard let snap = session.snapCandidate(near: point,tolerance: threshold) else { return point }
                view.engineeringSnapIndicator = (page,snap,snap.kind.title(russian: self.manager.language == .ru)); return snap.point
            }
            view.engineeringPreviewText = { [weak self] page,kind,points in
                guard let self else { return "" }
                let prefix = "BotPlus engineering calibration v1:"
                var scale = EngineeringScale(unit: self.manager.engineeringUnit)
                if let text = page.annotations.first(where: { ($0.contents ?? "").hasPrefix(prefix) })?.contents,let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),let stored = try? JSONDecoder().decode(EngineeringScale.self,from: data),stored.valid { scale.millimetersPerPoint = stored.millimetersPerPoint }
                if kind == .calibration,points.count >= 2 { return String(format: "%.3f pt",hypot(points.last!.x-points[0].x,points.last!.y-points[0].y)) }
                return EngineeringMeasure(kind: kind,points: points,scale: scale).label(russian: self.manager.language == .ru)
            }
            view.onEngineeringCommit = { [weak self,weak view] page,kind,points in if let self,let view { self.commitEngineering(page: page,kind: kind,points: points,view: view) } }
            view.onSnapshot = { [weak self] page, region in self?.copySnapshot(page: page, region: region) }
            view.onCreateText = { [weak self, weak view] page, point, leader in
                guard let self, let view else { return }
                self.createFreeText(on: page, at: point, in: view, leader: leader)
            }
            view.onSourceTextRequest = { [weak self, weak view] page, point, adding, activate in
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    guard let self, let view else { return }
                    self.openSourceEditor(on: page, point: point, adding: adding, activating: activate, view: view)
                }
            }
            view.onContentRequest = { [weak self,weak view] page,point in
                guard let self,let view else { return }; self.selectContent(on: page,point: point,in: view)
            }
            view.onContentTransform = { [weak self,weak view] page,object,rect,angle in
                guard let self,let view,let item = self.manager.selected else { return }
                self.changeContent(index: object.index,pageIndex: item.document.index(for: page),bounds: rect,rotation: angle,item: item,view: view)
            }
            view.onClipboardCommand = { [weak self, weak view] command in
                guard let self, let view else { return }
                self.perform(command, on: view)
            }
            view.onEditText = { [weak self, weak view] annotation in
                guard let self, let view, let page = annotation.page else { return }
                self.openTextEditor(annotation, page: page, in: view, isNew: false, leader: nil)
            }
            view.onSelectionChanged = { [weak self, weak view] _ in
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    self?.manager.selectedAnnotation = view?.selectedAnnotation
                    self?.manager.selectedAnnotationCount = view?.annotationSelectionUnitCount ?? 0
                    if view?.contentSelection == nil { self?.manager.contentProperties.reset() }
                    if let self,let annotation = view?.selectedAnnotation {
                        self.manager.annotationColor = Color(nsColor: annotation.type == "FreeText" ? annotation.fontColor ?? .black : annotation.color)
                        self.manager.annotationOpacity = Double(AnnotationMetadata.alpha(of: annotation))
                        self.manager.annotationStrokeWidth = Double(annotation.border?.lineWidth ?? 2)
                        if annotation.type == "FreeText" { self.manager.textFontSize = Double(annotation.font?.pointSize ?? 18); self.manager.textBorderEnabled = (annotation.border?.lineWidth ?? 0) > 0 }
                        if ["Square","Circle"].contains(annotation.type ?? "") { self.manager.annotationFill = annotation.interiorColor != nil }
                        self.manager.panels.select(.properties)
                    }
                    if view?.selectedAnnotation != nil || (view?.sourceSelection == nil && view?.sourceInline == nil && view?.contentSelection == nil) { self?.manager.selectedContent = nil }
                }
            }
            view.onWillModify = { [weak self] in if let self,let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") } }
            view.onAnnotationChanged = { [weak self] in self?.manager.send(.refresh) }
            view.onMarkupFinished = { [weak self,weak view] in
                guard let self,let view else { return }
                let subtype: PDFAnnotationSubtype = view.activeTool == .underline ? .underline : (view.activeTool == .strike ? .strikeOut : .highlight)
                if view.currentSelection == nil { view.selectAnnotation(nil) }
                else { self.addMarkup(on: view,subtype: subtype) }
            }
            view.onPlaceObject = { [weak self,weak view] page,point,tool in
                guard let self,let view else { return }; self.placeObject(tool,on: page,point: point,view: view)
            }

            view.onCursorChange = { [weak self] viewport, pagePoint in
                guard let self else { return }
                if self.manager.cursorViewport != viewport { self.manager.cursorViewport = viewport }
                if self.manager.cursorPage != pagePoint { self.manager.cursorPage = pagePoint }
            }
            view.onViewportChange = { [weak self, weak view] in
                guard let self, let view else { return }
                self.scheduleViewportSync(for: view)
            }
            for name in [Notification.Name.PDFViewScaleChanged, Notification.Name.PDFViewPageChanged,Notification.Name.PDFViewSelectionChanged] {
                let token = NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if let self, let view = self.view { self.scheduleViewportSync(for: view) } }
                }
                observationTokens.append(token)
            }
        }
        func detach() {
            manager.finishSourceEditing = nil; manager.captureNavigation = nil
            navigationWork?.cancel(); navigationWork = nil
            for token in observationTokens { NotificationCenter.default.removeObserver(token) }
            observationTokens.removeAll()
            if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
            clipToken = nil; observedClip = nil
            let closing = textPopover; textPopover = nil
            let inline = view?.sourceInline; view?.sourceInline = nil
            DispatchQueue.main.async { closing?.close(); inline?.cancel() }
        }
        private func observeScroll(in view: PDFViewerView) {
            guard let clip = view.internalScrollView?.contentView, clip !== observedClip else { return }
            if let clipToken { NotificationCenter.default.removeObserver(clipToken) }
            observedClip = clip; clip.postsBoundsChangedNotifications = true
            clipToken = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { if let self, let view = self.view { self.scheduleViewportSync(for: view) } }
            }
        }

        private var updatePending = false
        func requestUpdate(_ view: PDFViewerView) {
            guard !updatePending else { return }; updatePending = true
            DispatchQueue.main.async { [weak self,weak view] in
                guard let self else { return }; self.updatePending = false
                guard let view else { return }; self.update(view)
            }
        }
        private var previousBounds = CGRect.zero
        func update(_ view: PDFViewerView) {
            manager.invalidateStaleSearch()
            var changed = previousBounds != view.bounds
            previousBounds = view.bounds
            if activeDocumentID != manager.selected?.id || view.document !== manager.selected?.document {
                changed = true
                activeDocumentID = manager.selected?.id
                lastSearchRequestID = manager.searchRequestID
                if let popover = textPopover { Task { @MainActor in popover.close() } }
                if let inline = view.sourceInline { Task { @MainActor in inline.cancel() } }
                view.engineeringDraft = nil; view.contentSelection = nil; view.contentOutlines = []; self.manager.contentProperties.reset()
                view.setSourceSelection(nil)
                view.selectAnnotation(nil)
                Task { @MainActor [weak self] in self?.manager.selectedContent = nil }
                view.installDocument(manager.selected?.document)
                view.configureZoomLimits()
                if let item = manager.selected {
                    view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, item.zoom))
                    if let saved = item.navigation.current, saved.page < item.pageCount { applyNavigation(saved, view: view, item: item) }
                    else if let page = item.document.page(at: item.pageIndex) { view.go(to: page) }
                }
            }
            let gap = manager.pageGap.isFinite ? min(40,max(0,manager.pageGap)) / 2 : 2
            if view.configuredPageMargin != gap {
                view.configuredPageMargin = gap; view.resetPagePadding(); view.layoutDocumentView(); changed = true
            }
            if view.enableDataDetectors { view.enableDataDetectors = false }
            if view.displayMode != manager.layout.pdfMode { view.displayMode = manager.layout.pdfMode; changed = true }
            if view.displaysAsBook != (manager.layout == .spread) { view.displaysAsBook = manager.layout == .spread; changed = true }
            if view.activeTool != manager.tool {
                view.engineeringDraft = nil
                view.activeTool = manager.tool; changed = true
                if manager.tool == .snapshot { view.selectAnnotation(nil); view.contentSelection = nil; view.setSourceSelection(nil) }
            }
            let markup = ![PDFTool.textSelection,.highlight,.underline,.strike].contains(manager.tool)
            if view.isInMarkupMode != markup { view.isInMarkupMode = markup }
            view.fillEnabled = manager.annotationFill
            let background = NSColor(calibratedWhite: manager.theme.isDark ? 0.12 : 0.82,alpha: 1)
            if !view.backgroundColor.isEqual(background) { view.backgroundColor = background; changed = true }
            let stroke = NSColor(manager.annotationColor).withAlphaComponent(CGFloat(manager.annotationOpacity))
            if !view.strokeColor.isEqual(stroke) { view.strokeColor = stroke; changed = true }
            if view.strokeWidth != CGFloat(manager.annotationStrokeWidth) { view.strokeWidth = CGFloat(manager.annotationStrokeWidth); changed = true }
            if changed { view.refreshOverlay() }
            observeScroll(in: view)
            if manager.searchRequestID != lastSearchRequestID {
                lastSearchRequestID = manager.searchRequestID
                manager.runSearch()
            }
            if manager.searchNavigationID != lastSearchNavigationID {
                lastSearchNavigationID = manager.searchNavigationID
                if let selection = manager.currentSearchSelection {
                    if let item = manager.selected { recordNavigation(view, item: item) }
                    view.setCurrentSelection(selection, animate: true)
                    view.go(to: selection)
                }
            }
            if lastCommand != manager.commandIndex {
                lastCommand = manager.commandIndex
                let command = manager.command
                Task { @MainActor [weak self, weak view] in
                    await Task.yield()
                    guard let self, let view else { return }
                    self.perform(command, on: view)
                }
            }
            if changed { scheduleViewportSync(for: view) }
        }

        private func perform(_ command: ViewerCommand, on view: PDFViewerView) {
            guard let item = manager.selected, view.document === item.document else { return }
            if case .history(let offset) = command { restoreNavigation(offset, view: view, item: item); return }
            recordNavigation(view, item: item)
            switch command {
            case .rotate,.deletePageAt,.duplicatePageAt,.blankPageAt,.rotatePageAt,.insertBlankPage,.deletePage,.duplicatePage:
                guard finishSourceEditor() else { return }; manager.recordUndo(item,group: "pages")
            case .applyAnnotationStyle: if view.canModifyAnnotationSelection { manager.recordUndo(item,group: "annotationStyle") }
            default: break
            }
            switch command {
            case .history: break
            case .destination(let destination): view.go(to: destination)
            case .copy: copyObjects(on: view, cutting: false)
            case .cut: copyObjects(on: view, cutting: true)
            case .paste: pasteObjects(on: view)
            case .deleteSelection: deleteObjects(on: view)
            case .refresh: break
            case .zoomIn: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = min(view.maxScaleFactor, view.scaleFactor * 1.2)
            case .zoomOut: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = max(view.minScaleFactor, view.scaleFactor / 1.2)
            case .actualSize: view.resetPagePadding(); view.autoScales = false; view.scaleFactor = 1
            case .fitPage:
                view.resetPagePadding()
                view.autoScales = true
                view.layoutSubtreeIfNeeded()
                view.autoScales = false
            case .fitWidth:
                guard let page = view.currentPage ?? item.document.page(at: 0) else { return }
                let width = page.bounds(for: view.displayBox).width
                guard width > 0 else { return }
                view.resetPagePadding(); view.autoScales = false
                view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, (view.bounds.width - 32) / width))
            case .rotate(let angle):
                guard let page = view.currentPage else { return }
                page.rotation = (page.rotation + angle + 360) % 360
                let index = item.document.index(for: page)
                reload(view, document: item, pageIndex: index)
                manager.send(.refresh)
            case .page(let index):
                if let page = item.document.page(at: index) { center(page,in: view) }
            case .deletePageAt(let index):
                guard finishSourceEditor(),item.pageCount > 1,item.document.page(at: index) != nil else { return }
                item.document.removePage(at: index); item.pageIndex = min(index,item.pageCount-1)
                reload(view,document: item,pageIndex: item.pageIndex); manager.pageText = String(item.pageIndex+1); manager.send(.refresh)
            case .duplicatePageAt(let index):
                guard finishSourceEditor(),let source = item.document.page(at: index),let duplicate = source.copy() as? PDFPage else { return }
                AnnotationMetadata.copy(from: source,to: duplicate); item.document.insert(duplicate,at: index+1); item.pageIndex = index+1
                reload(view,document: item,pageIndex: index+1); manager.pageText = String(index+2); manager.send(.refresh)
            case .copyPageAt(let index): copyPage(index,item: item)
            case .pastePagesAt(let index): pastePages(index,item: item,view: view)
            case .blankPageAt(let index):
                guard finishSourceEditor() else { return }
                let blank = PDFPage(); blank.setBounds(item.document.page(at: min(max(0,index),item.pageCount-1))?.bounds(for: .mediaBox) ?? CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox)
                let target = min(max(0,index),item.pageCount); item.document.insert(blank,at: target); item.pageIndex = target
                reload(view,document: item,pageIndex: target); manager.pageText = String(target+1); manager.send(.refresh)
            case .rotatePageAt(let index,let angle):
                guard finishSourceEditor(),let page = item.document.page(at: index) else { return }
                page.rotation = (page.rotation+angle+360)%360; item.pageIndex = index
                reload(view,document: item,pageIndex: index); manager.send(.refresh)
            case .highlight: addMarkup(on: view, subtype: .highlight)
            case .underline: addMarkup(on: view, subtype: .underline)
            case .strike: addMarkup(on: view, subtype: .strikeOut)
            case .feature(let id): performFeature(id,on: view,item: item)
            case .insertBlankPage: insertBlankPage(on: view, document: item)
            case .deletePage: deleteCurrentPage(on: view, document: item)
            case .duplicatePage:
                guard let source = view.currentPage, let duplicate = source.copy() as? PDFPage else { return }
                let index = item.document.index(for: source) + 1
                AnnotationMetadata.copy(from: source, to: duplicate)
                item.document.insert(duplicate, at: index)
                item.pageIndex = index
                reload(view, document: item, pageIndex: index)
                manager.pageText = String(index + 1); manager.send(.refresh)
            case .applyAnnotationStyle:
                guard view.canModifyAnnotationSelection else { break }
                for annotation in view.selectedAnnotations {
                    if annotation.type == "Stamp" { continue }
                    annotation.removeValue(forAnnotationKey: .appearanceDictionary)
                    annotation.color = annotation.type == "FreeText" ? .clear : view.strokeColor
                    AnnotationMetadata.setOpacity(manager.annotationOpacity, on: annotation)
                    let border = PDFBorder(); border.lineWidth = view.strokeWidth
                    annotation.border = annotation.type == "FreeText" && !manager.textBorderEnabled ? nil : border
                    if ["Square","Circle"].contains(annotation.type ?? "") { annotation.interiorColor = manager.annotationFill ? view.strokeColor.withAlphaComponent(view.strokeColor.alphaComponent*0.25) : nil }
                    if annotation.type == "FreeText" {
                        annotation.fontColor = view.strokeColor
                        annotation.font = NSFont.systemFont(ofSize: CGFloat(manager.textFontSize))
                        if let group = AnnotationMetadata.group(of: annotation), let page = annotation.page {
                            for leader in page.annotations where leader.type == "Line" && AnnotationMetadata.group(of: leader) == group {
                                leader.removeValue(forAnnotationKey: .appearanceDictionary)
                                leader.color = view.strokeColor; leader.border = border
                                AnnotationMetadata.setOpacity(manager.annotationOpacity, on: leader)
                            }
                        }
                    }
                    if ["Highlight","Underline","StrikeOut"].contains(annotation.type ?? "") {
                        for part in annotationComponents(annotation) where part !== annotation {
                            part.removeValue(forAnnotationKey: .appearanceDictionary); part.color = view.strokeColor; part.border = border
                            AnnotationMetadata.setOpacity(manager.annotationOpacity,on: part)
                        }
                    }
                    view.updateEngineeringMeasurement(); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh)
                }
            case .print:
                guard view.document != nil, view.document === item.document else { return }
                showAdvancedPrint(item: item,view: view)
            case .setZoom(let zoom):
                view.autoScales = false
                view.scaleFactor = max(view.minScaleFactor, min(view.maxScaleFactor, zoom))
            }
            switch command { case .page,.destination: recordNavigation(view,item: item); default: break }
            scheduleViewportSync(for: view)
        }


        private var contentDocument: ObjectIdentifier?
        private var contentRevision = -1
        private var contentSessions: [Int:PDFContentSession] = [:]
        private var contentRefreshPending = false
        private func contentSession(item: PDFDocumentItem,index: Int) throws -> PDFContentSession {
            let identity = ObjectIdentifier(item.document)
            if identity != contentDocument || contentRevision != manager.contentRevision {
                contentDocument = identity; contentRevision = manager.contentRevision; contentSessions.removeAll()
            }
            if let cached = contentSessions[index] { return cached }
            let session = try PDFContentSession(data: sourceData(item),pageIndex: index)
            if contentSessions.count >= 3 { contentSessions.removeAll() }
            contentSessions[index] = session; return session
        }
        private struct ContentOutlineKey: Equatable {
            let document: ObjectIdentifier
            let revision: Int
            let pages: [Int]
        }
        private var contentOutlineKey: ContentOutlineKey?
        private(set) var contentOutlineBuildCount = 0
        private func refreshContentOutlines(_ view: PDFViewerView) {
            guard manager.tool == .editContent,let item = manager.selected,view.document === item.document else {
                view.contentOutlines = []; contentOutlineKey = nil
                if view.contentSelection != nil { clearContentSelection(view) }
                return
            }
            let visible = (view.visiblePages.isEmpty ? (view.currentPage.map { [$0] } ?? []) : view.visiblePages).prefix(3)
            let requestedKey = ContentOutlineKey(document: ObjectIdentifier(item.document), revision: manager.contentRevision,
                pages: visible.map { item.document.index(for: $0) })
            guard requestedKey != contentOutlineKey, !contentRefreshPending else { return }
            contentRefreshPending = true
            let identity = ObjectIdentifier(item.document)
            Task { @MainActor [weak self,weak view,weak item] in
                await Task.yield()
                guard let self else { return }; defer { self.contentRefreshPending = false }
                guard let view,let item,view.document === item.document,ObjectIdentifier(item.document) == identity,self.manager.tool == .editContent else { return }
                let pages = Array((view.visiblePages.isEmpty ? (view.currentPage.map { [$0] } ?? []) : view.visiblePages).prefix(3))
                let key = ContentOutlineKey(document: identity, revision: self.manager.contentRevision,
                    pages: pages.map { item.document.index(for: $0) })
                guard key != self.contentOutlineKey else { return }
                var outlines: [(page: PDFPage,object: PDFSourceSession.ContentObject)] = []
                do {
                    for page in pages {
                        let index = item.document.index(for: page)
                        let session = try self.contentSession(item: item,index: index)
                        outlines += session.objects.map { (page,$0) }
                    }
                    view.contentOutlines = outlines; self.contentOutlineKey = key
                    self.contentOutlineBuildCount += 1; view.refreshOverlay()
                } catch { self.sourceError(error) }
            }
        }
        private func clearContentSelection(_ view: PDFViewerView) {
            view.contentSelection = nil; view.contentPreview = nil
            manager.contentProperties.reset(); manager.selectedContent = nil; view.refreshOverlay()
        }
        private func selectContent(on page: PDFPage,point: CGPoint,in view: PDFViewerView) {
            guard let item = manager.selected,view.document === item.document,finishSourceEditor() else { return }
            manager.textProperties.reset()
            do {
                let index = item.document.index(for: page),session = try contentSession(item: item,index: index)
                guard let info = session.select(at: point,tolerance: 5/max(0.05,view.scaleFactor)) else { clearContentSelection(view); return }
                activateContent(info,page: page,item: item,index: index,view: view)
            } catch { sourceError(error) }
        }
        private func activateContent(_ info: PDFSourceSession.ContentObject,page: PDFPage,item: PDFDocumentItem,index: Int,view: PDFViewerView) {
            view.selectAnnotation(nil); view.setSourceSelection(nil)
            view.contentSelection = (page,info); manager.selectedAnnotation = nil; manager.selectedContent = info
            let properties = manager.contentProperties
            properties.load(info); manager.panels.select(.properties)
            let expected = item.document
            properties.apply = { [weak self,weak view,weak item,weak properties] in
                guard let self,let view,let item,let properties,item.document === expected else { return }
                self.changeContent(index: info.index,pageIndex: index,bounds: properties.bounds,rotation: properties.rotation*CGFloat.pi/180,style: properties.style,item: item,view: view)
            }
            properties.editNodes = { [weak self,weak view] in
                guard let self,let view,item.document === expected else { return }
                do {
                    let nodes = try self.contentSession(item: item,index: index).pathNodes(index: info.index)
                    self.manager.pathRequest = PDFPathRequest(nodes: nodes,russian: self.manager.language == .ru) { [weak self,weak view] nodes in
                        guard let self,let view,item.document === expected else { return "Document changed / Документ изменился" }
                        do {
                            let data = try self.contentSession(item: item,index: index).replacePath(index: info.index,nodes: nodes)
                            try self.installSourceData(data,item: item,index: index,view: view,bounds: nil); item.enableStreamPreservation(); self.clearContentSelection(view); self.refreshContentOutlines(view); return nil
                        } catch { return "This path could not be rebuilt safely. Clipping, tags, patterns or transparency require a deeper editor. / Этот контур нельзя безопасно пересоздать: обрезка, теги, узоры или прозрачность требуют расширенного редактора." }
                    }
                } catch { self.sourceError(error) }
            }
            properties.arrange = { [weak self,weak view] direction in
                guard let self,let view,item.document === expected else { return }
                do {
                    let (data,newIndex) = try self.contentSession(item: item,index: index).reorder(index: info.index,direction: direction)
                    try self.installSourceData(data,item: item,index: index,view: view,bounds: nil); item.enableStreamPreservation()
                    if let page = item.document.page(at: index),let selected = try self.contentSession(item: item,index: index).info(newIndex) { self.activateContent(selected,page: page,item: item,index: index,view: view) }
                    self.refreshContentOutlines(view)
                } catch { self.sourceError(error) }
            }
            properties.delete = { [weak self,weak view] in guard let self,let view else { return }; self.deleteContent(view) }
            properties.replace = { [weak self,weak view,weak item] in
                guard let self,let view else { return }
                PDFDialogs.open([.image]) { [weak self,weak view,weak item] urls in
                    guard let self,let view,let item,item.document === expected,let url = urls.first else { return }
                    let lease = FileAccessLease(url); _ = lease
                    guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil,context: nil,hints: nil) else { return }
                    self.changeContent(index: info.index,pageIndex: index,bounds: info.bounds,rotation: 0,image: image,item: item,view: view)
                }
            }
            view.refreshOverlay(); manager.refreshClipboard()
        }
        private func changeContent(index: Int,pageIndex: Int,bounds: CGRect,rotation: CGFloat,style: PDFContentSession.Style? = nil,image: CGImage? = nil,delete: Bool = false,item: PDFDocumentItem,view: PDFViewerView) {
            guard view.document === item.document else { return }
            do {
                let session = try contentSession(item: item,index: pageIndex)
                let data = try session.applying(index: index,bounds: bounds,rotation: rotation,style: style,image: image,delete: delete)
                let result = session.result
                try installSourceData(data,item: item,index: pageIndex,view: view,bounds: nil)
                contentSessions.removeAll(); manager.contentProperties.reset()
                if let result,let page = item.document.page(at: pageIndex) {
                    let newSession = try contentSession(item: item,index: pageIndex)
                    let match = newSession.objects.filter { $0.kind == result.kind }.min { a,b in
                        hypot(a.bounds.midX-result.bounds.midX,a.bounds.midY-result.bounds.midY) < hypot(b.bounds.midX-result.bounds.midX,b.bounds.midY-result.bounds.midY)
                    }
                    if let match { activateContent(match,page: page,item: item,index: pageIndex,view: view) }
                } else { clearContentSelection(view) }
                refreshContentOutlines(view)
            } catch { contentSessions.removeAll(); sourceError(error) }
        }
        private func deleteContent(_ view: PDFViewerView) {
            guard let item = manager.selected,let selection = view.contentSelection else { return }
            changeContent(index: selection.object.index,pageIndex: item.document.index(for: selection.page),bounds: selection.object.bounds,rotation: 0,delete: true,item: item,view: view)
        }
        private func copyContent(_ view: PDFViewerView,cut: Bool) -> Bool {
            guard let item = manager.selected,item.document.allowsCopying,let selection = view.contentSelection else { return false }
            do {
                let session = try contentSession(item: item,index: item.document.index(for: selection.page))
                let clipboard = try session.clipboard(index: selection.object.index)
                let board = NSPasteboard.general; board.clearContents()
                guard board.setData(try JSONEncoder().encode(clipboard),forType: ObjectClipboard.contentObject) else { return false }
                manager.refreshClipboard()
                if cut { deleteContent(view) }; return true
            } catch { sourceError(error); return false }
        }
        private func pasteContent(_ data: Data,item: PDFDocumentItem,view: PDFViewerView) throws {
            let clipboard = try JSONDecoder().decode(PDFContentSession.Clipboard.self,from: data)
            guard let page = view.currentPage else { return }
            let index = item.document.index(for: page),crop = page.bounds(for: .cropBox)
            let session = try PDFContentSession(data: sourceData(item),pageIndex: index)
            let changed = try session.pasting(clipboard,at: CGPoint(x: crop.midX-clipboard.bounds.width/2,y: crop.midY+clipboard.bounds.height/2))
            let info = session.result
            try installSourceData(changed,item: item,index: index,view: view,bounds: nil)
            manager.tool = .editContent
            if let info,let page = item.document.page(at: index),let inserted = try contentSession(item: item,index: index).objects.last { activateContent(inserted,page: page,item: item,index: index,view: view); _ = info }
            refreshContentOutlines(view)
        }
        private func sourceData(_ item: PDFDocumentItem) throws -> Data {
            guard item.document.allowsDocumentChanges else { throw PDFSourceError.permission }
            return try manager.serializedData(item)
        }
        private func sourceError(_ error: Error) {
            AppDiagnostics.error("source_edit", error)
            if let error = error as? PDFSourceError { manager.say(error.english, error.russian) }
            else { manager.say("Could not modify the PDF text.", "Не удалось изменить текст PDF.") }
        }
        private func installSourceData(_ data: Data, item: PDFDocumentItem, index: Int, view: PDFViewerView, bounds: CGRect?, anchor: CGPoint? = nil,restoreBookmarks: Bool = true) throws {
            guard let document = PDFDocument(data: data), document.pageCount == item.pageCount else { throw PDFSourceError.save }
            AnnotationMetadata.restore(document)
            if restoreBookmarks { PDFBookmarkStore.restore(PDFBookmarkStore.capture(item.document),on: document) }
            manager.recordUndo(item,group: "sourceText")
            item.document = document; item.pageIndex = index
            reload(view, document: item, pageIndex: index,centerPage: false)
            if let bounds, let page = document.page(at: index) {
                view.setSourceSelection((page, bounds)); sourceAnchor = (index, anchor ?? CGPoint(x: bounds.midX, y: bounds.midY))
            } else { view.setSourceSelection(nil); sourceAnchor = nil }
            manager.pageText = String(index + 1); manager.send(.refresh)
            manager.seedSerializedData(data,item: item)
        }
        private func finishSourceEditor() -> Bool {
            guard let inline = view?.sourceInline else { return true }
            return inline.finish()
        }
        private func refreshSourceOutlines(_ view: PDFViewerView) {
            guard manager.tool == .editText,let item = manager.selected,view.document === item.document else {
                view.sourceBlocks = []; view.refreshOverlay(); return
            }
            let identity = ObjectIdentifier(item.document)
            if sourceDocument != identity {
                sourceDocument = identity; sourceOutlineData = nil; sourceOutlineCache = [:]
                outlineGeneration += 1; outlinePending = false
            }
            let pages = view.visiblePages.isEmpty ? (view.currentPage.map { [$0] } ?? []) : view.visiblePages
            let indices = pages.map { item.document.index(for: $0) }.filter { $0 >= 0 && $0 < item.pageCount }
            @MainActor func install() {
                view.sourceBlocks = indices.flatMap { index -> [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] in
                    guard let page = item.document.page(at: index) else { return [] }
                    return (sourceOutlineCache[index] ?? []).map { (page,$0) }
                }
                view.refreshOverlay()
            }
            if indices.allSatisfy({ sourceOutlineCache[$0] != nil }) { install(); return }
            guard !outlinePending else { return }; outlinePending = true
            let generation = outlineGeneration
            Task { @MainActor [weak self,weak view,weak item] in
                await Task.yield()
                guard let self,let view,let item,self.outlineGeneration == generation,
                      view.document === item.document,self.manager.tool == .editText else { return }
                defer { self.outlinePending = false }
                do {
                    let data = try self.sourceOutlineData ?? self.sourceData(item)
                    self.sourceOutlineData = data
                    for index in indices where self.sourceOutlineCache[index] == nil {
                        self.sourceOutlineCache[index] = try PDFSourceSession.blocks(data: data,pageIndex: index)
                    }
                    view.sourceBlocks = indices.flatMap { index -> [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] in
                        guard let page = item.document.page(at: index) else { return [] }
                        return (self.sourceOutlineCache[index] ?? []).map { (page,$0) }
                    }
                    view.refreshOverlay()
                } catch { self.sourceError(error) }
            }
        }
        private func openSourceEditor(on page: PDFPage, point: CGPoint, adding: Bool, activating: Bool = true, view: PDFViewerView) {
            guard let item = manager.selected,item.document === view.document else { return }
            let requestedIndex = item.document.index(for: page)
            do {
                let index = requestedIndex
                let click = view.convert(point,from: page)
                let descriptor = view.sourceBlocks.last { $0.page === page && $0.block.snapshot.bounds.contains(point) }
                let selectionPoint = descriptor?.block.point ?? point
                guard finishSourceEditor() else { return }
                guard let targetPage = item.document.page(at: index) else { throw PDFSourceError.page }
                let data = try sourceData(item)
                let session = try adding
                    ? PDFSourceSession.adding(data: data,pageIndex: index,point: point,fontSize: CGFloat(manager.textFontSize),color: NSColor(manager.annotationColor))
                    : PDFSourceSession.editing(data: data,pageIndex: index,point: selectionPoint)
                view.selectAnnotation(nil); view.setSourceSelection((targetPage,session.snapshot.bounds)); sourceAnchor = (index,selectionPoint)
                let expectedDocument = item.document
                if fontDocument != ObjectIdentifier(item.document) {
                    fontNames = try PDFSourceSession.documentFonts(data: data); fontDocument = ObjectIdentifier(item.document)
                }
                manager.textProperties.fonts = fontNames
                let previewData = try session.previewWithoutSelectedText()
                let previewDocument = PDFDocument(data: previewData)
                if let previewDocument { AnnotationMetadata.restore(previewDocument) }
                let inline = PDFInlineTextEditor(snapshot: session.snapshot,page: targetPage,pdfView: view,model: manager.textProperties,previewPage: previewDocument?.page(at: index))
                manager.selectedContent = nil
                inline.onApply = { [weak self,weak view,weak item] text,width,height,geometry in
                    guard let self,let view,let item,self.manager.selected?.id == item.id,item.document === expectedDocument else { return false }
                    do {
                        let committing = try adding
                            ? PDFSourceSession.adding(data: data,pageIndex: index,point: point,fontSize: session.snapshot.fontSize,color: session.snapshot.color)
                            : PDFSourceSession.editing(data: data,pageIndex: index,point: selectionPoint)
                        let changed = try committing.applying(text: text.string,fontSize: session.snapshot.fontSize,color: session.snapshot.color,width: width,height: height,richText: text,geometry: geometry)
                        try self.installSourceData(changed,item: item,index: index,view: view,bounds: committing.resultingBounds,anchor: committing.resultingPoint)
                        return true
                    } catch { self.sourceError(error); return false }
                }
                inline.onCancel = { [weak self,weak view] in view?.setSourceSelection(nil); self?.sourceAnchor = nil }
                inline.onRedraw = { [weak view,weak inline] in
                    guard let view else { return }
                    if inline?.isAttached == false { view.sourceInline = nil }
                    view.refreshOverlay()
                }
                view.sourceInline = inline; manager.panels.select(.properties)
                inline.focus(at: click); view.refreshOverlay()
            } catch PDFSourceError.textNotFound {
                view.setSourceSelection(nil); sourceAnchor = nil; manager.selectedAnnotation = nil; manager.selectedContent = nil
                if let item = manager.selected,let currentPage = item.document.page(at: requestedIndex) {
                    let index = requestedIndex
                    if let object = try? PDFSourceSession.objectInfo(data: sourceData(item),pageIndex: index,point: point) {
                        manager.selectedContent = object; view.setSourceSelection((currentPage,object.bounds)); manager.panels.select(.properties)
                    }
                }
            } catch { sourceError(error) }
        }
        private func annotationComponents(_ annotation: PDFAnnotation) -> [PDFAnnotation] {
            if let group = AnnotationMetadata.group(of: annotation), let page = annotation.page {
                return page.annotations.filter { AnnotationMetadata.group(of: $0) == group }
            }
            return [annotation]
        }
        private func annotationCopy(_ original: PDFAnnotation) -> PDFAnnotation? {
            guard let copy = original.copy() as? PDFAnnotation else { return nil }
            copy.page = nil
            if let sourcePopup = original.popup {
                guard let popup = sourcePopup.copy() as? PDFAnnotation else { return nil }; popup.page = nil; copy.popup = popup
            } else { copy.popup = nil }
            return copy
        }
        private func annotationClipboardData(_ annotation: PDFAnnotation) -> Data? { annotationClipboardData(annotationComponents(annotation)) }
        private func annotationClipboardData(_ annotations: [PDFAnnotation]) -> Data? {
            guard let page = annotations.first?.page,page.document?.allowsCopying == true,!annotations.isEmpty,annotations.allSatisfy({ $0.page === page }) else { return nil }
            let components = page.annotations.filter { candidate in annotations.contains(where: { $0 === candidate }) }
            let clipboardPage = PDFPage(); clipboardPage.setBounds(page.bounds(for: .mediaBox), for: .mediaBox)
            clipboardPage.setBounds(page.bounds(for: .cropBox), for: .cropBox)
            let copies = components.compactMap(annotationCopy)
            guard copies.count == components.count else { return nil }
            for copy in copies { copy.page = nil; clipboardPage.addAnnotation(copy) }
            AnnotationMetadata.transfer(from: components, to: copies)
            let document = PDFDocument(); document.insert(clipboardPage, at: 0)
            AnnotationMetadata.prepareForSave(document)
            guard let data = document.dataRepresentation(options: [PDFDocumentWriteOption.saveTextFromOCROption: false]) else { return nil }
            return data
        }
        private func copyAnnotationObjects(_ annotation: PDFAnnotation, board: NSPasteboard = .general) -> Bool { copyAnnotationObjects(annotationComponents(annotation),board: board) }
        private func copyAnnotationObjects(_ annotations: [PDFAnnotation],board: NSPasteboard = .general) -> Bool {
            guard let data = annotationClipboardData(annotations) else { return false }
            board.clearContents()
            let success = board.setData(data, forType: ObjectClipboard.annotations)
            _ = board.setData(data, forType: .pdf)
            let text = annotations.compactMap(\.contents).joined(separator: "\n"); if !text.isEmpty { _ = board.setString(text,forType: .string) }
            return success
        }
        private func sourceSessionForSelection(view: PDFViewerView) throws -> (PDFSourceSession, PDFDocumentItem, Int, String?) {
            guard let item = manager.selected else { throw PDFSourceError.document }
            if let sourceAnchor, view.sourceSelection != nil {
                return (try PDFSourceSession.editing(data: sourceData(item), pageIndex: sourceAnchor.index, point: sourceAnchor.point), item, sourceAnchor.index, nil)
            }
            if let selection = view.currentSelection, let page = selection.pages.first, selection.pages.count == 1,
               let text = selection.string, !text.isEmpty {
                let bounds = selection.bounds(for: page), index = item.document.index(for: page)
                return (try PDFSourceSession.editing(data: sourceData(item), pageIndex: index, point: CGPoint(x: bounds.midX,y: bounds.midY)), item, index, text)
            }
            throw PDFSourceError.textNotFound
        }
        private func writeTextClipboard(_ text: String, snapshot: PDFSourceSession.Snapshot) {
            let board = NSPasteboard.general; board.clearContents(); _ = board.setString(text, forType: .string)
            let style = ObjectClipboard.TextStyle(text: text, size: snapshot.fontSize, name: snapshot.fontName, color: snapshot.color)
            if let data = try? JSONEncoder().encode(style) { _ = board.setData(data, forType: ObjectClipboard.sourceText) }
        }
        private func copyObjects(on view: PDFViewerView, cutting: Bool) {
            defer { manager.refreshClipboard() }
            guard view.document?.allowsCopying == true else { return }
            if view.contentSelection != nil { _ = copyContent(view,cut: cutting); return }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                if cutting { editor.cut(nil) } else { editor.copy(nil) }; return
            }
            if view.selectedAnnotation != nil {
                if cutting && !view.canModifyAnnotationSelection { return }
                if copyAnnotationObjects(view.selectedAnnotations) {
                    if cutting { _ = view.deleteSelectedAnnotation() }
                } else { manager.say("Could not write to the clipboard.", "Не удалось записать данные в буфер обмена.") }
                return
            }
            if !cutting, let selection = view.currentSelection, let text = selection.string, !text.isEmpty, view.sourceSelection == nil {
                let board = NSPasteboard.general; board.clearContents(); _ = board.setString(text, forType: .string); return
            }
            do {
                let (session, item, index, selected) = try sourceSessionForSelection(view: view)
                let copied = selected ?? session.snapshot.text
                writeTextClipboard(copied, snapshot: session.snapshot)
                if cutting {
                    let remaining: String
                    if let selected {
                        guard let range = session.snapshot.text.range(of: selected) else { throw PDFSourceError.content }
                        var updated = session.snapshot.text; updated.removeSubrange(range); remaining = updated
                    } else { remaining = "" }
                    let data = try session.applying(text: remaining, fontSize: session.snapshot.fontSize, color: session.snapshot.color)
                    try installSourceData(data, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
                }
            } catch { sourceError(error) }
        }
        private func deleteObjects(on view: PDFViewerView) {
            if view.contentSelection != nil { deleteContent(view); return }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.delete(nil); return }
            if view.deleteSelectedAnnotation() { return }
            do {
                let (session, item, index, selected) = try sourceSessionForSelection(view: view)
                var remaining = ""
                if let selected {
                    guard let range = session.snapshot.text.range(of: selected) else { throw PDFSourceError.content }
                    remaining = session.snapshot.text; remaining.removeSubrange(range)
                }
                let data = try session.applying(text: remaining, fontSize: session.snapshot.fontSize, color: session.snapshot.color)
                try installSourceData(data, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
            } catch { sourceError(error) }
        }
        private func pasteAnnotationData(_ data: Data, on view: PDFViewerView) -> Bool {
            guard let target = view.currentPage,let document = target.document,document === view.document,let source = PDFDocument(data: data),source.allowsCopying,let page = source.page(at: 0) else { return false }
                AnnotationMetadata.restore(source)
                let originals = page.annotations.filter { $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }
                guard originals.allSatisfy({ ["Widget","Link"].contains($0.type ?? "") ? document.allowsDocumentChanges : document.allowsCommenting }) else { return false }
                let copies = originals.compactMap(annotationCopy)
                guard !copies.isEmpty, copies.count == originals.count else { return false }
                let union = copies.reduce(CGRect.null) { $0.union($1.bounds) }
                let center = view.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), to: target)
                let crop = target.bounds(for: .cropBox)
                let x = min(max(crop.minX, center.x-union.width/2), max(crop.minX,crop.maxX-union.width))
                let y = min(max(crop.minY, center.y-union.height/2), max(crop.minY,crop.maxY-union.height))
                for copy in copies { copy.page = nil; copy.bounds = copy.bounds.offsetBy(dx: x-union.minX,dy: y-union.minY); target.addAnnotation(copy) }
                AnnotationMetadata.transfer(from: originals, to: copies)
                manager.tool = .selectComments; view.setSourceSelection(nil); view.selectAnnotations(copies)
                view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
        }

        private func pasteObjects(on view: PDFViewerView, board: NSPasteboard = .general) {
            if let data = board.data(forType: ObjectClipboard.contentObject),let item = manager.selected {
                do { try pasteContent(data,item: item,view: view) } catch { sourceError(error) }; return
            }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.paste(nil); return }
            guard let item = manager.selected, let target = view.currentPage else { return }
            if let data = board.data(forType: ObjectClipboard.annotations) {
                if !pasteAnnotationData(data, on: view) { manager.say("Could not paste these PDF objects.", "Не удалось вставить эти объекты PDF.") }
                return
            }
            let style = board.data(forType: ObjectClipboard.sourceText).flatMap { try? JSONDecoder().decode(ObjectClipboard.TextStyle.self, from: $0) }
            guard let text = style?.text ?? board.string(forType: .string), !text.isEmpty else {
                manager.say("The clipboard contains no PDF objects or text.", "В буфере обмена нет объектов PDF или текста."); return
            }
            do {
                let index = item.document.index(for: target)
                let point = view.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), to: target)
                let size = CGFloat(min(200,max(1,style?.fontSize ?? manager.textFontSize)))
                let color = style?.color ?? NSColor(manager.annotationColor)
                let session = try PDFSourceSession.adding(data: sourceData(item), pageIndex: index, point: point, fontSize: size, color: color, fontName: style?.fontName ?? "Arial")
                let changed = try session.applying(text: text, fontSize: size, color: color)
                manager.tool = .editText
                try installSourceData(changed, item: item, index: index, view: view, bounds: session.resultingBounds, anchor: session.resultingPoint)
            } catch { sourceError(error) }
        }

        private func scheduleViewportSync(for view: PDFViewerView) {
            guard !syncScheduled else { return }
            syncScheduled = true
            Task { @MainActor [weak self, weak view] in
                await Task.yield()
                guard let self else { return }
                self.syncScheduled = false
                guard let view, let item = self.manager.selected, view.document === item.document else { return }
                self.observeScroll(in: view)
                let hasSelection = view.currentSelection != nil
                if self.manager.hasTextSelection != hasSelection { self.manager.hasTextSelection = hasSelection }
                self.syncPage(); self.syncMetrics(for: view); view.sourceInline?.updatePlacement(); view.refreshOverlay(); self.refreshSourceOutlines(view); self.refreshContentOutlines(view)
                if item.zoom != view.scaleFactor { item.zoom = view.scaleFactor }
                self.scheduleNavigation(view, item: item)
            }
        }

        private func addMarkup(on view: PDFViewerView, subtype: PDFAnnotationSubtype) {
            guard let selection = view.currentSelection, !(selection.string ?? "").isEmpty else { return }
            if let item = manager.selected { manager.recordUndo(item,group: "markup") }
            let tint = NSColor(manager.annotationColor).withAlphaComponent(CGFloat(manager.annotationOpacity))
            let group = UUID().uuidString
            let lineSelections = selection.selectionsByLine()
            if lineSelections.isEmpty {
                addMarkup(selection, subtype: subtype, color: tint,group: group)
            } else {
                for lineSelection in lineSelections { addMarkup(lineSelection, subtype: subtype, color: tint,group: group) }
            }
            view.setCurrentSelection(nil, animate: false)
            view.setNeedsDisplay(view.bounds)
        }

        private func addMarkup(_ selection: PDFSelection, subtype: PDFAnnotationSubtype, color: NSColor,group: String) {
            for page in selection.pages {
                let bounds = selection.bounds(for: page).insetBy(dx: -1, dy: -1)
                guard !bounds.isEmpty else { continue }
                let annotation = PDFAnnotation(bounds: bounds, forType: subtype, withProperties: nil)
                annotation.color = color
                AnnotationMetadata.setGroup(group,on: annotation)
                AnnotationMetadata.setOpacity(Double(color.alphaComponent), on: annotation)
                page.addAnnotation(annotation)
                view?.selectAnnotation(annotation)
            }
        }

        func createFreeText(on page: PDFPage, at point: CGPoint, in view: PDFViewerView, leader: PDFAnnotation?) {
            let crop = page.bounds(for: .cropBox)
            let width = min(260, crop.width)
            let x = min(max(point.x, crop.minX), crop.maxX - width)
            let y = max(crop.minY, min(point.y - 60, crop.maxY - 60))
            let annotation = PDFAnnotation(bounds: CGRect(x: x, y: y, width: width, height: 60), forType: .freeText, withProperties: nil)
            annotation.contents = ""
            annotation.font = NSFont.systemFont(ofSize: CGFloat(manager.textFontSize))
            annotation.fontColor = view.strokeColor
            annotation.color = .clear
            AnnotationMetadata.setOpacity(manager.annotationOpacity, on: annotation)
            if let leader, let group = AnnotationMetadata.group(of: leader) {
                AnnotationMetadata.setGroup(group, on: annotation)
            }
            annotation.alignment = .left
            let border = PDFBorder(); border.lineWidth = manager.textBorderEnabled ? view.strokeWidth : 0
            annotation.border = border
            page.addAnnotation(annotation)
            view.selectAnnotation(annotation)
            openTextEditor(annotation, page: page, in: view, isNew: true, leader: leader)
        }
        private func openTextEditor(_ annotation: PDFAnnotation, page: PDFPage, in view: PDFViewerView, isNew: Bool, leader: PDFAnnotation?) {
            textPopover?.close()
            let popover = NSPopover()
            let editor = FreeTextEditorController(annotation: annotation, language: manager.language)
            editor.onLiveChange = { [weak view] in
                view?.updateCalloutLeader(for: annotation)
                view?.refreshOverlay(); view?.setNeedsDisplay(view?.bounds ?? .zero)
            }
            editor.onFinish = { [weak self,weak view,weak popover] cancelled in
                DispatchQueue.main.async { [weak self,weak view,weak popover] in
                    if isNew && (cancelled || (annotation.contents ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                        page.removeAnnotation(annotation)
                        if let leader { page.removeAnnotation(leader) }
                        if view?.selectedAnnotation === annotation { view?.selectAnnotation(nil) }
                    }
                    view?.updateCalloutLeader(for: annotation)
                    view?.refreshOverlay(); view?.setNeedsDisplay(view?.bounds ?? .zero)
                    Task { @MainActor [weak self] in
                        await Task.yield()
                        self?.manager.send(.refresh)
                    }
                    if self?.textPopover === popover { self?.textPopover = nil }
                }
            }
            popover.behavior = .transient
            popover.animates = false
            popover.contentSize = NSSize(width: 360, height: 255)
            popover.contentViewController = editor; popover.delegate = editor; editor.popover = popover
            textPopover = popover
            let anchor = view.convert(annotation.bounds, from: page).intersection(view.bounds)
            popover.show(relativeTo: anchor.isEmpty ? CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1) : anchor, of: view, preferredEdge: .maxY)
            popover.contentViewController?.view.window?.makeFirstResponder(editor.textView)
        }

        private func center(_ page: PDFPage,in view: PDFViewerView) {
            view.go(to: page); view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
            if let scroll = view.internalScrollView {
                let rect = view.convert(page.bounds(for: view.displayBox),from: page)
                let vertical = max(0,(scroll.contentView.bounds.height-rect.height)/2)
                let gap = view.configuredPageMargin
                let next = NSEdgeInsets(top: gap,left: gap,bottom: gap,right: gap)
                let previous = view.pageBreakMargins
                if previous.top != gap || previous.bottom != gap || previous.left != gap || previous.right != gap { view.pageBreakMargins = next; view.layoutDocumentView(); view.layoutSubtreeIfNeeded() }
                // Padding belongs at the document edges, not on every page.
                scroll.automaticallyAdjustsContentInsets = false
                scroll.contentInsets = NSEdgeInsets(top: vertical,left: 0,bottom: vertical,right: 0)
                view.layoutSubtreeIfNeeded()
            }
            guard let documentView = view.documentView,let scroll = view.internalScrollView else { return }
            let clip = scroll.contentView
            let rect = documentView.convert(view.convert(page.bounds(for: view.displayBox),from: page),from: view)
            let target = CGPoint(x: rect.midX-clip.bounds.width/2,y: rect.midY-clip.bounds.height/2)
            let constrained = clip.constrainBoundsRect(CGRect(origin: target,size: clip.bounds.size)).origin
            let centered = CGPoint(x: rect.width < clip.bounds.width ? target.x : constrained.x,y: rect.height < clip.bounds.height ? target.y : constrained.y)
            clip.setBoundsOrigin(centered)
            scroll.reflectScrolledClipView(clip); view.onViewportChange?()
        }
        private func copyPage(_ index: Int,item: PDFDocumentItem,board: NSPasteboard = .general) {
            guard finishSourceEditor(),let source = item.document.page(at: index),let copy = source.copy() as? PDFPage else { return }
            AnnotationMetadata.copy(from: source,to: copy)
            let document = PDFDocument(); document.insert(copy,at: 0); AnnotationMetadata.prepareForSave(document)
            guard let data = document.dataRepresentation(options: [PDFDocumentWriteOption.saveTextFromOCROption: false]) else { return }
            board.clearContents(); _ = board.setData(data,forType: ObjectClipboard.pages); _ = board.setData(data,forType: .pdf)
        }
        private func pastePages(_ index: Int,item: PDFDocumentItem,view: PDFViewerView,board: NSPasteboard = .general) {
            guard item.document.allowsDocumentAssembly || item.document.allowsDocumentChanges else { return }
            guard finishSourceEditor(),let data = board.data(forType: ObjectClipboard.pages) ?? board.data(forType: .pdf),let document = PDFDocument(data: data),document.pageCount > 0 else {
                manager.say("No PDF pages in the clipboard.","В буфере обмена нет страниц PDF."); return
            }
            AnnotationMetadata.restore(document)
            let target = min(max(0,index),item.pageCount)
            for offset in 0..<document.pageCount {
                guard let source = document.page(at: offset),let copy = source.copy() as? PDFPage else { continue }
                AnnotationMetadata.copy(from: source,to: copy); item.document.insert(copy,at: target+offset)
            }
            for offset in 0..<document.pageCount {
                guard let source = document.page(at: offset),let copy = item.document.page(at: target+offset) else { continue }
                let originals = source.annotations.filter { !AnnotationMetadata.isContainer($0) },duplicates = copy.annotations.filter { !AnnotationMetadata.isContainer($0) }
                for (a,b) in zip(originals,duplicates) {
                    guard let destination = (a.action as? PDFActionGoTo)?.destination ?? a.destination,let page = destination.page else { continue }
                    let local = document.index(for: page)
                    if local >= 0,local < document.pageCount,let actual = item.document.page(at: target+local) { let value = PDFDestination(page: actual,at: destination.point); value.zoom = destination.zoom; b.destination = value; b.action = PDFActionGoTo(destination: value) }
                }
            }
            if let bookmarks = PDFBookmarkStore.capture(document),!bookmarks.isEmpty {
                func shifted(_ record: PDFBookmarkStore.Record) -> PDFBookmarkStore.Record { PDFBookmarkStore.Record(title: record.title,page: record.page.map { $0+target },point: record.point,zoom: record.zoom,action: record.action,children: record.children.map(shifted)) }
                PDFBookmarkStore.restore((PDFBookmarkStore.capture(item.document) ?? [])+bookmarks.map(shifted),on: item.document)
            }
            item.pageIndex = target; reload(view,document: item,pageIndex: target); manager.pageText = String(target+1); manager.send(.refresh)
        }

        private func insertBlankPage(on view: PDFViewerView, document item: PDFDocumentItem) {
            let currentIndex = view.currentPage.map { item.document.index(for: $0) } ?? item.pageIndex
            let insertIndex = min(max(currentIndex, 0), item.pageCount)
            let page = PDFPage()
            page.setBounds(CGRect(x: 0, y: 0, width: 612, height: 792), for: .mediaBox)
            item.document.insert(page, at: insertIndex)
            item.pageIndex = insertIndex
            reload(view, document: item, pageIndex: insertIndex)
            manager.pageText = String(insertIndex + 1)
            manager.send(.refresh)
        }

        private func deleteCurrentPage(on view: PDFViewerView, document item: PDFDocumentItem) {
            guard item.pageCount > 1 else {
                manager.say("A PDF must keep at least one page.", "В PDF должна остаться хотя бы одна страница.")
                return
            }
            let currentIndex = view.currentPage.map { item.document.index(for: $0) } ?? item.pageIndex
            let removeIndex = min(max(currentIndex, 0), item.pageCount - 1)
            item.document.removePage(at: removeIndex)
            let nextIndex = min(removeIndex, item.pageCount - 1)
            item.pageIndex = nextIndex
            reload(view, document: item, pageIndex: nextIndex)
            manager.pageText = String(nextIndex + 1)
            manager.send(.refresh)
        }

        private func reload(_ view: PDFViewerView, document item: PDFDocumentItem, pageIndex: Int,centerPage: Bool = true) {
            let zoom = view.scaleFactor
            let viewportCenter = CGPoint(x: view.bounds.midX,y: view.bounds.midY)
            let anchor = view.document?.page(at: pageIndex).map { view.convert(viewportCenter,to: $0) }
            sourceDocument = nil; sourceOutlineData = nil; sourceOutlineCache = [:]; fontDocument = nil
            outlineGeneration += 1; outlinePending = false
            view.contentSelection = nil; view.contentPreview = nil; view.contentOutlines = []
            view.selectAnnotation(nil)
            view.installDocument(nil)
            view.installDocument(item.document)
            view.configureZoomLimits()
            view.scaleFactor = PDFZoomLimits.clamp(zoom)
            if let page = item.document.page(at: pageIndex) {
                if centerPage { center(page,in: view) }
                else {
                    view.go(to: page); view.layoutDocumentView()
                    if let anchor,let scroll = view.internalScrollView {
                        let clip = scroll.contentView
                        let movement = clip.convert(view.convert(anchor,from: page),from: view)-clip.convert(viewportCenter,from: view)
                        let next = clip.bounds.offsetBy(dx: movement.x,dy: movement.y)
                        clip.scroll(to: clip.constrainBoundsRect(next).origin); scroll.reflectScrolledClipView(clip)
                    }
                }
            }
            view.setCurrentSelection(nil, animate: false)
            view.setNeedsDisplay(view.bounds)
        }

        private func syncPage() {
            guard let view, let item = manager.selected, let page = view.currentPage else { return }
            let index = max(0, item.document.index(for: page))
            if item.pageIndex != index { item.pageIndex = index }
            let pageValue = String(index + 1)
            if manager.pageText != pageValue { manager.pageText = pageValue }
        }

        private func syncMetrics(for view: PDFViewerView) {
            guard let page = view.currentPage, !view.bounds.isEmpty else {
                if manager.rulerMetrics.valid { manager.rulerMetrics = RulerMetrics() }
                return
            }
            let crop = page.bounds(for: .cropBox)
            guard crop.width > 0, crop.height > 0 else { return }
            // PDFView conversions include page rotation, page-break spacing, pan, and magnification.
            let cropOriginInView = view.convert(CGPoint(x: crop.minX, y: crop.maxY), from: page)
            let cropOrigin = view.convert(cropOriginInView, to: page)
            let topLeft = CGPoint(x: view.bounds.minX, y: view.isFlipped ? view.bounds.minY : view.bounds.maxY)
            let origin = view.convert(topLeft, to: page)
            let right = view.convert(CGPoint(x: topLeft.x + 1, y: topLeft.y), to: page)
            let down = view.convert(CGPoint(x: topLeft.x, y: topLeft.y + (view.isFlipped ? 1 : -1)), to: page)
            let horizontalX = abs(right.x - origin.x) >= abs(right.y - origin.y)
            let verticalY = abs(down.y - origin.y) >= abs(down.x - origin.x)
            let metrics = RulerMetrics(
                horizontalOrigin: horizontalX ? origin.x - cropOrigin.x : origin.y - crop.minY,
                horizontalPointsPerPixel: horizontalX ? right.x - origin.x : right.y - origin.y,
                verticalOrigin: verticalY ? origin.y - crop.minY : origin.x - cropOrigin.x,
                verticalPointsPerPixel: verticalY ? down.y - origin.y : down.x - origin.x,
                valid: true
            )
            if manager.rulerMetrics != metrics { manager.rulerMetrics = metrics }
        }

        func pdfViewPageChanged(_ notification: Notification) {
            if let view { scheduleViewportSync(for: view) }
        }
    }
}

@MainActor
private final class FreeTextEditorController: NSViewController, NSTextViewDelegate, NSPopoverDelegate {
    let annotation: PDFAnnotation
    let language: AppLanguage
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 330, height: 105))
    private let fontSize = NSTextField(string: "18")
    private let thickness = NSTextField(string: "2")
    private let color = NSColorWell(frame: .zero)
    private let opacity = NSSlider(value: 1, minValue: 0.1, maxValue: 1, target: nil, action: nil)
    private let borderToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    weak var popover: NSPopover?
    var onLiveChange: (() -> Void)?
    var onFinish: ((Bool) -> Void)?
    private var cancelled = false
    private var finished = false
    private let originalContents: String?
    private let originalFont: NSFont?
    private let originalColor: NSColor
    private let originalFontColor: NSColor?
    private let originalBorder: PDFBorder?
    private let originalBounds: CGRect
    private let originalOpacity: CGFloat

    init(annotation: PDFAnnotation, language: AppLanguage) {
        self.annotation = annotation; self.language = language
        originalContents = annotation.contents; originalFont = annotation.font
        originalColor = annotation.color; originalFontColor = annotation.fontColor
        originalBorder = annotation.border?.copy() as? PDFBorder; originalBounds = annotation.bounds
        originalOpacity = AnnotationMetadata.alpha(of: annotation)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }
    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 255))
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 136, width: 336, height: 105))
        scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
        textView.isRichText = false; textView.delegate = self
        textView.isAutomaticTextCompletionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        if #available(macOS 15.0,*) { textView.writingToolsBehavior = .none }
        textView.string = annotation.contents ?? ""
        textView.font = annotation.font ?? NSFont.systemFont(ofSize: 18)
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 5, height: 5)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView; root.addSubview(scroll)
        fontSize.stringValue = String(format: "%.0f", annotation.font?.pointSize ?? 18)
        thickness.stringValue = String(format: "%.1f", annotation.border?.lineWidth ?? 2)
        color.color = annotation.fontColor ?? annotation.color
        opacity.doubleValue = Double(AnnotationMetadata.alpha(of: annotation))
        color.color = color.color.withAlphaComponent(1)
        borderToggle.title = language == .ru ? "Рамка" : "Border"
        borderToggle.state = (annotation.border?.lineWidth ?? 0) > 0 ? .on : .off
        for field in [fontSize, thickness] { field.target = self; field.action = #selector(applyControls) }
        color.target = self; color.action = #selector(applyControls)
        opacity.target = self; opacity.action = #selector(applyControls); opacity.isContinuous = true
        borderToggle.target = self; borderToggle.action = #selector(applyControls)
        let label1 = NSTextField(labelWithString: language == .ru ? "Шрифт" : "Font")
        let label2 = NSTextField(labelWithString: language == .ru ? "Толщина" : "Stroke")
        let row = NSStackView(views: [label1, fontSize, label2, thickness, color])
        row.frame = NSRect(x: 12, y: 96, width: 336, height: 30); row.spacing = 8; root.addSubview(row)
        let row2 = NSStackView(views: [borderToggle, NSTextField(labelWithString: language == .ru ? "Непрозрачность" : "Opacity"), opacity])
        row2.frame = NSRect(x: 12, y: 58, width: 336, height: 28); row2.spacing = 8; root.addSubview(row2)
        let done = NSButton(title: language == .ru ? "Готово" : "Done", target: self, action: #selector(commit))
        let cancel = NSButton(title: language == .ru ? "Отмена" : "Cancel", target: self, action: #selector(cancelEditing))
        let buttons = NSStackView(views: [cancel, done]); buttons.frame = NSRect(x: 190, y: 15, width: 158, height: 28)
        root.addSubview(buttons); view = root
    }
    func textDidChange(_ notification: Notification) { applyControls() }
    @objc private func applyControls() {
        let size = CGFloat(min(72, max(6, Double(fontSize.stringValue) ?? 18)))
        let font = NSFont.systemFont(ofSize: size)
        let tint = color.color.withAlphaComponent(CGFloat(opacity.doubleValue))
        annotation.removeValue(forAnnotationKey: .appearanceDictionary)
        annotation.contents = textView.string; annotation.font = font; annotation.fontColor = tint
        annotation.color = .clear
        AnnotationMetadata.setOpacity(opacity.doubleValue, on: annotation)
        let border = PDFBorder(); border.lineWidth = borderToggle.state == .on ? CGFloat(min(12, max(0.5, Double(thickness.stringValue) ?? 2))) : 0
        annotation.border = border
        let measured = (textView.string as NSString).boundingRect(with: CGSize(width: max(20, originalBounds.width - 16), height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let height = max(originalBounds.height, ceil(measured.height) + 16)
        annotation.bounds = CGRect(x: originalBounds.minX, y: originalBounds.maxY - height, width: originalBounds.width, height: height)
        textView.font = font; textView.textColor = .labelColor
        onLiveChange?()
    }
    @objc private func commit() { applyControls(); popover?.close() }
    @objc private func cancelEditing() { cancelled = true; popover?.close() }
    func popoverDidClose(_ notification: Notification) {
        guard !finished else { return }; finished = true
        DispatchQueue.main.async { [self] in
            if cancelled {
                annotation.contents = originalContents; annotation.font = originalFont
                annotation.color = originalColor; annotation.fontColor = originalFontColor
                annotation.border = originalBorder; annotation.bounds = originalBounds
                AnnotationMetadata.setOpacity(Double(originalOpacity), on: annotation)
            } else { applyControls() }
            onFinish?(cancelled)
        }
    }
}

@MainActor
private final class AnnotationOverlayView: NSView {
    weak var pdfView: PDFViewerView?
    override var isFlipped: Bool { pdfView?.isFlipped ?? false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let pdf = pdfView else { return }
        NSBezierPath(rect: bounds).addClip()
        for annotation in pdf.selectedAnnotations {
            guard let page = annotation.page else { continue }
            let rect = convert(pdf.convert(annotation.bounds, from: page), from: pdf)
            NSColor.systemBlue.setStroke()
            let outline = NSBezierPath(rect: rect.insetBy(dx: -2, dy: -2)); outline.lineWidth = 1
            outline.setLineDash([4, 3], count: 2, phase: 0); outline.stroke()
            for corner in pdf.selectedAnnotations.count == 1 ? pdf.annotationCorners(annotation) : [] {
                let point = convert(pdf.convert(corner, from: page), from: pdf)
                let handle = NSBezierPath(rect: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
                NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); handle.stroke()
            }
        }
        if let marquee = pdf.annotationMarquee {
            let area = CGRect(x: min(marquee.start.x,marquee.end.x),y: min(marquee.start.y,marquee.end.y),width: abs(marquee.end.x-marquee.start.x),height: abs(marquee.end.y-marquee.start.y))
            let rect = convert(pdf.convert(area,from: marquee.page),from: pdf)
            NSColor.systemBlue.withAlphaComponent(0.12).setFill(); NSBezierPath(rect: rect).fill()
            NSColor.systemBlue.setStroke(); let border = NSBezierPath(rect: rect); border.setLineDash([4,3],count: 2,phase: 0); border.stroke()
        }
        if pdf.activeTool == .editText {
            NSColor(calibratedWhite: 0.55,alpha: 0.9).setStroke()
            for entry in pdf.sourceBlocks {
                let rect = convert(pdf.convert(entry.block.snapshot.bounds,from: entry.page),from: pdf)
                if rect.intersects(bounds) { let path = NSBezierPath(rect: rect); path.lineWidth = 0.7; path.stroke() }
            }
        }
        if pdf.activeTool == .editContent {
            var budget = 1200
            NSColor(calibratedWhite: 0.55,alpha: 0.55).setStroke()
            for entry in pdf.contentOutlines where budget > 0 {
                let visible = pdf.convert(pdf.visibleRect,to: entry.page)
                guard entry.object.bounds.intersects(visible),max(entry.object.bounds.width,entry.object.bounds.height)*pdf.scaleFactor >= 8 else { continue }
                let rect = convert(pdf.convert(entry.object.bounds,from: entry.page),from: pdf)
                let path = NSBezierPath(rect: rect); path.lineWidth = 0.6; path.stroke(); budget -= 1
            }
            pdf.drawContentControls(in: self)
        }
        if let draft = pdf.engineeringDraft {
            let points = draft.points+[draft.hover],path = NSBezierPath()
            for (index,point) in points.enumerated() { let p = convert(pdf.convert(point,from: draft.page),from: pdf); if index == 0 { path.move(to: p) } else { path.line(to: p) } }
            if draft.kind == .area { path.close() }
            NSColor.systemCyan.setStroke(); path.lineWidth = 1.3; path.stroke()
            for point in points { let p = convert(pdf.convert(point,from: draft.page),from: pdf); NSColor.systemCyan.setFill(); NSBezierPath(ovalIn: CGRect(x: p.x-3,y: p.y-3,width: 6,height: 6)).fill() }
            if let text = pdf.engineeringPreviewText?(draft.page,draft.kind,points),!text.isEmpty {
                let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.monospacedDigitSystemFont(ofSize: 12,weight: .medium),.foregroundColor:NSColor.white]
                let size = (text as NSString).size(withAttributes: attributes),cursor = convert(pdf.convert(draft.hover,from: draft.page),from: pdf)
                let box = CGRect(x: min(bounds.maxX-size.width-12,max(bounds.minX+4,cursor.x+12)),y: min(bounds.maxY-size.height-12,max(bounds.minY+4,cursor.y+12)),width: size.width+8,height: size.height+8)
                NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: box,xRadius: 4,yRadius: 4).fill()
                (text as NSString).draw(at: CGPoint(x: box.minX+4,y: box.minY+4),withAttributes: attributes)
            }
        }
        if pdf.engineeringTool != nil,let (page,snap,label) = pdf.engineeringSnapIndicator,page.document === pdf.document {
            let point = convert(pdf.convert(snap.point,from: page),from: pdf),path = NSBezierPath()
            switch snap.kind {
            case .endpoint: path.move(to: CGPoint(x: point.x-4,y: point.y-4)); path.line(to: CGPoint(x: point.x+4,y: point.y-4)); path.line(to: CGPoint(x: point.x+4,y: point.y+4)); path.line(to: CGPoint(x: point.x-4,y: point.y+4)); path.close()
            case .midpoint: path.move(to: CGPoint(x: point.x,y: point.y+5)); path.line(to: CGPoint(x: point.x-5,y: point.y-4)); path.line(to: CGPoint(x: point.x+5,y: point.y-4)); path.close()
            case .intersection: path.move(to: CGPoint(x: point.x-5,y: point.y-5)); path.line(to: CGPoint(x: point.x+5,y: point.y+5)); path.move(to: CGPoint(x: point.x-5,y: point.y+5)); path.line(to: CGPoint(x: point.x+5,y: point.y-5))
            case .extremum: path.appendOval(in: CGRect(x: point.x-5,y: point.y-5,width: 10,height: 10)); path.move(to: CGPoint(x: point.x-7,y: point.y)); path.line(to: CGPoint(x: point.x+7,y: point.y))
            case .curveMidpoint: path.move(to: CGPoint(x: point.x,y: point.y+5)); path.line(to: CGPoint(x: point.x-5,y: point.y-4)); path.line(to: CGPoint(x: point.x+5,y: point.y-4)); path.close(); path.move(to: CGPoint(x: point.x-6,y: point.y-7)); path.line(to: CGPoint(x: point.x+6,y: point.y-7))
            case .nearest: path.appendOval(in: CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8))
            }
            NSColor.systemGreen.setStroke(); path.lineWidth = 2; path.stroke()
            let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize: 10,weight: .semibold),.foregroundColor:NSColor.white]
            let size = (label as NSString).size(withAttributes: attributes)
            let rect = CGRect(x: min(bounds.maxX-size.width-12,max(bounds.minX+4,point.x+10)),y: min(bounds.maxY-size.height-12,max(bounds.minY+4,point.y-20)),width: size.width+8,height: size.height+6)
            NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: rect,xRadius: 3,yRadius: 3).fill(); (label as NSString).draw(at: CGPoint(x: rect.minX+4,y: rect.minY+3),withAttributes: attributes)
        }
        pdf.sourceInline?.drawControls(in: self)
        if pdf.sourceInline == nil, let source = pdf.sourceSelection {
            let rect = convert(pdf.convert(source.bounds, from: source.page), from: pdf)
            NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: rect.insetBy(dx: -2,dy: -2)); path.lineWidth = 1; path.stroke()
        }
        if let preview = pdf.preview {
            let start = convert(pdf.convert(preview.start, from: preview.page), from: pdf)
            let end = convert(pdf.convert(preview.end, from: preview.page), from: pdf)
            pdf.strokeColor.setStroke()
            let path: NSBezierPath
            if [.rectangle,.ellipse,.cloud,.link,.marquee,.snapshot].contains(preview.tool) {
                let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                path = preview.tool == .ellipse ? NSBezierPath(ovalIn: rect) : NSBezierPath(rect: rect)
            } else if preview.tool == .pencil {
                path = NSBezierPath(); path.move(to: start)
                for p in preview.points { path.line(to: convert(pdf.convert(p,from: preview.page),from: pdf)) }
            } else { path = NSBezierPath(); path.move(to: start); path.line(to: end) }
            path.lineWidth = max(1, pdf.strokeWidth * pdf.scaleFactor); path.stroke()
        }
    }
}

private enum PDFScreenTileRenderer {
    static func draw(_ page: PDFPage, to destination: CGContext) {
        let clip = destination.boundingBoxOfClipPath
        let transform = destination.ctm
        guard [clip.minX, clip.minY, clip.width, clip.height,
               transform.a, transform.b, transform.c, transform.d].allSatisfy(\.isFinite),
              clip.width > 0, clip.height > 0 else { return }
        var scaleX = hypot(transform.a, transform.b)
        var scaleY = hypot(transform.c, transform.d)
        guard scaleX > 0, scaleY > 0 else { return }
        // Normally PDFKit requests small tiles. Bound exceptional full-page
        // requests as well, without allocating a page-sized Retina bitmap.
        let requestedWidth = clip.width * scaleX
        let requestedHeight = clip.height * scaleY
        let pixels = requestedWidth * requestedHeight
        guard requestedWidth.isFinite, requestedHeight.isFinite, pixels.isFinite else { return }
        let reduction = min(1, 16_384 / requestedWidth, 16_384 / requestedHeight,
                            sqrt(16_777_216 / max(1, pixels)))
        scaleX *= reduction; scaleY *= reduction
        let pixelWidth = max(1, Int(ceil(clip.width * scaleX)))
        let pixelHeight = max(1, Int(ceil(clip.height * scaleY)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        destination.saveGState()
        defer { destination.restoreGState() }
        destination.interpolationQuality = .high
        for y in stride(from: 0, to: pixelHeight, by: 1024) {
            for x in stride(from: 0, to: pixelWidth, by: 1024) {
                autoreleasepool {
                    let width = min(1024, pixelWidth - x)
                    let height = min(1024, pixelHeight - y)
                    guard let bitmap = CGContext(data: nil, width: width, height: height,
                        bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                    let rect = CGRect(x: clip.minX + CGFloat(x) / scaleX,
                                      y: clip.minY + CGFloat(y) / scaleY,
                                      width: CGFloat(width) / scaleX,
                                      height: CGFloat(height) / scaleY)
                    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                    bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    bitmap.scaleBy(x: scaleX, y: scaleY)
                    bitmap.translateBy(x: -rect.minX, y: -rect.minY)
                    page.draw(with: .cropBox, to: bitmap)
                    if let image = bitmap.makeImage() { destination.draw(image, in: rect) }
                }
            }
        }
    }
}

@MainActor
private final class PDFViewerView: PDFView {
    // PDFKit calls this on its tile workers, not necessarily on the main thread.
    // Submit images rather than PDF strokes to the layer-backed CGContext: on
    // affected macOS versions QuartzCore's WideLineRenderer can submit a zero
    // instance Metal draw and abort while opening an otherwise valid CAD PDF.
    // The PDF remains vector/editable; only the current screen tiles use Quartz
    // bitmap rendering, at the destination's pixel density.
    nonisolated override func draw(_ page: PDFPage, to context: CGContext) {
        PDFScreenTileRenderer.draw(page, to: context)
    }

    var configuredPageMargin: CGFloat = 2
    var onFocus: (() -> Void)?
    var engineeringDraft: (page: PDFPage,kind: EngineeringKind,points: [CGPoint],hover: CGPoint)?
    var engineeringSnapper: ((PDFPage,CGPoint) -> CGPoint)?
    var engineeringSnapIndicator: (PDFPage,PDFEngineeringSnap,String)?
    var engineeringPreviewText: ((PDFPage,EngineeringKind,[CGPoint]) -> String)?
    var onEngineeringCommit: ((PDFPage,EngineeringKind,[CGPoint]) -> Void)?
    var engineeringTool: EngineeringKind? {
        switch activeTool { case .distance: .distance; case .perimeter: .perimeter; case .area: .area; case .calibration: .calibration; default: nil }
    }
    struct Preview { let page: PDFPage; let start: CGPoint; var end: CGPoint; let tool: PDFTool; var points: [CGPoint] = [] }
    private struct Transform {
        let annotation: PDFAnnotation
        let page: PDFPage
        let start: CGPoint
        let bounds: CGRect
        let corner: Int?
        let lineStart: CGPoint
        let lineEnd: CGPoint
        var paths: [NSBezierPath] = []
        var recordedHistory = false
    }
    // Keep PDFView's Objective-C getter intact: PDFKit's formFillingQueue reads
    // it off-main. An actor-isolated Swift override (even a didSet observer)
    // synthesizes a getter thunk that traps before PDFKit can read the value.
    func installDocument(_ next: PDFDocument?) {
        if document !== next {
            batchMove = nil; annotationMarquee = nil; transform = nil; selectAnnotation(nil)
        }
        document = next
        AppDiagnostics.record("viewer_document_changed pages=\(next?.pageCount ?? 0)")
    }
    var activeTool: PDFTool = .hand { didSet { if activeTool != oldValue { contentDrag = nil; contentPreview = nil; batchMove = nil; annotationMarquee = nil; window?.invalidateCursorRects(for: self) } } }
    var strokeColor: NSColor = .systemRed
    var strokeWidth: CGFloat = 2
    var fillEnabled = false
    var onWillModify: (() -> Void)?
    var onMarkupFinished: (() -> Void)?
    var onPlaceObject: ((PDFPage,CGPoint,PDFTool) -> Void)?
    var onSnapshot: ((PDFPage, CGRect) -> Void)?
    var onViewportChange: (() -> Void)?
    var onCreateText: ((PDFPage, CGPoint, PDFAnnotation?) -> Void)?
    var onEditText: ((PDFAnnotation) -> Void)?
    var onContentRequest: ((PDFPage,CGPoint) -> Void)?
    var onContentTransform: ((PDFPage,PDFSourceSession.ContentObject,CGRect,CGFloat) -> Void)?
    var contentOutlines: [(page: PDFPage,object: PDFSourceSession.ContentObject)] = []
    var contentSelection: (page: PDFPage,object: PDFSourceSession.ContentObject)?
    var contentPreview: (bounds: CGRect,angle: CGFloat)?
    private var contentDrag: (start: CGPoint,bounds: CGRect,corner: Int?,rotate: Bool)?
    var onSourceTextRequest: ((PDFPage, CGPoint, Bool, Bool) -> Void)?
    var sourceInline: PDFInlineTextEditor?
    var sourceBlocks: [(page: PDFPage,block: PDFSourceSession.BlockDescriptor)] = []
    var pendingLinkBounds: CGRect?
    private var sourceDragging = false
    private var eraserRecorded = false
    var onClipboardCommand: ((ViewerCommand) -> Void)?
    private(set) var sourceSelection: (page: PDFPage, bounds: CGRect)?
    var onSelectionChanged: ((PDFAnnotation?) -> Void)?
    var onAnnotationChanged: (() -> Void)?
    var onCursorChange: ((CGPoint?, CGPoint?) -> Void)?
    private(set) var selectedAnnotation: PDFAnnotation?
    private(set) var selectedAnnotations: [PDFAnnotation] = []
    var annotationMarquee: (page: PDFPage,start: CGPoint,end: CGPoint,extending: Bool)?
    private struct BatchMove {
        struct Entry { let annotation: PDFAnnotation,bounds: CGRect,measurement: EngineeringMeasure? }
        let page: PDFPage,start: CGPoint,box: CGRect,entries: [Entry]
        var recorded = false
    }
    private var batchMove: BatchMove?
    private(set) var preview: Preview?
    private var transform: Transform?
    private var panPoint: CGPoint?
    private var cursorPushed = false
    private var requestedScrollOrigin: CGPoint?
    private var lastScrollOrigin: CGPoint?
    private var eventMonitor: Any?
    private var pendingZoomDocument: ObjectIdentifier?
    private var pendingZoom: CGFloat = 0
    private var zoomAnchor: CGPoint?
    private var zoomScheduled = false
    private var tracking: NSTrackingArea?
    private let overlay = AnnotationOverlayView(frame: .zero)
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override init(frame: NSRect) { super.init(frame: frame); clipsToBounds = true }
    required init?(coder: NSCoder) { super.init(coder: coder); clipsToBounds = true }

    var internalScrollView: NSScrollView? {
        if let scroll = documentView?.enclosingScrollView { scroll.clipsToBounds = true; scroll.contentView.clipsToBounds = true; return scroll }
        func find(_ view: NSView) -> NSScrollView? {
            for child in view.subviews {
                if let scroll = child as? NSScrollView { scroll.clipsToBounds = true; scroll.contentView.clipsToBounds = true; return scroll }
                if let result = find(child) { return result }
            }
            return nil
        }
        return find(self)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopEventMonitoring()
        guard window != nil else { return }
        overlay.clipsToBounds = true; overlay.pdfView = self; overlay.autoresizingMask = [.width, .height]
        addSubview(overlay, positioned: .above, relativeTo: nil); refreshOverlay()
        HoverGestureRouter.shared.register(self)
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, HoverEventLocation.point(for: event, in: self) != nil,
                   [.highlight,.underline,.strike].contains(self.activeTool) {
                    DispatchQueue.main.async { [weak self] in self?.onMarkupFinished?() }
                }
            }
            return event
        }
    }
    func stopEventMonitoring() {
        HoverGestureRouter.shared.unregister(self)
        pendingZoom = 0; pendingZoomDocument = nil; zoomAnchor = nil; zoomScheduled = false
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        trackCursor(event)
        if var draft = engineeringDraft { let point = convert(convert(event.locationInWindow,from: nil),to: draft.page); draft.hover = engineeringSnapper?(draft.page,point) ?? point; engineeringDraft = draft; refreshOverlay() }
        else if engineeringTool != nil,let page = page(for: convert(event.locationInWindow,from: nil),nearest: false) { _ = engineeringSnapper?(page,convert(convert(event.locationInWindow,from: nil),to: page)); refreshOverlay() }
    }
    override func mouseEntered(with event: NSEvent) { trackCursor(event) }
    override func mouseExited(with event: NSEvent) { onCursorChange?(nil, nil); engineeringSnapIndicator = nil; refreshOverlay() }
    private func trackCursor(_ event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let viewport = CGPoint(x: local.x - bounds.minX, y: isFlipped ? local.y - bounds.minY : bounds.maxY - local.y)
        var pdfPoint: CGPoint?
        if let page = page(for: local, nearest: false) {
            let point = convert(local, to: page); let crop = page.bounds(for: .cropBox)
            if crop.contains(point) { pdfPoint = CGPoint(x: point.x - crop.minX, y: point.y - crop.minY) }
        }
        onCursorChange?(viewport, pdfPoint)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Clipping affects drawing, not hit testing. Out-of-viewport editors
        // must never intercept the ribbon or docked panel controls.
        let viewportPoint = convert(point,from: superview)
        guard bounds.contains(viewportPoint) else { return nil }
        let local = convert(point,from: superview)
        if let scroll = internalScrollView {
            for scroller in [scroll.verticalScroller,scroll.horizontalScroller].compactMap({ $0 }) where !scroller.isHidden {
                let position = scroller.convert(local,from: self)
                if scroller.bounds.contains(position) { return scroller.hitTest(scroller.superview!.convert(local,from: self)) }
            }
        }
        if let inline = sourceInline {
            if inline.handle(at: local) != nil { return self }
            if let hit = inline.hit(at: local),inline.owns(hit) { return hit }
        }
        switch activeTool {
        case .distance,.perimeter,.area,.calibration: return self
        case .hand,.typewriter,.rectangle,.ellipse,.cloud,.pencil,.eraser,.note,.stamp,.link,.marquee,.snapshot,.formText,.formCheckbox,.formRadio,.formChoice,.formButton,.line,.arrow,.callout,.selectComments,.addText,.editText,.editContent:
            // Do not ask PDFKit to probe its text layer in non-selection modes.
            return self
        default: return super.hitTest(point)
        }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        switch activeTool {
        case .hand: addCursorRect(visibleRect, cursor: .openHand)
        case .textSelection, .highlight, .underline, .strike, .typewriter, .addText, .editText: addCursorRect(visibleRect, cursor: .iBeam)
        case .editContent: addCursorRect(visibleRect,cursor: .arrow)
        case .distance,.perimeter,.area,.calibration,.rectangle, .ellipse, .cloud, .pencil, .eraser, .link, .marquee, .snapshot, .note, .stamp, .formText, .formCheckbox, .formRadio, .formChoice, .formButton, .line, .arrow, .callout: addCursorRect(visibleRect, cursor: .crosshair)
        default: break
        }
    }
    func setSourceSelection(_ selection: (PDFPage, CGRect)?) {
        sourceSelection = selection.map { (page: $0.0, bounds: $0.1) }; refreshOverlay()
    }
    func selectAnnotation(_ annotation: PDFAnnotation?,extending: Bool = false,toggle: Bool = false) {
        selectAnnotations(annotation.map { [$0] } ?? [],extending: extending,toggle: toggle)
    }
    func selectAnnotations(_ annotations: [PDFAnnotation],extending: Bool = false,toggle: Bool = false) {
        guard let page = annotations.first?.page,page.document === document else {
            if !extending { selectedAnnotations = []; selectedAnnotation = nil }; refreshOverlay(); onSelectionChanged?(selectedAnnotation); return
        }
        let requested = annotations.filter { $0.page === page && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }
        let groups = Set(requested.compactMap(AnnotationMetadata.group))
        let expanded = page.annotations.filter { candidate in requested.contains(where: { $0 === candidate }) || AnnotationMetadata.group(of: candidate).map(groups.contains) == true }
        var ids = extending && selectedAnnotations.first?.page === page ? Set(selectedAnnotations.map(ObjectIdentifier.init)) : []
        let removing = toggle && !expanded.isEmpty && expanded.allSatisfy { ids.contains(ObjectIdentifier($0)) }
        for annotation in expanded { if removing { ids.remove(ObjectIdentifier(annotation)) } else { ids.insert(ObjectIdentifier(annotation)) } }
        selectedAnnotations = page.annotations.filter { ids.contains(ObjectIdentifier($0)) && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }
        let preferred = requested.last,preferredGroup = preferred.flatMap(AnnotationMetadata.group)
        let family = selectedAnnotations.filter { $0 === preferred || (preferredGroup != nil && AnnotationMetadata.group(of: $0) == preferredGroup) }
        selectedAnnotation = family.first(where: { AnnotationMetadata.measurement($0) != nil }) ?? family.first(where: { $0.type == "FreeText" }) ?? family.last ?? selectedAnnotations.last
        if selectedAnnotation != nil { sourceSelection = nil }
        refreshOverlay(); onSelectionChanged?(selectedAnnotation)
    }
    var annotationSelectionUnitCount: Int {
        Set(selectedAnnotations.map { AnnotationMetadata.group(of: $0).map { "group:"+$0 } ?? "annotation:"+String(describing: ObjectIdentifier($0)) }).count
    }
    var canModifyAnnotationSelection: Bool {
        guard let first = selectedAnnotations.first,let page = first.page,let document = page.document,document === self.document,!selectedAnnotations.isEmpty else { return false }
        return selectedAnnotations.allSatisfy { $0.page === page && !AnnotationMetadata.isLocked($0) && (["Widget","Link"].contains($0.type ?? "") ? document.allowsDocumentChanges : document.allowsCommenting) }
    }
    var annotationSelectionBounds: CGRect { selectedAnnotations.reduce(CGRect.null) { $0.union($1.bounds) } }
    func selectAnnotations(in rectangle: CGRect,page: PDFPage,extending: Bool = false) {
        selectAnnotations(page.annotations.filter { $0.shouldDisplay && $0.type != "Widget" && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) && $0.bounds.intersects(rectangle) },extending: extending)
    }
    private func selectionMoveEntries() -> [BatchMove.Entry] {
        let roots = selectedAnnotations,popups = roots.compactMap(\.popup).filter { popup in popup.page === roots.first?.page && !roots.contains(where: { $0 === popup }) }
        return (roots+popups).map { BatchMove.Entry(annotation: $0,bounds: $0.bounds,measurement: AnnotationMetadata.measurement($0)) }
    }
    private func translation(_ requested: CGPoint,box: CGRect,page: PDFPage) -> CGPoint {
        let crop = page.bounds(for: .cropBox)
        func clamp(_ value: CGFloat,_ low: CGFloat,_ high: CGFloat) -> CGFloat { low <= high ? min(high,max(low,value)) : 0 }
        return CGPoint(x: clamp(requested.x,crop.minX-box.minX,crop.maxX-box.maxX),y: clamp(requested.y,crop.minY-box.minY,crop.maxY-box.maxY))
    }
    private func move(_ entries: [BatchMove.Entry],by delta: CGPoint) {
        for entry in entries {
            entry.annotation.bounds = entry.bounds.offsetBy(dx: delta.x,dy: delta.y)
            if var measure = entry.measurement { measure.points = measure.points.map { CGPoint(x: $0.x+delta.x,y: $0.y+delta.y) }; AnnotationMetadata.setMeasurement(measure,on: entry.annotation) }
        }
    }
    @discardableResult func translateAnnotationSelection(dx: CGFloat,dy: CGFloat) -> Bool {
        guard canModifyAnnotationSelection,dx.isFinite,dy.isFinite,let page = selectedAnnotations.first?.page else { return false }
        let delta = translation(CGPoint(x: dx,y: dy),box: annotationSelectionBounds,page: page)
        guard delta != .zero else { return true }
        onWillModify?(); move(selectionMoveEntries(),by: delta); refreshOverlay(); setNeedsDisplay(bounds); onAnnotationChanged?(); return true
    }
    func updateCalloutLeader(for annotation: PDFAnnotation) {
        guard annotation.type == "FreeText", let group = AnnotationMetadata.group(of: annotation), let page = annotation.page,
              let leader = page.annotations.first(where: { $0.type == "Line" && AnnotationMetadata.group(of: $0) == group }) else { return }
        let start = CGPoint(x: leader.bounds.minX + leader.startPoint.x, y: leader.bounds.minY + leader.startPoint.y)
        let end = CGPoint(x: annotation.bounds.minX, y: annotation.bounds.maxY)
        let rect = CGRect(x: min(start.x, end.x) - 1, y: min(start.y, end.y) - 1, width: max(2, abs(end.x - start.x) + 2), height: max(2, abs(end.y - start.y) + 2))
        leader.bounds = rect
        leader.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
        leader.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
    }
    func refreshOverlay() {
        if overlay.frame != bounds { overlay.frame = bounds }
        if overlay.superview === self && subviews.last !== overlay { addSubview(overlay, positioned: .above, relativeTo: nil) }
        overlay.needsDisplay = true
    }
    func contentCorners(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.maxY),CGPoint(x: rect.minX,y: rect.maxY)]
    }
    func contentRotationHandle(page: PDFPage,bounds: CGRect) -> CGPoint {
        let rect = convert(bounds,from: page)
        return CGPoint(x: rect.midX,y: isFlipped ? rect.minY-20 : rect.maxY+20)
    }
    func drawContentControls(in overlay: NSView) {
        guard let selected = contentSelection else { return }
        let rect = contentPreview?.bounds ?? selected.object.bounds,angle = contentPreview?.angle ?? 0
        let c = cos(angle),s = sin(angle)
        let points = contentCorners(rect).map { p in
            let x = p.x-rect.midX,y = p.y-rect.midY
            return overlay.convert(convert(CGPoint(x: rect.midX+c*x-s*y,y: rect.midY+s*x+c*y),from: selected.page),from: self)
        }
        let path = NSBezierPath(); path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }; path.close()
        NSColor.systemBlue.setStroke(); path.lineWidth = 1; path.stroke()
        for point in points {
            let handle = NSBezierPath(rect: CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8))
            NSColor.white.setFill(); handle.fill(); NSColor.systemBlue.setStroke(); handle.stroke()
        }
        let knob = overlay.convert(contentRotationHandle(page: selected.page,bounds: rect),from: self)
        let circle = NSBezierPath(ovalIn: CGRect(x: knob.x-5,y: knob.y-5,width: 10,height: 10))
        NSColor.white.setFill(); circle.fill(); NSColor.systemBlue.setStroke(); circle.stroke()
    }
    func annotationCorners(_ annotation: PDFAnnotation) -> [CGPoint] {
        let r = annotation.bounds
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }
    override func mouseDown(with event: NSEvent) {
        onFocus?()
        trackCursor(event)
        if activeTool == .hand {
            window?.makeFirstResponder(self)
            setSourceSelection(nil); selectAnnotation(nil)
            panPoint = event.locationInWindow; NSCursor.closedHand.push(); cursorPushed = true; return
        }
        let local = convert(event.locationInWindow, from: nil)
        if let kind = engineeringTool,let page = page(for: local,nearest: false) {
            window?.makeFirstResponder(self)
            let raw = convert(local,to: page),point = engineeringSnapper?(page,raw) ?? raw
            if engineeringDraft?.page !== page || engineeringDraft?.kind != kind { engineeringDraft = (page,kind,[],point) }
            if let last = engineeringDraft?.points.last,hypot(last.x-point.x,last.y-point.y) < 0.1 { if event.clickCount >= 2 { finishEngineering() }; return }
            engineeringDraft?.points.append(point); engineeringDraft?.hover = point; refreshOverlay()
            if kind == .distance || kind == .calibration { if engineeringDraft?.points.count == 2 { finishEngineering() } }
            else if event.clickCount >= 2 { finishEngineering() }; return
        }
        if let inline = sourceInline,let handle = inline.handle(at: local) {
            sourceDragging = true; inline.beginDrag(handle,at: convert(local,to: inline.page)); return
        }
        guard let page = page(for: local, nearest: false) else {
            guard sourceInline?.finish() != false else { return }
            contentSelection = nil; contentPreview = nil; contentDrag = nil
            setSourceSelection(nil); selectAnnotation(nil); return
        }
        let point = convert(local, to: page)
        if activeTool == .editContent {
            window?.makeFirstResponder(self)
            if let selected = contentSelection,selected.page === page {
                let corners = contentCorners(selected.object.bounds)
                let corner = corners.firstIndex { hypot(convert($0,from: page).x-local.x,convert($0,from: page).y-local.y) < 9 }
                let rotation = contentRotationHandle(page: page,bounds: selected.object.bounds)
                let rotating = hypot(rotation.x-local.x,rotation.y-local.y) < 9
                if corner != nil || rotating || selected.object.bounds.contains(point) { contentDrag = (point,selected.object.bounds,corner,rotating); return }
            }
            contentSelection = nil; contentPreview = nil; onContentRequest?(page,point)
            if let selected = contentSelection { contentDrag = (point,selected.object.bounds,nil,false) }
            return
        }
        if activeTool == .selectComments {
            setSourceSelection(nil)
            window?.makeFirstResponder(self)
            if selectedAnnotations.count == 1,let annotation = selectedAnnotation, annotation.page === page,!AnnotationMetadata.isLocked(annotation),!event.modifierFlags.contains(.command),!event.modifierFlags.contains(.shift) {
                let corner = annotationCorners(annotation).firstIndex { corner in
                    let handle = convert(corner, from: page)
                    return hypot(handle.x - local.x, handle.y - local.y) <= 9
                }
                if let corner {
                    transform = Transform(annotation: annotation, page: page, start: point, bounds: annotation.bounds, corner: corner, lineStart: annotation.startPoint, lineEnd: annotation.endPoint,paths: (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath })
                    return
                }
            }
            let annotation = page.annotations.reversed().first { $0.shouldDisplay && $0.type != "Widget" && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) && $0.bounds.insetBy(dx: -3,dy: -3).contains(point) }
            let additive = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
            if let annotation {
                if additive || !selectedAnnotations.contains(where: { $0 === annotation }) { selectAnnotation(annotation,extending: additive,toggle: event.modifierFlags.contains(.command)) }
                if additive { return }
                if canModifyAnnotationSelection,selectedAnnotations.count > 1 {
                    batchMove = BatchMove(page: page,start: point,box: annotationSelectionBounds,entries: selectionMoveEntries()); return
                }
                if let annotation = selectedAnnotation,canModifyAnnotationSelection {
                    if event.clickCount == 2 && annotation.type == "FreeText" { onEditText?(annotation); return }
                    transform = Transform(annotation: annotation,page: page,start: point,bounds: annotation.bounds,corner: nil,lineStart: annotation.startPoint,lineEnd: annotation.endPoint,paths: (annotation.paths ?? []).compactMap { $0.copy() as? NSBezierPath })
                }
            } else {
                if !additive { selectAnnotation(nil) }
                annotationMarquee = (page,point,point,additive); refreshOverlay()
            }
            return
        }
        guard page.bounds(for: .cropBox).contains(point) else { return }
        switch activeTool {
        case .addText: window?.makeFirstResponder(self); onSourceTextRequest?(page,point,true,true)
        case .editText: window?.makeFirstResponder(self); onSourceTextRequest?(page,point,false,true)
        case .typewriter: onCreateText?(page, point, nil)
        case .note, .stamp, .formText, .formCheckbox, .formRadio, .formChoice, .formButton: onPlaceObject?(page,point,activeTool)
        case .eraser:
            eraserRecorded = false; eraseInk(page: page,point: point,whole: event.modifierFlags.contains(.option))
        case .rectangle, .ellipse, .cloud, .pencil, .link, .marquee, .snapshot, .line, .arrow, .callout: preview = Preview(page: page, start: point, end: point, tool: activeTool); refreshOverlay()
        default: super.mouseDown(with: event)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        if engineeringTool != nil { mouseMoved(with: event); return }
        trackCursor(event)
        if let drag = contentDrag,let selected = contentSelection {
            let point = convert(convert(event.locationInWindow,from: nil),to: selected.page)
            let rect = drag.bounds,dx = point.x-drag.start.x,dy = point.y-drag.start.y
            var next = rect,angle: CGFloat = 0
            if drag.rotate { angle = atan2(point.y-rect.midY,point.x-rect.midX)-atan2(drag.start.y-rect.midY,drag.start.x-rect.midX) }
            else if let corner = drag.corner {
                let left = corner == 0 || corner == 3, bottom = corner == 0 || corner == 1
                let x0 = left ? min(rect.maxX-0.1,rect.minX+dx) : rect.minX
                let x1 = left ? rect.maxX : max(rect.minX+0.1,rect.maxX+dx)
                let y0 = bottom ? min(rect.maxY-0.1,rect.minY+dy) : rect.minY
                let y1 = bottom ? rect.maxY : max(rect.minY+0.1,rect.maxY+dy)
                next = CGRect(x: x0,y: y0,width: x1-x0,height: y1-y0)
            } else { next.origin.x += dx; next.origin.y += dy }
            contentPreview = (next,angle); refreshOverlay(); return
        }
        if var marquee = annotationMarquee {
            marquee.end = convert(convert(event.locationInWindow,from: nil),to: marquee.page); annotationMarquee = marquee; refreshOverlay(); return
        }
        if var change = batchMove {
            guard canModifyAnnotationSelection else { batchMove = nil; return }
            let point = convert(convert(event.locationInWindow,from: nil),to: change.page)
            let delta = translation(CGPoint(x: point.x-change.start.x,y: point.y-change.start.y),box: change.box,page: change.page)
            if delta != .zero && !change.recorded { onWillModify?(); change.recorded = true }
            if change.recorded { move(change.entries,by: delta); setNeedsDisplay(bounds); refreshOverlay() }
            batchMove = change; return
        }
        if activeTool == .eraser {
            let local = convert(event.locationInWindow,from: nil)
            if let page = page(for: local,nearest: false) { eraseInk(page: page,point: convert(local,to: page),whole: event.modifierFlags.contains(.option)) }
            return
        }
        if sourceDragging,let inline = sourceInline {
            inline.drag(to: convert(convert(event.locationInWindow,from: nil),to: inline.page)); return
        }
        if var drawing = preview {
            let point = convert(convert(event.locationInWindow, from: nil), to: drawing.page)
            let crop = drawing.page.bounds(for: .cropBox)
            drawing.end = CGPoint(x: min(crop.maxX, max(crop.minX, point.x)), y: min(crop.maxY, max(crop.minY, point.y)))
            if drawing.tool == .pencil { if drawing.points.isEmpty { drawing.points.append(drawing.start) }; drawing.points.append(drawing.end) }
            preview = drawing; refreshOverlay(); return
        }
        if let change = transform {
            if !change.recordedHistory { onWillModify?(); transform?.recordedHistory = true }
            let point = convert(convert(event.locationInWindow, from: nil), to: change.page)
            let dx = point.x - change.start.x, dy = point.y - change.start.y
            var rect = change.bounds
            let crop = change.page.bounds(for: .cropBox)
            if let corner = change.corner {
                var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
                if corner == 0 || corner == 3 { minX = min(maxX - 6, max(crop.minX, minX + dx)) }
                else { maxX = max(minX + 6, min(crop.maxX, maxX + dx)) }
                if corner == 0 || corner == 1 { minY = min(maxY - 6, max(crop.minY, minY + dy)) }
                else { maxY = max(minY + 6, min(crop.maxY, maxY + dy)) }
                rect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            } else {
                rect.origin.x = min(max(crop.minX, rect.minX + dx), max(crop.minX, crop.maxX - rect.width))
                rect.origin.y = min(max(crop.minY, rect.minY + dy), max(crop.minY, crop.maxY - rect.height))
            }
            change.annotation.bounds = rect
            if change.corner != nil && change.annotation.type == "Line" {
                let sx = rect.width / max(1, change.bounds.width), sy = rect.height / max(1, change.bounds.height)
                change.annotation.startPoint = CGPoint(x: change.lineStart.x * sx, y: change.lineStart.y * sy)
                change.annotation.endPoint = CGPoint(x: change.lineEnd.x * sx, y: change.lineEnd.y * sy)
            }
            if change.corner != nil && change.annotation.type == "Ink" {
                for path in change.annotation.paths ?? [] { change.annotation.remove(path) }
                var affine = AffineTransform.identity; affine.scale(x: rect.width/max(1,change.bounds.width),y: rect.height/max(1,change.bounds.height))
                for original in change.paths { if let path = original.copy() as? NSBezierPath { path.transform(using: affine); change.annotation.add(path) } }
            }
            updateCalloutLeader(for: change.annotation)
            setNeedsDisplay(bounds); refreshOverlay(); return
        }
        if let previous = panPoint, let scroll = internalScrollView {
            let clip = scroll.contentView; let current = event.locationInWindow
            let deltaInView = convert(current, from: nil) - convert(previous, from: nil)
            let delta = clip.convert(deltaInView, from: self) - clip.convert(.zero, from: self)
            let proposed = CGRect(origin: CGPoint(x: clip.bounds.minX - delta.x, y: clip.bounds.minY - delta.y), size: clip.bounds.size)
            clip.scroll(to: clip.constrainBoundsRect(proposed).origin); scroll.reflectScrolledClipView(clip)
            panPoint = current; onViewportChange?(); return
        }
        super.mouseDragged(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        if activeTool == .eraser { if eraserRecorded { eraserRecorded = false; onAnnotationChanged?() }; return }
        if contentDrag != nil {
            contentDrag = nil
            if let selected = contentSelection,let preview = contentPreview { contentPreview = nil; onContentTransform?(selected.page,selected.object,preview.bounds,preview.angle) }
            return
        }
        if sourceDragging { sourceDragging = false; sourceInline?.endDrag(); return }
        if let drawing = preview {
            preview = nil; commitDrawing(drawing); refreshOverlay()
            if ![PDFTool.marquee,.snapshot,.link].contains(drawing.tool) { onAnnotationChanged?() }; return
        }
        if let marquee = annotationMarquee {
            annotationMarquee = nil
            let area = CGRect(x: min(marquee.start.x,marquee.end.x),y: min(marquee.start.y,marquee.end.y),width: abs(marquee.end.x-marquee.start.x),height: abs(marquee.end.y-marquee.start.y))
            selectAnnotations(in: area,page: marquee.page,extending: marquee.extending); return
        }
        if let change = batchMove { batchMove = nil; if change.recorded { onAnnotationChanged?() }; refreshOverlay(); return }
        if transform != nil { transform = nil; updateEngineeringMeasurement(); onAnnotationChanged?(); return }
        if panPoint != nil {
            panPoint = nil; if cursorPushed { NSCursor.pop(); cursorPushed = false }; return
        }
        if engineeringTool != nil { return }
        super.mouseUp(with: event)
    }
    func deleteSelectedAnnotation() -> Bool {
        guard canModifyAnnotationSelection else { return false }
        onWillModify?(); for annotation in selectedAnnotations { if let popup = annotation.popup { popup.page?.removeAnnotation(popup); annotation.popup = nil }; annotation.page?.removeAnnotation(annotation) }
        selectAnnotation(nil); setNeedsDisplay(bounds); onAnnotationChanged?(); return true
    }
    override func keyDown(with event: NSEvent) {
        if engineeringDraft != nil && (event.keyCode == 36 || event.keyCode == 76) { finishEngineering(); return }
        if engineeringDraft != nil && event.keyCode == 53 { engineeringDraft = nil; refreshOverlay(); return }
        if activeTool == .selectComments,event.modifierFlags.contains(.command),event.keyCode == 0,let page = currentPage {
            selectAnnotations(page.annotations.filter { $0.shouldDisplay && $0.type != "Widget" && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }); return
        }
        if activeTool == .selectComments,[123,124,125,126].contains(event.keyCode),!selectedAnnotations.isEmpty,let page = selectedAnnotations.first?.page {
            let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1,step = amount*scaleFactor
            let local = CGPoint(x: event.keyCode == 123 ? -step : event.keyCode == 124 ? step : 0,y: event.keyCode == 126 ? (isFlipped ? -step : step) : event.keyCode == 125 ? (isFlipped ? step : -step) : 0)
            let origin = convert(CGPoint.zero,to: page),end = convert(local,to: page)
            _ = translateAnnotationSelection(dx: end.x-origin.x,dy: end.y-origin.y); return
        }
        if event.modifierFlags.contains(.command) {
            switch event.keyCode {
            case 6: onClipboardCommand?(.feature(event.modifierFlags.contains(.shift) ? "redo" : "undo")); return
            case 8: onClipboardCommand?(.copy); return
            case 7: onClipboardCommand?(.cut); return
            case 9: onClipboardCommand?(.paste); return
            default: break
            }
        }
        if event.keyCode == 51 || event.keyCode == 117 {
            if activeTool == .selectComments && deleteSelectedAnnotation() { return }
            if sourceSelection != nil { onClipboardCommand?(.deleteSelection); return }
        }
        if event.keyCode == 53 { contentSelection = nil; contentPreview = nil; contentDrag = nil; onSelectionChanged?(nil); selectAnnotation(nil); setSourceSelection(nil); preview = nil; transform = nil; batchMove = nil; annotationMarquee = nil; refreshOverlay(); return }
        super.keyDown(with: event)
    }
    private func commitDrawing(_ drawing: Preview) {
        let start = drawing.start, end = drawing.end
        guard hypot(end.x - start.x, end.y - start.y) >= 3 else { return }
        let rect = CGRect(x: min(start.x, end.x) - 1, y: min(start.y, end.y) - 1, width: max(2, abs(end.x - start.x) + 2), height: max(2, abs(end.y - start.y) + 2))
        if drawing.tool == .marquee { zoom(to: rect,on: drawing.page); return }
        if drawing.tool == .snapshot { onSnapshot?(drawing.page,CGRect(x: min(start.x,end.x),y: min(start.y,end.y),width: abs(end.x-start.x),height: abs(end.y-start.y))); return }
        if drawing.tool == .link { pendingLinkBounds = rect; onPlaceObject?(drawing.page,rect.origin,.link); return }
        let subtype: PDFAnnotationSubtype
        switch drawing.tool { case .rectangle: subtype = .square; case .ellipse: subtype = .circle; case .pencil,.cloud: subtype = .ink; default: subtype = .line }
        let annotation = PDFAnnotation(bounds: rect, forType: subtype, withProperties: nil)
        if drawing.tool == .pencil || drawing.tool == .cloud {
            let path = NSBezierPath()
            if drawing.tool == .pencil {
                let points = drawing.points.isEmpty ? [start,end] : drawing.points
                for (index,p) in points.enumerated() { let local = CGPoint(x: p.x-rect.minX,y: p.y-rect.minY); if index == 0 { path.move(to: local) } else { path.line(to: local) } }
            } else {
                let inset = max(3,strokeWidth*2),box = CGRect(x: inset,y: inset,width: max(3,rect.width-inset*2),height: max(3,rect.height-inset*2))
                let radius = min(12,max(3,min(box.width,box.height)/8))
                let edges = [(CGPoint(x: box.minX,y: box.minY),CGPoint(x: box.maxX,y: box.minY)),(CGPoint(x: box.maxX,y: box.minY),CGPoint(x: box.maxX,y: box.maxY)),(CGPoint(x: box.maxX,y: box.maxY),CGPoint(x: box.minX,y: box.maxY)),(CGPoint(x: box.minX,y: box.maxY),CGPoint(x: box.minX,y: box.minY))]
                path.move(to: edges[0].0)
                for (a,b) in edges {
                    let length = hypot(b.x-a.x,b.y-a.y),count = max(1,Int(ceil(length/(radius*2))))
                    for i in 0..<count {
                        let t = CGFloat(i)/CGFloat(count),u = CGFloat(i+1)/CGFloat(count)
                        let from = CGPoint(x: a.x+(b.x-a.x)*t,y: a.y+(b.y-a.y)*t),to = CGPoint(x: a.x+(b.x-a.x)*u,y: a.y+(b.y-a.y)*u)
                        let dx = to.x-from.x,dy = to.y-from.y,normal = CGPoint(x: dy*0.55,y: -dx*0.55)
                        path.curve(to: to,controlPoint1: CGPoint(x: from.x+dx*0.25+normal.x,y: from.y+dy*0.25+normal.y),controlPoint2: CGPoint(x: from.x+dx*0.75+normal.x,y: from.y+dy*0.75+normal.y))
                    }
                }; path.close()
            }; annotation.add(path)
        }
        if drawing.tool == .rectangle || drawing.tool == .ellipse { annotation.interiorColor = fillEnabled ? strokeColor.withAlphaComponent(strokeColor.alphaComponent*0.25) : nil }
        annotation.color = strokeColor
        AnnotationMetadata.setOpacity(Double(strokeColor.alphaComponent), on: annotation)
        if drawing.tool == .callout { AnnotationMetadata.setGroup(UUID().uuidString, on: annotation) }
        let border = PDFBorder(); border.lineWidth = strokeWidth; annotation.border = border
        if [.line,.arrow,.callout].contains(drawing.tool) {
            annotation.startPoint = CGPoint(x: start.x - rect.minX, y: start.y - rect.minY)
            annotation.endPoint = CGPoint(x: end.x - rect.minX, y: end.y - rect.minY)
            if drawing.tool == .arrow { annotation.endLineStyle = .openArrow }
            if drawing.tool == .callout { annotation.startLineStyle = .openArrow }
        }
        onWillModify?(); drawing.page.addAnnotation(annotation)
        if drawing.tool == .callout { onCreateText?(drawing.page, end, annotation) }
        else { selectAnnotation(annotation) }
        setNeedsDisplay(bounds)
    }
    fileprivate func applyScroll(_ event: NSEvent) {
        guard let scroll = internalScrollView else { return }
        let clip = scroll.contentView
        let factorX = event.hasPreciseScrollingDeltas ? 1 : max(10, scroll.horizontalLineScroll)
        let factorY = event.hasPreciseScrollingDeltas ? 1 : max(10, scroll.verticalLineScroll)
        let deltaInView = CGPoint(x: -event.scrollingDeltaX * factorX,
                                  y: (isFlipped ? -1 : 1) * event.scrollingDeltaY * factorY)
        let delta = clip.convert(deltaInView, from: self) - clip.convert(.zero, from: self)
        if lastScrollOrigin != clip.bounds.origin || event.phase.contains(.began) {
            requestedScrollOrigin = clip.bounds.origin
        }
        let previous = requestedScrollOrigin ?? clip.bounds.origin
        var proposed = CGPoint(x: previous.x + delta.x, y: previous.y + delta.y)
        if let document = scroll.documentView {
            let content = document.frame
            if content.width > clip.bounds.width {
                proposed.x = min(max(content.minX, proposed.x), content.maxX - clip.bounds.width)
            } else { proposed.x = clip.bounds.minX }
            if content.height+scroll.contentInsets.top+scroll.contentInsets.bottom > clip.bounds.height {
                proposed.y = min(max(content.minY-scroll.contentInsets.top, proposed.y), content.maxY-clip.bounds.height+scroll.contentInsets.bottom)
            } else { proposed.y = clip.bounds.minY }
        }
        // Keep sub-point deltas between events when AppKit aligns clip origins.
        requestedScrollOrigin = proposed
        clip.setBoundsOrigin(proposed)
        lastScrollOrigin = clip.bounds.origin
        clip.needsDisplay = true
        scroll.reflectScrolledClipView(clip)
        refreshOverlay(); onViewportChange?()
    }
    fileprivate func queueMagnification(_ delta: CGFloat,at point: CGPoint) {
        guard delta.isFinite,delta != 0,let document else { return }
        let identity = ObjectIdentifier(document)
        if pendingZoomDocument != identity { pendingZoom = 0; pendingZoomDocument = identity }
        pendingZoom += delta; zoomAnchor = point
        guard !zoomScheduled else { return }; zoomScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flushMagnification() }
    }
    private func flushMagnification() {
        zoomScheduled = false
        let delta = pendingZoom,point = zoomAnchor,identity = pendingZoomDocument
        pendingZoom = 0; pendingZoomDocument = nil; zoomAnchor = nil
        if let point,let document,identity == ObjectIdentifier(document) { applyMagnification(delta,at: point) }
    }
    func configureZoomLimits() { if minScaleFactor != PDFZoomLimits.minimum { minScaleFactor = PDFZoomLimits.minimum }; if maxScaleFactor != PDFZoomLimits.maximum { maxScaleFactor = PDFZoomLimits.maximum } }
    private func applyMagnification(_ delta: CGFloat, at anchor: CGPoint) {
        guard document != nil else { return }; configureZoomLimits()
        requestedScrollOrigin = nil; lastScrollOrigin = nil
        guard delta.isFinite, delta != 0 else { return }
        let page = page(for: anchor, nearest: true)
        let pagePoint = page.map { convert(anchor, to: $0) }
        autoScales = false
        scaleFactor = min(maxScaleFactor, max(minScaleFactor, scaleFactor * exp(delta)))
        layoutDocumentView()
        if let page, let pagePoint, let scroll = internalScrollView {
            let clip = scroll.contentView
            // Older PDFKit releases adjust the clip origin during scale layout.
            // Recalculate the correction after layout, then once more after scroll.
            for _ in 0..<2 {
                let mapped = convert(pagePoint, from: page)
                let movement = clip.convert(mapped, from: self) - clip.convert(anchor, from: self)
                if hypot(movement.x, movement.y) < 0.25 { break }
                var origin = CGPoint(x: clip.bounds.minX + movement.x, y: clip.bounds.minY + movement.y)
                if let document = scroll.documentView {
                    let content = document.frame
                    if content.width > clip.bounds.width {
                        origin.x = min(max(content.minX, origin.x), content.maxX - clip.bounds.width)
                    } else { origin.x = clip.bounds.minX }
                    if content.height+scroll.contentInsets.top+scroll.contentInsets.bottom > clip.bounds.height {
                        origin.y = min(max(content.minY-scroll.contentInsets.top, origin.y), content.maxY-clip.bounds.height+scroll.contentInsets.bottom)
                    } else { origin.y = clip.bounds.minY }
                }
                // Retain fractional coordinates where supported. Older AppKit
                // releases may align the resulting origin to clip-space pixels.
                clip.setBoundsOrigin(origin)
                clip.needsDisplay = true
                scroll.reflectScrolledClipView(clip)
            }
        }
        refreshOverlay(); onViewportChange?()
    }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) {
            queueMagnification(-event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08),at: HoverEventLocation.point(for: event,in: self) ?? convert(event.locationInWindow,from: nil))
        } else {
            if internalScrollView != nil { applyScroll(event) } else { super.scrollWheel(with: event) }
        }
    }
    override func magnify(with event: NSEvent) {
        queueMagnification(event.magnification,at: HoverEventLocation.point(for: event,in: self) ?? convert(event.locationInWindow,from: nil))
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        backgroundColor = NSColor(calibratedWhite: effectiveAppearance.bestMatch(from: [.darkAqua,.aqua]) == .darkAqua ? 0.12 : 0.82,alpha: 1)
    }
    override func viewDidEndLiveResize() { super.viewDidEndLiveResize(); onViewportChange?() }
    private var resizeRefreshPending = false
    override func setFrameSize(_ size: NSSize) {
        guard size != frame.size else { return }
        super.setFrameSize(size)
        guard !resizeRefreshPending else { return }; resizeRefreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }; self.resizeRefreshPending = false
            self.onViewportChange?(); self.refreshOverlay()
        }
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

@MainActor
private enum PDFDialogs {
    static func prompt(_ title: String, fields: [(String,String)], completion: @escaping ([String]) -> Void) {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow else { return }
            let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel / Отмена")
            let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 6
            let inputs = fields.map { label,value -> NSTextField in
                stack.addArrangedSubview(NSTextField(labelWithString: label))
                let input = NSTextField(string: value); input.frame.size = CGSize(width: 340,height: 24); stack.addArrangedSubview(input); return input
            }
            stack.frame = CGRect(x: 0,y: 0,width: 340,height: CGFloat(fields.count*52)); alert.accessoryView = stack
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    let values = inputs.map(\.stringValue)
                    DispatchQueue.main.async { completion(values) }
                }
            }
        }
    }
    static func save(_ name: String, type: UTType, completion: @escaping (URL) -> Void) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [type]; panel.nameFieldStringValue = name
        panel.begin { response in if response == .OK,let url = panel.url { DispatchQueue.main.async { completion(url) } } }
    }
    static func open(_ types: [UTType], completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.allowsMultipleSelection = true
        panel.begin { response in if response == .OK { let urls = panel.urls; DispatchQueue.main.async { completion(urls) } } }
    }
}

@MainActor
private extension DocumentManager {
    func createBlankDocument() {
        let document = PDFDocument(); let page = PDFPage(); page.setBounds(CGRect(x: 0,y: 0,width: 612,height: 792),for: .mediaBox); document.insert(page,at: 0)
        let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf"),document: document); entry.isUntitled = true; insertDocument(entry)
    }
    func insertDocument(_ entry: PDFDocumentItem) { documents.append(entry); select(entry.id) }
    func embeddedText(in item: PDFDocumentItem,indices: [Int]) -> String? {
        guard item.document.allowsCopying else { say("Text copying is not permitted.","Документ запрещает копирование текста."); return nil }
        do {
            let identity = ObjectIdentifier(item.document)
            if identity != embeddedTextDocument || embeddedTextRevision != contentRevision {
                embeddedTextDocument = identity; embeddedTextRevision = contentRevision
                embeddedTextCache = [:]; embeddedTextData = nil
            }
            let missing = indices.filter { embeddedTextCache[$0] == nil }
            if !missing.isEmpty {
                if embeddedTextData == nil { embeddedTextData = try serializedData(item) }
                guard let data = embeddedTextData else { return nil }
                let pages = try PDFSourceTextReader.pages(data: data,indices: missing)
                for (index,text) in zip(missing,pages) { embeddedTextCache[index] = text }
            }
            return indices.compactMap { embeddedTextCache[$0] }.joined(separator: "\n")
        } catch {
            say("Could not read the existing PDF text layer.","Не удалось прочитать текстовый слой PDF."); return nil
        }
    }
    func activateMarkup(_ next: PDFTool) {
        guard finishSourceEditing?() != false else { return }
        if ![PDFTool.highlight,.underline,.strike].contains(tool) {
            annotationColor = next == .highlight ? .yellow : .red
            annotationOpacity = next == .highlight ? 0.45 : 0.85
        }
        tool = next; panels.select(.properties)
        send(next == .underline ? .underline : (next == .strike ? .strike : .highlight))
    }
    func bookmarkRoot() -> PDFOutline? {
        guard let document = selected?.document else { return nil }
        if document.outlineRoot == nil { document.outlineRoot = PDFOutline() }
        return document.outlineRoot
    }
    func bookmarkNodes(_ root: PDFOutline? = nil) -> [PDFOutline] {
        guard let root = root ?? selected?.document.outlineRoot else { return [] }
        var nodes: [PDFOutline] = []
        for index in 0..<root.numberOfChildren { if let child = root.child(at: index) { nodes.append(child); nodes += bookmarkNodes(child) } }
        return nodes
    }
    func addBookmark(title: String,page: PDFPage,parent: PDFOutline? = nil) {
        guard let root = parent ?? bookmarkRoot() else { return }
        let node = PDFOutline(); node.label = title; node.destination = PDFDestination(page: page,at: CGPoint(x: page.bounds(for: .cropBox).minX,y: page.bounds(for: .cropBox).maxY))
        if let item = selected { recordUndo(item,group: "bookmarks") }
        root.insertChild(node,at: root.numberOfChildren); selectedOutline = node; send(.refresh)
    }
    func addBookmarkPrompt(parent: PDFOutline? = nil) {
        guard let page = selected?.document.page(at: selected?.pageIndex ?? 0) else { return }
        PDFDialogs.prompt(language == .ru ? "Новая закладка" : "New bookmark",fields: [(language == .ru ? "Название" : "Title","Page \((selected?.pageIndex ?? 0)+1)")]) { [weak self] values in
            self?.addBookmark(title: values[0],page: page,parent: parent)
        }
    }
    func renameBookmark(_ node: PDFOutline) {
        PDFDialogs.prompt(language == .ru ? "Имя закладки" : "Bookmark title",fields: [("",node.label ?? "")]) { [weak self] values in if let self,let item = self.selected { self.recordUndo(item,group: "bookmarks") }; node.label = values[0]; self?.send(.refresh) }
    }
    func deleteBookmark(_ node: PDFOutline) { if let item = selected { recordUndo(item,group: "bookmarks") }; node.removeFromParent(); selectedOutline = nil; send(.refresh) }
    func editLink(_ annotation: PDFAnnotation) {
        let old = (annotation.action as? PDFActionURL)?.url?.absoluteString ?? "https://"
        PDFDialogs.prompt(language == .ru ? "Ссылка" : "Link",fields: [("URL",old)]) { [weak self] values in
            guard let url = URL(string: values[0]),["https","http","mailto"].contains(url.scheme?.lowercased() ?? "") else { self?.say("Invalid URL","Некорректный URL"); return }
            if let self,let item = self.selected { self.recordUndo(item,group: "link") }
            annotation.action = PDFActionURL(url: url); self?.send(.refresh)
        }
    }
}

@MainActor
private enum PDFRasterizer {
    private static let backingDocuments = NSMapTable<PDFPage,PDFDocument>.weakToStrongObjects()
    static func image(_ page: PDFPage,size: CGSize) -> NSImage {
        NSImage(size: size,flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.saveGState()
            context.concatenate(PDFFormattingGeometry.transform(page, box: .cropBox, target: rect))
            if let ref = page.pageRef { context.drawPDFPage(ref) }
            for annotation in page.annotations where annotation.shouldDisplay && !AnnotationMetadata.isContainer(annotation) { annotation.draw(with: .cropBox,in: context) }
            context.restoreGState(); return true
        }
    }
    static func textPage(_ text: String) -> PDFPage? {
        let data = NSMutableData(); var box = CGRect(x: 0,y: 0,width: 612,height: 792)
        guard let consumer = CGDataConsumer(data: data),let context = CGContext(consumer: consumer,mediaBox: &box,nil) else { return nil }
        context.beginPDFPage(nil); context.textMatrix = .identity
        let font = CTFontCreateWithName("Arial" as CFString,12,nil)
        let attributes: [NSAttributedString.Key:Any] = [NSAttributedString.Key(kCTFontAttributeName as String):font,NSAttributedString.Key(kCTForegroundColorAttributeName as String):NSColor.black.cgColor]
        let attributed = NSAttributedString(string: text,attributes: attributes)
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var offset = 0,y: CGFloat = 748
        while offset < attributed.length && y > 40 {
            let count = max(1,CTTypesetterSuggestLineBreak(typesetter,offset,532))
            let line = CTTypesetterCreateLine(typesetter,CFRange(location: offset,length: count))
            context.textPosition = CGPoint(x: 40,y: y); CTLineDraw(line,context)
            y -= 16; offset += count
        }
        context.endPDFPage(); context.closePDF()
        guard let document = PDFDocument(data: data as Data),let page = document.page(at: 0)?.copy() as? PDFPage else { return nil }
        backingDocuments.setObject(document,forKey: page)
        return page
    }
}

@MainActor
private extension PDFViewer.Coordinator {
    func placeObject(_ tool: PDFTool,on page: PDFPage,point: CGPoint,view: PDFViewerView) {
        if [.formText,.formCheckbox,.formRadio,.formChoice,.formButton].contains(tool) {
            PDFDialogs.prompt(manager.language == .ru ? "Поле формы" : "Form field",fields: [("Name / Имя","Field-"+UUID().uuidString.prefix(6)),("Choices / Варианты (через ;)","Yes;No")]) { [weak self,weak view] values in
                guard let self,let view else { return }
                let crop = page.bounds(for: .cropBox),small = tool == .formCheckbox || tool == .formRadio
                let width: CGFloat = small ? 24 : min(220,crop.width),height: CGFloat = 28
                let rect = CGRect(x: min(max(crop.minX,point.x),crop.maxX-width),y: min(max(crop.minY,point.y-height),crop.maxY-height),width: width,height: height)
                let annotation = PDFWidgetFactory.make(tool,bounds: rect,name: values[0],choices: values[1].components(separatedBy: ";"))
                if let item = self.manager.selected { self.manager.recordUndo(item,group: "form") }
                page.addAnnotation(annotation); view.selectAnnotation(annotation); self.manager.tool = .textSelection; self.manager.send(.refresh)
            }; return
        }
        if tool == .link {
            let bounds = view.pendingLinkBounds ?? CGRect(x: point.x,y: point.y,width: 140,height: 24); view.pendingLinkBounds = nil
            let annotation = PDFAnnotation(bounds: bounds,forType: .link,withProperties: nil)
            PDFDialogs.prompt(manager.language == .ru ? "Добавить ссылку" : "Add link",fields: [("URL","https://")]) { [weak self,weak view] values in
                guard let url = URL(string: values[0]),["http","https","mailto"].contains(url.scheme?.lowercased() ?? "") else { self?.manager.say("Invalid URL","Некорректный URL"); return }
                annotation.action = PDFActionURL(url: url); annotation.color = .systemBlue
                let border = PDFBorder(); border.lineWidth = 1; annotation.border = border
                if let self,let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") }
                page.addAnnotation(annotation); view?.selectAnnotation(annotation); view?.setNeedsDisplay(view?.bounds ?? .zero); self?.manager.send(.refresh)
            }; return
        }
        let note = tool == .note
        let title = manager.language == .ru ? (note ? "Заметка" : "Штамп") : (note ? "Note" : "Stamp")
        PDFDialogs.prompt(title,fields: [(manager.language == .ru ? "Текст" : "Text",note ? "" : manager.stampText)]) { [weak self,weak view] values in
            guard let self,let view else { return }
            let crop = page.bounds(for: .cropBox)
            let width: CGFloat = note ? 24 : min(230,crop.width),height: CGFloat = note ? 24 : 52
            let rect = CGRect(x: min(max(crop.minX,point.x),crop.maxX-width),y: min(max(crop.minY,point.y-height),crop.maxY-height),width: width,height: height)
            let annotation = PDFAnnotation(bounds: rect,forType: note ? .text : .freeText,withProperties: nil)
            annotation.contents = values[0]; annotation.userName = BotPlusBrand.name
            if note { annotation.iconType = .note; annotation.color = NSColor(self.manager.annotationColor) }
            else {
                self.manager.stampText = values[0]; annotation.font = NSFont.boldSystemFont(ofSize: 18); annotation.fontColor = view.strokeColor; annotation.color = .clear; annotation.alignment = .center
                let border = PDFBorder(); border.lineWidth = 2; annotation.border = border
            }
            AnnotationMetadata.setOpacity(self.manager.annotationOpacity,on: annotation)
            if let item = self.manager.selected { self.manager.recordUndo(item,group: "annotation") }
            page.addAnnotation(annotation); view.selectAnnotation(annotation); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
        }
    }
    func performFeature(_ id: String,on view: PDFViewerView,item: PDFDocumentItem) {
        guard finishSourceEditor() else { return }
        let tools: [String:PDFTool] = ["cloud":.cloud,"pencil":.pencil,"eraser":.eraser,"sticky":.note,"note":.note,"addComment":.note,"addLink":.link,"marquee":.marquee,"textField":.formText,"checkbox":.formCheckbox,"radio":.formRadio,"dropdown":.formChoice,"button":.formButton]
        if let tool = tools[id] {
            if tool == .stamp { manager.annotationColor = .red; manager.annotationOpacity = 1 }
            if tool == .note { manager.annotationColor = .yellow; manager.annotationOpacity = 1 }
            manager.tool = tool; manager.panels.select(.properties); manager.refreshPresentation(); return }
        let page = view.currentPage ?? item.document.page(at: item.pageIndex)
        if ["bookmarkSortPages","bookmarkLinks","clear"].contains(id) { manager.recordUndo(item,group: id) }
        if performAdditionalFeature(id,on: view,item: item) { return }
        switch id {
        case "margins","background": showFormatting(id, item: item, view: view)
        case "signature", "initials", "stamp": showGraphicMark(id, item: item, view: view)
        case "replace": replacePages(item: item,view: view)
        case "alignFields": alignFields(item: item,view: view)
        case "emailCurrent","emailAll": emailPDF(item: item,view: view,currentPage: id == "emailCurrent")
        case "strike": manager.activateMarkup(.strike)
        case "edit": manager.tool = .editText; manager.refreshPresentation()
        case "editContent": manager.tool = .editContent; manager.refreshPresentation()
        case "editLink":
            manager.tool = .selectComments
            if let annotation = view.selectedAnnotation,annotation.type == "Link" { manager.editLink(annotation) }
            else { manager.say("Select a link, then choose Edit Links.","Выберите ссылку и нажмите «Изменить ссылки».") }
        case "list","showComments": manager.panels.toggleDrawer(.comments)
        case "deleteComment": _ = view.deleteSelectedAnnotation()
        case "wordCount":
            guard let text = manager.embeddedText(in: item,indices: Array(0..<item.pageCount)) else { return }
            let count = text.split { $0.isWhitespace || $0.isNewline }.count
            manager.say("Words: \(count); characters: \(text.count)","Слов: \(count); знаков: \(text.count)")
        case "read":
            if manager.speech.isPaused { manager.speech.continueSpeaking() }
            else if !manager.speech.isSpeaking,let page,let text = manager.embeddedText(in: item,indices: [item.document.index(for: page)]),!text.isEmpty {
                let utterance = AVSpeechUtterance(string: text); utterance.voice = AVSpeechSynthesisVoice(language: manager.language == .ru ? "ru-RU" : "en-US"); manager.speech.speak(utterance)
            }
        case "pauseRead": manager.speech.pauseSpeaking(at: .word)
        case "bookmarkAdd": manager.addBookmarkPrompt()
        case "bookmarkDelete": if let node = manager.selectedOutline { manager.deleteBookmark(node) }
        case "bookmarkFromPageText":
            guard let page else { return }
            let title = view.currentSelection?.string ?? manager.embeddedText(in: item,indices: [item.document.index(for: page)])?.split(separator: "\n").first.map(String.init) ?? "Page \(item.pageIndex+1)"
            manager.addBookmark(title: String(title.prefix(160)),page: page); manager.panels.select(.bookmarks)
        case "bookmarkEveryN":
            PDFDialogs.prompt(manager.language == .ru ? "Закладки через N страниц" : "Bookmarks every N pages",fields: [("N","1"),(manager.language == .ru ? "Префикс" : "Prefix",manager.language == .ru ? "Страница" : "Page")]) { [weak self] values in
                guard let self,let step = Int(values[0]),step > 0 else { return }
                for index in stride(from: 0,to: item.pageCount,by: step) { if let page = item.document.page(at: index) { self.manager.addBookmark(title: "\(values[1]) \(index+1)",page: page) } }
                self.manager.panels.select(.bookmarks)
            }
        case "bookmarkFromTOC":
            guard let page,let text = manager.embeddedText(in: item,indices: [item.document.index(for: page)]) else { return }
            let regex = try! NSRegularExpression(pattern: "^(.+?)\\s*[.·…\\s]+(\\d+)\\s*$")
            var added = 0
            for line in text.components(separatedBy: .newlines) {
                let string = line as NSString
                if let match = regex.firstMatch(in: line,range: NSRange(location: 0,length: string.length)),let number = Int(string.substring(with: match.range(at: 2))),let target = item.document.page(at: number-1) {
                    manager.addBookmark(title: string.substring(with: match.range(at: 1)),page: target); added += 1
                }
            }
            manager.say("Created \(added) bookmarks from this page.","Создано закладок: \(added). Используется текст текущей страницы.")
        case "bookmarkFromFile":
            PDFDialogs.open([.plainText]) { [weak self] urls in
                guard let self,let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    guard let text = String(data: data,encoding: .utf8) ?? String(data: data,encoding: .utf16) ?? String(data: data,encoding: .windowsCP1251) else { throw PDFSourceError.content }
                    let lines = text.components(separatedBy: .newlines)
                    for (offset,line) in lines.enumerated() where !line.isEmpty {
                        let parts = line.components(separatedBy: "\t"); let index = parts.count > 1 ? (Int(parts[0]) ?? 0)-1 : offset
                        if let page = item.document.page(at: index) { self.manager.addBookmark(title: parts.count > 1 ? parts.dropFirst().joined(separator: "\t") : line,page: page) }
                    }
                    self.manager.panels.select(.bookmarks)
                } catch { self.manager.say("Cannot read UTF-8 text file.","Не удалось прочитать текстовый файл UTF-8.") }
            }
        case "bookmarkAddText","bookmarkFind":
            showBookmarkTextEditor(item: item,operation: id == "bookmarkFind" ? .replace : .affix)
        case "bookmarkCase":
            showBookmarkTextEditor(item: item,operation: .letterCase)
        case "bookmarkZoom":
            showBookmarkTextEditor(item: item,operation: .zoom,zoom: Double(view.scaleFactor*100))
        case "bookmarkActions":
            showBookmarkTextEditor(item: item,operation: .clearActions)
        case "bookmarkSort":
            showBookmarkTextEditor(item: item,operation: .sort)
        case "bookmarkMerge":
            showBookmarkTextEditor(item: item,operation: .merge)
        case "bookmarkValidate":
            showBookmarkValidation(item: item)
        case "bookmarkText","bookmarkHTML": exportBookmarks(html: id == "bookmarkHTML",item: item)
        case "bookmarkTOC": createTOC(item: item,view: view)
        case "bookmarkLinks":
            guard let page else { return }
            for node in manager.bookmarkNodes() {
                guard let destination = node.destination,let title = node.label,!title.isEmpty else { continue }
                for selection in item.document.findString(title,withOptions: .caseInsensitive) where selection.pages.contains(page) {
                    let bounds = selection.bounds(for: page); guard !bounds.isEmpty else { continue }
                    let link = PDFAnnotation(bounds: bounds,forType: .link,withProperties: nil); link.action = PDFActionGoTo(destination: destination); page.addAnnotation(link)
                }
            }; view.setNeedsDisplay(view.bounds); manager.send(.refresh)
        case "bookmarkSortPages": sortPagesByBookmarks(item: item,view: view)
        case "blank": manager.createBlankDocument()
        case "fromFiles","insert": importPages(item: item,view: view)
        case "extract","split","swap": showPageWorkflow(id, item: item, view: view)
        case "cropLegacy":
            guard let page else { return }
            PDFDialogs.prompt("Crop / Обрезка",fields: [("Inset, pt / Отступ, pt","18")]) { [weak self,weak view] values in
                guard let self,let view,let inset = Double(values[0]),inset >= 0 else { return }
                let box = page.bounds(for: .mediaBox).insetBy(dx: inset,dy: inset); guard box.width > 1,box.height > 1 else { return }
                page.setBounds(box,for: .cropBox); self.reload(view,document: item,pageIndex: item.pageIndex); self.manager.send(.refresh)
            }
        case "images": showFormatting(id, item: item, view: view)
        case "exportComments": exportComments(item: item)
        case "importComments": importComments(item: item,view: view)
        case "clear":
            for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" { AnnotationMetadata.clearFormSelections(field); field.widgetStringValue = ""; field.buttonWidgetState = .offState } }; view.setNeedsDisplay(view.bounds); manager.send(.refresh)
        case "fill": manager.tool = .textSelection; view.isInMarkupMode = false
        case "selectFields": manager.tool = .selectComments
        case "export": exportFormData(item: item)
        case "import": importFormData(item: item,view: view)
        case "watermark","header","bates": showFormatting(id, item: item, view: view)
        case "addImage": importImage(page: page,view: view)
        case "newWindow": PDFWindowPool.shared.open()
        case "cascade": for (index,window) in NSApp.windows.filter({ $0 is NSPanel == false }).enumerated() { window.setFrameOrigin(CGPoint(x: 100+index*24,y: 120+index*24)) }
        default: manager.say("Feature in development","Функция в разработке")
        }
    }
    func sortBookmarks(_ root: PDFOutline) {
        let children = (0..<root.numberOfChildren).compactMap { root.child(at: $0) }.sorted { ($0.label ?? "").localizedStandardCompare($1.label ?? "") == .orderedAscending }
        children.forEach { $0.removeFromParent() }
        for child in children { root.insertChild(child,at: root.numberOfChildren); sortBookmarks(child) }
    }
    func mergeBookmarks(_ root: PDFOutline,document: PDFDocument) {
        var seen: [String:PDFOutline] = [:]
        for child in (0..<root.numberOfChildren).compactMap({ root.child(at: $0) }) {
            let key = (child.label ?? "")+"|"+String(child.destination?.page.map { document.index(for: $0) } ?? -1)
            if let existing = seen[key] {
                let descendants = (0..<child.numberOfChildren).compactMap { child.child(at: $0) }
                for nested in descendants { nested.removeFromParent(); existing.insertChild(nested,at: existing.numberOfChildren) }; child.removeFromParent()
            } else { seen[key] = child }; mergeBookmarks(seen[key]!,document: document)
        }
    }
    func exportBookmarks(html: Bool,item: PDFDocumentItem) {
        let rows = makeBookmarkRows(root: manager.bookmarkRoot()!,document: item.document)
        func escape(_ text: String) -> String { text.replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: "\"",with: "&quot;") }
        let content: String
        if html {
            let lang = manager.language == .ru ? "ru" : "en"
            var result = "<!doctype html><html lang=\""+lang+"\"><meta charset=\"utf-8\"><title>Bookmarks</title><body><h1>"
            result += escape(item.filename)+"</h1><ul>"
            for row in rows { result += "<li>"+escape(row.title)+" — "+String(row.pageIndex+1)+"</li>" }
            result += "</ul></body></html>"; content = result
        } else {
            var lines: [String] = []
            for row in rows { let indent = String(repeating: "  ",count: row.depth); lines.append(String(row.pageIndex+1)+"\t"+indent+row.title) }
            content = lines.joined(separator: "\n")
        }
        PDFDialogs.save("Bookmarks."+(html ? "html" : "txt"),type: html ? .html : .plainText) { [weak self] url in
            do { try content.write(to: url,atomically: true,encoding: .utf8) } catch { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func createTOC(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentAssembly || item.document.allowsDocumentChanges,manager.finishSourceEditing?() != false else { return }
        let document = item.document,undoGroup = "tableOfContents-"+UUID().uuidString
        var stamp = PDFDocumentState.stamp(document)
        manager.tocRequest = PDFTOCRequest(russian: manager.language == .ru,load: { options in
            guard item.document === document else { throw PDFTOCError.layout }
            let result = try PDFTOCRenderer.render(entries: PDFTOCRenderer.entries(document: document,options: options),options: options)
            stamp = PDFDocumentState.stamp(document)
            return result
        },apply: { [weak self,weak view] result in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,
                  document.allowsDocumentAssembly || document.allowsDocumentChanges else { return "Документ изменён. Обновите предпросмотр / Document changed. Update the preview" }
            guard let generated = PDFDocument(data: result.data),generated.pageCount == result.pageCount,
                  result.links.allSatisfy({ (0..<document.pageCount).contains(document.index(for: $0.target.page)) }),
                  let _ = self.manager.snapshot(item) else { return "Не удалось подготовить вставку / Could not prepare insertion" }
            let pages = (0..<generated.pageCount).compactMap { generated.page(at: $0)?.copy() as? PDFPage }
            guard pages.count == generated.pageCount else { return "Не удалось прочитать содержание / Could not read table of contents" }
            self.manager.recordUndo(item,group: undoGroup)
            for (index,page) in pages.enumerated() { document.insert(page,at: index) }
            for link in result.links {
                let annotation = PDFAnnotation(bounds: link.bounds,forType: .link,withProperties: nil)
                annotation.destination = PDFDestination(page: link.target.page,at: link.target.point)
                pages[link.pageIndex].addAnnotation(annotation)
            }
            item.navigation.reset(); item.selectedPages = [0]; self.manager.navigationRevision &+= 1
            self.reload(view,document: item,pageIndex: 0); self.manager.send(.refresh); return nil
        })
    }
    func sortPagesByBookmarks(item: PDFDocumentItem,view: PDFViewerView) {
        let indices = manager.bookmarkNodes().compactMap { $0.destination?.page.map { item.document.index(for: $0) } }.filter { $0 >= 0 && $0 < item.pageCount }
        var order: [Int] = []; for index in indices+Array(0..<item.pageCount) where !order.contains(index) { order.append(index) }
        let old = (0..<item.pageCount).compactMap { item.document.page(at: $0) }
        let links = manager.bookmarkNodes().compactMap { node -> (PDFOutline,Int,CGPoint)? in guard let destination = node.destination,let page = destination.page else { return nil }; return (node,item.document.index(for: page),destination.point) }
        let copies = old.compactMap { $0.copy() as? PDFPage }; guard copies.count == old.count else { return }
        for (source,copy) in zip(old,copies) { AnnotationMetadata.copy(from: source,to: copy) }
        while item.document.pageCount > 0 { item.document.removePage(at: 0) }
        for index in order { item.document.insert(copies[index],at: item.document.pageCount) }
        for (node,index,point) in links where copies.indices.contains(index) { node.destination = PDFDestination(page: copies[index],at: point) }
        reload(view,document: item,pageIndex: 0); manager.send(.refresh)
    }
    func importPages(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.pdf]) { [weak self,weak view] urls in
            guard let self,let view else { return }; var target = item.pageIndex+1
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let doc = PDFDocument(url: url) else { continue }; AnnotationMetadata.restore(doc)
                for index in 0..<doc.pageCount { if let page = doc.page(at: index),let copy = page.copy() as? PDFPage { AnnotationMetadata.copy(from: page,to: copy); item.document.insert(copy,at: target); target += 1 } }
            }; self.reload(view,document: item,pageIndex: item.pageIndex); self.manager.send(.refresh)
        }
    }
    func exportComments(item: PDFDocumentItem) {
        PDFDialogs.save("Comments.pdf",type: .pdf) { [weak self] url in
            let result = PDFDocument()
            for index in 0..<item.pageCount {
                guard let source = item.document.page(at: index) else { continue }; let page = PDFPage(); page.setBounds(source.bounds(for: .mediaBox),for: .mediaBox); page.setBounds(source.bounds(for: .cropBox),for: .cropBox)
                for annotation in source.annotations where !AnnotationMetadata.isContainer(annotation) { if let copy = annotation.copy() as? PDFAnnotation { copy.page = nil; AnnotationMetadata.transfer(from: [annotation],to: [copy]); page.addAnnotation(copy) } }; result.insert(page,at: result.pageCount)
            }; AnnotationMetadata.prepareForSave(result)
            if !result.write(to: url) { self?.manager.say("Export failed","Ошибка экспорта") }
        }
    }
    func importComments(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.pdf]) { [weak self,weak view] urls in
            guard let self,let view else { return }
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let source = PDFDocument(url: url) else { continue }; AnnotationMetadata.restore(source)
                for index in 0..<min(source.pageCount,item.pageCount) { guard let page = item.document.page(at: index) else { continue }
                    for annotation in source.page(at: index)?.annotations ?? [] where !AnnotationMetadata.isContainer(annotation) {
                        if let copy = annotation.copy() as? PDFAnnotation { copy.page = nil; AnnotationMetadata.transfer(from: [annotation],to: [copy]); page.addAnnotation(copy) }
                    }
                }
            }; view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
        }
    }
    func importImage(page: PDFPage?,view: PDFViewerView) {
        guard let page else { return }
        PDFDialogs.open([.image]) { [weak self,weak view] urls in
            guard let self,let view,let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let image = NSImage(contentsOf: url),image.size.width > 0 else { return }
            let crop = page.bounds(for: .cropBox),width = min(240,crop.width*0.7),height = min(crop.height*0.7,width*image.size.height/image.size.width)
            guard let item = self.manager.selected,let cgImage = image.cgImage(forProposedRect: nil,context: nil,hints: nil) else { return }
            let index = item.document.index(for: page),rect = CGRect(x: crop.midX-width/2,y: crop.midY-height/2,width: width,height: height)
            do {
                let data = try PDFSourceSession.insertingImage(data: self.sourceData(item),pageIndex: index,image: cgImage,bounds: rect)
                try self.installSourceData(data,item: item,index: index,view: view,bounds: rect)
                self.manager.selectedContent = PDFSourceSession.ContentObject(kind: "image",bounds: rect,pixelSize: CGSize(width: cgImage.width,height: cgImage.height)); self.manager.panels.select(.properties)
            } catch { self.sourceError(error) }
        }
    }
}


private extension PDFViewerView {
    func zoom(to rect: CGRect,on page: PDFPage) {
        let viewport = bounds.size,current = convert(rect,from: page)
        guard current.width > 0,current.height > 0 else { return }
        autoScales = false; scaleFactor = min(maxScaleFactor,max(minScaleFactor,scaleFactor*min(viewport.width/current.width,viewport.height/current.height)*0.95))
        go(to: PDFDestination(page: page,at: CGPoint(x: rect.minX,y: rect.maxY))); onViewportChange?()
    }
}

@MainActor
private final class PDFWindowPool: NSObject,NSWindowDelegate {
    static let shared = PDFWindowPool()
    private var windows: [NSWindow] = []
    private var closing = Set<ObjectIdentifier>()
    private var managers: [ObjectIdentifier: DocumentManager] = [:]
    private var focused: [ObjectIdentifier:DocumentManager] = [:]
    var allManagers: [DocumentManager] { Array(managers.values).flatMap { [$0]+($0.splitManager.map { [$0] } ?? []) } }
    func focus(_ manager: DocumentManager,window: NSWindow?) { if let window { focused[ObjectIdentifier(window)] = manager } }
    func clearFocus(_ manager: DocumentManager) { focused = focused.filter { $0.value !== manager } }
    func manager(for window: NSWindow?) -> DocumentManager? {
        guard let window else { return nil }
        return focused[ObjectIdentifier(window)] ?? managers[ObjectIdentifier(window)]
    }
    func open(item: PDFDocumentItem? = nil) {
        let window = NSWindow(contentRect: CGRect(x: 80,y: 80,width: 1280,height: 820),styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
        let manager = DocumentManager()
        if let item { manager.insertDocument(item) }
        managers[ObjectIdentifier(window)] = manager
        window.contentView = NSHostingView(rootView: ContentView(manager: manager).frame(minWidth: 1060,minHeight: 700)); window.title = BotPlusBrand.name; window.isReleasedWhenClosed = false; window.delegate = self
        windows.append(window); window.makeKeyAndOrderFront(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let key = ObjectIdentifier(sender)
        if closing.remove(key) != nil { return true }
        guard let owner = managers[key] else { return true }
        let owners = [owner]+(owner.splitManager.map { [$0] } ?? [])
        guard owners.allSatisfy({ $0.operationTask == nil && $0.loadingFiles == 0 && $0.finishSourceEditing?() != false }),sender.attachedSheet == nil else { return false }
        let views = owners.flatMap(\.documents),ids = Set(views.map(\.id))
        let retained = DocumentManager.workspaceManagers.flatMap(\.documents).filter { !ids.contains($0.id) }
        let dirty = views.filter { item in item.store.hasChanges && !retained.contains(where: { $0.store === item.store }) }
        guard !dirty.isEmpty else { return true }
        let alert = NSAlert(); alert.messageText = owner.language == .ru ? "Закрыть окно без сохранения?" : "Close window without saving?"
        alert.informativeText = Array(Set(dirty.map(\.filename))).sorted().joined(separator: "\n")
        alert.addButton(withTitle: owner.language == .ru ? "Отмена" : "Cancel"); alert.addButton(withTitle: owner.language == .ru ? "Закрыть без сохранения" : "Close without saving")
        alert.beginSheetModal(for: sender) { [weak self,weak sender] response in
            if response == .alertSecondButtonReturn { DispatchQueue.main.async { guard let self,let sender else { return }; self.closing.insert(key); sender.performClose(nil) } }
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            windows.removeAll { $0 === window }
            managers.removeValue(forKey: ObjectIdentifier(window))
            focused.removeValue(forKey: ObjectIdentifier(window))
        }
    }
}

@MainActor
private enum PDFWidgetFactory {
    static func stringValue(_ field: PDFAnnotation) -> String? {
        // PDFKit's widgetStringValue assumes /V is scalar and can throw an ObjC exception for legal multi-select arrays.
        if let values = field.value(forAnnotationKey: .widgetValue) as? [String] { return values.joined(separator: ", ") }
        if field.widgetFieldType == .choice,let value = field.value(forAnnotationKey: .widgetValue) as? String { return value }
        return field.widgetStringValue
    }
    static func make(_ tool: PDFTool,bounds: CGRect,name: String,choices: [String]) -> PDFAnnotation {
        let field = PDFAnnotation(bounds: bounds,forType: .widget,withProperties: nil)
        field.fieldName = name; field.color = .white; field.font = NSFont.systemFont(ofSize: 14); field.fontColor = .black
        let border = PDFBorder(); border.lineWidth = 1; field.border = border
        switch tool {
        case .formText: field.widgetFieldType = .text; field.widgetStringValue = ""
        case .formChoice: field.widgetFieldType = .choice; field.choices = choices; field.isListChoice = false; field.widgetStringValue = choices.first ?? ""
        default:
            field.widgetFieldType = .button
            field.widgetControlType = tool == .formRadio ? .radioButtonControl : (tool == .formButton ? .pushButtonControl : .checkBoxControl)
            field.buttonWidgetStateString = tool == .formRadio ? UUID().uuidString : "Yes"; field.buttonWidgetState = .offState
            if tool == .formButton { field.caption = name; field.action = PDFActionResetForm() }
        }
        field.fieldName = name
        field.font = NSFont.systemFont(ofSize: 14); field.fontColor = .black
        return field
    }
}

@MainActor
private extension PDFViewer.Coordinator {
    func formValues(_ item: PDFDocumentItem) -> [String:String] {
        var values: [String:String] = [:]
        for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" {
            guard let name = field.fieldName else { continue }
            if field.widgetFieldType == .button {
                if field.buttonWidgetState == .onState { values[name] = field.buttonWidgetStateString }
                else if values[name] == nil { values[name] = "Off" }
            } else { values[name] = PDFWidgetFactory.stringValue(field) ?? "" }
        } }; return values
    }
    func exportFormData(item: PDFDocumentItem) {
        guard let data = try? JSONEncoder().encode(formValues(item)) else { return }
        PDFDialogs.save("FormData.json",type: .json) { [weak self] url in do { try data.write(to: url) } catch { self?.manager.say("Export failed","Ошибка экспорта") } }
    }
    func importFormData(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.json]) { [weak self,weak view] urls in
            guard let self,let view,let url = urls.first else { return }; let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                let values = try JSONDecoder().decode([String:String].self,from: Data(contentsOf: url))
                for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" {
                    guard let name = field.fieldName,let value = values[name] else { continue }
                    if field.widgetFieldType == .button { field.buttonWidgetState = field.buttonWidgetStateString == value ? .onState : .offState }
                    else { AnnotationMetadata.clearFormSelections(field); field.widgetStringValue = value }
                } }; view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
            } catch { self.manager.say("Invalid form JSON file","Некорректный JSON-файл формы") }
        }
    }
}

@MainActor
private extension DocumentManager {
    func snapshot(_ item: PDFDocumentItem) -> PDFDocumentItem.Snapshot? {
        guard let data = try? serializedData(item) else { return nil }
        return PDFDocumentItem.Snapshot(data: data,page: item.pageIndex,zoom: item.zoom,bookmarks: item.canPreserveStreams ? nil : PDFBookmarkStore.capture(item.document))
    }
    func recordUndo(_ item: PDFDocumentItem,group: String) {
        let now = Date()
        if item.historyGroup == group && now.timeIntervalSince(item.historyDate) < 0.4 { item.historyDate = now; return }
        guard let state = snapshot(item) else { return }
        item.undoHistory.append(state); item.redoHistory.removeAll(); item.historyGroup = group; item.historyDate = now
        while item.undoHistory.count > 1 && item.undoHistory.reduce(0,{ $0+$1.data.count }) > 64*1024*1024 { item.undoHistory.removeFirst() }
    }
    func undoDocument(redo: Bool) {
        if textProperties.active,let editor = NSApp.keyWindow?.firstResponder as? NSTextView,let undo = editor.undoManager {
            if redo && undo.canRedo { undo.redo(); return }
            if !redo && undo.canUndo { undo.undo(); return }
        }
        guard finishSourceEditing?() != false,let item = selected,let current = snapshot(item) else { return }
        guard let state = redo ? item.redoHistory.popLast() : item.undoHistory.popLast(),let document = PDFDocument(data: state.data) else { return }
        if redo { item.undoHistory.append(current) } else { item.redoHistory.append(current) }
        AnnotationMetadata.restore(document)
        if let bookmarks = state.bookmarks { PDFBookmarkStore.restore(bookmarks,on: document) }
        selectedOutline = nil; selectedAnnotation = nil; selectedContent = nil
        item.navigation.reset(); navigationRevision &+= 1
        item.document = document; item.pageIndex = min(max(0,state.page),document.pageCount-1); item.zoom = state.zoom
        if state.bookmarks == nil { item.enableStreamPreservation() }
        item.historyGroup = ""; item.historyDate = .distantPast; pageText = String(item.pageIndex+1); send(.refresh)
        seedSerializedData(state.data,item: item)
    }
}

private extension PDFViewerView {
    func resetPagePadding() {
        let margin = pageBreakMargins, gap = configuredPageMargin
        if margin.top != gap || margin.bottom != gap || margin.left != gap || margin.right != gap { pageBreakMargins = NSEdgeInsets(top: gap,left: gap,bottom: gap,right: gap) }
        if let scroll = internalScrollView { scroll.contentInsets = NSEdgeInsets(top: 0,left: 0,bottom: 0,right: 0) }
    }
}

@MainActor
private enum PDFDocumentState {
    private static func combine(_ value: Any,into hash: inout Hasher,depth: Int = 0) {
        guard depth < 20 else { hash.combine("depth-limit"); return }
        if let text = value as? String { hash.combine("string"); hash.combine(text) }
        else if let number = value as? NSNumber { hash.combine(String(cString: number.objCType)); hash.combine(number.stringValue) }
        else if let data = value as? Data { hash.combine("data"); hash.combine(data) }
        else if let date = value as? Date { hash.combine("date"); hash.combine(date.timeIntervalSinceReferenceDate) }
        else if let url = value as? URL { hash.combine("url"); hash.combine(url.absoluteString) }
        else if let array = value as? [Any] {
            hash.combine("array"); hash.combine(array.count)
            for element in array { combine(element,into: &hash,depth: depth+1) }
        } else if let dictionary = value as? [AnyHashable:Any] {
            hash.combine("dictionary"); hash.combine(dictionary.count)
            for key in dictionary.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
                hash.combine(String(describing: key)); combine(dictionary[key]!,into: &hash,depth: depth+1)
            }
        } else if let color = value as? NSColor,let rgb = color.usingColorSpace(.deviceRGB) {
            hash.combine("color"); for component in [rgb.redComponent,rgb.greenComponent,rgb.blueComponent,rgb.alphaComponent] { hash.combine(component) }
        } else if let path = value as? NSBezierPath {
            hash.combine("path"); hash.combine(path.elementCount)
            for index in 0..<path.elementCount {
                var points = [NSPoint](repeating: .zero,count: 3)
                let kind = points.withUnsafeMutableBufferPointer { path.element(at: index,associatedPoints: $0.baseAddress!) }
                hash.combine(kind.rawValue)
                for point in points { hash.combine(point.x); hash.combine(point.y) }
            }
        } else if let boxed = value as? NSValue {
            let type = String(cString: boxed.objCType); hash.combine(type)
            if type.contains("CGRect") || type.contains("NSRect") { let rect = boxed.rectValue; for component in [rect.minX,rect.minY,rect.width,rect.height] { hash.combine(component) } }
            else if type.contains("CGPoint") || type.contains("NSPoint") { hash.combine(boxed.pointValue.x); hash.combine(boxed.pointValue.y) }
            else if type.contains("CGSize") || type.contains("NSSize") { hash.combine(boxed.sizeValue.width); hash.combine(boxed.sizeValue.height) }
            else if type.contains("NSRange") { hash.combine(boxed.rangeValue.location); hash.combine(boxed.rangeValue.length) }
        } else {
            // PDFKit can recreate opaque wrappers on every read. Their memory
            // addresses are not document state; editable properties are hashed above.
            hash.combine(String(reflecting: type(of: value)))
        }
    }
    static func rootStamp(_ document: PDFDocument) -> Int {
        var hash = Hasher()
        let attributes: [AnyHashable:Any] = document.documentAttributes ?? [:]
        for key in attributes.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) { hash.combine(key); combine(attributes[key]!,into: &hash) }
        func visit(_ node: PDFOutline,depth: Int) {
            guard depth < 64 else { return }
            hash.combine(node.label); hash.combine(node.numberOfChildren); hash.combine(node.isOpen)
            if let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination {
                hash.combine(destination.page.map { document.index(for: $0) }); hash.combine(destination.point.x)
                hash.combine(destination.point.y); hash.combine(destination.zoom)
            }
            hash.combine(node.action?.type)
            if let action = node.action as? PDFActionURL { hash.combine(action.url?.absoluteString) }
            if let action = node.action as? PDFActionNamed { hash.combine(action.name.rawValue) }
            if let action = node.action as? PDFActionRemoteGoTo {
                hash.combine(action.safeFileURL?.absoluteString); hash.combine(action.pageIndex)
                hash.combine(action.point.x); hash.combine(action.point.y)
            }
            if let action = node.action as? PDFActionResetForm { hash.combine(action.fields); hash.combine(action.fieldsIncludedAreCleared) }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index) { visit(child,depth: depth+1) } }
        }
        if let root = document.outlineRoot { visit(root,depth: 0) }
        return hash.finalize()
    }
    // Native PDFKit form filling can change values without a ribbon command.
    // Include that state so a cached source/Undo/save never loses those edits.
    static func stamp(_ document: PDFDocument) -> Int {
        var hash = Hasher(); hash.combine(document.pageCount)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            hash.combine(ObjectIdentifier(page)); hash.combine(page.rotation)
            for kind in [PDFDisplayBox.mediaBox,.cropBox] {
                let box = page.bounds(for: kind)
                for value in [box.origin.x,box.origin.y,box.width,box.height] { hash.combine(value) }
            }
            hash.combine(page.annotations.count)
            for annotation in page.annotations {
                hash.combine(ObjectIdentifier(annotation)); hash.combine(annotation.contents)
                if let ink = AnnotationMetadata.inkCurves(annotation) {
                    hash.combine("ink-curves"); hash.combine(ink.nodes.count)
                    for node in ink.nodes { hash.combine(node.kind.rawValue); for p in [node.point,node.control1,node.control2] { hash.combine(p.x); hash.combine(p.y) } }
                }
                hash.combine(PDFWidgetFactory.stringValue(annotation)); hash.combine(AnnotationMetadata.formSelections(annotation)); hash.combine(AnnotationMetadata.formRule(annotation)); hash.combine(annotation.widgetControlType.rawValue)
                hash.combine(annotation.buttonWidgetState.rawValue)
                for value in [annotation.bounds.minX,annotation.bounds.minY,annotation.bounds.width,annotation.bounds.height] { hash.combine(value) }
                hash.combine(annotation.color.description); hash.combine(annotation.font?.fontName); hash.combine(annotation.font?.pointSize)
                hash.combine(annotation.border?.lineWidth)
                let values = annotation.annotationKeyValues
                for key in values.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
                    hash.combine(key); combine(values[key]!,into: &hash)
                }
            }
        }
        let attributes: [AnyHashable:Any] = document.documentAttributes ?? [:]
        for key in attributes.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
            hash.combine(key); combine(attributes[key]!,into: &hash)
        }
        func outlines(_ node: PDFOutline,depth: Int) {
            guard depth < 64 else { return }
            hash.combine(node.label); hash.combine(node.numberOfChildren); hash.combine(node.isOpen)
            if let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination {
                hash.combine(destination.page.map(ObjectIdentifier.init)); hash.combine(destination.point.x)
                hash.combine(destination.point.y); hash.combine(destination.zoom)
            }
            hash.combine(node.action?.type)
            if let action = node.action as? PDFActionURL { hash.combine(action.url?.absoluteString) }
            if let action = node.action as? PDFActionNamed { hash.combine(action.name.rawValue) }
            if let action = node.action as? PDFActionRemoteGoTo {
                hash.combine(action.safeFileURL?.absoluteString); hash.combine(action.pageIndex)
                hash.combine(action.point.x); hash.combine(action.point.y)
            }
            if let action = node.action as? PDFActionResetForm { hash.combine(action.fields); hash.combine(action.fieldsIncludedAreCleared) }
            for index in 0..<node.numberOfChildren { if let child = node.child(at: index) { outlines(child,depth: depth+1) } }
        }
        if let root = document.outlineRoot { outlines(root,depth: 0) }
        return hash.finalize()
    }
}

@MainActor
private enum PDFDocumentSerializer {
    static func save(_ document: PDFDocument,to url: URL) throws {
        try write(try data(document),to: url)
    }
    static func write(_ data: Data,to url: URL) throws {
        if !FileManager.default.isUbiquitousItem(at: url) { try data.write(to: url,options: .atomic); return }
        var coordinationError: NSError?,writeError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url,options: .forReplacing,error: &coordinationError) { target in
            do { try data.write(to: target,options: .atomic) } catch { writeError = error }
        }
        if let error = coordinationError ?? writeError as NSError? { throw error }
    }
    static func data(_ document: PDFDocument,preserveStreams: Bool = false) throws -> Data {
        let trace = ProcessInfo.processInfo.environment["BOTPLUS_TRACE_SERIALIZATION"] == "1"
        let started = Date.timeIntervalSinceReferenceDate
        let direct = preserveStreams
        let bookmarks = PDFBookmarkStore.capture(document),copy = direct ? document : PDFDocument()
        // A document loaded as one complete PDF can preserve its streams while
        // its original page identities/order remain intact. Write only to a new
        // temporary URL. Reassembled page graphs need an independent copy.
        for index in 0..<(direct ? 0 : document.pageCount) {
            guard let original = document.page(at: index),let cloned = original.copy() as? PDFPage else { throw PDFSourceError.page }
            AnnotationMetadata.copy(from: original,to: cloned); copy.insert(cloned,at: copy.pageCount)
        }
        copy.documentAttributes = document.documentAttributes
        if !direct { PDFBookmarkStore.restore(bookmarks,on: copy) }
        AnnotationMetadata.prepareForSave(copy)
        defer { if direct { AnnotationMetadata.removeContainers(copy) } }
        var inkOrigins: [Int:CGPoint] = [:]
        for index in 0..<copy.pageCount {
            guard let page = copy.page(at: index),page.annotations.contains(where: { $0.type == "Ink" }) else { continue }
            let origin = page.bounds(for: .mediaBox).origin; if origin != .zero { inkOrigins[index] = origin }
        }
        let prepared = Date.timeIntervalSinceReferenceDate
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlusSnapshot-"+UUID().uuidString+".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        guard copy.write(to: url,withOptions: [PDFDocumentWriteOption.saveTextFromOCROption:false]) else { throw PDFSourceError.save }
        let written = Date.timeIntervalSinceReferenceDate
        let data = try PDFDocumentExtras.repairWrittenInk(PDFSourceSession.validEmptyPageStreams(Data(contentsOf: url)),originalOrigins: inkOrigins)
        if trace { print(String(format: "PERF serializer copy %.2f ms; write %.2f ms; normalize %.2f ms",(prepared-started)*1000,(written-prepared)*1000,(Date.timeIntervalSinceReferenceDate-written)*1000)); fflush(nil) }
        return data
    }
}

@MainActor
private enum PDFBookmarkStore {
    struct Record {
        let title: String
        let page: Int?
        let point: CGPoint
        let zoom: CGFloat
        let action: PDFAction?
        let children: [Record]
        var isOpen: Bool? = nil
    }
    static func capture(_ document: PDFDocument) -> [Record]? {
        guard let root = document.outlineRoot else { return nil }
        @MainActor func children(_ parent: PDFOutline,depth: Int) -> [Record] {
            guard depth < 64 else { return [] }
            return (0..<parent.numberOfChildren).compactMap { index in
                guard let node = parent.child(at: index) else { return nil }
                let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination
                let candidate = destination?.page.map { document.index(for: $0) }
                let page = candidate.flatMap { $0 >= 0 && $0 < document.pageCount ? $0 : nil }
                return Record(title: node.label ?? "",page: page,point: destination?.point ?? .zero,zoom: destination?.zoom ?? 0,action: page == nil ? node.action?.copy() as? PDFAction : nil,children: children(node,depth: depth+1),isOpen: node.isOpen)
            }
        }
        return children(root,depth: 0)
    }
    static func restore(_ records: [Record]?,on document: PDFDocument) {
        guard let records else { document.outlineRoot = nil; return }
        let root = PDFOutline()
        @MainActor func append(_ records: [Record],to parent: PDFOutline) {
            for record in records {
                let node = PDFOutline(); node.label = record.title
                node.isOpen = record.isOpen ?? false
                if let index = record.page,let page = document.page(at: index) { let destination = PDFDestination(page: page,at: record.point); destination.zoom = record.zoom; node.destination = destination }
                else { node.action = record.action }
                append(record.children,to: node); parent.insertChild(node,at: parent.numberOfChildren)
            }
        }
        append(records,to: root); document.outlineRoot = root
    }
}

@MainActor
private extension DocumentManager {
    func createFromFiles() {
        PDFDialogs.open([.pdf]) { [weak self] urls in
            guard let self else { return }; let document = PDFDocument(); var bookmarks: [PDFBookmarkStore.Record] = []
            for url in urls {
                let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard let source = PDFDocument(url: url),!source.isLocked else { continue }; AnnotationMetadata.restore(source)
                let offset = document.pageCount
                for index in 0..<source.pageCount {
                    if let page = source.page(at: index),let copy = page.copy() as? PDFPage { AnnotationMetadata.copy(from: page,to: copy); document.insert(copy,at: document.pageCount) }
                }
                @MainActor func shifted(_ record: PDFBookmarkStore.Record) -> PDFBookmarkStore.Record {
                    PDFBookmarkStore.Record(title: record.title,page: record.page.map { $0+offset },point: record.point,zoom: record.zoom,action: record.action,children: record.children.map(shifted))
                }
                let children = (PDFBookmarkStore.capture(source) ?? []).map(shifted)
                if offset < document.pageCount { bookmarks.append(PDFBookmarkStore.Record(title: url.lastPathComponent,page: offset,point: CGPoint(x: 0,y: document.page(at: offset)?.bounds(for: .cropBox).maxY ?? 792),zoom: 0,action: nil,children: children)) }
            }
            guard document.pageCount > 0 else { self.say("No readable PDF pages selected.","Не выбраны доступные страницы PDF."); return }
            PDFBookmarkStore.restore(bookmarks,on: document)
            let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf"),document: document); entry.isUntitled = true; self.insertDocument(entry)
        }
    }
}

@MainActor
private struct ThumbnailGestureRegion: NSViewRepresentable {
    @ObservedObject var manager: DocumentManager
    func makeNSView(context: Context) -> ThumbnailGestureView {
        let view = ThumbnailGestureView(frame: .zero); view.manager = manager; return view
    }
    func updateNSView(_ view: ThumbnailGestureView,context: Context) { view.manager = manager }
    static func dismantleNSView(_ view: ThumbnailGestureView,coordinator: ()) { view.stop() }
}

@MainActor
private final class ThumbnailGestureView: NSView {
    weak var manager: DocumentManager?
    private var pendingValue: Double?
    private var scheduled = false
    private var detailWork: DispatchWorkItem?
    private let gestureID = UUID()
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow(); stop(); guard window != nil else { return }
        HoverGestureRouter.shared.register(self)
    }

    func adjust(_ delta: Double) {
        guard delta.isFinite,let manager else { return }
        manager.thumbnailGestureOwner = gestureID
        if !manager.thumbnailGestureActive { manager.thumbnailGestureActive = true }
        detailWork?.cancel()
        let owner = gestureID
        let work = DispatchWorkItem { [weak manager] in
            guard manager?.thumbnailGestureOwner == owner else { return }
            manager?.thumbnailGestureOwner = nil
            if manager?.thumbnailGestureActive == true { manager?.thumbnailGestureActive = false }
        }
        detailWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.18,execute: work)
        pendingValue = Self.zoom((pendingValue ?? manager.thumbnailZoom),delta: delta)
        guard !scheduled else { return }; scheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }
    func flush() {
        scheduled = false
        if let value = pendingValue { pendingValue = nil; manager?.thumbnailZoom = value }
    }
    static func zoom(_ value: Double,delta: Double) -> Double { min(1,max(0,value+delta*0.75)) }
    func stop() {
        HoverGestureRouter.shared.unregister(self)
        pendingValue = nil; scheduled = false
        detailWork?.cancel(); detailWork = nil
        let owner = gestureID
        DispatchQueue.main.async { [weak manager] in
            guard manager?.thumbnailGestureOwner == owner else { return }
            manager?.thumbnailGestureOwner = nil
            if manager?.thumbnailGestureActive == true { manager?.thumbnailGestureActive = false }
        }
    }
}

@MainActor
private final class PDFThumbnailCache {
    static let shared = PDFThumbnailCache()
    private final class Raster {
        let image: NSImage; let resolution: Int
        init(_ image: NSImage,resolution: Int) { self.image = image; self.resolution = resolution }
    }
    private let cache = NSCache<NSString,Raster>()
    private(set) var renderCount = 0
    init() { cache.totalCostLimit = 48*1024*1024; cache.countLimit = 240 }
    func image(page: PDFPage,documentID: UUID,index: Int,revision: Int,width: CGFloat,ratio: CGFloat,interactive: Bool = false) -> NSImage {
        let requestedBucket = min(1280,max(128,Int(ceil(width*2/128))*128))
        let bucket = interactive ? 128 : requestedBucket
        let key = "\(documentID.uuidString)|\(index)|\(revision)" as NSString
        // During a gesture, immediately scale the current raster. Upgrade its
        // detail after the gesture settles, without storing every zoom size.
        if let raster = cache.object(forKey: key),interactive || raster.resolution >= bucket { return raster.image }
        let height = max(1,CGFloat(bucket)*max(0.1,min(12,ratio)))
        let factor = min(1,4096/max(CGFloat(bucket),height))
        let w = max(1,Int(CGFloat(bucket)*factor)),h = max(1,Int(height*factor))
        guard let context = CGContext(data: nil,width: w,height: h,bitsPerComponent: 8,bytesPerRow: w*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage(size: CGSize(width: width,height: width*ratio)) }
        let rect = CGRect(x: 0,y: 0,width: w,height: h)
        context.setFillColor(NSColor.white.cgColor); context.fill(rect)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context,flipped: false)
        context.concatenate(PDFFormattingGeometry.transform(page, box: .cropBox, target: rect))
        if let ref = page.pageRef { context.drawPDFPage(ref) }
        for annotation in page.annotations where annotation.shouldDisplay && !AnnotationMetadata.isContainer(annotation) { annotation.draw(with: .cropBox,in: context) }
        NSGraphicsContext.restoreGraphicsState()
        guard let bitmap = context.makeImage() else { return NSImage(size: rect.size) }
        let image = NSImage(cgImage: bitmap,size: CGSize(width: width,height: width*ratio))
        cache.setObject(Raster(image,resolution: bucket),forKey: key,cost: w*h*4); renderCount += 1; return image
    }
}

@MainActor
private final class HoverGestureRouter {
    static let shared = HoverGestureRouter()
    private final class Entry { weak var view: NSView?; init(_ view: NSView) { self.view = view } }
    private var entries: [Entry] = []
    private var monitor: Any?
    func register(_ view: NSView) {
        entries.removeAll { $0.view == nil || $0.view === view }; entries.append(Entry(view))
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel]) { [weak self] event in
            var handled = false
            MainActor.assumeIsolated { handled = self?.route(event) ?? false }
            return handled ? nil : event
        }
    }
    func unregister(_ view: NSView) {
        entries.removeAll { $0.view == nil || $0.view === view }
        if entries.isEmpty, let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
    // Resolve each event independently; moving the pointer transfers ownership
    // without changing first responder or requiring mouseDown.
    func target(at screen: CGPoint, frontWindow: Int?) -> (NSView, CGPoint)? {
        entries.removeAll { $0.view == nil }
        for entry in entries.reversed() {
            guard let view = entry.view, let point = HoverEventLocation.point(at: screen, in: view, frontWindow: frontWindow) else { continue }
            return (view, point)
        }
        return nil
    }
    @discardableResult
    func zoom(_ delta: CGFloat, at screen: CGPoint, frontWindow: Int?) -> Bool {
        guard delta.isFinite, let (target, point) = target(at: screen, frontWindow: frontWindow) else { return false }
        if let thumbnails = target as? ThumbnailGestureView, thumbnails.manager?.selected != nil {
            thumbnails.adjust(Double(delta)); return true
        }
        if let pdf = target as? PDFViewerView, pdf.document != nil {
            pdf.queueMagnification(delta, at: point); return true
        }
        return false
    }
    private func route(_ event: NSEvent) -> Bool {
        let screen = NSEvent.mouseLocation
        let number = NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0)
        let front = number > 0 ? number : nil
        let zooming = event.type == .magnify || event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command)
        if zooming {
            let delta = event.type == .magnify ? event.magnification : -event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.08)
            return zoom(delta, at: screen, frontWindow: front)
        }
        if let (target, _) = target(at: screen, frontWindow: front), let pdf = target as? PDFViewerView,
           pdf.document != nil, pdf.internalScrollView != nil { pdf.applyScroll(event); return true }
        return false
    }

}

@MainActor
private enum HoverEventLocation {
    static func acceptsWindow(owner: Int, underPointer: Int?, modal: Int?, hasSheet: Bool) -> Bool {
        !hasSheet && (underPointer == nil || underPointer == owner) && (modal == nil || modal == owner)
    }
    static func point(for event: NSEvent, in view: NSView) -> CGPoint? {
        let screen = NSEvent.mouseLocation
        let front = NSWindow.windowNumber(at: screen, belowWindowWithWindowNumber: 0)
        return point(at: screen, in: view, frontWindow: front > 0 ? front : nil)
    }
    static func point(at screen: CGPoint, in view: NSView, frontWindow: Int?) -> CGPoint? {
        guard let window = view.window, window.isVisible, !view.isHiddenOrHasHiddenAncestor,
              acceptsWindow(owner: window.windowNumber, underPointer: frontWindow, modal: NSApp.modalWindow?.windowNumber, hasSheet: window.attachedSheet != nil) else { return nil }
        let inWindow = window.convertPoint(fromScreen: screen)
        let local = view.convert(inWindow, from: nil)
        // PDFKit's visibleRect may describe its scrolling document. Check the
        // viewport bounds and ancestor clipping instead of relying on it.
        guard view.bounds.contains(local) else { return nil }
        var ancestor = view.superview
        while let current = ancestor {
            guard current.bounds.contains(current.convert(inWindow, from: nil)) else { return nil }
            ancestor = current.superview
        }
        return local
    }
}

// MARK: Start screen, recent files, licensing and updates
private final class FileAccessLease {
    private let url: URL
    private let active: Bool
    init(_ url: URL) { self.url = url; active = url.startAccessingSecurityScopedResource() }
    deinit { if active { url.stopAccessingSecurityScopedResource() } }
}
private struct RecentPDF: Codable, Identifiable {
    var id: UUID = UUID()
    var path: String
    var name: String
    var size: Int64
    var openedAt: Date
    var modifiedAt: Date?
    var bookmark: Data?
}

@MainActor
private final class RecentPDFStore: ObservableObject {
    static let shared = RecentPDFStore()
    @Published private(set) var files: [RecentPDF]
    private let defaults: UserDefaults
    private let key = "BotPlusPDFEditor.recentPDFs.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        files = Array(((defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([RecentPDF].self,from: $0) }) ?? []).prefix(10))
    }
    func remember(_ url: URL) {
        let path = url.standardizedFileURL.path
        let old = files.first { $0.path == path }
        let info = try? url.resourceValues(forKeys: [.fileSizeKey,.contentModificationDateKey])
        let bookmark = (try? url.bookmarkData(options: [.withSecurityScope],includingResourceValuesForKeys: nil,relativeTo: nil)) ?? old?.bookmark
        files.removeAll { $0.path == path }
        files.insert(RecentPDF(id: old?.id ?? UUID(),path: path,name: url.lastPathComponent,size: Int64(info?.fileSize ?? 0),openedAt: Date(),modifiedAt: info?.contentModificationDate,bookmark: bookmark),at: 0)
        files = Array(files.prefix(10)); persist()
    }
    func resolve(_ file: RecentPDF) throws -> URL {
        guard let bookmark = file.bookmark else { return URL(fileURLWithPath: file.path) }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark,options: [.withSecurityScope,.withoutUI],relativeTo: nil,bookmarkDataIsStale: &stale)
        if stale { remember(url) }
        return url
    }
    func remove(_ id: UUID) { files.removeAll { $0.id == id }; persist() }
    func clear() { files.removeAll(); persist() }
    private func persist() { if let data = try? JSONEncoder().encode(files) { defaults.set(data,forKey: key) } }
}

private struct RecentPDFList: View {
    @ObservedObject var store: RecentPDFStore
    @ObservedObject var manager: DocumentManager
    var body: some View {
        VStack(alignment: .leading,spacing: 8) {
            HStack {
                Text(manager.language == .ru ? "Последние файлы" : "Recent files").font(.system(size: 14,weight: .semibold))
                Spacer()
                Button(manager.language == .ru ? "Очистить список" : "Clear list") { store.clear() }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
            if store.files.isEmpty {
                Text(manager.language == .ru ? "Здесь появятся последние 10 открытых PDF." : "Your last 10 opened PDFs will appear here.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            ForEach(store.files) { file in
                Button { manager.openRecent(file) } label: {
                    HStack(spacing: 12) {
                        SystemSymbolImage(name: "doc.text").font(.system(size: 22)).foregroundStyle(Palette.accent)
                        VStack(alignment: .leading,spacing: 3) {
                            Text(file.name).font(.system(size: 12,weight: .medium)).lineLimit(1)
                            Text(file.path).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                        }.frame(maxWidth: .infinity,alignment: .leading)
                        VStack(alignment: .trailing,spacing: 3) {
                            Text(ByteCountFormatter.string(fromByteCount: file.size,countStyle: .file)).font(.system(size: 11))
                            Text(file.openedAt,format: .dateTime.day().month().year().hour().minute()).font(.system(size: 10)).foregroundStyle(Palette.muted)
                        }
                    }.padding(10).background(Palette.raised,in: RoundedRectangle(cornerRadius: 5)).contentShape(Rectangle())
                }.buttonStyle(.plain).help((manager.language == .ru ? "Открыт: " : "Opened: ")+file.openedAt.formatted()+"\n"+file.path)
                .contextMenu { Button(manager.language == .ru ? "Убрать из списка" : "Remove from list") { store.remove(file.id) } }
            }
        }.frame(maxWidth: 760).padding(.horizontal,24)
    }
}

private struct LicenseDialog: View {
    @ObservedObject var manager: DocumentManager
    private let terms: String = Bundle.main.url(forResource: "LICENSE",withExtension: nil).flatMap { try? String(contentsOf: $0,encoding: .utf8) } ?? "GNU Affero General Public License v3.0\nhttps://www.gnu.org/licenses/agpl-3.0.html"
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text("BotPlus PDF Editor — AGPL-3.0-only").font(.title3)
            Text(manager.language == .ru ? "Исходный код доступен в репозитории проекта. Уведомления лицензий PDFium и его компонентов поставляются отдельно." : "Source code is available in the project repository. PDFium and its components retain their own license notices.").font(.system(size: 12))
            ScrollView { Text(verbatim: terms).font(.system(size: 11,design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity,alignment: .leading) }.padding(12).background(Palette.workspace)
            HStack {
                Link(manager.language == .ru ? "Исходный код" : "Source code",destination: BotPlusBrand.supportURL)
                Spacer()
                Button(manager.language == .ru ? "Закрыть" : "Close") { manager.isLicensePresented = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(22).frame(width: 700,height: 560).background(Palette.ribbon).foregroundStyle(Palette.text).preferredColorScheme(manager.theme.colorScheme)
    }
}

private struct UpdateDialog: View {
    @ObservedObject var manager: DocumentManager
    @ObservedObject private var updates = AppUpdateController.shared
    private func label(_ en: String,_ ru: String) -> String { manager.language == .ru ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            ScrollView { VStack(alignment: .leading,spacing: 12) {
            Text(label("Updates","Обновления")).font(.title2)
            Text(label("Installed version: ","Установлена версия: ")+updates.installed)
            Toggle(label("Check automatically (every 6 hours)","Проверять автоматически (каждые 6 часов)"),isOn: $updates.automaticChecks)
            Toggle(label("Download and install on quit","Загружать и устанавливать при выходе"),isOn: $updates.automaticInstall)
            Text(label("Updates come from Davud77/BotPlus-PDF-Editor on GitHub. Current releases use ad-hoc signing and are not notarized.","Обновления загружаются из Davud77/BotPlus-PDF-Editor на GitHub. Текущие релизы подписаны ad-hoc и не нотарифицированы.")).font(.caption).foregroundStyle(.secondary)
            Text(label("Installation requires one-time access to the installed app folder. Updates never interrupt editing. Open PDFs are restored from recovery copies on the next launch.","Для установки один раз выберите папку установленного приложения. Обновление не прерывает работу. Открытые PDF восстановятся из резервных копий при следующем запуске.")).font(.caption).foregroundStyle(.secondary)
            if updates.checking { ProgressView(label("Checking GitHub Releases…","Проверка GitHub Releases…")) }
            if let release = updates.release {
                Text((ReleaseUpdate.isNewer(release.tag_name,than: updates.installed) ? label("Available version: ","Доступна версия: ") : label("Latest version: ","Последняя версия: "))+release.tag_name)
                ScrollView { Text(verbatim: release.body ?? "").font(.system(size: 12)).frame(maxWidth: .infinity,alignment: .leading) }.frame(minHeight: 65,maxHeight: 160)
                if let url = release.pageURL { Link(label("Open release","Открыть релиз"),destination: url) }
                if ReleaseUpdate.isNewer(release.tag_name,than: updates.installed) {
                    HStack {
                        if updates.staged == nil {
                            Button(label("Download update","Загрузить обновление")) { updates.download() }.disabled(release.archive == nil || updates.progress != nil || updates.checking)
                        } else {
                            Button(updates.installationArmed ? label("Ready to install on quit","Готово к установке при выходе") : label("Install on quit…","Установить при выходе…")) { updates.selectInstallFolder() }.disabled(updates.installationArmed)
                        }
                        Button(label("Skip version","Пропустить версию")) { updates.skip() }
                        Button(label("Snooze for a month","Не уведомлять месяц")) { updates.snooze() }
                    }
                    if release.archive == nil { Text(label("This release has no installation archive. Open the release to download its DMG.","У этого релиза нет архива автоустановки. DMG можно скачать на странице релиза.")).font(.caption) }
                }
            }
            if let value = updates.progress { HStack { ProgressView(value: value); Button(label("Cancel","Отменить")) { updates.cancel() } } }
            if let date = updates.policy.snoozedUntil { Text(label("Notifications paused until ","Уведомления приостановлены до ")+date.formatted(date: .numeric,time: .omitted)).font(.caption) }
            if let version = updates.policy.skipped { Text(label("Skipped version: ","Пропущена версия: ")+version).font(.caption) }
            if updates.policy.skipped != nil || updates.policy.snoozedUntil != nil { Button(label("Restore notifications","Вернуть уведомления")) { updates.resetSuppression() } }
            if let error = updates.error {
                let variants = error.components(separatedBy: " / ")
                Text(manager.language == .ru ? variants.first ?? error : variants.last ?? error).font(.caption).foregroundStyle(.orange)
            }
            if let path = UserDefaults.standard.string(forKey: "BotPlus.update.previousApp") {
                Button(label("Show previous app in Finder","Показать предыдущую сборку в Finder")) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
            }
            }.frame(maxWidth: .infinity,alignment: .leading) }
            Spacer(minLength: 0)
            HStack {
                Button(label("Check again","Проверить снова")) { updates.check(manual: true) }.disabled(updates.checking || updates.progress != nil)
                if updates.installationArmed { Button(label("Cancel installation","Отменить установку")) { updates.disarm() } }
                Spacer(); Button(label("Close","Закрыть")) { manager.isUpdatePresented = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 740,height: 640).background(Palette.ribbon).foregroundStyle(Palette.text).preferredColorScheme(manager.theme.colorScheme)
    }
}

@MainActor
private extension DocumentManager {
    func openRecent(_ file: RecentPDF) {
        do { openAsync(try recent.resolve(file)) }
        catch { say("Access expired. Use Open PDF to select this file again.","Доступ к файлу истёк. Выберите его снова через «Открыть PDF».") }
    }
    func checkUpdates() {
        isUpdatePresented = true
        AppUpdateController.shared.check(manual: true)
    }

}

// MARK: First roadmap operations
enum PDFPageRange {
    static func parse(_ text: String,count: Int) -> [Int]? {
        guard count > 0 else { return nil }
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if input == "all" || input == "все" || input == "*" { return Array(0..<count) }
        let tokens = input.replacingOccurrences(of: "–",with: "-").replacingOccurrences(of: "—",with: "-").replacingOccurrences(of: ";",with: ",").components(separatedBy: ",")
        var result = Set<Int>()
        for token in tokens {
            let bounds = token.trimmingCharacters(in: .whitespaces).components(separatedBy: "-")
            guard bounds.count == 1 || bounds.count == 2,let first = Int(bounds[0].trimmingCharacters(in: .whitespaces)),first > 0,first <= count else { return nil }
            let last: Int
            if bounds.count == 2 { guard let end = Int(bounds[1].trimmingCharacters(in: .whitespaces)),end >= first,end <= count else { return nil }; last = end } else { last = first }
            result.formUnion((first-1)..<last)
        }
        return result.isEmpty ? nil : result.sorted()
    }
}

@MainActor
private enum PDFPageOperations {
    private static let importedOwners = NSMapTable<PDFPage,PDFDocument>.weakToStrongObjects()
    static func crop(_ document: PDFDocument,indices: [Int],left: Double,right: Double,top: Double,bottom: Double) -> Bool {
        let offsets = [left,right,top,bottom]
        guard !indices.isEmpty,offsets.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return false }
        var targets: [(PDFPage,CGRect)] = []
        for index in indices {
            guard let page = document.page(at: index) else { return false }
            let media = page.bounds(for: .mediaBox)
            let box = CGRect(x: media.minX+left,y: media.minY+bottom,width: media.width-left-right,height: media.height-top-bottom)
            guard box.width > 1,box.height > 1 else { return false }; targets.append((page,box))
        }
        for (page,box) in targets { page.setBounds(box,for: .cropBox) }; return true
    }
    static func replace(_ document: PDFDocument,targets: [Int],source: PDFDocument,sources: [Int]) -> Bool {
        guard !targets.isEmpty,targets.count == sources.count else { return false }
        var prepared: [(index: Int,old: PDFPage,copy: PDFPage)] = []
        var imported: [ObjectIdentifier:PDFPage] = [:]
        var replaced: [ObjectIdentifier:PDFPage] = [:]
        for (index,sourceIndex) in zip(targets,sources) {
            guard let old = document.page(at: index),let original = source.page(at: sourceIndex),let copy = original.copy() as? PDFPage else { return false }
            AnnotationMetadata.copy(from: original,to: copy); importedOwners.setObject(source,forKey: copy)
            prepared.append((index,old,copy)); imported[ObjectIdentifier(original)] = copy; replaced[ObjectIdentifier(old)] = copy
        }
        func destination(_ old: PDFDestination,map: [ObjectIdentifier:PDFPage]) -> PDFDestination? {
            guard let page = old.page,let new = map[ObjectIdentifier(page)] else { return nil }
            let next = PDFDestination(page: new,at: old.point); next.zoom = old.zoom; return next
        }
        // Remap imported links before installing pages; omit targets that were
        // not imported rather than retaining a pointer into another document.
        for entry in prepared { for annotation in entry.copy.annotations {
            if let action = annotation.action as? PDFActionGoTo {
                if let next = destination(action.destination,map: imported) { annotation.action = PDFActionGoTo(destination: next) }
                else { annotation.action = nil }
            }
        } }
        for entry in prepared { document.removePage(at: entry.index); document.insert(entry.copy,at: entry.index) }
        func outlines(_ root: PDFOutline) {
            if let old = root.destination,let next = destination(old,map: replaced) { root.destination = next }
            if let action = root.action as? PDFActionGoTo,let next = destination(action.destination,map: replaced) { root.action = PDFActionGoTo(destination: next) }
            for index in 0..<root.numberOfChildren { if let child = root.child(at: index) { outlines(child) } }
        }
        if let root = document.outlineRoot { outlines(root) }
        for index in 0..<document.pageCount { for annotation in document.page(at: index)?.annotations ?? [] {
            if let action = annotation.action as? PDFActionGoTo,let next = destination(action.destination,map: replaced) { annotation.action = PDFActionGoTo(destination: next) }
        } }
        return true
    }
    static func align(_ fields: [PDFAnnotation],mode: Int) {
        guard let anchor = fields.first,fields.count >= 2 else { return }
        let target = anchor.bounds
        for field in fields.dropFirst() {
            var rect = field.bounds
            switch mode {
            case 1: rect.origin.x = target.minX
            case 2: rect.origin.x = target.maxX-rect.width
            case 3: rect.origin.x = target.midX-rect.width/2
            case 4: rect.origin.y = target.maxY-rect.height
            case 5: rect.origin.y = target.minY
            case 6: rect.origin.y = target.midY-rect.height/2
            default: return
            }
            field.bounds = rect
        }
    }
}

@MainActor
private final class FieldAlignmentSelection: ObservableObject {
    @Published var indices = Set<Int>()
    @Published var mode = 1
}

private struct FieldAlignmentDialog: View {
    let fields: [PDFAnnotation]
    let russian: Bool
    let commit: ([Int],Int) -> Void
    let close: () -> Void
    @StateObject private var selection = FieldAlignmentSelection()
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(russian ? "Выравнивание полей текущей страницы" : "Align fields on current page").font(.title3)
            Text(russian ? "Опорное поле — первое выбранное в списке. Направления заданы в координатах PDF." : "The first selected field is the anchor. Directions use PDF page coordinates.").font(.system(size: 11)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(fields.indices,id: \.self) { index in
                        Toggle((fields[index].fieldName ?? "Field")+" #\(index+1)",isOn: Binding(get: { selection.indices.contains(index) },set: { if $0 { selection.indices.insert(index) } else { selection.indices.remove(index) } }))
                    }
                }.frame(maxWidth: .infinity,alignment: .leading)
            }
            Picker(russian ? "Выравнивание" : "Alignment",selection: $selection.mode) {
                Text(russian ? "Слева" : "Left").tag(1); Text(russian ? "Справа" : "Right").tag(2); Text(russian ? "По центру X" : "Center X").tag(3)
                Text(russian ? "Сверху" : "Top").tag(4); Text(russian ? "Снизу" : "Bottom").tag(5); Text(russian ? "По центру Y" : "Center Y").tag(6)
            }
            HStack {
                Button(russian ? "Выбрать все" : "Select all") { selection.indices = Set(fields.indices) }
                Spacer()
                Button(russian ? "Отмена" : "Cancel") { close() }
                Button(russian ? "Применить" : "Apply") { commit(selection.indices.sorted(),selection.mode); close() }.disabled(selection.indices.count < 2)
            }
        }.padding(20).frame(width: 490,height: 420)
    }
}

@MainActor
private final class ToolDialogPool: NSObject,NSWindowDelegate {
    static let shared = ToolDialogPool()
    private var windows: [NSWindow] = []
    func show<Content: View>(_ title: String,content: (@escaping () -> Void) -> Content) {
        let panel = NSPanel(contentRect: CGRect(x: 0,y: 0,width: 500,height: 440),styleMask: [.titled,.closable,.resizable],backing: .buffered,defer: false)
        panel.title = title; panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.contentView = NSHostingView(rootView: content { [weak panel] in DispatchQueue.main.async { panel?.close() } })
        windows.append(panel); panel.center(); panel.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        DispatchQueue.main.async { [weak self] in self?.windows.removeAll { $0 === window } }
    }
}

@MainActor
private extension PDFViewer.Coordinator {
    func replacePages(item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.pdf]) { [weak self,weak view] urls in
            guard let self,let view,let url = urls.first else { return }
            let lease = FileAccessLease(url)
            guard let document = PDFDocument(url: url),document.pageCount > 0 else { self.manager.say("Cannot open source PDF.","Не удалось открыть исходный PDF."); return }
            AnnotationMetadata.restore(document)
            PDFDialogs.prompt(self.manager.language == .ru ? "Замена страниц: старые аннотации заменяются; ссылки на неимпортированные страницы источника удаляются" : "Replace pages: old annotations are replaced; source links outside the imported range are removed",fields: [("Target pages / Заменить страницы",String(item.pageIndex+1)),("Source pages / Взять страницы","1")]) { [weak self,weak view] values in
                _ = lease
                guard let self,let view,view.document === item.document else { return }
                guard let targets = PDFPageRange.parse(values[0],count: item.pageCount),let sources = PDFPageRange.parse(values[1],count: document.pageCount),targets.count == sources.count else { self.manager.say("Select equal page counts in both PDFs.","Выберите одинаковое число страниц в обоих PDF."); return }
                self.manager.recordUndo(item,group: "replacePages")
                guard PDFPageOperations.replace(item.document,targets: targets,source: document,sources: sources) else { self.manager.say("Page replacement failed.","Не удалось заменить страницы."); return }
                self.reload(view,document: item,pageIndex: targets[0]); self.manager.send(.refresh)
            }
        }
    }
    func alignFields(item: PDFDocumentItem,view: PDFViewerView) {
        guard let page = view.currentPage else { return }
        let fields = page.annotations.filter { $0.type == "Widget" }
        guard fields.count >= 2 else { manager.say("At least two form fields are required on the page.","На странице должно быть не меньше двух полей формы."); return }
        let expectedDocument = item.document
        ToolDialogPool.shared.show(manager.language == .ru ? "Выравнивание полей" : "Align fields") { close in
            FieldAlignmentDialog(fields: fields,russian: manager.language == .ru,commit: { [weak self,weak view] indices,mode in
                guard let self,let view,item.document === expectedDocument,view.document === expectedDocument else { return }
                self.manager.recordUndo(item,group: "alignFields"); PDFPageOperations.align(indices.map { fields[$0] },mode: mode)
                view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
            },close: close)
        }
    }
    func emailPDF(item: PDFDocumentItem,view: PDFViewerView,currentPage: Bool) {
        do {
            let export = PDFDocument()
            let indices = currentPage ? [item.pageIndex] : Array(0..<item.pageCount)
            for index in indices { if let source = item.document.page(at: index),let copy = source.copy() as? PDFPage { AnnotationMetadata.copy(from: source,to: copy); export.insert(copy,at: export.pageCount) } }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlus-Mail-"+UUID().uuidString,isDirectory: true)
            try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(currentPage ? "Page-\(item.pageIndex+1).pdf" : item.filename)
            if currentPage { try PDFDocumentSerializer.save(export,to: url) }
            else { try PDFDocumentSerializer.write(try manager.serializedData(item),to: url) }
            guard let service = NSSharingService(named: .composeEmail),service.canPerform(withItems: [url]) else {
                // A picker supports the installed mail/share extensions without
                // sending anything automatically or requiring an account here.
                let picker = NSSharingServicePicker(items: [url]); picker.show(relativeTo: CGRect(x: view.bounds.midX,y: view.bounds.midY,width: 1,height: 1),of: view,preferredEdge: .minY); return
            }
            service.perform(withItems: [url])
        } catch { manager.say("Could not prepare a PDF attachment.","Не удалось подготовить PDF-вложение.") }
    }
}

// MARK: Page formatting and independent image export
@MainActor
private extension PDFViewer.Coordinator {
    func showFormatting(_ id: String, item: PDFDocumentItem, view: PDFViewerView) {
        guard let kind = PDFFormattingKind(rawValue: id), finishSourceEditor(), manager.operationTask == nil else { return }
        let document = item.document
        let request = PDFFormattingRequest(kind: kind, document: document, pageIndex: item.pageIndex,
            filename: item.filename, russian: manager.language == .ru,
            isOwned: { AnnotationMetadata.isContainer($0) || AnnotationMetadata.decoration(of: $0) == kind.rawValue },
            apply: { [weak self, weak view, weak item] options, remove in
                guard let self, let view, let item, item.document === document, self.manager.selected?.id == item.id else {
                    return "The document changed / Документ изменился"
                }
                return self.applyFormatting(kind, options: options, remove: remove, item: item, view: view)
            })
        DispatchQueue.main.async { [weak self] in self?.manager.formattingRequest = request }
    }
    func applyFormatting(_ kind: PDFFormattingKind, options: PDFFormattingOptions, remove: Bool,
                         item: PDFDocumentItem, view: PDFViewerView) -> String? {
        let russian = manager.language == .ru
        func error(_ en: String, _ ru: String) -> String { russian ? ru : en }
        guard manager.operationTask == nil else { return error("Another operation is running.", "Дождитесь текущей операции.") }
        guard let indices = PDFPageRange.parse(options.range, count: item.pageCount) else {
            return error("Invalid page range.", "Некорректный диапазон страниц.")
        }
        if kind == .images {
            guard item.document.allowsCopying else { return error("PDF does not permit copying.", "PDF запрещает копирование.") }
            for index in indices {
                guard let page = item.document.page(at: index) else { return error("Page unavailable.", "Страница недоступна.") }
                let (width, height) = PDFImageExporter.dimensions(page, dpi: options.dpi)
                guard width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000 else {
                    return error("Image exceeds 40 MP. Reduce DPI.", "Изображение превышает 40 Мп. Уменьшите DPI.")
                }
            }
            DispatchQueue.main.async { [weak self] in self?.chooseImageExport(item: item, indices: indices, options: options) }
            return nil
        }
        guard item.document.allowsDocumentChanges else { return error("PDF does not permit document changes.", "PDF запрещает изменение документа.") }
        if kind == .margins {
            let offsets = [options.left, options.right, options.top, options.bottom]
            guard offsets.allSatisfy({ $0.isFinite && $0 >= 0 }), indices.allSatisfy({ index in
                guard let page = item.document.page(at: index) else { return false }
                let media = page.bounds(for: .mediaBox)
                return media.width - options.left - options.right > 1 && media.height - options.top - options.bottom > 1
            }) else { return error("Margins exceed page dimensions.", "Отступы превышают размеры страницы.") }
            manager.recordUndo(item, group: "pageMargins")
            _ = PDFPageOperations.crop(item.document, indices: indices, left: options.left, right: options.right, top: options.top, bottom: options.bottom)
            reload(view, document: item, pageIndex: item.pageIndex); manager.send(.refresh)
            return nil
        }
        guard options.opacity.isFinite, (0...1).contains(options.opacity) else { return error("Invalid opacity.", "Некорректная непрозрачность.") }
        if kind == .watermark {
            guard options.angle.isFinite,abs(options.angle) <= 360,options.fontSize.isFinite,(4...200).contains(options.fontSize) else { return error("Invalid angle or font size.","Проверьте угол и размер шрифта.") }
            do {
                let layer = try PDFWatermarkLayer.data(document: item.document,indices: indices,options: options,filename: item.filename,russian: russian)
                let output = try PDFDocumentExtras.overlay(sourceData(item),layer: layer,indices: indices,markName: "BotPlusWatermark_v2",remove: remove)
                try installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil)
                item.enableStreamPreservation()
                for index in indices { if let page = item.document.page(at: index) { for annotation in page.annotations where AnnotationMetadata.decoration(of: annotation) == "watermark" { page.removeAnnotation(annotation) } } }
                manager.send(.refresh); return nil
            } catch let failure { return failure.localizedDescription }
        }
        if kind == .background {
            guard options.tileWidth.isFinite,(1...14400).contains(options.tileWidth) else { return error("Invalid tile width.","Проверьте ширину плитки.") }
            let document = item.document, stamp = PDFDocumentState.stamp(document)
            let color = PDFColorComponents(options.color, opacity: options.opacity)
            let operationID = UUID()
            manager.activeOperationID = operationID
            manager.operationProgress = 0
            manager.operationTitle = kind.title(russian: russian)
            manager.operationTask = Task { @MainActor [weak self, weak view] in
                guard let self else { return }
                defer { self.manager.operationTask = nil; self.manager.operationProgress = nil; self.manager.activeOperationID = nil }
                do {
                    let data = try self.sourceData(item)
                    let progressOwner = self.manager
                    let result = try await PDFPageBackgroundEngine.change(data: data, indices: indices, color: color,
                        image: options.image, placement: options.backgroundMode,tileWidth: options.tileWidth, remove: remove) { [weak progressOwner] value in
                            if progressOwner?.activeOperationID == operationID { progressOwner?.operationProgress = value }
                        }
                    try Task.checkCancellation()
                    guard let view, self.manager.selected?.id == item.id, item.document === document,
                          PDFDocumentState.stamp(document) == stamp else {
                        self.manager.say("Document changed during the operation. Changes were not applied.", "Документ изменился во время операции. Результат не применён."); return
                    }
                    try self.installSourceData(result, item: item, index: item.pageIndex, view: view, bounds: nil)
                } catch is CancellationError { }
                catch { self.sourceError(error) }
            }
            return nil
        }
        guard item.document.allowsCommenting else { return error("PDF does not permit annotations.", "PDF запрещает аннотации.") }
        guard remove || (options.fontSize.isFinite && (4...200).contains(options.fontSize)
                          && options.batesStart >= 0 && options.batesStart <= 1_000_000_000
                          && (1...12).contains(options.batesDigits)) else {
            return error("Font size: 4–200 pt; Bates start: 0–1000000000; digits: 1–12.", "Размер шрифта: 4–200 pt; начало Бейтса: 0–1000000000; цифр: 1–12.")
        }
        if kind == .header && !remove {
            guard indices.allSatisfy({ index in item.document.page(at: index).map { PDFDecorationEngine.validHeader(options,box: $0.bounds(for: .cropBox)) } ?? false }) else { return error("Header/footer insets and text rows must fit every selected page.","Отступы и строки колонтитулов должны помещаться на каждой выбранной странице.") }
        }
        manager.recordUndo(item, group: "decoration-" + kind.rawValue)
        for (sequence, index) in indices.enumerated() {
            guard let page = item.document.page(at: index) else { continue }
            for old in page.annotations where AnnotationMetadata.decoration(of: old) == kind.rawValue { page.removeAnnotation(old) }
            if !remove {
                for annotation in PDFDecorationEngine.annotations(kind: kind, options: options, box: page.bounds(for: .cropBox),
                    page: index, count: item.pageCount, filename: item.filename, sequence: sequence, russian: russian) {
                    AnnotationMetadata.setOpacity(options.opacity, on: annotation)
                    AnnotationMetadata.setDecoration(kind.rawValue, on: annotation)
                    page.addAnnotation(annotation)
                }
            }
        }
        view.setNeedsDisplay(view.bounds); manager.send(.refresh)
        return nil
    }
    func chooseImageExport(item: PDFDocumentItem, indices: [Int], options: PDFFormattingOptions) {
        guard manager.operationTask == nil else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let destination = panel.url else { return }
            DispatchQueue.main.async {
                guard self.manager.operationTask == nil else { return }
                let lease = FileAccessLease(destination)
                let basename = URL(fileURLWithPath: item.filename).deletingPathExtension().lastPathComponent
                let folder = destination.appendingPathComponent(basename + "-images-" + String(UUID().uuidString.prefix(8)), isDirectory: true)
                let exportOptions = PDFImageExportOptions(indices: indices, format: options.format, dpi: options.dpi,
                    transparent: options.transparent && options.format != .jpeg, quality: options.jpegQuality)
                let operationID = UUID()
                self.manager.activeOperationID = operationID
                self.manager.operationTitle = self.manager.language == .ru ? "Экспорт изображений" : "Export images"
                self.manager.operationProgress = 0
                let owner = self
                self.manager.operationTask = Task { @MainActor [weak owner] in
                    guard let self = owner else { return }
                    defer { _ = lease; self.manager.operationTask = nil; self.manager.operationProgress = nil; self.manager.activeOperationID = nil }
                    do {
                        let data = try self.manager.serializedData(item)
                        let manager = self.manager
                        let worker = Task.detached(priority: .userInitiated) {
                            try PDFImageExporter.export(data: data, to: folder, options: exportOptions) { [weak manager] value in
                                Task { @MainActor in
                                    if manager?.activeOperationID == operationID { manager?.operationProgress = value }
                                }
                            }
                        }
                        let count = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                        self.manager.say("Exported \(count) images to:\n\(folder.path)", "Экспортировано изображений: \(count)\n\(folder.path)")
                    } catch is CancellationError { }
                    catch PDFImageExportError.tooLarge { self.manager.say("Image exceeds 40 MP. Reduce DPI.", "Изображение превышает 40 Мп. Уменьшите DPI.") }
                    catch { self.manager.say("Image export failed. Existing files are intact.", "Ошибка экспорта изображений. Существующие файлы сохранены.") }
                }
            }
        }
    }
}

// MARK: Reusable graphic signatures, initials and stamps
@MainActor
private extension PDFViewer.Coordinator {
    func showGraphicMark(_ kind: String, item: PDFDocumentItem, view: PDFViewerView) {
        guard let page = view.currentPage, item.document.allowsDocumentChanges else { return }
        let document = item.document, index = document.index(for: page)
        let request = PDFGraphicMarkRequest(kind: kind, russian: manager.language == .ru, filename: item.filename, page: index) { [weak self, weak view] image in
            guard let self, let view, self.manager.selected === item, item.document === document, view.document === document,
                  let page = document.page(at: index), document.allowsDocumentChanges else {
                return "Document changed. / Документ изменился."
            }
            let crop = page.bounds(for: .cropBox)
            let width = min(240, crop.width*0.7), height = min(crop.height*0.7, width*CGFloat(image.height)/CGFloat(image.width))
            let bounds = CGRect(x: crop.midX-width/2, y: crop.midY-height/2, width: width, height: height)
            do {
                let data = try PDFSourceSession.insertingImage(data: self.sourceData(item), pageIndex: index, image: image, bounds: bounds)
                try self.installSourceData(data, item: item, index: index, view: view, bounds: nil)
                self.manager.tool = .editContent
                if let changedPage = item.document.page(at: index), let inserted = try self.contentSession(item: item, index: index).objects.last(where: { $0.kind == "image" }) {
                    self.activateContent(inserted, page: changedPage, item: item, index: index, view: view)
                }
                self.manager.panels.select(.properties); self.refreshContentOutlines(view)
                return nil
            } catch { return error.localizedDescription }
        }
        DispatchQueue.main.async { [weak self] in self?.manager.graphicMarkRequest = request }
    }
}

// MARK: View history without PDF serialization
@MainActor
private final class PDFNavigationHistory {
    struct Location {
        let page: Int
        let point: CGPoint
        let zoom: CGFloat
        let layout: PageLayout
        let padding: NSEdgeInsets
        var outerInsets = NSEdgeInsets(top: 0,left: 0,bottom: 0,right: 0)
        func matches(_ other: Location) -> Bool {
            page == other.page && layout == other.layout && abs(zoom-other.zoom) < 0.001 && hypot(point.x-other.point.x,point.y-other.point.y) < 2/max(0.05,zoom)
        }
    }
    private var locations: [Location] = []
    private var cursor = -1
    var canBack: Bool { cursor > 0 }
    var canForward: Bool { cursor >= 0 && cursor+1 < locations.count }
    var current: Location? { locations.indices.contains(cursor) ? locations[cursor] : nil }
    @discardableResult func record(_ value: Location) -> Bool {
        guard value.zoom.isFinite, value.point.x.isFinite, value.point.y.isFinite else { return false }
        if let current, current.matches(value) { return false }
        if cursor+1 < locations.count { locations.removeSubrange((cursor+1)..<locations.count) }
        locations.append(value)
        if locations.count > 150 { locations.removeFirst(locations.count-150) }
        cursor = locations.count-1; return true
    }
    func move(_ offset: Int) -> Location? {
        guard offset == -1 || offset == 1 else { return nil }
        let next = cursor+offset; guard locations.indices.contains(next) else { return nil }
        cursor = next; return locations[next]
    }
    func updateCurrent(_ value: Location) { if locations.indices.contains(cursor) { locations[cursor] = value } }
    func reset() { locations = []; cursor = -1 }
}

@MainActor
private extension PDFViewer.Coordinator {
    func navigationLocation(_ view: PDFViewerView, item: PDFDocumentItem) -> PDFNavigationHistory.Location? {
        guard view.document === item.document, !view.bounds.isEmpty, let page = view.currentPage else { return nil }
        let index = item.document.index(for: page)
        guard index >= 0, index < item.pageCount else { return nil }
        let point = view.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), to: page)
        return .init(page: index, point: point, zoom: view.scaleFactor, layout: manager.layout, padding: view.pageBreakMargins, outerInsets: view.internalScrollView?.contentInsets ?? NSEdgeInsets(top: 0,left: 0,bottom: 0,right: 0))
    }
    func recordNavigation(_ view: PDFViewerView, item: PDFDocumentItem) {
        guard !navigationRestoring else { return }
        if item.navigationPageCount != item.pageCount { item.navigation.reset(); item.navigationPageCount = item.pageCount }
        if let location = navigationLocation(view, item: item), item.navigation.record(location) { manager.navigationRevision &+= 1 }
    }
    func scheduleNavigation(_ view: PDFViewerView, item: PDFDocumentItem) {
        navigationWork?.cancel(); guard !navigationRestoring else { return }
        let work = DispatchWorkItem { [weak self, weak view, weak item] in
            guard let self, let view, let item, self.manager.selected === item else { return }
            self.recordNavigation(view, item: item)
        }
        navigationWork = work; DispatchQueue.main.asyncAfter(deadline: .now()+0.3, execute: work)
    }
    func restoreNavigation(_ offset: Int, view: PDFViewerView, item: PDFDocumentItem) {
        guard finishSourceEditor() else { return }
        navigationWork?.cancel(); navigationWork = nil
        recordNavigation(view, item: item)
        guard let location = item.navigation.move(offset), location.page < item.pageCount else { return }
        navigationRestoring = true; navigationGeneration &+= 1
        let generation = navigationGeneration
        applyNavigation(location, view: view, item: item); manager.navigationRevision &+= 1
        DispatchQueue.main.asyncAfter(deadline: .now()+0.05) { [weak self, weak view, weak item] in
            guard let self, self.navigationGeneration == generation else { return }
            self.navigationRestoring = false
            guard let view, let item, self.manager.selected === item else { return }
            if let actual = self.navigationLocation(view, item: item) { item.navigation.updateCurrent(actual) }
            self.scheduleViewportSync(for: view)
        }
    }
    func applyNavigation(_ location: PDFNavigationHistory.Location, view: PDFViewerView, item: PDFDocumentItem) {
        guard let page = item.document.page(at: location.page) else { return }
        manager.layout = location.layout
        view.displayMode = location.layout.pdfMode; view.displaysAsBook = location.layout == .spread
        view.autoScales = false; view.scaleFactor = PDFZoomLimits.clamp(location.zoom)
        let gap = view.configuredPageMargin
        view.pageBreakMargins = NSEdgeInsets(top: gap,left: gap,bottom: gap,right: gap)
        if let scroll = view.internalScrollView { scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = location.outerInsets }
        view.go(to: page); view.layoutDocumentView(); view.layoutSubtreeIfNeeded()
        if let scroll = view.internalScrollView {
            let clip = scroll.contentView
            for _ in 0..<2 {
                let mapped = clip.convert(view.convert(location.point, from: page), from: view)
                let center = clip.convert(CGPoint(x: view.bounds.midX,y: view.bounds.midY), from: view)
                let movement = mapped-center
                let proposed = clip.bounds.offsetBy(dx: movement.x,dy: movement.y)
                clip.setBoundsOrigin(clip.constrainBoundsRect(proposed).origin); scroll.reflectScrolledClipView(clip)
            }
        }
        item.pageIndex = location.page; item.zoom = view.scaleFactor; manager.pageText = String(location.page+1)
        view.refreshOverlay(); view.onViewportChange?()
    }
}

// MARK: Page workflow dialogs and independent export workers
@MainActor
private extension PDFViewer.Coordinator {
    func showPageWorkflow(_ kind: String, item: PDFDocumentItem, view: PDFViewerView) {
        guard manager.operationTask == nil else { return }
        let expected = item.document, count = item.pageCount
        let root = expected.outlineRoot
        let starts = (0..<(root?.numberOfChildren ?? 0)).compactMap { index -> Int? in
            guard let page = root?.child(at: index)?.destination?.page else { return nil }
            let target = expected.index(for: page); return target < count && target >= 0 ? target : nil
        }
        let request = PDFPageWorkflowRequest(kind: kind, russian: manager.language == .ru, count: count, current: item.pageIndex, bookmarkStarts: starts) { [weak self, weak view] options in
            guard let self, let view, self.manager.selected === item, item.document === expected, item.pageCount == count, self.manager.operationTask == nil else { return "Document changed. / Документ изменился." }
            guard let indices = kind == "swap" ? PDFPagePlan.order(options.range,count: count) : PDFPageRange.parse(options.range,count: count) else { return "Invalid page range. / Некорректный диапазон страниц." }
            if kind == "swap" {
                guard indices.count == count, expected.allowsDocumentChanges else { return "Include every page once. / Укажите все страницы ровно один раз." }
                do { _ = try self.manager.serializedData(item) } catch { return error.localizedDescription }
                self.manager.recordUndo(item,group: "reorderPages")
                let pages = (0..<count).compactMap { expected.page(at: $0) }
                let active = view.currentPage
                var positions = Array(0..<count), order = Array(0..<count)
                for (target, original) in indices.enumerated() {
                    let position = positions[original]
                    if position != target {
                        expected.exchangePage(at: position,withPageAt: target)
                        let displaced = order[target]; order.swapAt(position,target); positions[original] = target; positions[displaced] = position
                    }
                }
                item.navigation.reset(); self.manager.navigationRevision &+= 1
                let next = active.map { expected.index(for: $0) } ?? 0
                self.reload(view,document: item,pageIndex: min(count-1,max(0,next)))
                withExtendedLifetime(pages) {}; self.manager.send(.refresh); return nil
            }
            guard expected.allowsCopying else { return "Copying is not allowed. / Копирование запрещено." }
            if kind == "split" && options.splitMode == 1 && starts.isEmpty { return "No top-level page bookmarks. / Нет закладок первого уровня с целями страниц." }
            let groups = kind == "split" ? PDFPagePlan.groups(indices: indices,size: options.groupSize,starts: options.splitMode == 1 ? starts : nil) : [indices]
            guard !groups.isEmpty else { return "Invalid split options. / Некорректные параметры разделения." }
            self.manager.afterPageWorkflowDismiss = { [weak self] in self?.choosePageExport(item: item, expected: expected, groups: groups, split: kind == "split") }
            return nil
        }
        DispatchQueue.main.async { [weak self] in self?.manager.pageWorkflowRequest = request }
    }
    func choosePageExport(item: PDFDocumentItem, expected: PDFDocument, groups: [[Int]], split: Bool) {
        guard item.document === expected, manager.operationTask == nil else { return }
        if split {
            let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
            panel.begin { [weak self] response in
                guard response == .OK, let self, let url = panel.url else { return }
                let folder = url.appendingPathComponent("BotPlus-split-"+String(UUID().uuidString.prefix(8)),isDirectory: true)
                self.runPageExport(item: item,expected: expected,groups: groups,url: folder,scope: url,split: true)
            }
        } else {
            let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Extracted-"+item.filename
            panel.begin { [weak self] response in
                guard response == .OK, let self, let url = panel.url else { return }
                guard item.isUntitled || url.standardizedFileURL != item.url.standardizedFileURL else {
                    self.manager.say("Choose a different file to keep the original PDF.","Выберите другой файл, чтобы сохранить исходный PDF."); return
                }
                self.runPageExport(item: item,expected: expected,groups: groups,url: url,scope: url,split: false)
            }
        }
    }
    func runPageExport(item: PDFDocumentItem, expected: PDFDocument, groups: [[Int]], url: URL, scope: URL, split: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, item.document === expected, self.manager.operationTask == nil, expected.allowsCopying else { return }
            let lease = FileAccessLease(scope), id = UUID(), manager = self.manager
            manager.activeOperationID = id; manager.operationProgress = 0
            manager.operationTitle = manager.language == .ru ? "Экспорт страниц" : "Export pages"
            manager.operationTask = Task { @MainActor [manager] in
                defer { _ = lease; manager.activeOperationID = nil; manager.operationProgress = nil; manager.operationTask = nil }
                do {
                    let data = try manager.serializedData(item)
                    let worker = Task.detached(priority: .userInitiated) {
                        try PDFSubsetBuilder.export(data: data,groups: groups,to: url,split: split) { value in
                            Task { @MainActor [weak manager] in if manager?.activeOperationID == id { manager?.operationProgress = value } }
                        }
                    }
                    let count = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                    manager.say("Exported \(count) PDF file(s).", "Экспортировано PDF-файлов: \(count).")
                } catch is CancellationError { }
                catch { manager.say("Page export failed. Existing files are intact.","Не удалось экспортировать страницы. Существующие файлы сохранены.") }
            }
        }
    }
    func copySnapshot(page: PDFPage, region: CGRect) {
        guard let item = manager.selected, item.document.allowsCopying, manager.operationTask == nil else { return }
        let index = item.document.index(for: page); guard index >= 0, index < item.pageCount else { return }
        let manager = manager, id = UUID(), dpi = manager.snapshotDPI, transparent = manager.snapshotTransparent, clipboardRevision = NSPasteboard.general.changeCount
        manager.activeOperationID = id; manager.operationProgress = 0.1; manager.operationTitle = manager.language == .ru ? "Снимок области" : "Snapshot"
        manager.operationTask = Task { @MainActor in
            defer { manager.activeOperationID = nil; manager.operationProgress = nil; manager.operationTask = nil }
            do {
                let data = try manager.serializedData(item)
                let worker = Task.detached(priority: .userInitiated) { try PDFSnapshotRenderer.render(data: data,index: index,region: region,dpi: dpi,transparent: transparent) }
                let png = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                let preview = try await Task.detached(priority: .utility) { try PDFSnapshotRenderer.preview(png) }.value
                try Task.checkCancellation()
                manager.snapshotPNG = png; manager.snapshotImage = NSImage(data: preview)
                manager.snapshotSource = (item.id,index,region)
                // A newer Copy action wins if rendering takes time.
                guard NSPasteboard.general.changeCount == clipboardRevision else { return }
                NSPasteboard.general.clearContents(); NSPasteboard.general.setData(png,forType: .png); manager.refreshClipboard()
            } catch is CancellationError { }
            catch { manager.say("Cannot capture the region. Reduce DPI or select a smaller area.","Не удалось создать снимок. Уменьшите DPI или выделенную область.") }
        }
    }
}

// MARK: Workspace feature integration (implementation stage)
@MainActor private extension PDFViewer.Coordinator {
    func performAdditionalFeature(_ id: String,on view: PDFViewerView,item: PDFDocumentItem) -> Bool {
        if id == "annotationScale" { showAnnotationScale(item: item,view: view); return true }
        if id == "annotationRotate" { showAnnotationRotation(item: item,view: view); return true }
        if id == "annotationFlip:horizontal" || id == "annotationFlip:vertical" {
            if !view.flipAnnotationSelection(horizontal: id.hasSuffix("horizontal")) { manager.say("Select unlocked Line, Ink, Square or Circle annotations without measurements. The result must fit the page.","Выберите незаблокированные Line, Ink, Square или Circle без измерений. Результат должен помещаться на странице.") }; return true
        }
        if id == "annotationRotate:left" || id == "annotationRotate:right" {
            if !view.rotateAnnotationSelection(clockwise: id.hasSuffix("right")) { manager.say("Select unlocked Line, Ink, Square or Circle annotations without measurements. The rotated group must fit the page.","Выберите незаблокированные Line, Ink, Square или Circle без измерений. После поворота группа должна помещаться на странице.") }; return true
        }
        if id.hasPrefix("annotationBatch") {
            let parts = id.split(separator: ":"); guard parts.count == 2,["annotationBatchLock","annotationBatchVisible","annotationBatchPrint"].contains(String(parts[0])),let value = Int(parts[1]),[0,1].contains(value),let first = view.selectedAnnotations.first,let page = first.page,page.document === item.document else { return true }
            let selection = view.selectedAnnotations
            let permissions = selection.allSatisfy { $0.page === page && (["Widget","Link"].contains($0.type ?? "") ? item.document.allowsDocumentChanges : item.document.allowsCommenting) }
            guard permissions,parts[0] == "annotationBatchLock" || view.canModifyAnnotationSelection else { return true }
            manager.recordUndo(item,group: "annotationBatchFlags-"+UUID().uuidString)
            for annotation in selection {
                switch parts[0] { case "annotationBatchLock": AnnotationMetadata.setLocked(value == 1,on: annotation); case "annotationBatchVisible": annotation.shouldDisplay = value == 1; case "annotationBatchPrint": annotation.shouldPrint = value == 1; default: break }
            }
            view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
        }
        if id == "selectAllAnnotations" {
            if let page = view.currentPage { manager.tool = .selectComments; view.selectAnnotations(page.annotations.filter { $0.shouldDisplay && $0.type != "Widget" && $0.type != "Popup" && !AnnotationMetadata.isContainer($0) }) }; return true
        }
        if id == "manageLayerPresets" { showLayerPresetEditor(item: item,view: view); return true }
        if id == "layerOrderEditor" { showLayerOrderEditor(item: item,view: view); return true }
        if id == "layerRadioEditor" { showLayerRadioEditor(item: item,view: view); return true }
        if id == "layerStateEditor" { showLayerStateEditor(item: item,view: view); return true }
        if id == "xObjectConditionEditor" { showXObjectConditionEditor(item: item,view: view); return true }
        if id == "formResourceTransform" { showFormResourceTransform(item: item,view: view); return true }
        if id.hasPrefix("measurementAxis:"),let axis = EngineeringDistanceAxis(rawValue: String(id.dropFirst("measurementAxis:".count))),let ink = view.selectedAnnotation {
            if axis == .custom { showMeasurementDirection(ink,item: item,view: view); return true }
            if !setMeasurementAxis(ink,axis: axis,item: item,view: view) { manager.say("Check measurement parts, locks and page bounds.","Проверьте состав измерения, блокировки и границы страницы.") }; return true
        }
        if id == "membershipBindingEditor" { showMembershipBindingEditor(item: item,view: view); return true }
        if id == "membershipEditor" { showMembershipEditor(item: item,view: view); return true }
        if id == "layersRefresh" || id.hasPrefix("layerToggle:") || id.hasPrefix("layerLock:") || id.hasPrefix("layerPreset:") { layerCommand(id,item: item,view: view); return true }
        if id.hasPrefix("layerPolicy:") { showLayerPolicy(id,item: item,view: view); return true }
        if id.hasPrefix("annotationSelect:") {
            let parts = id.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,let page = item.document.page(at: parts[0]),page.annotations.indices.contains(parts[1]) {
                view.go(to: page); view.selectAnnotation(page.annotations[parts[1]]); manager.panels.select(.properties); manager.refreshPresentation()
            }; return true
        }
        if id.hasPrefix("pages-") { performPageBatch(id,on: view,item: item); return true }
        if id.hasPrefix("attachment") { attachmentCommand(id,on: view,item: item); return true }
        switch id {
        case "namedDestinations": showNamedDestinations(item: item,view: view)
        case "formOrder": showFormOrder(item: item,view: view)
        case "tabTraversal": showTabTraversal(item: item,view: view)
        case "formValues": showFormValues(item: item,view: view)
        case "formRule": showFormRule(item: item)
        case "validateForm": validateForm(item: item)
        case "annotationVertices": showAnnotationVertices(item: item,view: view)
        case "bookmarkNamed","bookmarkDestination": namedBookmarks(item: item,view: view,convertToNames: id == "bookmarkNamed")
        case "bookmarkFromPageText","bookmarkFromTOC": showHeadingBookmarks(item: item,view: view,fromTOC: id == "bookmarkFromTOC")
        case "check","order","alt": showStructure(item: item,view: view)
        case "word","excel","powerpoint": showOfficeExport(item: item,format: id)
        case "compare": showComparison(item: item)
        case "colors","enhance": showRasterWorkflow(item: item,view: view,enhancement: id == "enhance")
        case "ocr": showOCR(item: item,view: view)
        case "protect","password": showSecurity(item: item)
        case "exportXFDF": exportXFDF(item: item,comments: false)
        case "importXFDF": importXFDF(item: item,view: view,comments: false)
        case "importFDF": importFDF(item: item,view: view)
        case "exportFDF": exportFDF(item: item)
        case "exportCommentsXFDF": exportXFDF(item: item,comments: true)
        case "importCommentsFDF": importCommentsFDF(item: item,view: view)
        case "exportCommentsFDF": exportCommentsFDF(item: item)
        case "importCommentsXFDF": importXFDF(item: item,view: view,comments: true)
        case "measureRefresh": view.updateEngineeringMeasurement(); manager.send(.refresh)
        case "distance": manager.tool = .distance; manager.panels.select(.properties); manager.refreshPresentation()
        case "perimeter": manager.tool = .perimeter; manager.panels.select(.properties); manager.refreshPresentation()
        case "area": manager.tool = .area; manager.panels.select(.properties); manager.refreshPresentation()
        case "scale": manager.tool = .calibration; manager.panels.select(.properties); manager.refreshPresentation()
        case "measurementScale": showEngineeringScale(item: item,view: view)
        case "measurementTransform": showEngineeringTransform(item: item,view: view)
        case "measurementLabel": if let ink = view.selectedAnnotation { showMeasurementLabel(ink,item: item,view: view) }
        case "measurementTransfer": showEngineeringTransfer(item: item,view: view)
        case "measurementCopyDocument": showEngineeringDocumentCopy(item: item,view: view)
        case "crop","resize": showGeometry(crop: id == "crop",item: item,view: view)
        case "spell": showSpelling(item: item,view: view)
        case "bookmarkJSON": exportBookmarkTree(item)
        case "bookmarkFromFile": importBookmarkTree(item,view: view)
        case "bookmarkHTML": exportBookmarkHTML(item)
        case "snapshotRegion": showSnapshotRegion(item: item)
        case "snapshotAgain": if let source = manager.snapshotSource,source.id == item.id,let page = item.document.page(at: source.page) { copySnapshot(page: page,region: source.region) }
        case "snapshotObject":
            if let annotation = view.selectedAnnotation,let page = annotation.page { copySnapshot(page: page,region: annotation.bounds) }
            else if let selected = view.contentSelection { copySnapshot(page: selected.page,region: selected.object.bounds) }
        case "snapshotPrint":
            guard let png = manager.snapshotPNG,let image = NSImage(data: png),let page = PDFPage(image: image) else { return true }
            let document = PDFDocument(); document.insert(page,at: 0)
            showAdvancedPrint(document: document,current: 0,selected: [0])
        default: return false
        }
        return true
    }
    func attachmentCommand(_ id: String,on view: PDFViewerView,item: PDFDocumentItem) {
        do {
            let data = try manager.serializedData(item)
            if id == "attachmentRefresh" { manager.attachments = try PDFDocumentExtras.attachments(data); manager.attachmentError = nil; return }
            if id == "attachmentAdd" {
                guard item.document.allowsDocumentChanges else { return }
                PDFDialogs.open([.data]) { [weak self,weak view] urls in
                    guard let self,let view,item.document === view.document,let url = urls.first else { return }
                    let lease = FileAccessLease(url); defer { _ = lease }
                    do {
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 256*1024*1024 else { throw PDFSourceError.content }
                        let bytes = try PDFDocumentExtras.changeAttachment(self.manager.serializedData(item),name: url.lastPathComponent,file: Data(contentsOf: url))
                        try self.installSourceData(bytes,item: item,index: item.pageIndex,view: view,bounds: nil)
                        item.enableStreamPreservation(); self.manager.attachments = try PDFDocumentExtras.attachments(bytes)
                    } catch { self.manager.say("Cannot add attachment.","Не удалось добавить вложение.") }
                }
            } else if id.hasPrefix("attachmentDelete:"),let index = Int(id.split(separator: ":").last ?? ""),item.document.allowsDocumentChanges {
                let bytes = try PDFDocumentExtras.changeAttachment(data,delete: index)
                try installSourceData(bytes,item: item,index: item.pageIndex,view: view,bounds: nil); item.enableStreamPreservation()
                manager.attachments = try PDFDocumentExtras.attachments(bytes)
            } else if (id.hasPrefix("attachmentExtract:") || id.hasPrefix("attachmentOpen:")),let index = Int(id.split(separator: ":").last ?? ""),item.document.allowsCopying {
                let entries = try PDFDocumentExtras.attachments(data),file = try PDFDocumentExtras.attachment(data,index: index)
                let name = entries.first { $0.index == index }?.name ?? "Attachment.bin"
                PDFAttachmentExport.save(file,name: name,openAfterSaving: id.hasPrefix("attachmentOpen:"),russian: manager.language == .ru) { [weak manager] message in
                    if let message { manager?.notice = message }
                }
            }
        } catch { manager.attachmentError = manager.language == .ru ? "Не удалось прочитать дерево вложений PDF." : "Cannot read the PDF attachment tree." }
    }
    func showGeometry(crop: Bool,item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges else { return }
        let document = item.document,selected = item.selectedPages.sorted()
        let request = PageGeometryRequest(document: document,index: item.pageIndex,crop: crop,russian: manager.language == .ru,initialRange: selected.isEmpty ? "all" : "selected") { [weak self,weak view] options in
            guard let self,let view,view.document === document,item.document === document else { return "Документ изменился / Document changed" }
            let indices = options.range == "selected" ? selected : PDFPageRange.parse(options.range,count: item.pageCount) ?? []
            guard !indices.isEmpty else { return "Диапазон: all, selected или 1-3,5 / Use all, selected or 1-3,5" }
            let f = options.unit.factor
            do {
                if crop {
                    let margins = [options.left,options.right,options.top,options.bottom]
                    guard margins.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return "Проверьте отступы / Invalid margins" }
                    var boxes: [(PDFPage,CGRect)] = []
                    for index in indices {
                        guard let page = document.page(at: index) else { throw PDFSourceError.page }
                        let box = page.bounds(for: .mediaBox)
                        let next = CGRect(x: box.minX+options.left*f,y: box.minY+options.bottom*f,width: box.width-(options.left+options.right)*f,height: box.height-(options.top+options.bottom)*f)
                        guard next.width > 1,next.height > 1 else { return "Рамка должна оставаться внутри страницы / Crop must remain inside the page" }; boxes.append((page,next))
                    }
                    self.manager.recordUndo(item,group: "cropPages"); for (page,box) in boxes { page.setBounds(box,for: .cropBox) }
                    self.reload(view,document: item,pageIndex: item.pageIndex); self.manager.send(.refresh)
                } else {
                    let bytes = try PDFDocumentExtras.resize(self.manager.serializedData(item),indices: indices,width: options.width*f,height: options.height*f,scale: options.scaleContent)
                    // Preserve bookmark target coordinates when their pages scale.
                    let records = self.manager.bookmarkNodes().enumerated().compactMap { offset,node -> (Int,Int,CGPoint,CGFloat)? in
                        guard let d = node.destination,let p = d.page else { return nil }; return (offset,document.index(for: p),d.point,d.zoom)
                    }
                    let oldBoxes = Dictionary(uniqueKeysWithValues: indices.compactMap { index in document.page(at: index).map { (index,$0.bounds(for: .mediaBox)) } })
                    try self.installSourceData(bytes,item: item,index: item.pageIndex,view: view,bounds: nil)
                    let newNodes = self.manager.bookmarkNodes()
                    for record in records where record.0 < newNodes.count {
                        guard let page = item.document.page(at: record.1) else { continue }
                        var point = record.2
                        if options.scaleContent,let box = oldBoxes[record.1] { point = CGPoint(x: (point.x-box.minX)*options.width*f/box.width,y: (point.y-box.minY)*options.height*f/box.height) }
                        let d = PDFDestination(page: page,at: point); d.zoom = record.3; newNodes[record.0].destination = d
                    }
                    if options.scaleContent {
                        for pageIndex in 0..<item.pageCount { for annotation in item.document.page(at: pageIndex)?.annotations ?? [] {
                            guard let action = annotation.action as? PDFActionGoTo,let target = action.destination.page else { continue }
                            let index = item.document.index(for: target)
                            guard let box = oldBoxes[index] else { continue }
                            let old = action.destination, point = CGPoint(x: (old.point.x-box.minX)*options.width*f/box.width,y: (old.point.y-box.minY)*options.height*f/box.height)
                            let next = PDFDestination(page: target,at: point); next.zoom = old.zoom; annotation.action = PDFActionGoTo(destination: next)
                        } }
                    }
                    item.enableStreamPreservation(); self.manager.send(.refresh)
                }
                return nil
            } catch { return "Не удалось изменить геометрию страниц / Page geometry change failed" }
        }
        manager.geometryRequest = request
    }
    func showSpelling(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsCopying,manager.operationTask == nil else { return }
        let prefix = manager.language == .ru ? "ru" : "en",checker = NSSpellChecker.shared
        let languages = checker.availableLanguages.sorted()
        guard let language = languages.first(where: { $0 == prefix }) ?? languages.first(where: { $0.replacingOccurrences(of: "-",with: "_").hasPrefix(prefix+"_") }) else {
            manager.say("Install this spelling language in macOS.","Установите словарь этого языка в macOS."); return
        }
        let expected = item.document,operationID = UUID()
        manager.activeOperationID = operationID; manager.operationProgress = 0
        manager.operationTitle = manager.language == .ru ? "Проверка орфографии" : "Checking spelling"
        manager.operationTask = Task { @MainActor [weak self,weak view] in
            guard let self else { return }
            defer { self.manager.activeOperationID = nil; self.manager.operationTask = nil; self.manager.operationProgress = nil }
            let tag = NSSpellChecker.uniqueSpellDocumentTag(); defer { checker.closeSpellDocument(withTag: tag) }
            do {
                await Task.yield()
                let data = try self.manager.serializedData(item)
                var issues: [PDFSpellIssue] = []
                try await PDFSourceTextReader.enumeratePages(data: data) { index,text,count in
                    let string = text as NSString; var position = 0
                    while position < string.length && issues.count < 2000 {
                        let range = checker.checkSpelling(of: text,startingAt: position,language: language,wrap: false,inSpellDocumentWithTag: tag,wordCount: nil)
                        guard range.location != NSNotFound,range.length > 0,range.location >= position,NSMaxRange(range) <= string.length else { break }
                        let word = string.substring(with: range)
                        let guesses = checker.guesses(forWordRange: range,in: text,language: language,inSpellDocumentWithTag: tag) ?? []
                        issues.append(PDFSpellIssue(page: index,word: word,suggestions: Array(guesses.prefix(8)))); position = NSMaxRange(range)
                    }
                    self.manager.operationProgress = Double(index+1)/Double(max(1,count))
                    return issues.count < 2000
                }
                try Task.checkCancellation()
                guard let view,item.document === expected,self.manager.selected?.id == item.id else { return }
                self.manager.spellRequest = PDFSpellRequest(issues: issues,russian: self.manager.language == .ru) { [weak self,weak view] issue in
                    DispatchQueue.main.async {
                        guard let self,let view,item.document === expected,view.document === expected else { return }
                        self.manager.navigate(to: issue.page); self.manager.searchText = issue.word; self.manager.searchRequestID &+= 1
                        self.manager.tool = .editText; self.manager.refreshPresentation()
                    }
                }
            } catch is CancellationError {} catch { self.sourceError(error) }
        }
    }
    func importBookmarkTree(_ item: PDFDocumentItem,view: PDFViewerView) {
        PDFDialogs.open([.plainText,.json]) { [weak self,weak view] urls in
            guard let self,let view,item.document === view.document,let url = urls.first else { return }
            let lease = FileAccessLease(url); defer { _ = lease }
            do {
                let data = try Data(contentsOf: url); guard data.count <= 16*1024*1024 else { throw PDFSourceError.content }
                let records: [PDFBookmarkExchange]
                if url.pathExtension.lowercased() == "json" { records = try JSONDecoder().decode([PDFBookmarkExchange].self,from: data) }
                else {
                    guard let text = String(data: data,encoding: .utf8) ?? String(data: data,encoding: .utf16) ?? String(data: data,encoding: .windowsCP1251) else { throw PDFSourceError.content }
                    records = PDFBookmarkExchange.plain(text,count: item.pageCount)
                }
                guard records.allSatisfy({ $0.valid(pageCount: item.pageCount) }) else { throw PDFSourceError.content }
                try self.applyBookmarkExchange(records,item: item,view: view)
            } catch { self.manager.say("Cannot import bookmark hierarchy.","Не удалось импортировать дерево закладок.") }
        }
    }
    func applyBookmarkExchange(_ records: [PDFBookmarkExchange],item: PDFDocumentItem,view: PDFViewerView) throws {
        guard item.document === view.document,item.document.allowsDocumentChanges,finishSourceEditor() else { throw PDFSourceError.permission }
        let source = try manager.serializedData(item)
        let output = try PDFDocumentExtras.appendBookmarkExchange(source,records: records)
        try installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false)
        item.enableStreamPreservation(); manager.panels.select(.bookmarks); manager.send(.refresh)
    }
    func exportBookmarkTree(_ item: PDFDocumentItem) {
        guard item.document.outlineRoot != nil,finishSourceEditor() else { return }
        do {
            let records = try PDFDocumentExtras.bookmarkExchange(manager.serializedData(item))
            let bytes = try JSONEncoder().encode(records)
            PDFDialogs.save("Bookmarks.json",type: .json) { [weak manager] url in do { try bytes.write(to: url,options: .atomic) } catch { manager?.say("Export failed","Ошибка экспорта") } }
        } catch { manager.say("Some bookmark actions or destinations cannot be exported losslessly.","Некоторые действия или назначения закладок нельзя экспортировать без потери данных.") }
    }
    func exportBookmarkHTML(_ item: PDFDocumentItem) {
        guard let root = item.document.outlineRoot else { return }
        let records = (0..<root.numberOfChildren).compactMap { root.child(at: $0).map { PDFBookmarkExchange.read($0,document: item.document) } }
        let content = "<!doctype html><html><meta charset=\"utf-8\"><title>Bookmarks</title><body><ul>"+records.map { $0.html(pdf: item.url.lastPathComponent.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "document.pdf") }.joined()+"</ul></body></html>"
        PDFDialogs.save("Bookmarks.html",type: .html) { [weak manager] url in do { try content.write(to: url,atomically: true,encoding: .utf8) } catch { manager?.say("Export failed","Ошибка экспорта") } }
    }
    func showAdvancedPrint(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsPrinting else { return }; showAdvancedPrint(document: item.document,current: item.pageIndex,selected: item.selectedPages.sorted())
    }
    func showAdvancedPrint(document: PDFDocument,current: Int,selected: [Int]) {
        manager.printRequest = PDFPrintRequest(document: document,current: current,selected: selected,russian: manager.language == .ru) { [weak self] options,indices in
            self?.manager.afterFeatureDismiss = { [weak self] in self?.runAdvancedPrint(document: document,indices: indices,options: options) }
        }
    }
    func runAdvancedPrint(document: PDFDocument,indices: [Int],options: PDFPrintOptions) {
        let copy = PDFDocument()
        for index in indices { if let original = document.page(at: index),let page = original.copy() as? PDFPage {
            for annotation in page.annotations { annotation.shouldDisplay = options.annotations && annotation.shouldPrint }
            copy.insert(page,at: copy.pageCount)
        } }
        guard copy.pageCount > 0 else { return }
        let size = options.paperSize
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo; info.paperSize = size
        let margin = options.marginPoints
        info.leftMargin = margin; info.rightMargin = margin; info.topMargin = margin; info.bottomMargin = margin
        info.scalingFactor = 1; info.isHorizontallyCentered = false; info.isVerticallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.copies] = options.copies
        info.dictionary()[NSPrintInfo.AttributeKey.mustCollate] = options.collate
        let area = CGSize(width: max(1,size.width-2*margin),height: max(1,size.height-2*margin))
        for index in 0..<copy.pageCount { if let page = copy.page(at: index) {
            let box = page.bounds(for: .cropBox),rotated = page.rotation%180 != 0
            let width = rotated ? box.height : box.width,height = rotated ? box.width : box.height
            _ = width; _ = height // Auto-rotation is computed from the final driver paper size while drawing.
            if options.raster && box.width*box.height*pow(CGFloat(options.dpi)/72,2) > 40_000_000 { manager.say("Reduce print image DPI for this page size.","Уменьшите DPI растровой печати для этого размера страницы."); return }
        } }
        let canvas = PDFPrintCanvas(document: copy,options: options,area: area)
        let operation = NSPrintOperation(view: canvas,printInfo: info); operation.showsPrintPanel = true; operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsCopies,.showsPageRange,.showsPaperSize,.showsOrientation,.showsPreview])
        operation.run()
    }
}

@MainActor private extension DocumentManager {
    var thumbnailPages: [Int] { guard let item = selected else { return [] }; let values = item.selectedPages.filter { $0 >= 0 && $0 < item.pageCount }.sorted(); return values.isEmpty ? [item.pageIndex] : values }
    func canThumbnailCommand(_ action: String, selectionCount: Int? = nil) -> Bool {
        guard let item = selected, item.pageCount > 0 else { return false }
        let document = item.document
        let assembly = document.allowsDocumentAssembly || document.allowsDocumentChanges
        switch action {
        case "selectAll", "selectNone": return true
        case "copy", "extract", "new", "exportImages": return document.allowsCopying
        case "cut": return assembly && document.allowsCopying && (selectionCount ?? thumbnailPages.count) < item.pageCount
        case "delete": return assembly && (selectionCount ?? thumbnailPages.count) < item.pageCount
        case "duplicate": return assembly && document.allowsCopying
        case "paste": return assembly && NSPasteboard.general.availableType(from: [ObjectClipboard.pages, .pdf]) != nil
        case "print": return document.allowsPrinting
        case "rotateLeft", "rotateRight", "crop", "insert", "replace", "blankBefore", "blankAfter": return assembly
        default: return false
        }
    }
    func thumbnailCommand(_ action: String,index: Int) {
        guard let item = selected, canThumbnailCommand(action) else { return }
        if !item.selectedPages.contains(index) { item.selectedPages = [index]; item.thumbnailAnchor = index }
        if action == "insert" || action == "replace" { send(.feature(action)); return }
        if action == "blankBefore" || action == "blankAfter" { send(.blankPageAt(index + (action == "blankAfter" ? 1 : 0))); return }
        send(.feature("pages-"+action))
    }
}
@MainActor private extension PDFViewer.Coordinator {
    func performPageBatch(_ id: String,on view: PDFViewerView,item: PDFDocumentItem) {
        let indices = manager.thumbnailPages, action = String(id.dropFirst(6)), document = item.document
        guard !indices.isEmpty,indices.allSatisfy({ $0 >= 0 && $0 < item.pageCount }) else { return }
        if action.hasPrefix("drop:") {
            let fields = action.split(separator: ":")
            guard fields.count == 5,let sourceID = UUID(uuidString: String(fields[1])),let destination = Int(fields[3]),let revision = Int(fields[4]),(0...item.pageCount).contains(destination),let sourceOwner = DocumentManager.workspaceManagers.first(where: { $0.documents.contains { $0.id == sourceID } }),let source = sourceOwner.documents.first(where: { $0.id == sourceID }),source.store.revision == revision,sourceOwner.finishSourceEditing?() != false,source.store.revision == revision else { return }
            let pages = Array(Set(fields[2].split(separator: ",").compactMap { Int($0) })).sorted()
            guard !pages.isEmpty,pages.allSatisfy({ $0 >= 0 && $0 < source.pageCount }) else { return }
            if source.store === item.store { item.selectedPages = Set(pages); performPageBatch("pages-move:\(destination)",on: view,item: item); return }
            guard source.document.allowsCopying,item.document.allowsDocumentAssembly || item.document.allowsDocumentChanges else { return }
            do {
                let data = try PDFSubsetBuilder.build(source.document,indices: pages),board = NSPasteboard.withUniqueName()
                defer { board.releaseGlobally() }
                board.setData(data,forType: ObjectClipboard.pages); manager.recordUndo(item,group: "pageDrop")
                pastePages(destination,item: item,view: view,board: board); item.selectedPages = Set(destination..<(destination+pages.count))
            } catch { sourceError(error) }; return
        }
        if action == "selectAll" { item.selectedPages = Set(0..<item.pageCount); manager.refreshPresentation(); return }
        if action == "selectNone" { item.selectedPages = []; manager.refreshPresentation(); return }
        if ["copy","cut","extract","new","exportImages"].contains(action) && !document.allowsCopying { return }
        if action == "copy" || action == "cut" || action == "new" {
            do {
                let data = try PDFSubsetBuilder.build(document,indices: indices)
                if action == "new",let copy = PDFDocument(data: data) {
                    AnnotationMetadata.restore(copy)
                    let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent("Selected.pdf"),document: copy,preserveStreams: true); entry.isUntitled = true; entry.recoveredFilename = "Selected-"+item.filename
                    manager.insertDocument(entry); manager.seedSerializedData(data,item: entry); return
                }
                let board = NSPasteboard.general; board.clearContents(); board.setData(data,forType: ObjectClipboard.pages); board.setData(data,forType: .pdf)
                if action == "copy" { return }
            } catch { sourceError(error); return }
        }
        if action == "extract" { choosePageExport(item: item,expected: document,groups: [indices],split: false); return }
        if action == "print" { showAdvancedPrint(document: document,current: item.pageIndex,selected: indices); return }
        if action == "crop" { showGeometry(crop: true,item: item,view: view); return }
        if action == "exportImages" { showFormatting("images",item: item,view: view); return }
        guard document.allowsDocumentAssembly || document.allowsDocumentChanges, finishSourceEditor() else { return }
        if action == "delete" || action == "cut" {
            guard indices.count < item.pageCount else { manager.say("At least one page must remain.","В документе должна остаться хотя бы одна страница."); return }
            let removed = Set(indices.compactMap { document.page(at: $0).map(ObjectIdentifier.init) })
            manager.recordUndo(item,group: "pageBatchDelete")
            for node in manager.bookmarkNodes() { if let page = node.destination?.page,removed.contains(ObjectIdentifier(page)) { node.destination = nil; node.action = nil } }
            for index in 0..<document.pageCount { for link in document.page(at: index)?.annotations ?? [] {
                if let destination = (link.action as? PDFActionGoTo)?.destination,let page = destination.page,removed.contains(ObjectIdentifier(page)) { link.action = nil; link.destination = nil }
            } }
            for index in indices.reversed() { document.removePage(at: index) }
            item.pageIndex = min(indices[0],item.pageCount-1); item.selectedPages = [item.pageIndex]
        } else if action == "duplicate" {
            let copies = indices.compactMap { index -> PDFPage? in guard let source = document.page(at: index),let copy = source.copy() as? PDFPage else { return nil }; AnnotationMetadata.copy(from: source,to: copy); return copy }
            guard copies.count == indices.count else { return }
            manager.recordUndo(item,group: "pageBatchDuplicate")
            let at = indices.last!+1
            for (offset,page) in copies.enumerated() { document.insert(page,at: at+offset) }; item.selectedPages = Set(at..<(at+copies.count)); item.pageIndex = at
        } else if action == "rotateLeft" || action == "rotateRight" {
            manager.recordUndo(item,group: "pageBatchRotate")
            for index in indices { if let page = document.page(at: index) { page.rotation = (page.rotation+(action == "rotateLeft" ? 270 : 90))%360 } }
        } else if action == "paste" {
            manager.recordUndo(item,group: "pageBatchPaste"); pastePages((indices.last ?? item.pageIndex)+1,item: item,view: view); return
        } else if action.hasPrefix("move:"),let destination = Int(action.dropFirst(5)) {
            guard (0...item.pageCount).contains(destination) else { return }
            let selected = Set(indices), remaining = Array(0..<item.pageCount).filter { !selected.contains($0) }
            let offset = min(remaining.count,max(0,destination-indices.filter { $0 < destination }.count))
            var order = remaining; order.insert(contentsOf: indices,at: offset)
            guard order != Array(0..<item.pageCount) else { return }
            manager.recordUndo(item,group: "pageBatchMove")
            var current = Array(0..<item.pageCount), positions = Dictionary(uniqueKeysWithValues: current.enumerated().map { ($0.element,$0.offset) })
            for i in order.indices where current[i] != order[i] {
                guard let j = positions[order[i]] else { return }
                document.exchangePage(at: i,withPageAt: j); current.swapAt(i,j); positions[current[i]] = i; positions[current[j]] = j
            }
            item.selectedPages = Set(offset..<(offset+indices.count)); item.pageIndex = offset
        } else { return }
        item.navigation.reset(); manager.navigationRevision &+= 1
        reload(view,document: item,pageIndex: item.pageIndex); manager.pageText = String(item.pageIndex+1); manager.send(.refresh)
    }
}

private struct WorkspaceSheets: ViewModifier {
    @ObservedObject var manager: DocumentManager
    func body(content: Content) -> some View {
        content
        .sheet(item: $manager.pageWorkflowRequest, onDismiss: { let action = manager.afterPageWorkflowDismiss; manager.afterPageWorkflowDismiss = nil; DispatchQueue.main.async { action?() } }) { PDFPageWorkflowEditor(request: $0) }
        .sheet(item: $manager.graphicMarkRequest) { PDFGraphicMarkEditor(request: $0) }
        .sheet(item: $manager.formattingRequest) { PDFFormattingEditor(request: $0) }
        .sheet(isPresented: $manager.isAboutPresented) { AboutDialog(manager: manager) }
        .sheet(isPresented: $manager.isLicensePresented) { LicenseDialog(manager: manager) }
        .sheet(isPresented: $manager.isUpdatePresented) { UpdateDialog(manager: manager) }
        .sheet(isPresented: $manager.isRibbonCustomizationPresented) {
            RibbonCustomizationView(tabs: RibbonTab.allCases.map { tab in
                RibbonCatalogTab(id: String(describing: tab),title: manager.text(tab.title),groups: RibbonView.groups(for: tab).map { group in
                    RibbonCatalogTab.Group(id: group.id,title: manager.text(group.title),commands: group.commands.map { RibbonCatalogTab.Command(id: $0.id,title: manager.text($0.title)) })
                })
            },russian: manager.language == .ru,close: { manager.isRibbonCustomizationPresented = false }).preferredColorScheme(manager.theme.colorScheme)
        }
        .sheet(item: $manager.regionRequest) { PDFRegionEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.geometryRequest) { PageGeometryEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.printRequest,onDismiss: { let action = manager.afterFeatureDismiss; manager.afterFeatureDismiss = nil; DispatchQueue.main.async { action?() } }) { PDFPrintEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.namedRequest) { PDFNamedEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.layerPresetRequest) { PDFLayerPresetEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.layerStateRequest) { PDFLayerStateEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.layerRadioRequest) { PDFLayerRadioEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.layerOrderRequest) { PDFLayerOrderEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.pathRequest) { PDFPathEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.structureRequest) { PDFStructurePanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.officeRequest,onDismiss: { let action = manager.afterFeatureDismiss; manager.afterFeatureDismiss = nil; DispatchQueue.main.async { action?() } }) { PDFOfficePanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.comparisonRequest) { PDFComparisonPanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.rasterRequest) { PDFRasterEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.scannerRequest) { PDFScannerPanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.headingRequest) { PDFHeadingEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.bookmarkTextRequest) { PDFBookmarkTextEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.bookmarkValidationRequest) { PDFBookmarkValidationPanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.tocRequest) { PDFTOCEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.tabTraversalRequest) { PDFTabTraversalEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.formOrderRequest) { PDFFormOrderEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.engineeringScaleRequest) { EngineeringScaleEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.annotationScaleRequest) { PDFAnnotationScaleEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.annotationRotationRequest) { PDFAnnotationRotationEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.annotationVertexRequest) { PDFAnnotationVertexEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.formValuesRequest) { PDFFormValuesEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.formRuleRequest) { PDFFormRuleEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.formValidationRequest) { PDFFormValidationPanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.ocrReviewRequest) { PDFOCRReviewPanel(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.layerPolicyRequest) { PDFLayerPolicyEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.membershipRequest) { PDFMembershipEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.membershipBindingRequest) { PDFMembershipBindingEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.xObjectConditionRequest) { PDFXObjectConditionEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.formResourceTransformRequest) { PDFFormResourceTransformEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.engineeringTransformRequest) { EngineeringTransformEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.engineeringTransferRequest) { EngineeringTransferEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.engineeringDirectionRequest) { EngineeringDirectionEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.engineeringLabelRequest) { EngineeringLabelEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.securityRequest,onDismiss: { let action = manager.afterFeatureDismiss; manager.afterFeatureDismiss = nil; DispatchQueue.main.async { action?() } }) { PDFSecurityEditor(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(item: $manager.spellRequest) { PDFSpellResults(request: $0).preferredColorScheme(manager.theme.colorScheme) }
        .sheet(isPresented: $manager.isSpacingPresented) {
            VStack(alignment: .leading,spacing: 20) {
                Text(manager.language == .ru ? "Расстояние между страницами" : "Page spacing").font(.title2)
                HStack { Slider(value: $manager.pageGap,in: 0...40,step: 1); Text("\(Int(manager.pageGap)) pt").monospacedDigit().frame(width: 55) }
                Text(manager.language == .ru ? "Сохраняется для новых окон. Масштаб PDF и размеры страниц не изменяются." : "Saved for new windows. PDF zoom and page sizes stay unchanged.").font(.caption)
                HStack { Button(manager.language == .ru ? "Сбросить" : "Reset") { manager.pageGap = 4 }; Spacer(); Button(manager.language == .ru ? "Готово" : "Done") { manager.isSpacingPresented = false } }
            }.padding(24).frame(width: 450).preferredColorScheme(manager.theme.colorScheme)
        }
        .alert(manager.language == .ru ? "Сообщение" : "Notice", isPresented: Binding(
            get: { manager.notice != nil }, set: { if !$0 { manager.notice = nil } }
        )) {
            Button(manager.language == .ru ? "OK" : "OK", role: .cancel) { manager.notice = nil }
        } message: { Text(manager.notice ?? "") }
    }
}

private struct ActivePanelBody: View {
    let panel: WorkspacePanel
    @ObservedObject var manager: DocumentManager
    var body: some View { PanelBody(panel: panel,manager: manager.activePane) }
}
@MainActor private extension DocumentManager {
    static var workspaceManagers: [DocumentManager] {
        let root = (NSApp.delegate as? BotPlusAppDelegate)?.manager
        let values = (root.map { [$0]+($0.splitManager.map { [$0] } ?? []) } ?? []) + PDFWindowPool.shared.allManagers
        var seen = Set<ObjectIdentifier>(); return values.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
    func moveTab(_ id: UUID,before target: UUID) {
        guard let owner = (Self.workspaceManagers+[self]).first(where: { $0.documents.contains { $0.id == id } }),let entry = owner.documents.first(where: { $0.id == id }),owner.finishSourceEditing?() != false,let destination = documents.firstIndex(where: { $0.id == target }) else { return }
        if owner === self {
            guard let from = documents.firstIndex(where: { $0.id == id }),from != destination else { return }
            documents.remove(at: from); documents.insert(entry,at: min(destination-(from < destination ? 1 : 0),documents.count))
        } else {
            owner.documents.removeAll { $0.id == id }; if owner.selectedID == id { owner.selectedID = owner.documents.last?.id; owner.refreshPresentation() }
            documents.insert(entry,at: min(destination,documents.count)); select(id)
        }
    }
    func duplicateView(_ id: UUID,detached: Bool = false) {
        guard finishSourceEditing?() != false,let source = documents.first(where: { $0.id == id }) else { return }
        let item = PDFDocumentItem(shared: source.store,page: source.pageIndex,zoom: source.zoom)
        if detached { PDFWindowPool.shared.open(item: item) } else { insertDocument(item) }
    }
    func detachTab(_ id: UUID) {
        guard finishSourceEditing?() != false,let item = documents.first(where: { $0.id == id }) else { return }
        documents.removeAll { $0.id == id }; if selectedID == id { selectedID = documents.last?.id; refreshPresentation() }
        PDFWindowPool.shared.open(item: item)
    }
    func splitView(_ id: UUID,horizontal: Bool) {
        guard finishSourceEditing?() != false,let source = documents.first(where: { $0.id == id }) else { return }
        if splitManager == nil {
            let child = DocumentManager(recent: recent,panels: panels); child.parentManager = self
            child.language = language; child.theme = theme; child.layout = layout; child.rulersVisible = rulersVisible
            child.insertDocument(PDFDocumentItem(shared: source.store,page: source.pageIndex,zoom: source.zoom))
            splitManager = child
        } else { splitManager?.insertDocument(PDFDocumentItem(shared: source.store,page: source.pageIndex,zoom: source.zoom)) }
        splitHorizontal = horizontal
    }
    func closeSplit() {
        guard let child = splitManager,child.finishSourceEditing?() != false else { return }
        // Keep documents opened only in the second pane when closing the split.
        for item in child.documents where !documents.contains(where: { $0.store === item.store }) { documents.append(item) }
        PDFWindowPool.shared.clearFocus(child); splitFocused = false; splitManager = nil
    }
    func closeTabs(_ ids: [UUID]) {
        guard !isClosingTabs,let window = NSApp.keyWindow,window.attachedSheet == nil else { return }
        let closing = Set(ids),stores = Set(documents.filter { closing.contains($0.id) }.map { $0.store.id })
        // Commit drafts in every view of the affected documents before checking dirtiness.
        let owners = (Self.workspaceManagers+[self]).filter { manager in manager.documents.contains { stores.contains($0.store.id) } }
        guard owners.allSatisfy({ $0.operationTask == nil && $0.loadingFiles == 0 && $0.finishSourceEditing?() != false }) else { return }
        let dirty = documentsRequiringSaveForClosing(ids,managers: Self.workspaceManagers+[self])
        guard !dirty.isEmpty else { for id in ids { close(id) }; return }
        isClosingTabs = true
        let alert = NSAlert(); alert.messageText = language == .ru ? "Сохранить изменения перед закрытием вкладок?" : "Save changes before closing tabs?"
        alert.informativeText = dirty.map(\.filename).joined(separator: "\n")
        alert.addButton(withTitle: language == .ru ? "Сохранить всё и закрыть" : "Save all and close")
        alert.addButton(withTitle: language == .ru ? "Отмена" : "Cancel")
        alert.addButton(withTitle: language == .ru ? "Закрыть без сохранения" : "Close without saving")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        alert.beginSheetModal(for: window) { [weak self] response in
            DispatchQueue.main.async {
                guard let self else { return }
                if response == .alertFirstButtonReturn {
                    self.saveDocumentsForClosing(dirty) { [weak self] saved in
                        guard let self else { return }; self.isClosingTabs = false
                        // Recheck after asynchronous Save As panels: another view may have changed.
                        if saved { self.closeTabs(ids) }
                    }
                } else {
                    self.isClosingTabs = false
                    if response == .alertThirdButtonReturn { for id in ids { self.close(id) } }
                }
            }
        }
    }
    func documentsRequiringSaveForClosing(_ ids: [UUID],managers: [DocumentManager]) -> [PDFDocumentItem] {
        let closing = Set(ids)
        let retained = managers.flatMap(\.documents).filter { !closing.contains($0.id) }
        var seen = Set<UUID>()
        return documents.filter { item in
            closing.contains(item.id) && item.store.hasChanges &&
            !retained.contains(where: { $0.store === item.store }) && seen.insert(item.store.id).inserted
        }
    }
    func saveForClosing(_ item: PDFDocumentItem,to url: URL) throws {
        try PDFDocumentSerializer.write(try serializedData(item),to: url)
        item.url = url; item.isUntitled = false
        item.store.savedRevision = item.store.revision; item.store.savedStamp = PDFDocumentState.stamp(item.document)
        recent.remember(url); refreshPresentation()
    }
    func saveDocumentsForClosing(_ items: [PDFDocumentItem],completion: @escaping (Bool) -> Void) {
        guard let item = items.first else { completion(true); return }
        let remaining = Array(items.dropFirst())
        let save: (URL) -> Void = { [weak self] url in
            guard let self else { completion(false); return }
            let owners = (Self.workspaceManagers+[self]).filter { $0.documents.contains { $0.store === item.store } }
            guard owners.allSatisfy({ $0.operationTask == nil && $0.finishSourceEditing?() != false }) else { completion(false); return }
            do { try self.saveForClosing(item,to: url); self.saveDocumentsForClosing(remaining,completion: completion) }
            catch { self.say("Could not save \(item.filename). Tabs remain open.","Не удалось сохранить \(item.filename). Вкладки остаются открытыми."); completion(false) }
        }
        guard item.isUntitled else { save(item.url); return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = item.filename
        panel.begin { response in
            DispatchQueue.main.async {
                guard response == .OK,let url = panel.url else { completion(false); return }
                save(url)
            }
        }
    }
}

@MainActor private extension PDFViewerView {
    func finishEngineering() {
        guard let draft = engineeringDraft,draft.points.count >= (draft.kind == .area ? 3 : 2) else { return }
        engineeringDraft = nil; refreshOverlay(); onEngineeringCommit?(draft.page,draft.kind,draft.points)
    }
}
@MainActor private extension PDFViewer.Coordinator {
    func showMembershipEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),configuration = try PDFDocumentExtras.membershipConfiguration(data)
            let document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.membershipRequest = PDFMembershipRequest(russian: manager.language == .ru,editable: document.allowsDocumentChanges,configuration: configuration,create: { [weak self,weak view] name,members,policy,expression in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён или запрещает изменения / Document changed or disallows changes" }
                do {
                    let output = try PDFDocumentExtras.createMembership(data,name: name,members: members,policy: policy,expression: expression)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Проверьте уникальное название, группы и выражение / Check unique name, groups and expression" }
            },apply: { [weak self,weak view] entry,members,policy,expression in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён или запрещает изменения / Document changed or disallows changes" }
                do {
                    let output = try PDFDocumentExtras.setMembership(data,entry: entry,members: members,policy: policy,expression: expression)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Проверьте группы, политику и выражение And/Or/Not / Check groups, policy and And/Or/Not expression" }
            })
        } catch { manager.say("Cannot read OCMD conditions in this PDF.","Не удалось прочитать условия OCMD в этом PDF.") }
    }
    func showMembershipBindingEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,item.document.allowsDocumentChanges,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),configuration = try PDFDocumentExtras.membershipConfiguration(data),document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.membershipBindingRequest = PDFMembershipBindingRequest(russian: manager.language == .ru,pageCount: item.pageCount,currentPage: item.pageIndex,selectedPages: item.selectedPages.sorted(),entries: configuration.entries,apply: { [weak self,weak view] condition,pages in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён или запрещает изменения / Document changed or disallows changes" }
                do {
                    let output = try PDFDocumentExtras.bindMembershipPages(data,entry: condition,indices: pages)
                    if output == data { return nil }
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Не удалось назначить условие. Проверьте диапазон, баланс marked content и целостность прежнего назначения / Check page range, marked-content balance and integrity of previous assignment" }
            })
        } catch { manager.say("Cannot read page visibility conditions.","Не удалось прочитать условия видимости страниц.") }
    }
    func showFormResourceTransform(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,item.document.allowsDocumentChanges,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),targets = try PDFDocumentExtras.xObjectConditionTargets(data,pageIndex: item.pageIndex).filter { $0.kind == "Form" },document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.formResourceTransformRequest = PDFFormResourceTransformRequest(russian: manager.language == .ru,pageIndex: item.pageIndex,targets: targets,apply: { [weak self,weak view] target,options in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён или запрещает изменения / Document changed or disallows changes" }
                do {
                    let output = try PDFDocumentExtras.transformFormResource(data,target: target,options: options)
                    if output == data { return nil }
                    try self.installSourceData(output,item: item,index: target.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Проверьте Form, матрицу и актуальность пути ресурсов / Check Form, matrix and resource path" }
            })
        } catch { manager.say("Cannot read Form resources.","Не удалось прочитать ресурсы Form.") }
    }
    func showXObjectConditionEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,item.document.allowsDocumentChanges,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),conditions = try PDFDocumentExtras.membershipConfiguration(data),targets = try PDFDocumentExtras.xObjectConditionTargets(data,pageIndex: item.pageIndex),document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.xObjectConditionRequest = PDFXObjectConditionRequest(russian: manager.language == .ru,pageIndex: item.pageIndex,targets: targets,entries: conditions.entries,apply: { [weak self,weak view] target,condition in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён или запрещает изменения / Document changed or disallows changes" }
                do {
                    let output = try PDFDocumentExtras.bindXObjectCondition(data,target: target,entry: condition)
                    if output == data { return nil }
                    try self.installSourceData(output,item: item,index: target.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Объект изменён или имеет неподдерживаемое условие/структуру / Object changed or has unsupported condition/structure" }
            })
        } catch { manager.say("Cannot read XObject visibility resources.","Не удалось прочитать ресурсы видимости XObject.") }
    }
    func commitEngineering(page: PDFPage,kind: EngineeringKind,points: [CGPoint],view: PDFViewerView) {
        guard let item = manager.selected,item.document === view.document,item.document.allowsCommenting else { return }
        let prefix = "BotPlus engineering calibration v1:"
        if kind == .calibration {
            let length = hypot(points[1].x-points[0].x,points[1].y-points[0].y)
            guard length > 0 else { return }
            PDFDialogs.prompt(manager.language == .ru ? "Калибровка текущей страницы" : "Calibrate current page",fields: [("Реальная длина, мм / Real length, mm","1000")]) { [weak self,weak view] values in
                guard let self,let view,item.document === view.document,let real = Double(values[0].replacingOccurrences(of: ",",with: ".")),real.isFinite,real > 0 else { return }
                let scale = EngineeringScale(millimetersPerPoint: real/length,unit: self.manager.engineeringUnit)
                guard scale.valid,let data = try? JSONEncoder().encode(scale) else { return }
                self.manager.recordUndo(item,group: "engineeringScale")
                for marker in page.annotations where (marker.contents ?? "").hasPrefix(prefix) { page.removeAnnotation(marker) }
                let marker = PDFAnnotation(bounds: CGRect(x: page.bounds(for: .cropBox).minX,y: page.bounds(for: .cropBox).minY,width: 1,height: 1),forType: .freeText,withProperties: nil)
                marker.contents = prefix+data.base64EncodedString(); marker.shouldDisplay = false; marker.shouldPrint = false; page.addAnnotation(marker)
                self.manager.tool = .distance; self.manager.send(.refresh)
            }; return
        }
        var scale = EngineeringScale(unit: manager.engineeringUnit)
        if let marker = page.annotations.first(where: { ($0.contents ?? "").hasPrefix(prefix) }),let text = marker.contents,let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),let saved = try? JSONDecoder().decode(EngineeringScale.self,from: data),saved.valid { scale.millimetersPerPoint = saved.millimetersPerPoint }
        let measurement = EngineeringMeasure(kind: kind,points: points,scale: scale,dimensionOffset: kind == .distance ? 12 : nil)
        guard measurement.value.isFinite else { return }
        manager.recordUndo(item,group: "engineeringMeasure")
        let minX = points.map(\.x).min()!,minY = points.map(\.y).min()!,maxX = points.map(\.x).max()!,maxY = points.map(\.y).max()!
        let bounds = CGRect(x: minX-2,y: minY-2,width: max(4,maxX-minX+4),height: max(4,maxY-minY+4))
        let ink = PDFAnnotation(bounds: bounds,forType: .ink,withProperties: nil),path = NSBezierPath(),group = UUID().uuidString
        for (i,point) in points.enumerated() { let p = CGPoint(x: point.x-bounds.minX,y: point.y-bounds.minY); if i == 0 { path.move(to: p) } else { path.line(to: p) } }
        if kind == .area { path.close() }; ink.add(path); ink.color = view.strokeColor
        let border = PDFBorder(); border.lineWidth = view.strokeWidth; ink.border = border; ink.contents = measurement.label(russian: manager.language == .ru)
        AnnotationMetadata.setGroup(group,on: ink); AnnotationMetadata.setMeasurement(measurement,on: ink); AnnotationMetadata.setOpacity(manager.annotationOpacity,on: ink)
        let label = PDFAnnotation(bounds: CGRect(x: bounds.midX-70,y: bounds.maxY+4,width: 140,height: 24),forType: .freeText,withProperties: nil)
        label.contents = ink.contents; label.font = .systemFont(ofSize: 12); label.fontColor = ink.color; label.color = .clear; label.alignment = .center
        AnnotationMetadata.setGroup(group,on: label); page.addAnnotation(ink); page.addAnnotation(label)
        EngineeringDimensionRenderer.update(annotation: ink,measurement: measurement)
        view.selectAnnotation(ink); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh)
    }
}

@MainActor private enum EngineeringDimensionRenderer {
    static func update(annotation: PDFAnnotation,measurement: EngineeringMeasure) {
        guard let page = annotation.page,let group = AnnotationMetadata.group(of: annotation),measurement.validLabelPlacement else { return }
        for part in page.annotations where AnnotationMetadata.group(of: part) == group && AnnotationMetadata.decoration(of: part) == "engineeringDimension" { page.removeAnnotation(part) }
        func line(_ start: CGPoint,_ end: CGPoint,arrows: Bool) {
            let box = CGRect(x: min(start.x,end.x)-4,y: min(start.y,end.y)-4,width: max(1,abs(end.x-start.x))+8,height: max(1,abs(end.y-start.y))+8)
            let part = PDFAnnotation(bounds: box,forType: .line,withProperties: nil)
            part.startPoint = CGPoint(x: start.x-box.minX,y: start.y-box.minY); part.endPoint = CGPoint(x: end.x-box.minX,y: end.y-box.minY)
            part.color = annotation.color; let border = PDFBorder(); border.lineWidth = max(0.5,annotation.border?.lineWidth ?? 1); part.border = border
            if arrows { part.startLineStyle = .closedArrow; part.endLineStyle = .closedArrow }
            part.shouldDisplay = annotation.shouldDisplay; part.shouldPrint = annotation.shouldPrint
            AnnotationMetadata.setGroup(group,on: part); AnnotationMetadata.setDecoration("engineeringDimension",on: part)
            AnnotationMetadata.setOpacity(Double(AnnotationMetadata.alpha(of: annotation)),on: part)
            AnnotationMetadata.setLocked(AnnotationMetadata.isLocked(annotation),on: part); page.addAnnotation(part)
        }
        if measurement.kind == .perimeter || measurement.kind == .area {
            guard let origin = measurement.contourLeaderMidpoint else { return }
            let anchor: CGPoint
            switch measurement.effectiveLeaderAnchor {
            case .midpoint: anchor = origin
            case .dimensionStart,.measuredStart: anchor = measurement.points.first!
            case .dimensionEnd,.measuredEnd: anchor = measurement.points.last!
            }
            for label in page.annotations where label.type == "FreeText" && AnnotationMetadata.group(of: label) == group {
                let displacement = measurement.labelOffset ?? .zero
                label.bounds = CGRect(x: annotation.bounds.midX-70+displacement.x,y: annotation.bounds.maxY+4+displacement.y,width: 140,height: 24)
                label.contents = annotation.contents
                let route = measurement.labelLeaderPoints(midpoint: origin,labelBounds: label.bounds,anchor: anchor)
                for (start,end) in zip(route,route.dropFirst()) where hypot(end.x-start.x,end.y-start.y) > 0.000001 { line(start,end,arrows: false) }
            }
            return
        }
        guard measurement.kind == .distance,measurement.points.count == 2,let offset = measurement.dimensionOffset,offset.isFinite else { return }
        guard let (baseA,baseB) = measurement.dimensionBaseline else { return }
        let a = measurement.points[0],b = measurement.points[1],length = hypot(baseB.x-baseA.x,baseB.y-baseA.y)
        guard length > 0.000001 else { return }
        let nx = -(baseB.y-baseA.y)/length,ny = (baseB.x-baseA.x)/length
        let p = CGPoint(x: baseA.x+nx*offset,y: baseA.y+ny*offset),q = CGPoint(x: baseB.x+nx*offset,y: baseB.y+ny*offset)
        line(p,q,arrows: true)
        let extensionOffset = offset+(offset >= 0 ? 4 : -4)
        line(a,CGPoint(x: baseA.x+nx*extensionOffset,y: baseA.y+ny*extensionOffset),arrows: false)
        line(b,CGPoint(x: baseB.x+nx*extensionOffset,y: baseB.y+ny*extensionOffset),arrows: false)
        for label in page.annotations where label.type == "FreeText" && AnnotationMetadata.group(of: label) == group {
            let displacement = measurement.labelOffset ?? .zero
            label.bounds = CGRect(x: (p.x+q.x)/2-70+displacement.x,y: (p.y+q.y)/2+4+displacement.y,width: 140,height: 24)
            label.contents = annotation.contents
            let route = measurement.labelLeaderPoints(midpoint: CGPoint(x: (p.x+q.x)/2,y: (p.y+q.y)/2),labelBounds: label.bounds,anchor: measurement.leaderAnchorPoint(dimensionStart: p,dimensionEnd: q))
            for (start,end) in zip(route,route.dropFirst()) where hypot(end.x-start.x,end.y-start.y) > 0.000001 { line(start,end,arrows: false) }
        }
    }
}
@MainActor private extension PDFViewerView {
    func updateEngineeringMeasurement() {
        guard let ink = selectedAnnotation,let page = ink.page,var measure = AnnotationMetadata.measurement(ink),let path = ink.paths?.first else { return }
        var points: [CGPoint] = []
        for index in 0..<path.elementCount {
            var buffer = [NSPoint](repeating: .zero,count: 3)
            let type = buffer.withUnsafeMutableBufferPointer { path.element(at: index,associatedPoints: $0.baseAddress!) }
            if type == .moveTo || type == .lineTo || type == .cubicCurveTo {
                let point = buffer[type == .cubicCurveTo ? 2 : 0]; points.append(CGPoint(x: ink.bounds.minX+point.x,y: ink.bounds.minY+point.y))
            }
        }
        guard points.count >= 2 else { return }; measure.points = points
        AnnotationMetadata.setMeasurement(measure,on: ink)
        let text = measure.label(russian: Locale.current.language.languageCode?.identifier == "ru")
        ink.contents = text
        if let group = AnnotationMetadata.group(of: ink) {
            for label in page.annotations where label !== ink && label.type == "FreeText" && AnnotationMetadata.group(of: label) == group {
                label.contents = text; label.fontColor = ink.color
                label.bounds = CGRect(x: ink.bounds.midX-70,y: ink.bounds.maxY+4,width: 140,height: 24)
            }
        }
        EngineeringDimensionRenderer.update(annotation: ink,measurement: measure)
        refreshOverlay(); setNeedsDisplay(bounds)
    }
}

@MainActor private extension DocumentManager {
    func recordFieldChange() { if let selected { recordUndo(selected,group: "formProperties") } }
}
@MainActor private extension PDFViewer.Coordinator {
    func showSecurity(item: PDFDocumentItem) {
        guard !item.document.isEncrypted || item.document.permissionsStatus == .owner else { manager.say("Open with the owner password to change security.","Для изменения защиты откройте документ с паролем владельца."); return }
        manager.securityRequest = PDFSecurityRequest(russian: manager.language == .ru) { [weak self] options in
            self?.manager.afterFeatureDismiss = { [weak self] in
                guard let self else { return }
                let panel = NSSavePanel(); panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Protected-"+item.filename
                panel.begin { response in
                    guard response == .OK,let url = panel.url else { return }
                    DispatchQueue.main.async {
                        do {
                            guard url.standardizedFileURL != item.url.standardizedFileURL else { throw PDFSourceError.permission }
                            let bytes = try self.manager.serializedData(item)
                            guard let copy = PDFDocument(data: bytes) else { throw PDFSourceError.document }
                            var permissions: UInt = 0
                            if options.printing { permissions |= 3 }; if options.copying { permissions |= 1<<4 }; if options.changes { permissions |= 1<<2 }; if options.assembly { permissions |= 1<<3 }; if options.comments { permissions |= 1<<6 }; if options.forms { permissions |= 1<<7 }; if options.accessibility { permissions |= 1<<5 }
                            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".pdf"); defer { try? FileManager.default.removeItem(at: temp) }
                            guard copy.write(to: temp,withOptions: [.ownerPasswordOption: options.owner,.userPasswordOption: options.user,.accessPermissionsOption: NSNumber(value: permissions),.saveTextFromOCROption: false]),let encrypted = PDFDocument(url: temp),encrypted.isEncrypted,encrypted.unlock(withPassword: options.owner) else { throw PDFSourceError.save }
                            try PDFDocumentSerializer.write(Data(contentsOf: temp),to: url)
                        } catch { self.manager.say("Could not export encrypted PDF; the original is intact.","Не удалось сохранить защищённый PDF. Исходный файл не изменён.") }
                    }
                }
            }
        }
    }
    func exportXFDF(item: PDFDocumentItem,comments: Bool) {
        let data = comments ? PDFXFDF.comments(item.document,include: { !AnnotationMetadata.isContainer($0) },opacity: { Double(AnnotationMetadata.alpha(of: $0)) }) : PDFXFDF.forms(fdfValues(item))
        let panel = NSSavePanel(); panel.nameFieldStringValue = comments ? "Comments.xfdf" : "FormData.xfdf"; panel.allowedContentTypes = [UTType(filenameExtension: "xfdf") ?? .xml]
        panel.begin { [weak manager] response in guard response == .OK,let url = panel.url else { return }; DispatchQueue.main.async { do { try data.write(to: url,options: .atomic) } catch { manager?.say("Export failed","Ошибка экспорта") } } }
    }
    func fdfValues(_ item: PDFDocumentItem) -> [String:PDFFDF.FieldValue] {
        var values: [String:PDFFDF.FieldValue] = [:]
        for index in 0..<item.pageCount { for field in item.document.page(at: index)?.annotations ?? [] where field.type == "Widget" {
            guard let name = field.fieldName else { continue }
            if field.widgetFieldType == .button {
                if field.widgetControlType == .pushButtonControl { continue }
                if field.buttonWidgetState == .onState { values[name] = .name(field.buttonWidgetStateString) }
                else if values[name] == nil { values[name] = .name("Off") }
            } else if let selected = AnnotationMetadata.formSelections(field) ?? (field.value(forAnnotationKey: .widgetValue) as? [String]) { values[name] = .array(selected) }
            else { values[name] = .text(PDFWidgetFactory.stringValue(field) ?? "") }
        } }
        return values
    }
    func exportCommentsFDF(item: PDFDocumentItem) {
        guard item.document.allowsCopying else { return }
        do {
            let xml = PDFXFDF.comments(item.document,include: { !AnnotationMetadata.isContainer($0) },opacity: { Double(AnnotationMetadata.alpha(of: $0)) })
            let entries = try PDFXFDF.read(xml).comments
            guard !entries.isEmpty else { manager.say("No supported comments to export.","Нет поддерживаемых комментариев для экспорта."); return }
            let data = try PDFFDF.writeComments(entries)
            PDFDialogs.save("Comments.fdf",type: UTType(filenameExtension: "fdf") ?? .data) { [weak manager] url in
                do { try data.write(to: url,options: .atomic) } catch { manager?.say("Export failed","Ошибка экспорта") }
            }
        } catch { manager.say("Cannot export these comments as FDF.","Не удалось экспортировать эти комментарии в FDF.") }
    }
    @discardableResult func applyExchangedComments(_ entries: [PDFXFDF.Comment],item: PDFDocumentItem,view: PDFViewerView) -> Bool {
        guard view.document === item.document,!entries.isEmpty,entries.count <= 50000 else { return false }
        var plans: [(PDFPage,PDFAnnotation)] = []
        for entry in entries {
            guard let (index,annotation) = PDFXFDF.annotation(entry),let page = item.document.page(at: index),annotation.type == "Link" ? item.document.allowsDocumentChanges : item.document.allowsCommenting else { return false }
            plans.append((page,annotation))
        }
        guard manager.snapshot(item) != nil else { return false }
        manager.recordUndo(item,group: "importComments-"+UUID().uuidString)
        for (page,annotation) in plans {
            page.addAnnotation(annotation)
            AnnotationMetadata.setOpacity(Double((annotation.type == "FreeText" ? annotation.fontColor ?? .black : annotation.color).alphaComponent),on: annotation)
        }
        view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
    }
    func importCommentsFDF(item: PDFDocumentItem,view: PDFViewerView) {
        let document = item.document,stamp = PDFDocumentState.stamp(document)
        PDFDialogs.open([UTType(filenameExtension: "fdf") ?? .data]) { [weak self,weak view] urls in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,let url = urls.first else { return }
            let lease = FileAccessLease(url); defer { _ = lease }
            do {
                let parsed = try PDFFDF.readComments(Data(contentsOf: url))
                guard self.applyExchangedComments(parsed.entries,item: item,view: view) else { throw PDFSourceError.content }
                if parsed.unsupported > 0 { self.manager.say("Imported supported comments; skipped unsupported types: \(parsed.unsupported).","Поддерживаемые комментарии импортированы; пропущено неподдерживаемых типов: \(parsed.unsupported).") }
            } catch { self.manager.say("Cannot import FDF comments. Check page numbers, geometry, permissions and supported types.","Не удалось импортировать комментарии FDF. Проверьте номера страниц, геометрию, разрешения и поддерживаемые типы.") }
        }
    }
    func exportFDF(item: PDFDocumentItem) {
        guard item.document.allowsCopying else { return }
        let bytes = PDFFDF.write(fdfValues(item))
        PDFDialogs.save("FormData.fdf",type: UTType(filenameExtension: "fdf") ?? .data) { [weak manager] url in
            do { try bytes.write(to: url,options: .atomic) } catch { manager?.say("Export failed","Ошибка экспорта") }
        }
    }
    func applyFDF(_ values: [String:PDFFDF.FieldValue],item: PDFDocumentItem) -> Bool {
        guard item.document.allowsFormFieldEntry,manager.snapshot(item) != nil else { return false }
        let fields = (0..<item.pageCount).flatMap { item.document.page(at: $0)?.annotations ?? [] }.filter { $0.type == "Widget" && !$0.isReadOnly && values[$0.fieldName ?? ""] != nil }
        guard !fields.isEmpty,fields.allSatisfy({ field in
            if case .array? = values[field.fieldName ?? ""] { return field.widgetFieldType == .choice }
            if let rule = AnnotationMetadata.formRule(field),let value = values[field.fieldName ?? ""]?.strings.first {
                let candidate = field.maximumLength > 0 ? String(value.prefix(field.maximumLength)) : value
                return rule.issue(candidate,russian: manager.language == .ru) == nil
            }
            return true
        }) else { return false }
        manager.recordUndo(item,group: "importFDF-"+UUID().uuidString)
        for field in fields {
            guard let value = values[field.fieldName ?? ""] else { continue }
            if field.widgetFieldType == .button {
                if field.widgetControlType != .pushButtonControl { field.buttonWidgetState = value.strings.first == field.buttonWidgetStateString ? .onState : .offState }
            } else if case .array(let selected) = value {
                AnnotationMetadata.setFormSelections(selected,on: field)
            } else {
                let text = value.strings.first ?? ""
                AnnotationMetadata.clearFormSelections(field)
                field.widgetStringValue = field.maximumLength > 0 ? String(text.prefix(field.maximumLength)) : text
            }
        }
        manager.send(.refresh); return true
    }
    func importFDF(item: PDFDocumentItem,view: PDFViewerView) {
        let document = item.document
        PDFDialogs.open([UTType(filenameExtension: "fdf") ?? .data]) { [weak self,weak view] urls in
            guard let self,let view,item.document === document,view.document === document,let url = urls.first else { return }
            let lease = FileAccessLease(url); defer { _ = lease }
            do {
                let values = try PDFFDF.read(Data(contentsOf: url))
                guard self.applyFDF(values,item: item) else { throw PDFSourceError.content }; view.setNeedsDisplay(view.bounds)
            } catch { self.manager.say("Cannot import FDF form data. Check field names and permissions.","Не удалось импортировать FDF. Проверьте имена полей и разрешения.") }
        }
    }
    func importXFDF(item: PDFDocumentItem,view: PDFViewerView,comments: Bool) {
        PDFDialogs.open([UTType(filenameExtension: "xfdf") ?? .xml,.xml]) { [weak self,weak view] urls in
            guard let self,let view,item.document === view.document,let url = urls.first else { return }
            let lease = FileAccessLease(url); defer { _ = lease }
            do {
                let parsed = try PDFXFDF.read(Data(contentsOf: url))
                if !comments {
                    let values = parsed.multipleValues.mapValues { $0.count == 1 ? PDFFDF.FieldValue.text($0[0]) : PDFFDF.FieldValue.array($0) }
                    guard self.applyFDF(values,item: item) else { throw PDFSourceError.content }; view.setNeedsDisplay(view.bounds); return
                }
                guard self.applyExchangedComments(parsed.comments,item: item,view: view) else { throw PDFSourceError.content }
                view.setNeedsDisplay(view.bounds); self.manager.send(.refresh)
            } catch { self.manager.say("Cannot import XFDF.","Не удалось импортировать XFDF.") }
        }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showOCR(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,item.document.allowsCopying,manager.operationTask == nil else { return }
        PDFDialogs.prompt(manager.language == .ru ? "Локальное распознавание текста" : "Local OCR",fields: [("Страницы / Pages","all"),("Языки Vision / Languages","ru-RU,en-US"),("DPI (72–300)","150"),("Пропускать страницы с текстом / Skip text pages: 1/0","1")]) { [weak self,weak view] values in
            guard let self,let view,item.document === view.document,self.manager.operationTask == nil,let indices = PDFPageRange.parse(values[0],count: item.pageCount),let dpi = Int(values[2]),(72...300).contains(dpi) else { return }
            do {
                let data = try self.manager.serializedData(item),document = item.document,stamp = PDFDocumentState.stamp(document)
                let text = values[3] == "1" ? try PDFSourceTextReader.pages(data: data,indices: indices) : indices.map { _ in "" }
                let target = zip(indices,text).filter { $0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.0)
                guard !target.isEmpty else { self.manager.say("Selected pages already contain text.","Выбранные страницы уже содержат текст."); return }
                let languages = values[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                let id = UUID(),manager = self.manager
                manager.activeOperationID = id; manager.operationProgress = 0; manager.operationTitle = "OCR"
                manager.operationTask = Task { @MainActor [weak self,weak view] in
                    defer { manager.activeOperationID = nil; manager.operationProgress = nil; manager.operationTask = nil }
                    do {
                        let worker = Task.detached(priority: .userInitiated) {
                            try PDFOCREngine.recognize(data: data,indices: target,languages: languages,dpi: dpi) { progress in Task { @MainActor in if manager.activeOperationID == id { manager.operationProgress = progress } } }
                        }
                        let result = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                        try Task.checkCancellation()
                        guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp else { throw PDFSourceError.alreadyUsed }
                        guard result.lines > 0 else { manager.say("No text recognized.","Текст не распознан."); return }
                        self.showOCRReview(result: result,source: data,dpi: dpi,item: item,view: view)
                    } catch is CancellationError { }
                    catch { manager.say("OCR unavailable or failed. Check Vision language support and the page size.","OCR недоступен или завершился ошибкой. Проверьте языки Vision и размер страницы.") }
                }
            } catch { self.sourceError(error) }
        }
    }
    func showOCRReview(result: PDFOCRResult,source: Data,dpi: Int,item: PDFDocumentItem,view: PDFViewerView) {
        let document = item.document,stamp = PDFDocumentState.stamp(item.document),manager = self.manager
        manager.ocrReviewRequest = PDFOCRReviewRequest(russian: manager.language == .ru,dpi: dpi,source: source,pages: result.review,apply: { [weak self,weak view,weak manager] pages in
            guard let self,let view,let manager,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges,
                  manager.operationTask == nil,pages.allSatisfy({ (0..<document.pageCount).contains($0.index) }),PDFOCREngine.valid(pages: pages) else { return "Проверьте выбранные строки и рамки; документ не должен изменяться / Check selected lines and boxes; document must be unchanged" }
            let id = UUID(); manager.activeOperationID = id; manager.operationProgress = 0; manager.operationTitle = "OCR"
            manager.operationTask = Task { @MainActor [weak self,weak view] in
                defer { manager.activeOperationID = nil; manager.operationProgress = nil; manager.operationTask = nil }
                do {
                    let worker = Task.detached(priority: .userInitiated) { try PDFOCREngine.render(pages: pages) }
                    let edited = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                    try Task.checkCancellation()
                    guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp else { throw PDFSourceError.alreadyUsed }
                    let bytes = try PDFDocumentExtras.overlay(source,layer: edited.layer,indices: edited.pages)
                    try self.installSourceData(bytes,item: item,index: item.pageIndex,view: view,bounds: nil); item.enableStreamPreservation()
                    manager.say("OCR lines: \(edited.lines)","Строк OCR: \(edited.lines)")
                } catch is CancellationError { }
                catch { manager.say("Could not apply OCR layer. Original PDF is intact.","Не удалось применить слой OCR. Исходный PDF сохранён.") }
            }
            return nil
        })
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showBookmarkTextEditor(item: PDFDocumentItem,operation: PDFBookmarkTextOperation,zoom: Double = 100) {
        guard item.document.allowsDocumentChanges,manager.finishSourceEditing?() != false else { return }
        let document = item.document
        let scope = operation == .sort || operation == .merge ? manager.selectedOutline ?? document.outlineRoot : manager.selectedOutline
        let nodes = scope.map { [$0]+manager.bookmarkNodes($0) } ?? manager.bookmarkNodes()
        let undoGroup = "bookmarkTitles-"+UUID().uuidString
        var previewStamp = PDFDocumentState.stamp(document)
        manager.bookmarkTextRequest = PDFBookmarkTextRequest(russian: manager.language == .ru,operation: operation,initialZoom: zoom,load: { [weak self] options in
            guard item.document === document else { return nil }
            previewStamp = PDFDocumentState.stamp(document)
            return PDFBookmarkTextPlan.make(nodes: nodes,document: document,operation: operation,options: options,russian: self?.manager.language == .ru)
        },apply: { [weak self] changes in
            guard let self,item.document === document,PDFDocumentState.stamp(document) == previewStamp,
                  document.allowsDocumentChanges,changes.allSatisfy({ change in
                      if case .title = change.mutation { return (change.node.label ?? "") == change.before }
                      return true
                  }) else {
                return "Документ изменён. Обновите предпросмотр / Document changed. Update the preview"
            }
            guard !changes.isEmpty else { return nil }
            let current = Set((self.manager.bookmarkNodes()+(document.outlineRoot.map { [$0] } ?? [])).map(ObjectIdentifier.init))
            guard changes.allSatisfy({ current.contains($0.id) }) else { return "Состав закладок изменился. Откройте команду заново / Bookmarks changed. Reopen the command" }
            guard self.manager.snapshot(item) != nil else { return "Не удалось подготовить Undo / Could not prepare Undo" }
            self.manager.recordUndo(item,group: undoGroup)
            PDFBookmarkTextPlan.apply(changes)
            self.manager.send(.refresh); return nil
        })
    }
    func showBookmarkValidation(item: PDFDocumentItem) {
        let document = item.document,russian = manager.language == .ru
        manager.bookmarkValidationRequest = PDFBookmarkValidationRequest(russian: russian,load: {
            guard item.document === document else { return [] }
            return PDFBookmarkValidator.rows(document: document,russian: russian)
        },navigate: { [weak self] row in
            guard let self,item.document === document,let page = row.page,
                  document.page(at: page) === (row.node.destination ?? (row.node.action as? PDFActionGoTo)?.destination)?.page else { return }
            self.manager.select(item.id)
            guard self.manager.selectedID == item.id else { return }
            self.manager.navigate(to: page)
        })
    }
    func showTabTraversal(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,finishSourceEditor() else { return }
        do {
            let document = item.document,index = item.pageIndex,data = try manager.serializedData(item)
            let rule = try PDFDocumentExtras.tabTraversal(data,pageIndex: index),stamp = PDFDocumentState.stamp(document)
            manager.tabTraversalRequest = PDFTabTraversalRequest(russian: manager.language == .ru,current: rule.value,hasStructure: rule.hasStructure,apply: { [weak self,weak view] mode in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён. Откройте команду заново / Document changed. Reopen the command" }
                do {
                    let output = try PDFDocumentExtras.setTabTraversal(data,pageIndex: index,mode: mode)
                    try self.installSourceData(output,item: item,index: index,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Не удалось записать правило Tab / Could not write Tab rule" }
            })
        } catch { sourceError(error) }
    }
    func showFormOrder(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,let page = item.document.page(at: item.pageIndex),manager.finishSourceEditing?() != false else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(item.document),undoGroup = "formOrder-"+UUID().uuidString
        manager.formOrderRequest = PDFFormOrderRequest(russian: manager.language == .ru,page: page,apply: { [weak self,weak view] fields in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges,
                  Set(fields.map(ObjectIdentifier.init)) == Set(page.annotations.filter { $0.type == "Widget" }.map(ObjectIdentifier.init)),self.manager.snapshot(item) != nil else { return "Документ изменён / Document changed" }
            self.manager.recordUndo(item,group: undoGroup)
            guard PDFFormOrder.apply(fields,page: page) else { return "Некорректный порядок полей / Invalid field order" }
            view.setNeedsDisplay(view.bounds); self.manager.send(.refresh); return nil
        })
    }
    func showFormValues(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsFormFieldEntry,let field = manager.selectedAnnotation,field.widgetFieldType == .choice,!field.isReadOnly else { return }
        let choices = field.choices ?? [],exports = field.values ?? choices
        let values = choices.enumerated().map { $0.offset < exports.count ? exports[$0.offset] : $0.element }
        let selected = AnnotationMetadata.formSelections(field) ?? [PDFWidgetFactory.stringValue(field) ?? ""]
        let multiple = ((field.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0)&(1<<21) != 0
        let document = item.document,stamp = PDFDocumentState.stamp(item.document),undoGroup = "formValues-"+UUID().uuidString
        manager.formValuesRequest = PDFFormValuesRequest(russian: manager.language == .ru,multiple: multiple,choices: choices,values: values,selected: selected,apply: { [weak self,weak view] selected in
            guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsFormFieldEntry,!field.isReadOnly,
                  selected.allSatisfy(values.contains),multiple || selected.count <= 1,self.manager.snapshot(item) != nil else { return "Документ изменён или некорректен выбор / Document changed or invalid selection" }
            self.manager.recordUndo(item,group: undoGroup)
            AnnotationMetadata.setFormSelections(selected,on: field); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh); return nil
        })
    }
    func showFormRule(item: PDFDocumentItem) {
        guard item.document.allowsDocumentChanges,let field = manager.selectedAnnotation,field.widgetFieldType == .text else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(item.document),undoGroup = "formRule-"+UUID().uuidString
        manager.formRuleRequest = PDFFormRuleRequest(russian: manager.language == .ru,value: PDFWidgetFactory.stringValue(field) ?? "",initial: AnnotationMetadata.formRule(field) ?? PDFFormRule(),apply: { [weak self] rule in
            guard let self,item.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges,
                  rule.minimum?.isFinite != false,rule.maximum?.isFinite != false,self.manager.snapshot(item) != nil else { return "Документ изменён / Document changed" }
            self.manager.recordUndo(item,group: undoGroup); AnnotationMetadata.setFormRule(rule,on: field); self.manager.send(.refresh); return nil
        })
    }
    func formIssues(item: PDFDocumentItem) -> [PDFFormIssue] {
        let russian = manager.language == .ru
        let all = (0..<item.pageCount).flatMap { index in (item.document.page(at: index)?.annotations ?? []).filter { $0.type == "Widget" }.map { (index,$0) } }
        var issues: [PDFFormIssue] = [],requiredButtons = Set<String>()
        for (page,field) in all {
            let name = field.fieldName ?? "Field",value = PDFWidgetFactory.stringValue(field) ?? "",flags = (field.value(forAnnotationKey: .widgetFieldFlags) as? NSNumber)?.intValue ?? 0
            var message: String?
            if field.widgetFieldType == .button {
                if flags&2 != 0,requiredButtons.insert(name).inserted,!all.contains(where: { $0.1.fieldName == name && $0.1.buttonWidgetState == .onState }) { message = russian ? "Обязательная группа не заполнена" : "Required group is empty" }
            } else {
                if flags&2 != 0,value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { message = russian ? "Обязательное поле не заполнено" : "Required field is empty" }
                else if field.maximumLength > 0,value.count > field.maximumLength { message = russian ? "Превышена максимальная длина" : "Maximum length exceeded" }
                else if let rule = AnnotationMetadata.formRule(field) { message = rule.issue(value,russian: russian) }
                if message == nil,field.widgetFieldType == .choice {
                    let allowed = field.values ?? field.choices ?? [],values = AnnotationMetadata.formSelections(field) ?? [value]
                    if flags&(1<<18) == 0,values.contains(where: { !$0.isEmpty && !allowed.contains($0) }) { message = russian ? "Значение отсутствует в списке вариантов" : "Value is not among field choices" }
                }
            }
            if let message { issues.append(PDFFormIssue(page: page,name: name,message: message)) }
        }
        return issues
    }
    func validateForm(item: PDFDocumentItem) {
        guard item.document.allowsFormFieldEntry || item.document.allowsCopying else { return }
        manager.formValidationRequest = PDFFormValidationRequest(russian: manager.language == .ru,issues: formIssues(item: item))
    }
    private func measurementSelectionCenter(_ inks: [PDFAnnotation]) -> CGPoint? {
        var bounds = CGRect.null,count = 0
        for ink in inks {
            guard let measure = AnnotationMetadata.measurement(ink) else { return nil }; count += measure.points.count
            guard count <= 200000 else { return nil }
            for point in measure.points {
                guard point.x.isFinite,point.y.isFinite,abs(point.x) <= 1_000_000,abs(point.y) <= 1_000_000 else { return nil }
                bounds = bounds.union(CGRect(origin: point,size: .zero))
            }
        }
        guard !bounds.isNull else { return nil }; return CGPoint(x: bounds.midX,y: bounds.midY)
    }
    func showMeasurementLabel(_ ink: PDFAnnotation,item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,view.canModifyAnnotationSelection,let measure = AnnotationMetadata.measurement(ink),[EngineeringKind.distance,.perimeter,.area].contains(measure.kind),(measure.kind != .distance || measure.dimensionOffset != nil) else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),selection = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        let initial = EngineeringLabelOptions(x: Double(measure.labelOffset?.x ?? 0),y: Double(measure.labelOffset?.y ?? 0),leader: measure.labelLeader != false,elbow: measure.leaderElbow != nil,elbowX: Double(measure.leaderElbow?.x ?? 40),elbowY: Double(measure.leaderElbow?.y ?? 20),waypoints: measure.leaderWaypoints,anchor: measure.effectiveLeaderAnchor)
        manager.engineeringLabelRequest = EngineeringLabelRequest(russian: manager.language == .ru,initial: initial,apply: { [weak self,weak view] options in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == selection,let current = AnnotationMetadata.measurement(ink),current.labelOffset == measure.labelOffset,current.labelLeader == measure.labelLeader,current.leaderElbow == measure.leaderElbow,current.leaderWaypoints == measure.leaderWaypoints,current.effectiveLeaderAnchor == measure.effectiveLeaderAnchor else { return "Документ, выбор или подпись изменены / Document, selection or label changed" }
            return self.setMeasurementLabel(ink,options: options,item: item,view: view) ? nil : "Проверьте смещения, размерные линии, блокировки и границы страницы / Check offsets, dimensions, locks and page bounds"
        },contour: measure.kind != .distance)
    }
    @discardableResult func setMeasurementLabel(_ ink: PDFAnnotation,options: EngineeringLabelOptions,item: PDFDocumentItem,view: PDFViewerView) -> Bool {
        guard view.document === item.document,item.document.allowsCommenting,let page = ink.page,page.document === item.document,ink.type == "Ink",let group = AnnotationMetadata.group(of: ink),var measure = AnnotationMetadata.measurement(ink),[EngineeringKind.distance,.perimeter,.area].contains(measure.kind),measure.value.isFinite,measure.value > 0,measure.points.count >= (measure.kind == .area ? 3 : 2),measure.points.count <= 20000,[options.x,options.y,options.elbowX,options.elbowY].allSatisfy({ $0.isFinite && abs($0) <= 10000 }),measure.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return false }
        if measure.kind == .distance {
            guard measure.points.count == 2,measure.dimensionOffset?.isFinite == true,let (a,b) = measure.dimensionBaseline,hypot(b.x-a.x,b.y-a.y) > 0.000001 else { return false }
        } else { guard measure.contourLeaderMidpoint != nil else { return false } }
        let parts = page.annotations.filter { AnnotationMetadata.group(of: $0) == group },labels = parts.filter { $0.type == "FreeText" }
        guard labels.count == 1,let label = labels.first,parts.allSatisfy({ !AnnotationMetadata.isLocked($0) && ($0 === ink || $0 === label || ($0.type == "Line" && AnnotationMetadata.decoration(of: $0) == "engineeringDimension")) }) else { return false }
        guard (options.waypoints?.count ?? 0) <= 32,(options.waypoints ?? []).allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10000 && abs($0.y) <= 10000 }) else { return false }
        let offset = CGPoint(x: options.x,y: options.y),leader: Bool? = offset == .zero ? nil : options.leader
        let requested = options.waypoints ?? (options.elbow ? [CGPoint(x: options.elbowX,y: options.elbowY)] : [])
        let route = offset != .zero && options.leader ? requested : []
        let anchor: EngineeringLeaderAnchor = offset != .zero && options.leader ? options.anchor : .midpoint
        if (measure.labelOffset ?? .zero) == offset && (offset == .zero || (measure.labelLeader != false) == options.leader) && measure.effectiveLeaderWaypoints == route && measure.effectiveLeaderAnchor == anchor { return true }
        measure.labelOffset = offset == .zero ? nil : offset; measure.labelLeader = leader; measure.leaderAnchor = anchor == .midpoint ? nil : anchor
        measure.leaderElbow = route.count == 1 ? route[0] : nil; measure.leaderWaypoints = route.count > 1 ? route : nil
        let probeDocument = PDFDocument(),probePage = PDFPage(); probePage.setBounds(page.bounds(for: .cropBox),for: .mediaBox); probeDocument.insert(probePage,at: 0)
        defer { withExtendedLifetime(probeDocument) {} }
        let probe = PDFAnnotation(bounds: ink.bounds,forType: .ink,withProperties: nil),probeLabel = PDFAnnotation(bounds: label.bounds,forType: .freeText,withProperties: nil)
        probe.color = ink.color; probe.border = ink.border; probe.contents = measure.label(russian: manager.language == .ru)
        AnnotationMetadata.setGroup(group,on: probe); AnnotationMetadata.setGroup(group,on: probeLabel); probePage.addAnnotation(probe); probePage.addAnnotation(probeLabel)
        EngineeringDimensionRenderer.update(annotation: probe,measurement: measure)
        let crop = page.bounds(for: .cropBox).insetBy(dx: -0.001,dy: -0.001)
        guard probePage.annotations.allSatisfy({ crop.contains($0.bounds) }),manager.snapshot(item) != nil else { return false }
        manager.recordUndo(item,group: "measurementLabel-"+UUID().uuidString)
        AnnotationMetadata.setMeasurement(measure,on: ink); ink.contents = probe.contents; label.removeValue(forAnnotationKey: .appearanceDictionary)
        EngineeringDimensionRenderer.update(annotation: ink,measurement: measure)
        view.selectAnnotation(ink); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
    }
    func showMeasurementDirection(_ ink: PDFAnnotation,item: PDFDocumentItem,view: PDFViewerView) {
        guard view.document === item.document,view.canModifyAnnotationSelection,let measure = AnnotationMetadata.measurement(ink),measure.kind == .distance else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),selection = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        manager.engineeringDirectionRequest = EngineeringDirectionRequest(russian: manager.language == .ru,degrees: measure.direction ?? 0,apply: { [weak self,weak view] angle in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == selection,let current = AnnotationMetadata.measurement(ink),current.axis == measure.axis,current.directionDegrees == measure.directionDegrees else { return "Документ, выбор или направление изменены / Document, selection or direction changed" }
            guard angle.isFinite,(-360...360).contains(angle),self.setMeasurementAxis(ink,axis: .custom,item: item,view: view,degrees: angle) else { return "Проверьте угол, блокировки и границы размерных линий / Check angle, locks and dimension bounds" }; return nil
        })
    }
    @discardableResult func setMeasurementAxis(_ ink: PDFAnnotation,axis: EngineeringDistanceAxis,item: PDFDocumentItem,view: PDFViewerView,degrees: Double? = nil) -> Bool {
        guard view.document === item.document,item.document.allowsCommenting,let page = ink.page,page.document === item.document,ink.type == "Ink",let group = AnnotationMetadata.group(of: ink),var measure = AnnotationMetadata.measurement(ink),measure.kind == .distance,measure.points.count == 2,measure.scale.valid,measure.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return false }
        let parts = page.annotations.filter { AnnotationMetadata.group(of: $0) == group },labels = parts.filter { $0.type == "FreeText" }
        guard labels.count == 1,let label = labels.first,parts.allSatisfy({ !AnnotationMetadata.isLocked($0) && ($0 === ink || $0 === label || ($0.type == "Line" && AnnotationMetadata.decoration(of: $0) == "engineeringDimension")) }) else { return false }
        let direction = axis == .custom ? (degrees ?? measure.directionDegrees).flatMap(EngineeringMeasure.normalizedDirection) : nil
        guard axis != .custom || direction != nil else { return false }
        if measure.axis == axis && (axis != .custom || measure.direction == direction) { return true }
        measure.distanceAxis = axis == .aligned ? nil : axis; measure.directionDegrees = direction
        guard measure.value.isFinite else { return false }
        let probeDocument = PDFDocument(),probePage = PDFPage(); probePage.setBounds(page.bounds(for: .cropBox),for: .mediaBox); probeDocument.insert(probePage,at: 0)
        defer { withExtendedLifetime(probeDocument) {} }
        let probe = PDFAnnotation(bounds: ink.bounds,forType: .ink,withProperties: nil),probeLabel = PDFAnnotation(bounds: label.bounds,forType: .freeText,withProperties: nil)
        probe.color = ink.color; probe.border = ink.border; probe.contents = measure.label(russian: manager.language == .ru)
        AnnotationMetadata.setGroup(group,on: probe); AnnotationMetadata.setGroup(group,on: probeLabel); probePage.addAnnotation(probe); probePage.addAnnotation(probeLabel)
        EngineeringDimensionRenderer.update(annotation: probe,measurement: measure)
        let crop = page.bounds(for: .cropBox).insetBy(dx: -0.001,dy: -0.001)
        guard probePage.annotations.allSatisfy({ crop.contains($0.bounds) }),manager.snapshot(item) != nil else { return false }
        manager.recordUndo(item,group: "measurementAxis-"+UUID().uuidString)
        AnnotationMetadata.setMeasurement(measure,on: ink); ink.contents = probe.contents; label.contents = probe.contents
        label.removeValue(forAnnotationKey: .appearanceDictionary); EngineeringDimensionRenderer.update(annotation: ink,measurement: measure)
        view.selectAnnotation(ink); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
    }
    func showEngineeringTransform(item: PDFDocumentItem,view: PDFViewerView) {
        let inks = view.selectedAnnotations.filter { AnnotationMetadata.measurement($0) != nil }
        guard view.document === item.document,view.canModifyAnnotationSelection,!inks.isEmpty,inks.count == view.annotationSelectionUnitCount,let center = measurementSelectionCenter(inks) else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),selection = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        let apply: (EngineeringAffineOptions) -> String? = { [weak self,weak view] options in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == selection else { return "Документ или выбор изменён / Document or selection changed" }
            return self.transformMeasurements(inks,options: options,item: item,view: view) ? nil : "Проверьте матрицу, центр, блокировку, состав измерений и границы страницы / Check matrix, center, locks, measurement parts and page bounds"
        }
        manager.engineeringTransformRequest = EngineeringTransformRequest(russian: manager.language == .ru,count: inks.count,selectionCenter: center,applyAffine: apply,apply: { angle,mx,my,percent,preservingValue in
            var options = EngineeringAffineOptions(); options.degrees = angle; options.mirrorX = mx; options.mirrorY = my; options.scaleX = percent/100; options.scaleY = percent/100; options.preservingValue = preservingValue; return apply(options)
        })
    }
    @discardableResult func transformMeasurement(_ ink: PDFAnnotation,degrees: Double,mirrorX: Bool,mirrorY: Bool,factor: Double = 1,preservingValue: Bool = true,item: PDFDocumentItem,view: PDFViewerView) -> Bool {
        transformMeasurements([ink],degrees: degrees,mirrorX: mirrorX,mirrorY: mirrorY,factor: factor,preservingValue: preservingValue,item: item,view: view)
    }
    @discardableResult func transformMeasurements(_ inks: [PDFAnnotation],degrees: Double,mirrorX: Bool,mirrorY: Bool,factor: Double = 1,preservingValue: Bool = true,item: PDFDocumentItem,view: PDFViewerView) -> Bool {
        var options = EngineeringAffineOptions(); options.degrees = degrees; options.mirrorX = mirrorX; options.mirrorY = mirrorY; options.scaleX = factor; options.scaleY = factor; options.preservingValue = preservingValue
        return transformMeasurements(inks,options: options,item: item,view: view)
    }
    @discardableResult func transformMeasurements(_ inks: [PDFAnnotation],options: EngineeringAffineOptions,item: PDFDocumentItem,view: PDFViewerView) -> Bool {
        guard view.document === item.document,item.document.allowsCommenting,!inks.isEmpty,inks.count <= 10000,let page = inks.first?.page,page.document === item.document,Set(inks.map(ObjectIdentifier.init)).count == inks.count else { return false }
        guard let commonCenter = measurementSelectionCenter(inks) else { return false }
        struct Plan { let ink: PDFAnnotation,label: PDFAnnotation,measure: EngineeringMeasure,box: CGRect,paths: [NSBezierPath],labelBox: CGRect,text: String }
        var plans: [Plan] = [],groups = Set<String>()
        for ink in inks {
            guard ink.type == "Ink",ink.page === page,let group = AnnotationMetadata.group(of: ink),groups.insert(group).inserted,let old = AnnotationMetadata.measurement(ink),let measure = old.transformed(options: options,selectionCenter: commonCenter) else { return false }
            let parts = page.annotations.filter { AnnotationMetadata.group(of: $0) == group },labels = parts.filter { $0.type == "FreeText" }
            guard labels.count == 1,parts.allSatisfy({ !AnnotationMetadata.isLocked($0) && ($0 === ink || $0.type == "FreeText" || ($0.type == "Line" && AnnotationMetadata.decoration(of: $0) == "engineeringDimension")) }),let label = labels.first else { return false }
            if options.isIdentity { continue }
            let probeDocument = PDFDocument(),probePage = PDFPage(); probePage.setBounds(page.bounds(for: .cropBox),for: .mediaBox); probeDocument.insert(probePage,at: 0)
            defer { withExtendedLifetime(probeDocument) {} }
            let probe = PDFAnnotation(bounds: ink.bounds,forType: .ink,withProperties: nil); probe.border = ink.border; probe.color = ink.color; probe.contents = measure.label(russian: manager.language == .ru)
            let path = PDFAnnotationVertexPath(vertices: measure.points.map { PDFAnnotationVertex(x: $0.x,y: $0.y) },closed: measure.kind == .area)
            guard PDFAnnotationVertexGeometry.apply([path],to: probe) else { return false }
            let probeLabel = PDFAnnotation(bounds: CGRect(x: probe.bounds.midX-label.bounds.width/2,y: probe.bounds.maxY+4,width: label.bounds.width,height: label.bounds.height),forType: .freeText,withProperties: nil)
            AnnotationMetadata.setGroup(group,on: probe); AnnotationMetadata.setGroup(group,on: probeLabel)
            probePage.addAnnotation(probe); probePage.addAnnotation(probeLabel); EngineeringDimensionRenderer.update(annotation: probe,measurement: measure)
            let crop = page.bounds(for: .cropBox).insetBy(dx: -0.001,dy: -0.001)
            guard probePage.annotations.allSatisfy({ crop.contains($0.bounds) }),let paths = probe.paths else { return false }
            plans.append(Plan(ink: ink,label: label,measure: measure,box: probe.bounds,paths: paths,labelBox: probeLabel.bounds,text: probe.contents ?? ""))
        }
        guard !plans.isEmpty else { return true }
        guard manager.snapshot(item) != nil else { return false }
        manager.recordUndo(item,group: "measurementTransform-"+UUID().uuidString)
        for plan in plans {
            for path in plan.ink.paths ?? [] { plan.ink.remove(path) }; plan.ink.bounds = plan.box
            for path in plan.paths { plan.ink.add(path) }
            AnnotationMetadata.setMeasurement(plan.measure,on: plan.ink); AnnotationMetadata.setInkCurves(nil,on: plan.ink); plan.ink.contents = plan.text; plan.ink.removeValue(forAnnotationKey: .appearanceDictionary)
            plan.label.bounds = plan.labelBox; plan.label.contents = plan.text; plan.label.removeValue(forAnnotationKey: .appearanceDictionary)
            EngineeringDimensionRenderer.update(annotation: plan.ink,measurement: plan.measure)
        }
        view.selectAnnotations(inks); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); manager.send(.refresh); return true
    }
    func showEngineeringTransfer(item: PDFDocumentItem,view: PDFViewerView) {
        let inks = view.selectedAnnotations.filter { AnnotationMetadata.measurement($0) != nil }
        guard view.document === item.document,item.pageCount > 1,view.canModifyAnnotationSelection,!inks.isEmpty,inks.count == view.annotationSelectionUnitCount,let page = inks.first?.page else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),selection = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        manager.engineeringTransferRequest = EngineeringTransferRequest(russian: manager.language == .ru,count: inks.count,pageCount: item.pageCount,sourcePage: document.index(for: page),apply: { [weak self,weak view] options in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == selection else { return "Документ или выбор изменён / Document or selection changed" }
            return self.transferMeasurements(inks,options: options,item: item,view: view) ? nil : "Проверьте страницу, калибровку, блокировку и границы всех частей измерений / Check destination, calibration, locks and bounds of all measurement parts"
        })
    }
    func showEngineeringDocumentCopy(item: PDFDocumentItem,view: PDFViewerView) {
        let inks = view.selectedAnnotations.filter { AnnotationMetadata.measurement($0) != nil }
        guard view.document === item.document,item.document.allowsCopying,view.canModifyAnnotationSelection,!inks.isEmpty,inks.count == view.annotationSelectionUnitCount else { return }
        var seen = Set<ObjectIdentifier>()
        let targets = manager.documents.filter { $0.document !== item.document && $0.document.allowsCommenting && $0.pageCount > 0 && seen.insert(ObjectIdentifier($0.document)).inserted }
        guard let first = targets.first else { manager.say("Open another PDF that allows comments.","Откройте другой PDF, разрешающий комментарии."); return }
        let source = item.document,stamp = PDFDocumentState.stamp(source),selection = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        let states = targets.map { ($0,$0.document,PDFDocumentState.stamp($0.document)) }
        manager.engineeringTransferRequest = EngineeringTransferRequest(russian: manager.language == .ru,count: inks.count,pageCount: first.pageCount,sourcePage: -1,apply: { _ in "Выберите целевой PDF / Select destination PDF" },destinations: targets.map { EngineeringCopyDestination(id: $0.id,title: $0.filename,pageCount: $0.pageCount,currentPage: $0.pageIndex) },applyToDocument: { [weak self,weak view] id,options in
            guard let self,let view,item.document === source,view.document === source,PDFDocumentState.stamp(source) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == selection,
                  self.manager.documents.contains(where: { $0 === item }),let state = states.first(where: { $0.0.id == id }),self.manager.documents.contains(where: { $0 === state.0 }),state.0.document === state.1,PDFDocumentState.stamp(state.1) == state.2 else { return "Документ, выбор или целевой PDF изменён/закрыт / Document, selection or destination changed/closed" }
            return self.transferMeasurements(inks,options: options,item: item,view: view,destination: state.0) ? nil : "Проверьте разрешения, страницу, калибровку, блокировки и границы измерений / Check permissions, page, calibration, locks and measurement bounds"
        })
    }
    @discardableResult func transferMeasurements(_ inks: [PDFAnnotation],options: EngineeringTransferOptions,item: PDFDocumentItem,view: PDFViewerView,destination: PDFDocumentItem? = nil) -> Bool {
        let output = destination ?? item,copying = destination != nil
        guard !copying || (item.document.allowsCopying && output.document !== item.document && manager.documents.contains(where: { $0 === output })),output.document.allowsCommenting else { return false }
        guard view.document === item.document,item.document.allowsCommenting,!inks.isEmpty,inks.count <= 10000,let source = inks.first?.page,source.document === item.document,
              (0..<output.pageCount).contains(options.pageIndex),let target = output.document.page(at: options.pageIndex),target !== source,
              Set(inks.map(ObjectIdentifier.init)).count == inks.count,measurementSelectionCenter(inks) != nil,
              options.offsetX.isFinite,options.offsetY.isFinite,abs(options.offsetX) <= 1_000_000,abs(options.offsetY) <= 1_000_000 else { return false }
        let targetScale = EngineeringCalibration.read(target)
        guard !options.useTargetScale || targetScale?.valid == true else { return false }
        struct Family { let ink: PDFAnnotation,label: PDFAnnotation,parts: [PDFAnnotation],measure: EngineeringMeasure }
        var families: [Family] = [],groups = Set<String>(),bounds = CGRect.null
        for ink in inks {
            guard ink.type == "Ink",ink.page === source,let group = AnnotationMetadata.group(of: ink),groups.insert(group).inserted,
                  (copying || !target.annotations.contains(where: { AnnotationMetadata.group(of: $0) == group })),let measure = AnnotationMetadata.measurement(ink) else { return false }
            let parts = source.annotations.filter { AnnotationMetadata.group(of: $0) == group },labels = parts.filter { $0.type == "FreeText" }
            guard labels.count == 1,let label = labels.first,parts.allSatisfy({ !AnnotationMetadata.isLocked($0) && ($0 === ink || $0 === label || ($0.type == "Line" && AnnotationMetadata.decoration(of: $0) == "engineeringDimension")) }) else { return false }
            for part in parts { let box = part.bounds; guard [box.minX,box.minY,box.width,box.height].allSatisfy({ $0.isFinite }),box.width >= 0,box.height >= 0 else { return false }; bounds = bounds.union(box) }
            families.append(Family(ink: ink,label: label,parts: parts,measure: measure))
        }
        let crop = target.bounds(for: .cropBox),original = source.bounds(for: .cropBox)
        guard [crop.minX,crop.minY,crop.width,crop.height,original.minX,original.minY].allSatisfy({ $0.isFinite }),crop.width > 0,crop.height > 0 else { return false }
        let dx = (options.centered ? crop.midX-bounds.midX : crop.minX-original.minX)+options.offsetX,dy = (options.centered ? crop.midY-bounds.midY : crop.minY-original.minY)+options.offsetY
        var transform = EngineeringAffineOptions(); transform.offsetX = dx; transform.offsetY = dy; transform.preservingValue = false
        var measures: [EngineeringMeasure] = []
        for family in families {
            guard var measure = family.measure.transformed(options: transform),family.parts.allSatisfy({ crop.insetBy(dx: -0.001,dy: -0.001).contains($0.bounds.offsetBy(dx: dx,dy: dy)) }) else { return false }
            if options.useTargetScale,let targetScale { measure.scale = targetScale }
            guard measure.value.isFinite else { return false }; measures.append(measure)
        }
        var outputFamilies = families
        if copying {
            outputFamilies = []
            for family in families {
                let copies = family.parts.compactMap(annotationCopy)
                guard copies.count == family.parts.count,let inkIndex = family.parts.firstIndex(where: { $0 === family.ink }),let labelIndex = family.parts.firstIndex(where: { $0 === family.label }) else { return false }
                AnnotationMetadata.transfer(from: family.parts,to: copies)
                for copy in copies { copy.removeValue(forAnnotationKey: PDFAnnotationKey(rawValue: "NM")) }
                outputFamilies.append(Family(ink: copies[inkIndex],label: copies[labelIndex],parts: copies,measure: family.measure))
            }
        }
        guard manager.snapshot(output) != nil else { return false }
        manager.recordUndo(output,group: "measurementTransfer-"+UUID().uuidString)
        for (family,measure) in zip(outputFamilies,measures) {
            for part in family.parts { if !copying { source.removeAnnotation(part) }; part.bounds = part.bounds.offsetBy(dx: dx,dy: dy); target.addAnnotation(part) }
            AnnotationMetadata.setMeasurement(measure,on: family.ink)
            let text = measure.label(russian: manager.language == .ru); family.ink.contents = text; family.label.contents = text
            if options.useTargetScale { family.label.removeValue(forAnnotationKey: .appearanceDictionary) }
        }
        output.pageIndex = options.pageIndex
        if copying { manager.select(output.id) }
        else { view.go(to: target); view.selectAnnotations(inks); view.refreshOverlay(); view.setNeedsDisplay(view.bounds) }
        manager.send(.refresh); return true
    }

    func showEngineeringScale(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsCommenting,let page = item.document.page(at: item.pageIndex),manager.finishSourceEditing?() != false else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(item.document),selected = manager.selectedAnnotation
        let selectedMeasure = selected.flatMap(AnnotationMetadata.measurement),current = selectedMeasure?.scale ?? EngineeringCalibration.read(page) ?? EngineeringScale(unit: manager.engineeringUnit)
        var initial = EngineeringScaleOptions(); initial.denominator = current.millimetersPerPoint/(25.4/72); initial.unit = current.unit; initial.selectedOnly = selectedMeasure != nil
        if let selectedMeasure { initial.dimensionLines = selectedMeasure.dimensionOffset != nil; initial.dimensionOffset = selectedMeasure.dimensionOffset ?? 12 }
        let undoGroup = "engineeringScaleEditor-"+UUID().uuidString
        manager.engineeringScaleRequest = EngineeringScaleRequest(russian: manager.language == .ru,hasSelection: selectedMeasure != nil,initial: initial,apply: { [weak self,weak view] options in
            guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsCommenting,
                  options.denominator.isFinite,(0.000001...1e12).contains(options.denominator),options.dimensionOffset.isFinite,abs(options.dimensionOffset) <= 10000 else { return "Документ изменён или некорректен масштаб / Document changed or invalid scale" }
            let scale = EngineeringScale(millimetersPerPoint: (25.4/72)*options.denominator,unit: options.unit)
            let indices = options.range.trimmingCharacters(in: .whitespaces).lowercased() == "current" ? [document.index(for: page)] : PDFPageRange.parse(options.range,count: document.pageCount) ?? []
            guard scale.valid,options.selectedOnly ? selectedMeasure != nil : !indices.isEmpty,
                  self.manager.snapshot(item) != nil else { return "Проверьте диапазон / Check page range" }
            self.manager.recordUndo(item,group: undoGroup)
            let pages = options.selectedOnly ? [page] : indices.compactMap { document.page(at: $0) }
            for target in pages {
                if !options.selectedOnly { do { try EngineeringCalibration.write(scale,page: target) } catch { return "Ошибка калибровки / Calibration failed" } }
                let measurements = options.selectedOnly ? selected.map { [$0] } ?? [] : target.annotations.filter { AnnotationMetadata.measurement($0) != nil }
                if options.selectedOnly || options.updateExisting {
                    for annotation in measurements {
                        guard var measure = AnnotationMetadata.measurement(annotation) else { continue }; measure.scale = scale
                        if measure.kind == .distance { measure.dimensionOffset = options.dimensionLines ? options.dimensionOffset : nil }
                        AnnotationMetadata.setMeasurement(measure,on: annotation); annotation.contents = measure.label(russian: self.manager.language == .ru)
                        if let group = AnnotationMetadata.group(of: annotation) {
                            for label in target.annotations where label !== annotation && label.type == "FreeText" && AnnotationMetadata.group(of: label) == group { label.contents = annotation.contents }
                        }
                        EngineeringDimensionRenderer.update(annotation: annotation,measurement: measure)
                    }
                }
            }
            self.manager.engineeringUnit = options.unit; view.refreshOverlay(); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh); return nil
        })
    }
    func showAnnotationRotation(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.canModifyAnnotationSelection,view.document === item.document else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),ids = Set(view.selectedAnnotations.map(ObjectIdentifier.init))
        manager.annotationRotationRequest = PDFAnnotationRotationRequest(russian: manager.language == .ru,apply: { [weak self,weak view] degrees in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == ids else { return "Документ или выбор изменён / Document or selection changed" }
            guard degrees.isFinite,(-360...360).contains(degrees),view.rotateAnnotationSelection(degrees: CGFloat(degrees)) else { return "Проверьте угол, типы объектов, блокировку и границы страницы / Check angle, object types, locks and page bounds" }
            self.manager.send(.refresh); return nil
        })
    }
    func showAnnotationScale(item: PDFDocumentItem,view: PDFViewerView) {
        guard view.canModifyAnnotationSelection,view.document === item.document else { return }
        let document = item.document,stamp = PDFDocumentState.stamp(document),ids = Set(view.selectedAnnotations.map(ObjectIdentifier.init)),box = view.annotationSelectionBounds
        manager.annotationScaleRequest = PDFAnnotationScaleRequest(russian: manager.language == .ru,width: Double(box.width),height: Double(box.height),apply: { [weak self,weak view] x,y in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,Set(view.selectedAnnotations.map(ObjectIdentifier.init)) == ids else { return "Документ или выбор изменён / Document or selection changed" }
            guard x.isFinite,y.isFinite,(10...1000).contains(x),(10...1000).contains(y),view.scaleAnnotationSelection(x: CGFloat(x/100),y: CGFloat(y/100)) else { return "Проверьте масштаб, типы объектов, блокировку и границы страницы / Check scale, object types, locks and page bounds" }
            self.manager.send(.refresh); return nil
        })
    }
    func showInkCurves(_ annotation: PDFAnnotation,item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsCommenting,annotation.type == "Ink",annotation.page?.document === item.document,!AnnotationMetadata.isLocked(annotation) else { return }
        do {
            let nodes = try PDFInkCurveGeometry.read(annotation,record: AnnotationMetadata.inkCurves(annotation)),document = item.document
            let stamp = PDFDocumentState.stamp(document),undoGroup = "inkCurves-"+UUID().uuidString
            manager.pathRequest = PDFPathRequest(nodes: nodes,russian: manager.language == .ru,ink: true,apply: { [weak self,weak view] nodes in
                guard let self,let view,item.document === document,view.document === document,annotation.page?.document === document,
                      PDFDocumentState.stamp(document) == stamp,document.allowsCommenting,!AnnotationMetadata.isLocked(annotation) else { return "Документ изменён / Document changed" }
                let probe = PDFAnnotation(bounds: annotation.bounds,forType: .ink,withProperties: nil); probe.border = annotation.border
                guard PDFInkCurveGeometry.apply(nodes,to: probe) != nil,self.manager.snapshot(item) != nil else { return "Проверьте узлы, координаты и сложность кривых / Check nodes, coordinates and curve complexity" }
                self.manager.recordUndo(item,group: undoGroup)
                guard let record = PDFInkCurveGeometry.apply(nodes,to: annotation) else { return "Не удалось применить кривые / Could not apply curves" }
                AnnotationMetadata.setInkCurves(record,on: annotation); view.refreshOverlay(); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh); return nil
            })
        } catch { manager.say("Cannot read the Ink paths.","Не удалось прочитать штрихи Ink.") }
    }
    func showAnnotationVertices(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsCommenting,let selected = manager.selectedAnnotation else { return }
        let annotation: PDFAnnotation
        if ["Line","Ink"].contains(selected.type ?? "") { annotation = selected }
        else if let group = AnnotationMetadata.group(of: selected),let line = selected.page?.annotations.first(where: { $0.type == "Line" && AnnotationMetadata.group(of: $0) == group }) { annotation = line }
        else { return }
        guard !AnnotationMetadata.isLocked(annotation) else { return }
        if annotation.type == "Ink",AnnotationMetadata.measurement(annotation) == nil { showInkCurves(annotation,item: item,view: view); return }
        do {
            let paths = try PDFAnnotationVertexGeometry.read(annotation),document = item.document,stamp = PDFDocumentState.stamp(item.document),undoGroup = "annotationVertices-"+UUID().uuidString
            manager.annotationVertexRequest = PDFAnnotationVertexRequest(russian: manager.language == .ru,line: annotation.type == "Line",initial: paths,apply: { [weak self,weak view] paths in
                guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp,annotation.page?.document === document,
                      document.allowsCommenting,!AnnotationMetadata.isLocked(annotation),self.manager.snapshot(item) != nil else { return "Документ изменён / Document changed" }
                let probe = PDFAnnotation(bounds: annotation.bounds,forType: annotation.type == "Line" ? .line : .ink,withProperties: nil)
                guard PDFAnnotationVertexGeometry.apply(paths,to: probe) else { return "Проверьте координаты и число вершин / Check coordinates and vertex count" }
                self.manager.recordUndo(item,group: undoGroup)
                _ = PDFAnnotationVertexGeometry.apply(paths,to: annotation)
                AnnotationMetadata.setInkCurves(nil,on: annotation)
                if AnnotationMetadata.measurement(annotation) != nil { view.selectAnnotation(annotation); view.updateEngineeringMeasurement() }
                view.refreshOverlay(); view.setNeedsDisplay(view.bounds); self.manager.send(.refresh); return nil
            })
        } catch { manager.say("Only line segments and polygonal Ink paths are supported. Curved strokes are kept intact.","Поддерживаются отрезки и ломаные Ink. Штрихи с кривыми сохраняются без изменений.") }
    }
    func showHeadingBookmarks(item: PDFDocumentItem,view: PDFViewerView,fromTOC: Bool) {
        guard item.document.allowsCopying else { return }
        let document = item.document,initialPage = item.pageIndex,undoGroup = "headingBookmarks-"+UUID().uuidString
        var previewStamp = PDFDocumentState.stamp(document)
        manager.headingRequest = PDFHeadingRequest(russian: manager.language == .ru,fromTOC: fromTOC,load: { [weak self] options in
            guard let self,item.document === document,options.minimumFont.isFinite,(1...200).contains(options.minimumFont),
                  (-100000...100000).contains(options.offset),(0...3).contains(options.columns) else { throw PDFSourceError.content }
            let indices = options.range.trimmingCharacters(in: .whitespaces).lowercased() == "current" ? [initialPage] : PDFPageRange.parse(options.range,count: item.pageCount) ?? []
            guard !indices.isEmpty else { throw PDFSourceError.content }
            previewStamp = PDFDocumentState.stamp(document)
            var rows: [PDFHeadingCandidate] = []
            if fromTOC {
                for index in indices {
                    guard let page = document.page(at: index) else { continue }
                    let box = page.bounds(for: .cropBox)
                    let selections = page.selection(for: box)?.selectionsByLine() ?? []
                    let lines = selections.compactMap { selection -> PDFTOCTextLine? in
                        guard let text = selection.string,!text.isEmpty else { return nil }
                        let bounds = selection.bounds(for: page)
                        return PDFTOCTextLine(text: text,bounds: bounds,fontSize: max(6,bounds.height))
                    }
                    rows += PDFTOCRecognizer.candidates(lines: lines,bounds: box,document: document,options: options)
                }
            } else {
                let data = try self.manager.serializedData(item)
                var values: [(String,Int,CGPoint,Double)] = []
                for index in indices {
                    guard let page = document.page(at: index) else { continue }
                    let blocks = try PDFSourceSession.blocks(data: data,pageIndex: index)
                    let lines = blocks.enumerated().map { PDFTOCTextLine(text: $0.element.snapshot.text,bounds: $0.element.snapshot.bounds,fontSize: Double($0.element.snapshot.fontSize),sourceIndex: $0.offset) }
                    for column in PDFTOCRecognizer.columns(lines,bounds: page.bounds(for: .cropBox),count: options.columns) {
                        for line in column {
                            guard let at = line.sourceIndex,blocks.indices.contains(at) else { continue }
                            let block = blocks[at],snapshot = block.snapshot
                            let title = snapshot.text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
                            guard snapshot.fontSize >= options.minimumFont,(2...600).contains(title.count) else { continue }
                            if options.scheme == 1,title.range(of: #"^\d+(?:\.\d+)*[.)]?\s+"#,options: .regularExpression) == nil { continue }
                            if options.scheme == 2,!["bold","demi","black","heavy"].contains(where: snapshot.fontName.lowercased().contains) { continue }
                            values.append((title,index,CGPoint(x: snapshot.bounds.minX,y: snapshot.bounds.maxY),Double(snapshot.fontSize)))
                        }
                    }
                }
                let sizes = Array(Set(values.map { ($0.3*2).rounded()/2 })).sorted(by: >)
                for row in values {
                    let numbered = row.0.prefix { $0.isNumber || $0 == "." }.split(separator: ".").count
                    let level = options.scheme == 1 ? max(0,numbered-1) : sizes.firstIndex(of: (row.3*2).rounded()/2) ?? 0
                    rows.append(PDFHeadingCandidate(title: row.0,page: row.1,point: row.2,level: min(8,level)))
                }
            }
            return Array(rows.prefix(10000))
        },apply: { [weak self] rows in
            guard let self,item.document === document,PDFDocumentState.stamp(document) == previewStamp,
                  document.allowsDocumentChanges,rows.allSatisfy({ (0..<document.pageCount).contains($0.page) && !$0.title.trimmingCharacters(in: .whitespaces).isEmpty && $0.title.utf16.count <= 20000 }),
                  self.manager.snapshot(item) != nil else { return "Документ изменён или некорректны заголовки / Document changed or invalid headings" }
            self.manager.recordUndo(item,group: undoGroup)
            guard let root = self.manager.bookmarkRoot() else { return "Нет дерева закладок / No bookmark tree" }
            var stack: [(Int,PDFOutline)] = []
            for row in rows {
                guard let page = document.page(at: row.page) else { continue }
                while let last = stack.last,last.0 >= row.level { stack.removeLast() }
                let node = PDFOutline(); node.label = row.title; node.destination = PDFDestination(page: page,at: row.point)
                let parent = stack.last?.1 ?? root; parent.insertChild(node,at: parent.numberOfChildren); stack.append((row.level,node))
            }
            self.manager.panels.select(.bookmarks); self.manager.send(.refresh); return nil
        })
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func namedBookmarks(item: PDFDocumentItem,view: PDFViewerView,convertToNames: Bool) {
        do {
            let data = try manager.serializedData(item)
            if !convertToNames {
                let nodes = manager.bookmarkNodes(),targets = try PDFDocumentExtras.namedTargets(data)
                manager.recordUndo(item,group: "namedToDirect")
                var converted = 0
                for node in nodes { if let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination,let page = destination.page {
                    let copy = PDFDestination(page: page,at: destination.point); copy.zoom = destination.zoom; node.destination = copy; node.action = PDFActionGoTo(destination: copy); converted += 1
                } }
                manager.send(.refresh); manager.say("Named destinations: \(targets.count). Resolved bookmark links: \(converted).","Именованных назначений: \(targets.count). Прямых ссылок закладок: \(converted).")
                return
            }
            var targets = try PDFDocumentExtras.namedTargets(data),mapping: [Int:String] = [:]
            let nodes = manager.bookmarkNodes(),selected = manager.selectedOutline.map { Set(([$0]+manager.bookmarkNodes($0)).map(ObjectIdentifier.init)) }
            for (index,node) in nodes.enumerated() {
                guard selected == nil || selected!.contains(ObjectIdentifier(node)),let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination,let page = destination.page else { continue }
                let at = item.document.index(for: page); guard at >= 0,at < item.pageCount else { continue }
                let name = "BotPlus-"+UUID().uuidString
                targets.append(PDFNamedTarget(name: name,page: at,x: destination.point.x,y: destination.point.y,zoom: destination.zoom)); mapping[index] = name
            }
            guard !mapping.isEmpty else { return }
            let bytes = try PDFDocumentExtras.writeNamedTargets(data,targets: targets,bookmarks: mapping)
            guard let document = PDFDocument(data: bytes),document.pageCount == item.pageCount else { throw PDFSourceError.save }
            AnnotationMetadata.restore(document); manager.recordUndo(item,group: "bookmarksToNamed")
            item.document = document; item.enableStreamPreservation(); reload(view,document: item,pageIndex: item.pageIndex); manager.send(.refresh); manager.seedSerializedData(bytes,item: item)
        } catch { sourceError(error) }
    }
}

@MainActor private extension DocumentManager {
    func openScanner() {
        scannerRequest = PDFScannerRequest(russian: language == .ru) { [weak self] urls in
            guard let self else { return "Окно документа закрыто / Document window closed" }
            let document = PDFDocument()
            for url in urls {
                if let source = PDFDocument(url: url),!source.isLocked,source.pageCount > 0 {
                    for index in 0..<source.pageCount {
                        guard let page = source.page(at: index)?.copy() as? PDFPage else { return "Не удалось прочитать страницу / Could not read page: \(url.lastPathComponent)" }
                        document.insert(page,at: document.pageCount)
                    }
                }
                else if let image = NSImage(contentsOf: url),let page = PDFPage(image: image) { document.insert(page,at: document.pageCount) }
                else { return "Не удалось прочитать скан / Could not read scan: \(url.lastPathComponent)" }
            }
            guard document.pageCount > 0 else { return "Отсканированные страницы не удалось прочитать / No readable scanned pages" }
            do {
                let data = try PDFDocumentSerializer.data(document)
                guard let loaded = PDFDocument(data: data) else { throw PDFSourceError.document }
                let item = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent("Scan.pdf"),document: loaded,preserveStreams: true)
                item.isUntitled = true; item.recoveredFilename = "Scan.pdf"; self.insertDocument(item); self.seedSerializedData(data,item: item)
                return nil
            } catch { return "Не удалось собрать отсканированные страницы / Could not assemble scanned pages" }
        }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showRasterWorkflow(item: PDFDocumentItem,view: PDFViewerView,enhancement: Bool) {
        guard item.document.allowsCopying,manager.operationTask == nil else { return }
        manager.rasterRequest = PDFRasterRequest(russian: manager.language == .ru,enhancement: enhancement,pageCount: item.pageCount,initialPage: item.pageIndex+1,preview: { [weak self,weak view] options,index in
            guard let self,let view,item.document === view.document,item.document.allowsCopying,
                  let indices = PDFPageRange.parse(options.range,count: item.pageCount),indices.contains(index),let page = item.document.page(at: index) else { throw PDFSourceError.content }
            let bytes = try self.manager.serializedData(item),region = page.bounds(for: .cropBox)
            let worker = Task.detached(priority: .userInitiated) {
                let before = try PDFSnapshotRenderer.render(data: bytes,index: index,region: region,dpi: options.dpi)
                let after = try PDFRasterEngine.process(data: bytes,indices: [index],options: options,progress: { _ in })
                return (before,after)
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        },deskew: { [weak self,weak view] index in
            guard let self,let view,item.document.allowsCopying,item.document === view.document else { throw PDFSourceError.permission }
            let bytes = try self.manager.serializedData(item)
            let worker = Task.detached(priority: .userInitiated) { try PDFRasterEngine.suggestDeskew(data: bytes,index: index) }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        },detectBounds: { [weak self,weak view] index in
            guard let self,let view,item.document.allowsCopying,item.document === view.document else { throw PDFSourceError.permission }
            let bytes = try self.manager.serializedData(item)
            let worker = Task.detached(priority: .userInitiated) { try PDFRasterEngine.detectBounds(data: bytes,index: index) }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        },detectPerspective: { [weak self,weak view] index in
            guard let self,let view,item.document.allowsCopying,item.document === view.document else { throw PDFSourceError.permission }
            let bytes = try self.manager.serializedData(item)
            let worker = Task.detached(priority: .userInitiated) { try PDFRasterEngine.detectPerspective(data: bytes,index: index) }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        }) { [weak self] options in
            guard let self,let indices = PDFPageRange.parse(options.range,count: item.pageCount),self.manager.operationTask == nil,(0...2).contains(options.perspectiveMode),(options.perspectiveMode != 1 || options.quad.valid),abs(options.angle) <= 20 else { return "Проверьте диапазон, угол (−20…20°) и углы перспективы / Check range, angle and perspective corners" }
            do {
                let data = try self.manager.serializedData(item),manager = self.manager,id = UUID()
                manager.activeOperationID = id; manager.operationProgress = 0; manager.operationTitle = enhancement ? "Enhance / Улучшение сканов" : "Colors / Цвета"
                manager.operationTask = Task { @MainActor in
                    defer { manager.activeOperationID = nil; manager.operationProgress = nil; manager.operationTask = nil }
                    do {
                        let worker = Task.detached(priority: .userInitiated) {
                            try PDFRasterEngine.process(data: data,indices: indices,options: options) { value in Task { @MainActor in if manager.activeOperationID == id { manager.operationProgress = value } } }
                        }
                        let bytes = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                        try Task.checkCancellation()
                        guard let document = PDFDocument(data: bytes) else { throw PDFSourceError.document }
                        let entry = PDFDocumentItem(url: FileManager.default.temporaryDirectory.appendingPathComponent("Raster-"+item.filename),document: document,preserveStreams: true)
                        entry.isUntitled = true; entry.recoveredFilename = "Raster-"+item.filename
                        manager.insertDocument(entry); manager.seedSerializedData(bytes,item: entry)
                    } catch is CancellationError { }
                    catch { manager.say("Raster conversion failed. Original PDF is intact.","Не удалось создать растровую копию. Исходный PDF не изменён.") }
                }; return nil
            } catch { return "Не удалось подготовить PDF / Cannot prepare PDF" }
        }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showComparison(item: PDFDocumentItem) {
        guard item.document.allowsCopying,finishSourceEditor() else { return }
        PDFDialogs.open([.pdf]) { [weak self] urls in
            guard let self,let url = urls.first,self.manager.selected?.id == item.id else { return }
            let lease = FileAccessLease(url); defer { _ = lease }
            do {
                let left = try self.manager.serializedData(item),right = try Data(contentsOf: url)
                guard let other = PDFDocument(data: right),!other.isLocked,other.allowsCopying else { throw PDFSourceError.permission }
                self.manager.comparisonRequest = PDFComparisonRequest(left: left,right: right,leftName: item.filename,rightName: url.lastPathComponent,russian: self.manager.language == .ru)
            } catch { self.sourceError(error) }
        }
    }
}

@MainActor private extension DocumentManager {
    func changeAnnotation(_ annotation: PDFAnnotation,lock: Bool? = nil,visible: Bool? = nil,printable: Bool? = nil) {
        guard let item = selected,item.document.allowsCommenting else { return }
        recordUndo(item,group: "annotationFlags")
        let parts: [PDFAnnotation]
        if let group = AnnotationMetadata.group(of: annotation),let page = annotation.page { parts = page.annotations.filter { AnnotationMetadata.group(of: $0) == group } } else { parts = [annotation] }
        for part in parts {
            if let lock { AnnotationMetadata.setLocked(lock,on: part) }
            if let visible { part.shouldDisplay = visible }
            if let printable { part.shouldPrint = printable }
        }
        send(.refresh)
    }
}
@MainActor private extension PDFViewerView {
    func eraseInk(page: PDFPage,point: CGPoint,whole: Bool) {
        guard document?.allowsCommenting == true else { return }
        let radius = max(3,8/max(0.01,scaleFactor))
        for annotation in page.annotations.reversed() where annotation.shouldDisplay && !AnnotationMetadata.isContainer(annotation) && !AnnotationMetadata.isLocked(annotation) && annotation.bounds.insetBy(dx: -radius,dy: -radius).contains(point) {
            if whole {
                if !eraserRecorded { onWillModify?(); eraserRecorded = true }
                if let group = AnnotationMetadata.group(of: annotation) { for part in page.annotations where AnnotationMetadata.group(of: part) == group { page.removeAnnotation(part) } }
                else { page.removeAnnotation(annotation) }
                selectAnnotation(nil); setNeedsDisplay(bounds); return
            }
            guard annotation.type == "Ink",AnnotationMetadata.measurement(annotation) == nil,let paths = annotation.paths else { continue }
            let local = CGPoint(x: point.x-annotation.bounds.minX,y: point.y-annotation.bounds.minY)
            let result = PDFInkEraser.erase(paths,center: local,radius: radius)
            guard result.changed else { continue }
            if !eraserRecorded { onWillModify?(); eraserRecorded = true }
            if result.paths.isEmpty { page.removeAnnotation(annotation) }
            else { for path in paths { annotation.remove(path) }; for path in result.paths { annotation.add(path) }; AnnotationMetadata.setInkCurves(nil,on: annotation); annotation.removeValue(forAnnotationKey: .appearanceDictionary) }
            selectAnnotation(nil); setNeedsDisplay(bounds)
        }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showOfficeExport(item: PDFDocumentItem,format: String) {
        guard item.document.allowsCopying,finishSourceEditor() else { return }
        let document = item.document
        manager.officeRequest = PDFOfficeRequest(format: format,russian: manager.language == .ru,count: item.pageCount) { [weak self] range in
            guard let self,item.document === document,let indices = PDFPageRange.parse(range,count: item.pageCount) else { return "Invalid page range / Проверьте диапазон" }
            self.manager.afterFeatureDismiss = { [weak self] in
                guard let self,self.manager.operationTask == nil else { return }
                let panel = NSSavePanel(),ext = format == "word" ? "docx" : format == "excel" ? "xlsx" : "pptx"
                panel.nameFieldStringValue = URL(fileURLWithPath: item.filename).deletingPathExtension().lastPathComponent+"."+ext
                panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
                panel.begin { [weak self] response in
                    guard let self,response == .OK,let url = panel.url else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self,self.manager.operationTask == nil,item.document === document else { return }
                        let lease = FileAccessLease(url),operationID = UUID()
                        self.manager.activeOperationID = operationID; self.manager.operationTitle = "Office · "+ext.uppercased(); self.manager.operationProgress = 0
                        self.manager.operationTask = Task { @MainActor [weak self] in
                            guard let self else { return }
                            defer { self.manager.operationTask = nil; self.manager.operationProgress = nil; self.manager.activeOperationID = nil; _ = lease }
                            do {
                                let data = try self.manager.serializedData(item)
                                var pages: [PDFOfficePage] = []
                                for (position,index) in indices.enumerated() {
                                    try Task.checkCancellation()
                                    guard let page = document.page(at: index) else { throw PDFSourceError.page }
                                    let crop = page.bounds(for: .cropBox),blocks = try PDFSourceSession.blocks(data: data,pageIndex: index)
                                    let rotation = ((page.rotation%360)+360)%360
                                    let transform = PDFFormattingGeometry.transform(page,box: .cropBox,target: CGRect(x: 0,y: 0,width: rotation%180 == 0 ? crop.width : crop.height,height: rotation%180 == 0 ? crop.height : crop.width))
                                    var text: [PDFOfficeText] = blocks.map { descriptor -> PDFOfficeText in
                                        let snapshot = descriptor.snapshot
                                        return PDFOfficeText(text: snapshot.text,bounds: snapshot.bounds.applying(transform),font: snapshot.fontName,size: Double(snapshot.fontSize))
                                    }
                                    text.sort { left,right in
                                        if abs(left.bounds.maxY-right.bounds.maxY) > 3 { return left.bounds.maxY > right.bounds.maxY }
                                        return left.bounds.minX < right.bounds.minX
                                    }
                                    pages.append(PDFOfficePage(width: rotation%180 == 0 ? crop.width : crop.height,height: rotation%180 == 0 ? crop.height : crop.width,blocks: text))
                                    self.manager.operationProgress = Double(position+1)/Double(indices.count)*0.8; await Task.yield()
                                }
                                let snapshot = pages
                                let worker = Task.detached(priority: .userInitiated) { try PDFOfficeExporter.create(pages: snapshot,format: format) }
                                let output = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                                try Task.checkCancellation(); try output.write(to: url,options: .atomic)
                            } catch is CancellationError {} catch { self.sourceError(error) }
                        }
                    }
                }
            }
            return nil
        }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showLayerStateEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,view.document === item.document,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),report = try PDFDocumentExtras.layerStateReport(data),document = item.document,stamp = PDFDocumentState.stamp(document)
            let apply: (PDFLayerStateConfiguration,String,[String],[Int],[Int],[Int]?) -> String? = { [weak self,weak view] entry,base,intents,on,off,locks in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён / Document changed" }
                do {
                    let output = try PDFDocumentExtras.setLayerState(data,entry: entry,base: base,intents: intents,on: on,off: off,locked: locks)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Проверьте Intent, ON/OFF, Locked и радиогруппы / Check intent, ON/OFF, locked states and radio groups" }
            }
            manager.layerStateRequest = PDFLayerStateRequest(russian: manager.language == .ru,report: report,applyWithLocks: { apply($0,$1,$2,$3,$4,$5) },apply: { apply($0,$1,$2,$3,$4,nil) })
        } catch { manager.say("Cannot read layer configuration settings.","Не удалось прочитать параметры конфигураций слоёв.") }
    }
    func showLayerRadioEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,view.document === item.document,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),report = try PDFDocumentExtras.layerStateReport(data),document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.layerRadioRequest = PDFLayerRadioRequest(russian: manager.language == .ru,report: report,apply: { [weak self,weak view] entry,radios in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён / Document changed" }
                do {
                    let output = try PDFDocumentExtras.setLayerRadios(data,entry: entry,radios: radios)
                    if output == data { return nil }
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Проверьте состав групп и конфликтующие ON в выбранной и наследующих конфигурациях / Check membership and conflicting ON states in this and inheriting configurations" }
            })
        } catch { manager.say("Cannot read layer radio groups.","Не удалось прочитать радиогруппы слоёв.") }
    }
    func showLayerOrderEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,view.document === item.document,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),configurations = try PDFDocumentExtras.layerOrderConfigurations(data),document = item.document,stamp = PDFDocumentState.stamp(document)
            manager.layerOrderRequest = PDFLayerOrderRequest(russian: manager.language == .ru,configurations: configurations,layers: try PDFDocumentExtras.layerCatalogGroups(data),apply: { [weak self,weak view] entry,operation in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён / Document changed" }
                do {
                    let output = try PDFDocumentExtras.editLayerOrder(data,entry: entry,operation: operation)
                    if output == data { return nil }
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                    self.layerCommand("layersRefresh",item: item,view: view); return nil
                } catch { return "Не удалось изменить Order. Проверьте имя, выбор, вложенность и пустоту удаляемого элемента / Could not edit Order. Check title, selection, nesting and empty children" }
            })
        } catch { manager.say("Cannot read layer presentation order.","Не удалось прочитать порядок слоёв.") }
    }
    func showLayerPresetEditor(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,view.document === item.document,finishSourceEditor() else { return }
        layerCommand("layersRefresh",item: item,view: view)
        guard let snapshot = manager.layerSnapshot,!manager.layerPresets.isEmpty else { return }
        let document = item.document
        manager.layerPresetRequest = PDFLayerPresetRequest(russian: manager.language == .ru,presets: manager.layerPresets,apply: { [weak self,weak view] operation in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == snapshot.stamp,document.allowsDocumentChanges else { return "Документ изменён. Откройте редактор заново / Document changed. Reopen the editor" }
            do {
                let output = try PDFDocumentExtras.editLayerPreset(snapshot.data,operation: operation)
                try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                self.layerCommand("layersRefresh",item: item,view: view); return nil
            } catch PDFSourceError.alreadyUsed { return "Это название уже используется / This name is already used" }
            catch { return "Проверьте название и выбранную конфигурацию / Check the name and selected configuration" }
        })
    }
    func layerCommand(_ id: String,item: PDFDocumentItem,view: PDFViewerView) {
        do {
            if id.hasPrefix("layerLock:") {
                let parts = id.split(separator: ":")
                guard parts.count == 3,let number = Int(parts[1]),let state = Int(parts[2]),[0,1].contains(state),view.document === item.document,item.document.allowsDocumentChanges,
                      let snapshot = manager.layerSnapshot,snapshot.document == ObjectIdentifier(item.document),snapshot.stamp == PDFDocumentState.stamp(item.document),let entry = manager.layerEntries.first(where: { $0.id == number }) else { throw PDFSourceError.alreadyUsed }
                if entry.locked != (state == 1) {
                    let output = try PDFDocumentExtras.setLayerLocked(snapshot.data,entry: entry,locked: state == 1)
                    try installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                }
            }
            if id.hasPrefix("layerPreset:") {
                guard let index = Int(id.dropFirst("layerPreset:".count)),item.document.allowsDocumentChanges,let snapshot = manager.layerSnapshot,
                      snapshot.document == ObjectIdentifier(item.document),snapshot.stamp == PDFDocumentState.stamp(item.document),view.document === item.document else { throw PDFSourceError.alreadyUsed }
                let output = try PDFDocumentExtras.makeLayerPresetDefault(snapshot.data,index: index)
                try installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
            }
            if id.hasPrefix("layerToggle:") {
                let components = id.split(separator: ":").compactMap { Int($0) }
                guard components.count == 2,item.document.allowsDocumentChanges,let snapshot = manager.layerSnapshot,snapshot.document == ObjectIdentifier(item.document),snapshot.stamp == PDFDocumentState.stamp(item.document),let entry = manager.layerEntries.first(where: { $0.id == components[0] }) else { throw PDFSourceError.alreadyUsed }
                let output = try PDFDocumentExtras.setLayer(snapshot.data,entry: entry,visible: components[1] == 1)
                try installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
            }
            let data = try manager.serializedData(item)
            let configuration = try PDFDocumentExtras.layerConfiguration(data)
            manager.layerEntries = configuration.groups; manager.layerOutline = configuration.rows; manager.layerHasOrder = configuration.hasOrder
            manager.layerPresets = try PDFDocumentExtras.layerPresets(data)
            manager.layerSnapshot = (data,ObjectIdentifier(item.document),PDFDocumentState.stamp(item.document)); manager.layerError = nil
        } catch {
            manager.layerSnapshot = nil
            manager.layerError = manager.language == .ru ? "Не удалось прочитать или изменить OCG. Обновите список; исходная страница не изменена при ошибке записи." : "Could not read or change OCG. Refresh the list; a failed write leaves the original page intact."
        }
    }
    func showStructure(item: PDFDocumentItem,view: PDFViewerView) {
        guard finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),document = item.document,stamp = PDFDocumentState.stamp(document)
            let report = try PDFDocumentExtras.structure(data,russian: manager.language == .ru)
            let apply: (String,PDFStructureNode?,String,PDFStructureTextChange,PDFStructureProperties) -> String? = { [weak self,weak view] language,node,alt,actualText,properties in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Document changed / Документ изменился" }
                do {
                    let output = try PDFDocumentExtras.setStructure(data,language: language,node: node,alternative: alt,actualText: actualText,properties: properties)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return error.localizedDescription }
            }
            let reorder: (PDFStructureNode,Int) -> String? = { [weak self,weak view] node,direction in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Document changed / Документ изменился" }
                do {
                    let output = try PDFDocumentExtras.reorderStructure(data,node: node,direction: direction)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Перестановка недоступна для выбранного узла / Cannot reorder this element" }
            }
            let reparent: (PDFStructureNode,PDFStructureNode?) -> String? = { [weak self,weak view] node,parent in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Document changed / Документ изменился" }
                do {
                    let output = try PDFDocumentExtras.reparentStructure(data,node: node,parent: parent)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Перенос к этому родителю недоступен / Cannot move to this parent" }
            }
            let wrap: (PDFStructureNode,String) -> String? = { [weak self,weak view] node,title in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Document changed / Документ изменился" }
                do {
                    let output = try PDFDocumentExtras.wrapStructure(data,node: node,title: title)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Создать контейнер вокруг этого элемента нельзя / Cannot wrap this element" }
            }
            let deleteEmpty: (PDFStructureNode) -> String? = { [weak self,weak view] node in
                guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == stamp,document.allowsDocumentChanges else { return "Документ изменён / Document changed" }
                do {
                    let output = try PDFDocumentExtras.deleteEmptyStructure(data,node: node)
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return "Тег содержит данные, ID/описания или внутренние ссылки; удаление недоступно / Tag has content, ID/descriptions or internal references; deletion unavailable" }
            }
            manager.structureRequest = PDFStructureRequest(report: report,russian: manager.language == .ru,editable: document.allowsDocumentChanges,deleteEmpty: deleteEmpty,wrap: wrap,reparent: reparent,reorder: reorder,applyProperties: apply) { language,node,alt,actual in apply(language,node,alt,actual,PDFStructureProperties()) }

        } catch { sourceError(error) }
    }
    func showLayerPolicy(_ id: String,item: PDFDocumentItem,view: PDFViewerView) {
        guard let number = Int(id.dropFirst("layerPolicy:".count)),let entry = manager.layerEntries.first(where: { $0.id == number }),!entry.locked,
              let snapshot = manager.layerSnapshot,snapshot.document == ObjectIdentifier(item.document),snapshot.stamp == PDFDocumentState.stamp(item.document),item.document.allowsDocumentChanges else { return }
        let document = item.document
        let apply: (Bool?,Bool?,[String]?,PDFLayerExtendedUsage?,String?) -> String? = { [weak self,weak view] viewState,printState,intents,extended,name in
            guard let self,let view,item.document === document,view.document === document,PDFDocumentState.stamp(document) == snapshot.stamp,document.allowsDocumentChanges else { return "Документ изменён. Обновите список слоёв / Document changed. Refresh layers" }
            do {
                let output = try PDFDocumentExtras.setLayerUsage(snapshot.data,entry: entry,viewState: viewState,printState: printState,intents: intents,extended: extended,name: name)
                try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation()
                self.layerCommand("layersRefresh",item: item,view: view); return nil
            } catch { return "Не удалось записать имя, Intent или Usage слоя / Could not write layer name, intent or usage" }
        }
        let extended = try? PDFDocumentExtras.layerExtendedUsage(snapshot.data,entry: entry)
        let applyExtended: ((Bool?,Bool?,[String],PDFLayerExtendedUsage) -> String?)? = extended == nil ? nil : { apply($0,$1,$2,$3,nil) }
        manager.layerPolicyRequest = PDFLayerPolicyRequest(russian: manager.language == .ru,entry: entry,applyIntent: { apply($0,$1,$2,nil,nil) },extended: extended,applyExtended: applyExtended,applyNamed: { apply($0,$1,$2,$3,$4) },apply: { apply($0,$1,nil,nil,nil) })
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showNamedDestinations(item: PDFDocumentItem,view: PDFViewerView) {
        guard item.document.allowsDocumentChanges,finishSourceEditor() else { return }
        do {
            let data = try manager.serializedData(item),document = item.document,stamp = PDFDocumentState.stamp(document)
            let targets = try PDFDocumentExtras.namedTargets(data),point = document.page(at: item.pageIndex)?.bounds(for: .cropBox).origin ?? .zero
            manager.namedRequest = PDFNamedRequest(targets: targets,currentPage: item.pageIndex,point: point,pageCount: item.pageCount,russian: manager.language == .ru) { [weak self,weak view] targets in
                guard let self,let view,item.document === document,PDFDocumentState.stamp(document) == stamp else { return "Document changed / Документ изменился" }
                do {
                    let output = try PDFDocumentExtras.writeNamedTargets(data,targets: targets,bookmarks: [:])
                    try self.installSourceData(output,item: item,index: item.pageIndex,view: view,bounds: nil,restoreBookmarks: false); item.enableStreamPreservation(); return nil
                } catch { return error.localizedDescription }
            }
        } catch { sourceError(error) }
    }
}

@MainActor private extension PDFViewer.Coordinator {
    func showSnapshotRegion(item: PDFDocumentItem) {
        guard item.document.allowsCopying,manager.operationTask == nil,let source = manager.snapshotSource,source.id == item.id,let page = item.document.page(at: source.page) else { return }
        let expected = item.document,stamp = PDFDocumentState.stamp(expected)
        manager.regionRequest = PDFRegionRequest(page: page,region: source.region,russian: manager.language == .ru) { [weak self] region in
            guard let self,self.manager.selected?.id == item.id,item.document === expected,PDFDocumentState.stamp(expected) == stamp,self.manager.operationTask == nil else { return "Document changed / Документ изменился" }
            self.copySnapshot(page: page,region: region); return nil
        }
    }
}

@MainActor private extension PDFViewerView {
    @discardableResult func rotateAnnotationSelection(clockwise: Bool) -> Bool {
        rotateAnnotationSelection(degrees: clockwise ? -90 : 90)
    }
    @discardableResult func rotateAnnotationSelection(degrees: CGFloat) -> Bool {
        guard canModifyAnnotationSelection,degrees.isFinite,(-360...360).contains(degrees) else { return false }
        let angle = degrees.truncatingRemainder(dividingBy: 360),quarter = angle/90
        let orthogonal = abs(quarter-quarter.rounded()) < 1e-10
        let supported = orthogonal ? ["Line","Ink","Square","Circle"] : ["Line","Ink"]
        guard selectedAnnotations.allSatisfy({ supported.contains($0.type ?? "") && AnnotationMetadata.measurement($0) == nil }) else { return false }
        if angle == 0 { return true }
        let radians = angle*CGFloat.pi/180
        let cosine = orthogonal ? cos(radians).rounded() : cos(radians),sine = orthogonal ? sin(radians).rounded() : sin(radians)
        let union = annotationSelectionBounds,center = CGPoint(x: union.midX,y: union.midY)
        let transform = CGAffineTransform(a: cosine,b: sine,c: -sine,d: cosine,tx: center.x*(1-cosine)+center.y*sine,ty: center.y*(1-cosine)-center.x*sine)
        return applyAnnotationSelectionTransform(transform)
    }
    @discardableResult func scaleAnnotationSelection(x: CGFloat,y: CGFloat) -> Bool {
        guard canModifyAnnotationSelection,x.isFinite,y.isFinite,(0.1...10).contains(x),(0.1...10).contains(y) else { return false }
        if x == 1 && y == 1 { return true }
        let box = annotationSelectionBounds
        return applyAnnotationSelectionTransform(CGAffineTransform(a: x,b: 0,c: 0,d: y,tx: box.midX*(1-x),ty: box.midY*(1-y)))
    }
    @discardableResult func flipAnnotationSelection(horizontal: Bool) -> Bool {
        guard canModifyAnnotationSelection else { return false }
        let box = annotationSelectionBounds
        return applyAnnotationSelectionTransform(CGAffineTransform(a: horizontal ? -1 : 1,b: 0,c: 0,d: horizontal ? 1 : -1,tx: horizontal ? 2*box.midX : 0,ty: horizontal ? 0 : 2*box.midY))
    }
    private func applyAnnotationSelectionTransform(_ transform: CGAffineTransform) -> Bool {
        guard canModifyAnnotationSelection,let page = selectedAnnotations.first?.page,
              selectedAnnotations.allSatisfy({ ["Line","Ink","Square","Circle"].contains($0.type ?? "") && AnnotationMetadata.measurement($0) == nil }) else { return false }
        struct Plan { let annotation: PDFAnnotation,box: CGRect,start: CGPoint?,end: CGPoint?,paths: [NSBezierPath]?,record: PDFInkCurveRecord? }
        var plans: [Plan] = []
        for annotation in selectedAnnotations {
            if annotation.type == "Ink" {
                guard let nodes = try? PDFInkCurveGeometry.read(annotation,record: AnnotationMetadata.inkCurves(annotation)) else { return false }
                let rotated = PDFInkCurveGeometry.mapped(nodes) { $0.applying(transform) },probe = PDFAnnotation(bounds: annotation.bounds,forType: .ink,withProperties: nil)
                probe.border = annotation.border
                guard let record = PDFInkCurveGeometry.apply(rotated,to: probe),let paths = probe.paths else { return false }
                plans.append(Plan(annotation: annotation,box: probe.bounds,start: nil,end: nil,paths: paths,record: record))
            } else {
                let box = annotation.bounds.applying(transform)
                func rotated(_ p: CGPoint) -> CGPoint {
                    let absolute = CGPoint(x: annotation.bounds.minX+p.x,y: annotation.bounds.minY+p.y).applying(transform)
                    return CGPoint(x: absolute.x-box.minX,y: absolute.y-box.minY)
                }
                plans.append(Plan(annotation: annotation,box: box,start: annotation.type == "Line" ? rotated(annotation.startPoint) : nil,end: annotation.type == "Line" ? rotated(annotation.endPoint) : nil,paths: nil,record: nil))
            }
        }
        let crop = page.bounds(for: .cropBox).insetBy(dx: -0.001,dy: -0.001)
        guard plans.allSatisfy({ crop.contains($0.box) }) else { return false }
        onWillModify?()
        for plan in plans {
            if let paths = plan.paths {
                for old in plan.annotation.paths ?? [] { plan.annotation.remove(old) }
                plan.annotation.bounds = plan.box; for path in paths { plan.annotation.add(path) }
                AnnotationMetadata.setInkCurves(plan.record,on: plan.annotation)
            } else {
                plan.annotation.bounds = plan.box
                if let start = plan.start,let end = plan.end { plan.annotation.startPoint = start; plan.annotation.endPoint = end }
            }
            plan.annotation.removeValue(forAnnotationKey: .appearanceDictionary)
        }
        refreshOverlay(); setNeedsDisplay(bounds); onAnnotationChanged?(); return true
    }
}
