// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus

import AppKit
import CoreText
import PDFKit
import CPDFium
import CryptoKit

// Owned by a synchronous CoreGraphics scanner; callbacks never cross threads.
private final class PDFMarkedContentScope {
    var depth = 0,maximum = 0,operators = 0,valid = true
    func begin() { depth += 1; maximum = max(maximum,depth); operators += 1; if depth > 128 || operators > 1000000 { valid = false } }
}

/// Content changes happen in an independent PDFium snapshot. The visible
/// PDFDocument is replaced only after the complete block has been serialized.
enum PDFSourceError: Error {
    case document, page, textNotFound, font, content, save, alreadyUsed, permission, unsupportedGlyph
    var english: String {
        switch self {
        case .document: "Could not open this PDF for content editing."
        case .page: "The PDF page is unavailable."
        case .textNotFound: "No editable text block was found here. Scanned image text requires OCR."
        case .font: "A suitable system font could not be loaded."
        case .content: "This text block could not be changed safely. The original is intact."
        case .save: "Could not serialize the modified PDF."
        case .alreadyUsed: "The text selection has changed. Select the text again."
        case .permission: "The document does not permit content editing."
        case .unsupportedGlyph: "The selected font cannot represent all entered characters. The original text has been kept."
        }
    }
    var russian: String {
        switch self {
        case .document: "Не удалось открыть PDF для редактирования содержимого."
        case .page: "Страница PDF недоступна."
        case .textNotFound: "Здесь нет редактируемого текстового блока. Для текста на скане требуется OCR."
        case .font: "Не удалось загрузить подходящий системный шрифт."
        case .content: "Не удалось безопасно изменить текстовый блок. Оригинал сохранён."
        case .save: "Не удалось сохранить изменённое содержимое PDF."
        case .alreadyUsed: "Выделение изменилось. Выберите текст заново."
        case .permission: "Документ не разрешает редактирование содержимого."
        case .unsupportedGlyph: "Выбранный шрифт не поддерживает все введённые символы. Исходный текст сохранён."
        }
    }
}

@MainActor private enum PDFiumRuntime {
    static let ready: Void = { FPDF_InitLibrary() }()
}
private final class PDFiumDocumentHandle {
    let data: NSData
    let originalData: Data
    let document: FPDF_DOCUMENT
    let page: FPDF_PAGE
    var textPage: FPDF_TEXTPAGE?
    var fonts: [FPDF_FONT] = []
    @MainActor init(data: Data, pageIndex: Int) throws {
        _ = PDFiumRuntime.ready
        self.originalData = data
        self.data = try PDFContentNormalizer.prepare(data,pageIndex: pageIndex) as NSData
        guard let document = FPDF_LoadMemDocument64(self.data.bytes, self.data.length, nil) else { throw PDFSourceError.document }
        guard FPDF_GetDocPermissions(document) & (1 << 3) != 0 else { FPDF_CloseDocument(document); throw PDFSourceError.permission }
        guard let page = FPDF_LoadPage(document, Int32(pageIndex)) else { FPDF_CloseDocument(document); throw PDFSourceError.page }
        self.document = document; self.page = page; textPage = FPDFText_LoadPage(page)
    }
    func closeTextPage() { if let textPage { FPDFText_ClosePage(textPage) }; textPage = nil }
    deinit {
        if let textPage { FPDFText_ClosePage(textPage) }
        FPDF_ClosePage(page)
        for font in fonts { FPDFFont_Close(font) }
        FPDF_CloseDocument(document)
    }
}

struct PDFTextGeometry: Equatable {
    var origin: CGPoint
    var xAxis: CGPoint
    var yAxis: CGPoint
    func point(x: CGFloat, y: CGFloat) -> CGPoint {
        CGPoint(x: origin.x+xAxis.x*x+yAxis.x*y,y: origin.y+xAxis.y*x+yAxis.y*y)
    }
    func local(_ point: CGPoint) -> CGPoint {
        let determinant = xAxis.x*yAxis.y-xAxis.y*yAxis.x
        guard abs(determinant) > 0.00001 else { return .zero }
        let x = point.x-origin.x, y = point.y-origin.y
        return CGPoint(x: (yAxis.y*x-yAxis.x*y)/determinant,y: (-xAxis.y*x+xAxis.x*y)/determinant)
    }
    var angle: CGFloat { atan2(xAxis.y,xAxis.x) }
    func rotated(by radians: CGFloat, around center: CGPoint) -> Self {
        let cosine = cos(radians), sine = sin(radians)
        func rotate(_ p: CGPoint) -> CGPoint { CGPoint(x: cosine*p.x-sine*p.y,y: sine*p.x+cosine*p.y) }
        let offset = rotate(CGPoint(x: origin.x-center.x,y: origin.y-center.y))
        return Self(origin: CGPoint(x: center.x+offset.x,y: center.y+offset.y),xAxis: rotate(xAxis),yAxis: rotate(yAxis))
    }
}

@MainActor
final class PDFSourceSession {
    struct Snapshot {
        let text: String
        let bounds: CGRect
        let fontSize: CGFloat
        let fontName: String
        let color: NSColor
        let width: CGFloat
        let height: CGFloat
        let fragmentCount: Int
        let geometry: PDFTextGeometry
        let leading: CGFloat
        let attributedText: NSAttributedString
    }
    static func documentFonts(data: Data) throws -> [String] { try PDFFontCatalog.names(in: data) }
    struct BlockDescriptor {
        let snapshot: Snapshot
        let point: CGPoint
    }
    private struct Style {
        let url: URL
        let size: CGFloat
        let color: NSColor
        @MainActor var font: CTFont { PDFFontCatalog.font(at: url,size: size) }
    }
    private struct BlockInfo { let id: String; let text: String?; let width: CGFloat?; let height: CGFloat? }
    private struct Fragment {
        let object: FPDF_PAGEOBJECT
        let parent: FPDF_PAGEOBJECT?
        let rootIndex: Int
        let matrix: FS_MATRIX
        let bounds: CGRect
        let text: String
        let style: Style
        let block: BlockInfo?
    }
    private struct EmbeddedFont { let handle: FPDF_FONT; let codes: [UInt32: UInt32]; let unicode: Bool }
    private struct Glyph: Codable { let unicode: UInt32; let origin: CGPoint }
    private struct LayoutRecord: Codable {
        let id: String
        let text: String
        let width: CGFloat
        let height: CGFloat?
        let glyphs: [Glyph]
    }
    private struct GlyphKey: Hashable { let unicode: UInt32; let x: Int; let y: Int }
    private struct LayoutIndex {
        let records: [LayoutRecord]
        let points: [String: [GlyphKey: [CGPoint]]]
        let candidates: [GlyphKey: Set<String>]
        static func key(_ glyph: Glyph) -> GlyphKey { GlyphKey(unicode: glyph.unicode,x: Int(floor(glyph.origin.x*4)),y: Int(floor(glyph.origin.y*4))) }
        static func matches(_ glyph: Glyph,in table: [GlyphKey:[CGPoint]]) -> Bool {
            let key = key(glyph)
            for x in (key.x-1)...(key.x+1) {
                for y in (key.y-1)...(key.y+1) {
                    if table[GlyphKey(unicode: key.unicode,x: x,y: y)]?.contains(where: { hypot($0.x-glyph.origin.x,$0.y-glyph.origin.y) < 0.2 }) == true { return true }
                }
            }
            return false
        }
        init(records: [LayoutRecord], readings: [UInt:[Glyph]]) {
            var live: [GlyphKey:[CGPoint]] = [:]
            for glyph in readings.values.joined() { live[Self.key(glyph),default: []].append(glyph.origin) }
            var accepted: [LayoutRecord] = [], points: [String:[GlyphKey:[CGPoint]]] = [:], candidates: [GlyphKey:Set<String>] = [:]
            for record in records where !record.glyphs.isEmpty && record.width.isFinite && record.width >= 10 && record.width <= 20000 {
                guard record.glyphs.count <= 2_000_000, record.glyphs.allSatisfy({ $0.origin.x.isFinite && $0.origin.y.isFinite && abs($0.origin.x) <= 1_000_000_000 && abs($0.origin.y) <= 1_000_000_000 && Self.matches($0,in: live) }) else { continue }
                accepted.append(record)
                for glyph in record.glyphs {
                    let key = Self.key(glyph)
                    points[record.id,default: [:]][key,default: []].append(glyph.origin)
                    candidates[key,default: []].insert(record.id)
                }
            }
            self.records = accepted; self.points = points; self.candidates = candidates
        }
        func block(for glyphs: [Glyph]) -> BlockInfo? {
            let visible = glyphs.filter { $0.unicode > 32 && UnicodeScalar($0.unicode).map({ !Character(String($0)).isWhitespace }) == true }
            guard let first = visible.first else { return nil }
            let key = Self.key(first); var ids = Set<String>()
            for x in (key.x-1)...(key.x+1) {
                for y in (key.y-1)...(key.y+1) { ids.formUnion(candidates[GlyphKey(unicode: key.unicode,x: x,y: y)] ?? []) }
            }
            for id in ids {
                guard let table = points[id], visible.allSatisfy({ Self.matches($0,in: table) }), let record = records.first(where: { $0.id == id }) else { continue }
                return BlockInfo(id: id,text: record.text,width: record.width,height: record.height)
            }
            return nil
        }
    }
    private static let layoutPrefix = "BotPlus source text blocks v1:"
    static func isLayoutMetadata(_ contents: String) -> Bool { contents.hasPrefix(layoutPrefix) }
    private struct Positioned {
        let fragment: Fragment
        let box: CGRect
        let baseline: CGPoint
    }
    private struct Line {
        let runs: [Positioned]
        let baseline: CGFloat
        let box: CGRect
        let size: CGFloat
        let startsListItem: Bool
        init(runs: [Positioned]) {
            self.runs = runs
            baseline = runs.reduce(0) { $0+$1.baseline.y } / CGFloat(max(1,runs.count))
            box = runs.reduce(CGRect.null) { $0.union($1.box) }
            size = runs.map { $0.fragment.style.size }.max() ?? 12
            let text = runs.map { $0.fragment.text }.joined().trimmingCharacters(in: .whitespaces)
            startsListItem = text.range(of: #"^([•\-–—]|\d+[\).])"#,options: .regularExpression) != nil
        }
    }
    let snapshot: Snapshot
    private let handle: PDFiumDocumentHandle
    private let fragments: [Fragment]
    private let matrix: FS_MATRIX
    private let styles: [Style] // One style per Swift Character in snapshot.text.
    private let leading: CGFloat
    private let selectionPoint: CGPoint
    private var used = false
    private(set) var resultingBounds: CGRect?
    private(set) var resultingPoint: CGPoint?
    private static let identity = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 0,f: 0)
    private struct ParsedPage {
        let data: Data
        let index: Int
        let handle: PDFiumDocumentHandle
        let fragments: [Fragment]
    }
    private static var parsedPage: ParsedPage?

    private static func parsed(data: Data,index: Int,takeOwnership: Bool) throws -> ParsedPage {
        if let cached = parsedPage,cached.index == index,cached.data == data {
            if takeOwnership { parsedPage = nil }
            return cached
        }
        parsedPage = nil
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: index)
        let result = ParsedPage(data: data,index: index,handle: handle,fragments: collectPage(handle))
        // A session takes exclusive ownership before it can mutate PDFium.
        // Never retain an unbounded catalog or share a mutable editing handle.
        if !takeOwnership && data.count <= 64*1024*1024 && result.fragments.count <= 50_000 { parsedPage = result }
        return result
    }

    @MainActor static func editing(data: Data, pageIndex: Int, point: CGPoint) throws -> PDFSourceSession {
        let parsed = try parsed(data: data,index: pageIndex,takeOwnership: true)
        let handle = parsed.handle,all = parsed.fragments
        guard let seed = all.reversed().first(where: { $0.bounds.insetBy(dx: -3,dy: -3).contains(point) }) else { throw PDFSourceError.textNotFound }
        return try makeSession(handle: handle,all: all,seed: seed,point: point)
    }
    static func blocks(data: Data,pageIndex: Int) throws -> [BlockDescriptor] {
        let parsed = try parsed(data: data,index: pageIndex,takeOwnership: false)
        let handle = parsed.handle,all = parsed.fragments
        var consumed = Set<UInt>(), result: [BlockDescriptor] = []
        var groups: [String:[Fragment]] = [:]
        for fragment in all {
            let matrix = fragment.matrix
            let orientation = [matrix.a,matrix.b,matrix.c,matrix.d].map { String(Int(($0*50).rounded())) }.joined(separator: ":")
            let parent = fragment.parent.map { String(UInt(bitPattern: $0)) } ?? "page"
            let size = fragment.block.map { "block:"+$0.id } ?? "size:"+String(Int((fragment.style.size*2).rounded()))
            groups[parent+":"+orientation+":"+size,default: []].append(fragment)
        }
        for group in groups.values {
            guard let first = group.first else { continue }
            let basis = first.matrix, lines = buildLines(all: group,seed: first,basis: basis)
            for seed in group where !consumed.contains(UInt(bitPattern: seed.object)) {
                let point = CGPoint(x: seed.bounds.midX,y: seed.bounds.midY)
                guard let session = try? makeSession(handle: handle,all: group,seed: seed,point: point,reference: basis,cachedLines: lines) else { continue }
                for fragment in session.fragments { consumed.insert(UInt(bitPattern: fragment.object)) }
                result.append(BlockDescriptor(snapshot: session.snapshot,point: point))
            }
        }
        return result
    }
    private static func collectPage(_ handle: PDFiumDocumentHandle) -> [Fragment] {
        guard let textPage = handle.textPage else { return [] }
        let readings = indexedText(textPage)
        let layoutIndex = LayoutIndex(records: readLayouts(handle.page),readings: readings)
        var all: [Fragment] = []
        for index in 0..<max(0,Int(FPDFPage_CountObjects(handle.page))) {
            if let object = FPDFPage_GetObject(handle.page,Int32(index)) {
                collect(object,parent: nil,parentMatrix: identity,rootIndex: index,depth: 0,textPage: textPage,readings: readings,layouts: layoutIndex,into: &all)
            }
        }
        return all
    }
    private static func buildLines(all: [Fragment],seed: Fragment,basis: FS_MATRIX) -> [Line] {
        guard let inverse = inverse(basis) else { return [] }
        let positioned: [Positioned] = all.compactMap { fragment in
            // Separate transformed objects and form instances; never sweep a whole page.
            guard fragment.parent == seed.parent,
                  abs(fragment.matrix.a-basis.a) < 0.02, abs(fragment.matrix.b-basis.b) < 0.02,
                  abs(fragment.matrix.c-basis.c) < 0.02, abs(fragment.matrix.d-basis.d) < 0.02,
                  (seed.block == nil ? (fragment.block == nil && fragment.style.size >= seed.style.size*0.6 && fragment.style.size <= seed.style.size*1.6) : fragment.block?.id == seed.block?.id) else { return nil }
            return Positioned(fragment: fragment,box: transformed(fragment.bounds,by: inverse),baseline: transform(CGPoint(x: CGFloat(fragment.matrix.e),y: CGFloat(fragment.matrix.f)),by: inverse))
        }
        // PDF producers may emit one object per word or per glyph. Cluster by
        // baseline, then split at large gaps so columns/table cells stay separate.
        var rows: [[Positioned]] = []
        for run in positioned.sorted(by: { $0.baseline.y > $1.baseline.y }) {
            if let index = rows.firstIndex(where: { abs($0[0].baseline.y-run.baseline.y) <= min($0[0].fragment.style.size,run.fragment.style.size)*0.28 }) { rows[index].append(run) }
            else { rows.append([run]) }
        }
        var lines: [Line] = []
        for row in rows {
            var current: [Positioned] = []
            for run in row.sorted(by: { $0.baseline.x < $1.baseline.x }) {
                if let previous = current.last, run.box.minX-previous.box.maxX > max(previous.fragment.style.size,run.fragment.style.size)*1.0 {
                    lines.append(Line(runs: current)); current = []
                }
                current.append(run)
            }
            if !current.isEmpty { lines.append(Line(runs: current)) }
        }
        return lines
    }
    private static func makeSession(handle: PDFiumDocumentHandle,all: [Fragment],seed: Fragment,point: CGPoint,reference: FS_MATRIX? = nil,cachedLines: [Line]? = nil) throws -> PDFSourceSession {
        let basis = reference ?? seed.matrix
        let lines = cachedLines ?? buildLines(all: all,seed: seed,basis: basis)
        guard let selected = lines.firstIndex(where: { $0.runs.contains { $0.fragment.object == seed.object } }) else { throw PDFSourceError.textNotFound }
        var chosen = seed.block == nil ? Set([selected]) : Set(lines.indices)
        func adjacent(_ a: Line, _ b: Line) -> Bool {
            let gap = abs(a.baseline-b.baseline), size = max(a.size,b.size)
            guard gap >= size*0.75 && gap <= size*1.65,
                  abs(a.size-b.size) <= size*0.12,
                  abs(a.box.minX-b.box.minX) <= size*0.75 else { return false }
            let lower = a.baseline < b.baseline ? a : b
            if lower.startsListItem { return false }
            let overlap = min(a.box.maxX,b.box.maxX)-max(a.box.minX,b.box.minX)
            return overlap >= min(a.box.width,b.box.width)*0.6
        }
        // Walk only nearest aligned lines above/below, not every nearby object.
        var changed = true
        while changed && seed.block == nil {
            changed = false
            for index in Array(chosen) {
                for direction: CGFloat in [-1,1] {
                    let candidate = lines.indices.filter { !chosen.contains($0) && (lines[$0].baseline-lines[index].baseline)*direction > 0 && adjacent(lines[index],lines[$0]) }
                        .min { abs(lines[$0].baseline-lines[index].baseline) < abs(lines[$1].baseline-lines[index].baseline) }
                    if let candidate { chosen.insert(candidate); changed = true }
                }
            }
        }
        let block = chosen.map { lines[$0] }.sorted { $0.baseline > $1.baseline }
        var text = "", styles: [Style] = [], selectedFragments: [Fragment] = []
        for (lineIndex,line) in block.enumerated() {
            if lineIndex > 0 { text += " "; styles.append(line.runs[0].fragment.style) }
            var previous: Positioned?
            var visualRuns: [Positioned] = []
            for run in line.runs {
                selectedFragments.append(run.fragment)
                if visualRuns.contains(where: {
                    $0.fragment.text == run.fragment.text && $0.fragment.style.color.isEqual(run.fragment.style.color) &&
                    abs($0.fragment.style.size-run.fragment.style.size) < 0.01 &&
                    hypot($0.baseline.x-run.baseline.x,$0.baseline.y-run.baseline.y) < 0.05
                }) { continue }
                visualRuns.append(run)
                if let previous, !text.hasSuffix(" "), !run.fragment.text.hasPrefix(" "),
                   !",.;:!?)]}".contains(run.fragment.text.first ?? " "),
                   !"([{“".contains(text.last ?? " "),
                   run.box.minX-previous.box.maxX > min(previous.fragment.style.size,run.fragment.style.size)*0.18 {
                    text += " "; styles.append(run.fragment.style)
                }
                text += run.fragment.text
                styles.append(contentsOf: Array(repeating: run.fragment.style,count: run.fragment.text.count))
                previous = run
            }
        }
        let localBox = block.reduce(CGRect.null) { $0.union($1.box) }
        var placement = basis
        let startX = block[0].runs.map { $0.baseline.x }.min() ?? localBox.minX
        let start = transform(CGPoint(x: startX,y: block[0].baseline),by: basis)
        placement.e = Float(start.x); placement.f = Float(start.y)
        let bounds = selectedFragments.reduce(CGRect.null) { $0.union($1.bounds) }
        let gaps = zip(block,block.dropFirst()).map { $0.baseline-$1.baseline }.sorted()
        let leading = gaps.isEmpty ? seed.style.size*1.2 : gaps[gaps.count/2]
        if let logical = seed.block?.text,
           logical.filter({ !$0.isWhitespace }) == text.filter({ !$0.isWhitespace }) {
            styles = remapStyles(from: text,styles: styles,to: logical); text = logical
        }
        if styles.isEmpty { styles = [seed.style] }
        let width = seed.block?.width ?? max(20,localBox.maxX-startX+1)
        let fieldHeight = max(seed.style.size*1.3,seed.block?.height ?? localBox.height)
        let container = transformed(CGRect(x: startX,y: block[0].baseline+seed.style.size*0.85-fieldHeight,width: width,height: fieldHeight),by: basis).union(bounds)
        let snapshot = Snapshot(text: text,bounds: container,fontSize: seed.style.size,fontName: seed.style.url.deletingPathExtension().lastPathComponent,color: seed.style.color,width: width,height: fieldHeight,fragmentCount: selectedFragments.count,geometry: geometry(placement),leading: leading,attributedText: attributed(text,styles: styles,leading: leading))
        return PDFSourceSession(handle: handle,fragments: selectedFragments,matrix: placement,styles: styles,leading: leading,selectionPoint: point,snapshot: snapshot)
    }
    @MainActor static func adding(data: Data, pageIndex: Int, point: CGPoint, fontSize: CGFloat, color: NSColor, fontName: String = "Arial") throws -> PDFSourceSession {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let url = try systemFontURL(fontName)
        let matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: Float(point.x),f: Float(point.y))
        let snapshot = Snapshot(text: "",bounds: CGRect(x: point.x,y: point.y,width: 240,height: max(20,fontSize*1.2)),fontSize: fontSize,fontName: url.deletingPathExtension().lastPathComponent,color: color,width: 240,height: fontSize*1.3,fragmentCount: 0,geometry: geometry(matrix),leading: fontSize*1.2,attributedText: NSAttributedString(string: ""))
        return PDFSourceSession(handle: handle,fragments: [],matrix: matrix,styles: [Style(url: url,size: fontSize,color: color)],leading: fontSize*1.2,selectionPoint: point,snapshot: snapshot)
    }
    private init(handle: PDFiumDocumentHandle, fragments: [Fragment], matrix: FS_MATRIX, styles: [Style], leading: CGFloat, selectionPoint: CGPoint, snapshot: Snapshot) {
        self.handle = handle; self.fragments = fragments; self.matrix = matrix; self.styles = styles; self.leading = leading; self.selectionPoint = selectionPoint; self.snapshot = snapshot
    }

    private static func geometry(_ matrix: FS_MATRIX) -> PDFTextGeometry {
        PDFTextGeometry(origin: CGPoint(x: CGFloat(matrix.e),y: CGFloat(matrix.f)),xAxis: CGPoint(x: CGFloat(matrix.a),y: CGFloat(matrix.b)),yAxis: CGPoint(x: CGFloat(matrix.c),y: CGFloat(matrix.d)))
    }
    private static func attributed(_ text: String,styles: [Style],leading: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        var offset = 0
        for (character,style) in zip(text,styles) {
            let name = CTFontCopyPostScriptName(style.font) as String
            let font = NSFont(name: name,size: style.size) ?? NSFont.systemFont(ofSize: style.size)
            let length = String(character).utf16.count
            result.addAttributes([.font: font,.foregroundColor: style.color],range: NSRange(location: offset,length: length)); offset += length
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.minimumLineHeight = leading
        result.addAttribute(.paragraphStyle,value: paragraph,range: NSRange(location: 0,length: result.length))
        return result
    }
    private func styles(from attributed: NSAttributedString, text: String) throws -> [Style] {
        guard attributed.string == text else { throw PDFSourceError.content }
        var result: [Style] = [], offset = 0
        for character in text {
            let attributes = attributed.attributes(at: offset,effectiveRange: nil)
            let font = attributes[.font] as? NSFont ?? NSFont(name: snapshot.fontName,size: snapshot.fontSize) ?? NSFont.systemFont(ofSize: snapshot.fontSize)
            let color = attributes[.foregroundColor] as? NSColor ?? snapshot.color
            result.append(Style(url: try Self.systemFontURL(font.fontName),size: min(2000,max(1,font.pointSize)),color: color))
            offset += String(character).utf16.count
        }
        return result
    }

    func previewWithoutSelectedText() throws -> Data {
        handle.closeTextPage()
        for fragment in fragments {
            guard FPDFPageObj_SetIsActive(fragment.object,0) != 0 else { throw PDFSourceError.content }
        }
        // PDFium may serialize /Contents [] after hiding the last page object.
        // PDFKit diagnoses that empty stream array. A transparent path keeps
        // the preview content stream valid without painting a text-field mask.
        guard let spacer = FPDFPageObj_CreateNewRect(0,0,0.01,0.01) else { throw PDFSourceError.content }
        _ = FPDFPageObj_SetFillColor(spacer,0,0,0,0)
        _ = FPDFPath_SetDrawMode(spacer,FPDF_FILLMODE_WINDING,0)
        FPDFPage_InsertObject(handle.page,spacer)
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length),length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        return Data(bytes: bytes,count: length)
    }
    struct ContentObject {
        let kind: String
        let bounds: CGRect
        let pixelSize: CGSize?
        var index: Int = -1
        var stroke: NSColor? = nil
        var fill: NSColor? = nil
        var lineWidth: CGFloat = 1
        var opacity: CGFloat = 1
        var strokeEnabled = false
        var fillEnabled = false
        var fillRule: Int32 = 0
    }
    static func objectInfo(data: Data,pageIndex: Int,point: CGPoint) throws -> ContentObject? {
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        @MainActor func find(_ object: FPDF_PAGEOBJECT,transform parent: FS_MATRIX,depth: Int) -> ContentObject? {
            guard depth < 32 else { return nil }
            let type = FPDFPageObj_GetType(object)
            if type == FPDF_PAGEOBJ_FORM {
                var local = identity; guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return nil }
                let transform = multiply(parent,local)
                for i in (0..<max(0,Int(FPDFFormObj_CountObjects(object)))).reversed() {
                    if let child = FPDFFormObj_GetObject(object,UInt(i)),let found = find(child,transform: transform,depth: depth+1) { return found }
                }
                return nil
            }
            guard type == FPDF_PAGEOBJ_IMAGE || type == FPDF_PAGEOBJ_PATH,let bounds = bounds(object) else { return nil }
            let world = transformed(bounds,by: parent)
            guard !world.isEmpty,world.insetBy(dx: -2,dy: -2).contains(point) else { return nil }
            if type == FPDF_PAGEOBJ_IMAGE {
                var width: UInt32 = 0,height: UInt32 = 0
                _ = FPDFImageObj_GetImagePixelSize(object,&width,&height)
                return ContentObject(kind: "image",bounds: world,pixelSize: CGSize(width: Int(width),height: Int(height)))
            }
            // A large rectangle enclosing a page is not a selectable object on
            // every empty click. Paths require a click close to their edges.
            let nearEdge = min(abs(point.x-world.minX),abs(point.x-world.maxX),abs(point.y-world.minY),abs(point.y-world.maxY)) < 3
            return nearEdge ? ContentObject(kind: "path",bounds: world,pixelSize: nil) : nil
        }
        for i in (0..<max(0,Int(FPDFPage_CountObjects(handle.page)))).reversed() {
            if let object = FPDFPage_GetObject(handle.page,Int32(i)),let found = find(object,transform: identity,depth: 0) { return found }
        }
        return nil
    }

    /// Preserve styles on unchanged characters. Insertions inherit their neighbor;
    /// explicit size/color controls apply to the entire selected block.
    private func editedStyles(_ text: String, size: CGFloat, color: NSColor) -> [Style] {
        let result = Self.remapStyles(from: snapshot.text,styles: styles,to: text)
        return result.map { Style(url: $0.url,size: abs(size-snapshot.fontSize) < 0.01 ? $0.size : size,color: color.isEqual(snapshot.color) ? $0.color : color) }
    }

    private static func remapStyles(from originalText: String, styles originalStyles: [Style], to text: String) -> [Style] {
        let old = Array(originalText), new = Array(text)
        var result = Array(originalStyles.prefix(old.count))
        let fallback = originalStyles.first!
        let difference = new.difference(from: old)
        let removed = difference.removals.compactMap { change -> Int? in
            if case let .remove(offset,_,_) = change { return offset }; return nil
        }.sorted(by: >)
        for offset in removed { result.remove(at: offset) }
        let inserted = difference.insertions.compactMap { change -> Int? in
            if case let .insert(offset,_,_) = change { return offset }; return nil
        }.sorted()
        for offset in inserted {
            let inherited = result.isEmpty ? fallback : result[min(max(0,offset-1),result.count-1)]
            result.insert(inherited,at: offset)
        }
        return result
    }

    @MainActor func applying(text: String, fontSize: CGFloat, color: NSColor, width: CGFloat? = nil, height: CGFloat? = nil, richText: NSAttributedString? = nil, geometry: PDFTextGeometry? = nil) throws -> Data {
        guard !used else { throw PDFSourceError.alreadyUsed }; used = true
        guard !text.contains("\0"), fontSize.isFinite, fontSize > 0 else { throw PDFSourceError.content }
        let normalized = text.replacingOccurrences(of: "\r\n",with: "\n").replacingOccurrences(of: "\r",with: "\n")
        let blockWidth = width ?? snapshot.width
        let blockHeight = height ?? snapshot.height
        guard blockWidth.isFinite, blockWidth >= 10, blockWidth <= 20_000, blockHeight.isFinite, blockHeight >= 1, blockHeight <= 20_000 else { throw PDFSourceError.content }
        if richText == nil && geometry == nil && normalized == snapshot.text && abs(fontSize-snapshot.fontSize) < 0.01 && color.isEqual(snapshot.color) && abs(blockWidth-snapshot.width) < 0.01 && abs(blockHeight-snapshot.height) < 0.01 {
            resultingBounds = snapshot.bounds; resultingPoint = selectionPoint; return handle.originalData
        }
        let characterStyles = try richText.map { try styles(from: $0,text: normalized) } ?? editedStyles(normalized,size: fontSize,color: color)
        let pose = geometry ?? snapshot.geometry
        guard [pose.origin.x,pose.origin.y,pose.xAxis.x,pose.xAxis.y,pose.yAxis.x,pose.yAxis.y].allSatisfy({ $0.isFinite }), abs(pose.xAxis.x*pose.yAxis.y-pose.xAxis.y*pose.yAxis.x) > 0.00001 else { throw PDFSourceError.content }
        let placementMatrix = FS_MATRIX(a: Float(pose.xAxis.x),b: Float(pose.xAxis.y),c: Float(pose.yAxis.x),d: Float(pose.yAxis.y),e: Float(pose.origin.x),f: Float(pose.origin.y))
        let attributed = NSMutableAttributedString(string: normalized)
        var offset = 0
        for (character,style) in zip(normalized,characterStyles) {
            let units = Array(String(character).utf16)
            if !character.isWhitespace {
                var glyphs = [CGGlyph](repeating: 0,count: units.count)
                guard CTFontGetGlyphsForCharacters(style.font,units,&glyphs,units.count) else { throw PDFSourceError.unsupportedGlyph }
            }
            attributed.addAttributes([NSAttributedString.Key(kCTFontAttributeName as String): style.font,NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,NSAttributedString.Key(kCTLigatureAttributeName as String): 0],range: NSRange(location: offset,length: units.count))
            offset += units.count
        }
        let originalReadings = handle.textPage.map(Self.indexedText) ?? [:]
        var layoutRecords = LayoutIndex(records: Self.readLayouts(handle.page),readings: originalReadings).records
        let replacedIDs = Set(fragments.compactMap { $0.block?.id })
        layoutRecords.removeAll { replacedIDs.contains($0.id) }
        handle.closeTextPage()
        var loadedFonts: [URL: EmbeddedFont] = [:]
        @MainActor func load(_ url: URL) throws -> EmbeddedFont {
            if let existing = loadedFonts[url] { return existing }
            let data = try Data(contentsOf: url)
            guard data.count <= Int(UInt32.max) else { throw PDFSourceError.font }
            if data.starts(with: [0x4f,0x54,0x54,0x4f]) {
                let loaded = data.withUnsafeBytes { FPDFText_LoadFont(handle.document,$0.bindMemory(to: UInt8.self).baseAddress,UInt32(data.count),FPDF_FONT_TYPE1,1) }
                guard let loaded else { throw PDFSourceError.font }
                let embedded = EmbeddedFont(handle: loaded,codes: [:],unicode: true)
                loadedFonts[url] = embedded; handle.fonts.append(loaded); return embedded
            }
            let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary),12,nil)
            // Keep CID == glyph ID for PDFKit's save path on macOS 14/15.
            // The explicit ToUnicode map still prevents automatic cmap aliases
            // from turning '-' into soft hyphen or ';' into Greek question mark.
            let scalars = Array(Set(zip(normalized,characterStyles).filter { $0.1.url == url }.flatMap { String($0.0).unicodeScalars.filter { $0 != "\n" }.map(\.value) })).sorted()
            guard scalars.count < 65_535 else { throw PDFSourceError.content }
            var glyphMap: [UInt8] = [0,0], codes: [UInt32: UInt32] = [:], mappings: [String] = []
            var unicodeForGlyph: [CGGlyph: UInt32] = [:]
            for scalar in scalars {
                let unicode = UnicodeScalar(scalar)!
                let units = Array(String(unicode).utf16)
                var glyphs = [CGGlyph](repeating: 0,count: units.count)
                let supported = CTFontGetGlyphsForCharacters(font,units,&glyphs,units.count)
                guard supported || Character(String(unicode)).isWhitespace else { throw PDFSourceError.unsupportedGlyph }
                let glyph = glyphs[0], cid = UInt32(glyph)
                if let previous = unicodeForGlyph[glyph], previous != scalar {
                    guard Character(String(UnicodeScalar(previous)!)).isWhitespace && Character(String(unicode)).isWhitespace else { throw PDFSourceError.unsupportedGlyph }
                    codes[scalar] = cid; continue
                }
                unicodeForGlyph[glyph] = scalar
                codes[scalar] = cid
                while glyphMap.count < (Int(glyph)+1)*2 { glyphMap.append(0) }
                glyphMap[Int(glyph)*2] = UInt8(glyph >> 8); glyphMap[Int(glyph)*2+1] = UInt8(glyph & 255)
                mappings.append(String(format: "<%04X> <%@>",UInt32(cid),units.map { String(format: "%04X",UInt32($0)) }.joined()))
            }
            var cmap = "/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n/CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> def\n/CMapName /BotPlusUnicode def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n"
            for start in stride(from: 0,to: mappings.count,by: 100) {
                let chunk = mappings[start..<min(start+100,mappings.count)]
                cmap += "\(chunk.count) beginbfchar\n"+chunk.joined(separator: "\n")+"\nendbfchar\n"
            }
            cmap += "endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n"
            let loaded = data.withUnsafeBytes { bytes in
                cmap.withCString { cmapBytes in
                    glyphMap.withUnsafeBufferPointer { map in
                        FPDFText_LoadCidType2Font(handle.document,bytes.bindMemory(to: UInt8.self).baseAddress,UInt32(data.count),cmapBytes,map.baseAddress,UInt32(glyphMap.count))
                    }
                }
            }
            guard let loaded else { throw PDFSourceError.font }
            let embedded = EmbeddedFont(handle: loaded,codes: codes,unicode: false)
            loadedFonts[url] = embedded; handle.fonts.append(loaded); return embedded
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var objects: [FPDF_PAGEOBJECT] = [], cursor = 0, baseline: CGFloat = 0
        let blockName = "BotPlusTextBlock_"+UUID().uuidString.replacingOccurrences(of: "-",with: "")
        var sharedMark: FPDF_PAGEOBJECTMARK?
        let nsText = normalized as NSString
        do {
            while cursor < attributed.length {
                let count = max(1,CTTypesetterSuggestLineBreak(typesetter,cursor,Double(blockWidth)))
                let line = CTTypesetterCreateLine(typesetter,CFRange(location: cursor,length: count))
                let runs = CTLineGetGlyphRuns(line) as! [CTRun]
                for run in runs {
                    let range = CTRunGetStringRange(run)
                    let substring = nsText.substring(with: NSRange(location: range.location,length: range.length)).trimmingCharacters(in: .newlines)
                    guard !substring.isEmpty else { continue }
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    let ctFont = attributes[kCTFontAttributeName] as! CTFont
                    let postScriptName = CTFontCopyPostScriptName(ctFont) as String
                    let url = try characterStyles.first(where: { CTFontCopyPostScriptName($0.font) as String == postScriptName })?.url ?? Self.systemFontURL(postScriptName)
                    let font = try load(url)
                    guard let object = FPDFPageObj_CreateTextObj(handle.document,font.handle,Float(CTFontGetSize(ctFont))) else { throw PDFSourceError.font }
                    let codes = substring.unicodeScalars.compactMap { font.codes[$0.value] }
                    let success: Bool
                    if font.unicode {
                        let units = Array(substring.utf16)+[0]
                        success = units.withUnsafeBufferPointer { FPDFText_SetText(object,$0.baseAddress) } != 0
                    } else {
                        success = codes.count == substring.unicodeScalars.count && codes.withUnsafeBufferPointer { FPDFText_SetCharcodes(object,$0.baseAddress,$0.count) } != 0
                    }
                    guard success else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    var position = CGPoint.zero
                    CTRunGetPositions(run,CFRange(location: 0,length: 1),&position)
                    if substring.unicodeScalars.count > 1 {
                        var positions: [Float] = [], utf16Index = range.location
                        for (index,scalar) in substring.unicodeScalars.enumerated() {
                            if index > 0 { positions.append(Float(CTLineGetOffsetForStringIndex(line,utf16Index,nil)-position.x)) }
                            utf16Index += scalar.value > 0xFFFF ? 2 : 1
                        }
                        guard positions.withUnsafeBufferPointer({ FPDFText_SetPositions(object,$0.baseAddress,$0.count) }) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    }
                    var placement = placementMatrix
                    placement.e += placementMatrix.a*Float(position.x)+placementMatrix.c*Float(baseline+position.y)
                    placement.f += placementMatrix.b*Float(position.x)+placementMatrix.d*Float(baseline+position.y)
                    guard FPDFPageObj_SetMatrix(object,&placement) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    let cgColor = attributes[kCTForegroundColorAttributeName] as! CGColor
                    let rgb = NSColor(cgColor: cgColor)?.usingColorSpace(.deviceRGB) ?? .black
                    _ = FPDFPageObj_SetFillColor(object,UInt32((rgb.redComponent*255).rounded()),UInt32((rgb.greenComponent*255).rounded()),UInt32((rgb.blueComponent*255).rounded()),UInt32((rgb.alphaComponent*255).rounded()))
                    if let sharedMark {
                        guard FPDFPageObj_AddExistingMark(object,sharedMark) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    } else {
                        let mark = blockName.withCString { FPDFPageObj_AddMark(object,$0) }
                        guard let mark else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                        let body = Data(normalized.utf8).base64EncodedString()
                        guard body.withCString({ FPDFPageObjMark_SetStringParam(handle.document,object,mark,"Body",$0) }) != 0,
                              FPDFPageObjMark_SetFloatParam(handle.document,object,mark,"Width",Float(blockWidth)) != 0,
                              FPDFPageObjMark_SetFloatParam(handle.document,object,mark,"Height",Float(blockHeight)) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                        sharedMark = mark
                    }
                    objects.append(object)
                }
                var ascent: CGFloat = 0, descent: CGFloat = 0, lineLeading: CGFloat = 0
                _ = CTLineGetTypographicBounds(line,&ascent,&descent,&lineLeading)
                baseline -= max(leading*fontSize/snapshot.fontSize,ascent+descent+lineLeading)
                cursor += count
            }
        } catch { for object in objects { FPDFPageObj_Destroy(object) }; throw error }
        // All replacement glyphs and objects exist before removing anything.
        let firstRoot = fragments.map(\.rootIndex).min() ?? Int(FPDFPage_CountObjects(handle.page))
        let insertion = firstRoot + (fragments.first?.parent == nil ? 0 : 1)
        for fragment in fragments {
            let removed = fragment.parent.map { FPDFFormObj_RemoveObject($0,fragment.object) } ?? FPDFPage_RemoveObject(handle.page,fragment.object)
            guard removed != 0 else { for object in objects { FPDFPageObj_Destroy(object) }; throw PDFSourceError.content }
            FPDFPageObj_Destroy(fragment.object)
        }
        for (index,object) in objects.enumerated() {
            if FPDFPage_InsertObjectAtIndex(handle.page,object,insertion+index) == 0 {
                for remaining in objects[index...] { FPDFPageObj_Destroy(remaining) }; throw PDFSourceError.content
            }
        }
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        var union = CGRect.null
        for object in objects { if let rect = Self.bounds(object) { union = union.union(rect) } }
        let maximumSize = characterStyles.map(\.size).max() ?? fontSize
        let finalHeight = max(blockHeight,maximumSize*1.3,abs(baseline))
        let container = Self.transformed(CGRect(x: 0,y: maximumSize*0.85-finalHeight,width: blockWidth,height: finalHeight),by: placementMatrix)
        resultingBounds = union.isNull ? nil : union.union(container)
        if let first = objects.compactMap({ Self.bounds($0) }).first(where: { !$0.isEmpty }) {
            resultingPoint = CGPoint(x: first.midX,y: first.midY)
        }
        // Validate each generated object's text, not a clipped/partial page selection.
        if let check = FPDFText_LoadPage(handle.page) {
            defer { FPDFText_ClosePage(check) }
            let actual = objects.compactMap { try? Self.text(of: $0,in: check) }.joined()
            let index = Self.indexedText(check)
            let glyphs = objects.flatMap { index[UInt(bitPattern: $0)] ?? [] }.filter { $0.unicode > 32 && UnicodeScalar($0.unicode).map({ !Character(String($0)).isWhitespace }) == true }
            if !glyphs.isEmpty { layoutRecords.append(LayoutRecord(id: blockName,text: normalized,width: blockWidth,height: finalHeight,glyphs: glyphs)) }
            let expected = normalized.filter { !$0.isWhitespace }
            guard actual.filter({ !$0.isWhitespace }) == expected else { throw PDFSourceError.content }
        } else if !objects.isEmpty { throw PDFSourceError.content }
        try Self.writeLayouts(layoutRecords,page: handle.page)
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length), length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        return Data(bytes: bytes,count: length)
    }

    private static func collect(_ object: FPDF_PAGEOBJECT, parent: FPDF_PAGEOBJECT?, parentMatrix: FS_MATRIX, rootIndex: Int, depth: Int, textPage: FPDF_TEXTPAGE, readings: [UInt: [Glyph]]? = nil, layouts: LayoutIndex? = nil, into result: inout [Fragment]) {
        guard depth < 32 else { return }
        if FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_FORM {
            var local = identity
            guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return }
            for index in 0..<max(0,Int(FPDFFormObj_CountObjects(object))) {
                if let child = FPDFFormObj_GetObject(object,UInt(index)) { collect(child,parent: object,parentMatrix: multiply(parentMatrix,local),rootIndex: rootIndex,depth: depth+1,textPage: textPage,readings: readings,layouts: layouts,into: &result) }
            }
            return
        }
        guard FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_TEXT else { return }
        let mode = FPDFTextObj_GetTextRenderMode(object)
        // Clipping text also controls other artwork; do not destructively rewrite it.
        guard mode == FPDF_TEXTRENDERMODE_FILL || mode == FPDF_TEXTRENDERMODE_STROKE || mode == FPDF_TEXTRENDERMODE_FILL_STROKE else { return }
        guard let rect = bounds(object), let rawText = try? text(of: object,in: textPage), !rawText.isEmpty else { return }
        let text = readings?[UInt(bitPattern: object)].map(uniqueText) ?? rawText
        guard !text.isEmpty else { return }
        var local = identity
        guard FPDFPageObj_GetMatrix(object,&local) != 0 else { return }
        var effective = multiply(parentMatrix,local)
        let scale = max(0.0001,hypot(effective.c,effective.d))
        var size: Float = 12; _ = FPDFTextObj_GetFontSize(object,&size)
        let physicalSize = CGFloat(size*scale)
        effective.a /= scale; effective.b /= scale; effective.c /= scale; effective.d /= scale
        guard let url = try? systemFontURL(fontName(of: object)) else { return }
        var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 255
        _ = FPDFPageObj_GetFillColor(object,&r,&g,&b,&a)
        let color = NSColor(calibratedRed: CGFloat(r)/255,green: CGFloat(g)/255,blue: CGFloat(b)/255,alpha: CGFloat(a)/255)
        result.append(Fragment(object: object,parent: parent,rootIndex: rootIndex,matrix: effective,bounds: transformed(rect,by: parentMatrix),text: text,style: Style(url: url,size: max(1,physicalSize),color: color),block: blockInfo(object) ?? layouts?.block(for: readings?[UInt(bitPattern: object)] ?? [])))
    }
    private static func annotationContents(_ annotation: FPDF_ANNOTATION) -> String? {
        let length = FPDFAnnot_GetStringValue(annotation,"Contents",nil,0)
        guard length >= 2 && length < 32_000_000 else { return nil }
        var units = [UInt16](repeating: 0,count: Int(length/2))
        _ = units.withUnsafeMutableBufferPointer { FPDFAnnot_GetStringValue(annotation,"Contents",$0.baseAddress,length) }
        return String(decoding: units.prefix { $0 != 0 },as: UTF16.self)
    }
    private static func readLayouts(_ page: FPDF_PAGE) -> [LayoutRecord] {
        for index in 0..<max(0,FPDFPage_GetAnnotCount(page)) {
            guard let annotation = FPDFPage_GetAnnot(page,index) else { continue }
            defer { FPDFPage_CloseAnnot(annotation) }
            guard let contents = annotationContents(annotation), contents.hasPrefix(layoutPrefix),
                  let data = Data(base64Encoded: String(contents.dropFirst(layoutPrefix.count))),
                  let records = try? JSONDecoder().decode([LayoutRecord].self,from: data) else { continue }
            return records
        }
        return []
    }
    private static func writeLayouts(_ records: [LayoutRecord], page: FPDF_PAGE) throws {
        let count = max(0,FPDFPage_GetAnnotCount(page))
        if count > 0 {
            for index in (0..<count).reversed() {
                guard let annotation = FPDFPage_GetAnnot(page,index) else { continue }
                let metadata = annotationContents(annotation).map(isLayoutMetadata) ?? false
                FPDFPage_CloseAnnot(annotation)
                if metadata && FPDFPage_RemoveAnnot(page,index) == 0 { throw PDFSourceError.content }
            }
        }
        guard !records.isEmpty else { return }
        let body = layoutPrefix+(try JSONEncoder().encode(records)).base64EncodedString()
        let units = Array(body.utf16)+[0]
        guard let annotation = FPDFPage_CreateAnnot(page,FPDF_ANNOT_FREETEXT) else { throw PDFSourceError.content }
        defer { FPDFPage_CloseAnnot(annotation) }
        var rect = FS_RECTF(left: 0,top: 1,right: 1,bottom: 0)
        guard units.withUnsafeBufferPointer({ FPDFAnnot_SetStringValue(annotation,"Contents",$0.baseAddress) }) != 0,
              FPDFAnnot_SetFlags(annotation,FPDF_ANNOT_FLAG_HIDDEN | FPDF_ANNOT_FLAG_NOVIEW) != 0,
              FPDFAnnot_SetRect(annotation,&rect) != 0 else { throw PDFSourceError.content }
    }

    private static func blockInfo(_ object: FPDF_PAGEOBJECT) -> BlockInfo? {
        for index in 0..<max(0,FPDFPageObj_CountMarks(object)) {
            guard let mark = FPDFPageObj_GetMark(object,UInt(index)) else { continue }
            var length: UInt = 0
            guard FPDFPageObjMark_GetName(mark,nil,0,&length) != 0, length > 0, length < 4096 else { continue }
            var buffer = [UInt16](repeating: 0,count: Int(length/2))
            _ = buffer.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetName(mark,$0.baseAddress,length,&length) }
            let name = String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
            guard name.hasPrefix("BotPlusTextBlock_") else { continue }
            var body: String?
            if FPDFPageObjMark_GetParamStringValue(mark,"Body",nil,0,&length) != 0, length > 0, length < 12_000_000 {
                buffer = [UInt16](repeating: 0,count: Int(length/2))
                _ = buffer.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetParamStringValue(mark,"Body",$0.baseAddress,length,&length) }
                let encoded = String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
                if let data = Data(base64Encoded: encoded) { body = String(data: data,encoding: .utf8) }
            }
            var width: Float = 0
            let validWidth = FPDFPageObjMark_GetParamFloatValue(mark,"Width",&width) != 0 && width.isFinite && width >= 10 && width <= 20000
            var height: Float = 0
            let validHeight = FPDFPageObjMark_GetParamFloatValue(mark,"Height",&height) != 0 && height.isFinite && height > 0 && height <= 20000
            return BlockInfo(id: name,text: body,width: validWidth ? CGFloat(width) : nil,height: validHeight ? CGFloat(height) : nil)
        }
        return nil
    }
    private static func indexedText(_ page: FPDF_TEXTPAGE) -> [UInt: [Glyph]] {
        var result: [UInt: [Glyph]] = [:]
        for index in 0..<max(0,FPDFText_CountChars(page)) {
            guard let object = FPDFText_GetTextObject(page,index), FPDFText_IsGenerated(page,index) != 1 else { continue }
            let unicode = FPDFText_GetUnicode(page,index)
            var x: Double = 0, y: Double = 0
            guard unicode != 0, FPDFText_GetCharOrigin(page,index,&x,&y) != 0, x.isFinite, y.isFinite, abs(x) <= 1_000_000_000, abs(y) <= 1_000_000_000 else { continue }
            result[UInt(bitPattern: object),default: []].append(Glyph(unicode: unicode,origin: CGPoint(x: x,y: y)))
        }
        return result
    }
    /// CAD exporters often draw an identical string twice at coincident positions
    /// (synthetic weight). Remove repeated drawing passes, not repeated letters.
    private static func uniqueText(_ glyphs: [Glyph]) -> String {
        func same(_ a: Glyph, _ b: Glyph) -> Bool {
            a.unicode == b.unicode && hypot(a.origin.x-b.origin.x,a.origin.y-b.origin.y) < 0.05
        }
        var accepted: [Glyph] = [], index = 0
        while index < glyphs.count {
            var duplicate = 0
            for start in accepted.indices where same(accepted[start],glyphs[index]) {
                let length = accepted.count-start
                if length >= 2, index+length <= glyphs.count,
                   (0..<length).allSatisfy({ same(accepted[start+$0],glyphs[index+$0]) }) {
                    duplicate = length; break
                }
            }
            if duplicate > 0 { index += duplicate }
            else { accepted.append(glyphs[index]); index += 1 }
        }
        return String(String.UnicodeScalarView(accepted.compactMap { UnicodeScalar($0.unicode) }))
    }
    private static func bounds(_ object: FPDF_PAGEOBJECT) -> CGRect? {
        var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
        guard FPDFPageObj_GetBounds(object,&l,&b,&r,&t) != 0 else { return nil }
        return CGRect(x: Double(l),y: Double(b),width: Double(r-l),height: Double(t-b))
    }
    private static func text(of object: FPDF_PAGEOBJECT, in page: FPDF_TEXTPAGE) throws -> String {
        let length = FPDFTextObj_GetText(object,page,nil,0)
        guard length > 0 && length <= 4_194_304 else { throw PDFSourceError.textNotFound }
        var buffer = [UInt16](repeating: 0,count: Int(length/2))
        _ = buffer.withUnsafeMutableBufferPointer { FPDFTextObj_GetText(object,page,$0.baseAddress,length) }
        return String(decoding: buffer.prefix { $0 != 0 },as: UTF16.self)
    }
    private static func fontName(of object: FPDF_PAGEOBJECT) -> String {
        guard let font = FPDFTextObj_GetFont(object) else { return "Arial" }
        let count = FPDFFont_GetBaseFontName(font,nil,0)
        guard count > 0 && count < 16_384 else { return "Arial" }
        var buffer = [CChar](repeating: 0,count: count)
        _ = buffer.withUnsafeMutableBufferPointer { FPDFFont_GetBaseFontName(font,$0.baseAddress,count) }
        let name = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },as: UTF8.self)
        return name.split(separator: "+").last.map(String.init) ?? "Arial"
    }
    private static func systemFontURL(_ name: String) throws -> URL {
        if let extracted = try? PDFFontCatalog.url(for: name) { return extracted }
        let font = CTFontCreateWithName(name as CFString,12,nil)
        if let url = CTFontCopyAttribute(font,kCTFontURLAttribute) as? URL, url.pathExtension.lowercased() == "ttf", FileManager.default.isReadableFile(atPath: url.path) { return url }
        let lower = name.lowercased()
        let style = lower.contains("bold") ? (lower.contains("italic") || lower.contains("oblique") ? " Bold Italic" : " Bold") : (lower.contains("italic") || lower.contains("oblique") ? " Italic" : "")
        let family = lower.contains("times") ? "Times New Roman" : (lower.contains("courier") ? "Courier New" : "Arial")
        for candidate in [family+style,"Arial"+style,"Arial"] {
            let url = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental/"+candidate+".ttf")
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        throw PDFSourceError.font
    }
    private static func multiply(_ p: FS_MATRIX, _ q: FS_MATRIX) -> FS_MATRIX {
        FS_MATRIX(a: p.a*q.a+p.c*q.b,b: p.b*q.a+p.d*q.b,c: p.a*q.c+p.c*q.d,d: p.b*q.c+p.d*q.d,e: p.a*q.e+p.c*q.f+p.e,f: p.b*q.e+p.d*q.f+p.f)
    }
    private static func inverse(_ m: FS_MATRIX) -> FS_MATRIX? {
        let determinant = m.a*m.d-m.b*m.c
        guard abs(determinant) > 0.00001 else { return nil }
        return FS_MATRIX(a: m.d/determinant,b: -m.b/determinant,c: -m.c/determinant,d: m.a/determinant,e: (m.c*m.f-m.d*m.e)/determinant,f: (m.b*m.e-m.a*m.f)/determinant)
    }
    private static func transform(_ point: CGPoint, by m: FS_MATRIX) -> CGPoint {
        CGPoint(x: CGFloat(m.a)*point.x+CGFloat(m.c)*point.y+CGFloat(m.e),y: CGFloat(m.b)*point.x+CGFloat(m.d)*point.y+CGFloat(m.f))
    }
    private static func transformed(_ rect: CGRect, by matrix: FS_MATRIX) -> CGRect {
        [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),CGPoint(x: rect.minX,y: rect.maxY),CGPoint(x: rect.maxX,y: rect.maxY)]
            .map { transform($0,by: matrix) }.reduce(CGRect.null) { $0.union(CGRect(origin: $1,size: .zero)) }
    }
}

/// CAD producers may split one BT/ET text scope across several /Contents
/// streams. Regenerating just one such stream breaks the text state of the
/// others. Coalesce the selected page before PDFium marks any stream dirty.
@MainActor
private enum PDFContentNormalizer {
    static func prepare(_ input: Data, pageIndex: Int) throws -> Data {
        guard let provider = CGDataProvider(data: input as CFData), let cgDocument = CGPDFDocument(provider),
              let page = cgDocument.page(at: pageIndex+1), let dictionary = page.dictionary else { return input }
        var contents: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dictionary,"Contents",&contents), let contents,
              CGPDFArrayGetCount(contents) > 1 else { return input }
        var joined = Data()
        for index in 0..<CGPDFArrayGetCount(contents) {
            var stream: CGPDFStreamRef?
            guard CGPDFArrayGetStream(contents,index,&stream), let stream else { throw PDFSourceError.content }
            var format = CGPDFDataFormat.raw
            guard let decoded = CGPDFStreamCopyData(stream,&format), format == .raw else { throw PDFSourceError.content }
            joined.append(decoded as Data); joined.append(10)
        }
        let memory = input as NSData
        guard let document = FPDF_LoadMemDocument64(memory.bytes,memory.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document) }
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(document,&length), length > 0 else { throw PDFSourceError.save }
        let normalized = Data(bytes: bytes,count: length); BotPlusPDFium_Free(bytes)
        var syntax = Syntax(bytes: Array(normalized))
        let start = try syntax.lastXref()
        let objects = try syntax.objectOffsets(xref: start)
        let trailer = try syntax.trailer(xref: start)
        guard trailer["Encrypt"] == nil else { throw PDFSourceError.permission }
        guard let rootValue = trailer["Root"], let root = syntax.reference(rootValue),
              let rootOffset = objects[root.0] else { throw PDFSourceError.content }
        let catalog = try syntax.objectDictionary(at: rootOffset)
        guard let pagesValue = catalog.values["Pages"], let pagesRoot = syntax.reference(pagesValue) else { throw PDFSourceError.content }
        var pageObjects: [(Int,Int)] = [], visited = Set<Int>()
        func visit(_ reference: (Int,Int), depth: Int) throws {
            guard depth < 128, visited.insert(reference.0).inserted, let offset = objects[reference.0] else { throw PDFSourceError.content }
            let object = try syntax.objectDictionary(at: offset)
            if let type = object.values["Type"], syntax.string(type) == "/Page" { pageObjects.append(reference); return }
            guard let kids = object.values["Kids"] else { throw PDFSourceError.content }
            for child in syntax.references(kids) { try visit(child,depth: depth+1) }
        }
        try visit(pagesRoot,depth: 0)
        guard pageObjects.indices.contains(pageIndex) else { throw PDFSourceError.page }
        let pageReference = pageObjects[pageIndex]
        guard let offset = objects[pageReference.0] else { throw PDFSourceError.content }
        let pageObject = try syntax.objectDictionary(at: offset)
        guard let oldContents = pageObject.values["Contents"], let sizeValue = trailer["Size"],
              let size = Int(syntax.string(sizeValue)) else { throw PDFSourceError.content }
        let streamID = max(size,(objects.keys.max() ?? 0)+1)
        var output = normalized
        output.append(Data("\n".utf8))
        let pageOffset = output.count
        output.append(Data("\(pageReference.0) \(pageReference.1) obj\n".utf8))
        output.append(contentsOf: syntax.bytes[pageObject.range.lowerBound..<oldContents.lowerBound])
        output.append(Data(" \(streamID) 0 R ".utf8))
        output.append(contentsOf: syntax.bytes[oldContents.upperBound..<pageObject.range.upperBound])
        output.append(Data("\nendobj\n".utf8))
        let streamOffset = output.count
        output.append(Data("\(streamID) 0 obj\n<< /Length \(joined.count) >>\nstream\n".utf8)); output.append(joined)
        output.append(Data("\nendstream\nendobj\n".utf8))
        let xrefOffset = output.count
        var xref = "xref\n\(pageReference.0) 1\n"+String(format: "%010lld %05d n \n",Int64(pageOffset),Int32(pageReference.1))
        xref += "\(streamID) 1\n"+String(format: "%010lld 00000 n \n",Int64(streamOffset))
        xref += "trailer\n<< /Size \(streamID+1) /Root \(root.0) \(root.1) R /Prev \(start)"
        output.append(Data(xref.utf8))
        for key in ["Info","ID"] {
            if let value = trailer[key] {
                output.append(Data(" /\(key) ".utf8)); output.append(contentsOf: syntax.bytes[value])
            }
        }
        output.append(Data(" >>\nstartxref\n\(xrefOffset)\n%%EOF\n".utf8))
        return output
    }

    /// This reader handles the conventional xref/dictionaries emitted by
    /// FPDF_SaveAsCopy, including nested dictionaries, strings and references.
    /// It never scans binary stream data looking for object-like byte patterns.
    private struct Syntax {
        let bytes: [UInt8]
        var cursor = 0
        func string(_ range: Range<Int>) -> String { String(decoding: bytes[range],as: UTF8.self) }
        mutating func whitespace() {
            while cursor < bytes.count {
                if [0,9,10,12,13,32].contains(bytes[cursor]) { cursor += 1 }
                else if bytes[cursor] == 37 { while cursor < bytes.count && bytes[cursor] != 10 && bytes[cursor] != 13 { cursor += 1 } }
                else { break }
            }
        }
        mutating func token() -> String {
            whitespace(); let start = cursor
            while cursor < bytes.count && ![0,9,10,12,13,32,40,41,60,62,91,93,123,125,47,37].contains(bytes[cursor]) { cursor += 1 }
            return string(start..<cursor)
        }
        mutating func value(depth: Int = 0) throws -> Range<Int> {
            guard depth < 128 else { throw PDFSourceError.content }
            whitespace(); let start = cursor
            guard cursor < bytes.count else { throw PDFSourceError.content }
            switch bytes[cursor] {
            case 60:
                if cursor+1 < bytes.count && bytes[cursor+1] == 60 { _ = try dictionary(depth: depth+1) }
                else { cursor += 1; while cursor < bytes.count && bytes[cursor] != 62 { cursor += 1 }; guard cursor < bytes.count else { throw PDFSourceError.content }; cursor += 1 }
            case 40:
                cursor += 1; var depth = 1
                while cursor < bytes.count && depth > 0 {
                    if bytes[cursor] == 92 { cursor += min(2,bytes.count-cursor); continue }
                    if bytes[cursor] == 40 { depth += 1 }; if bytes[cursor] == 41 { depth -= 1 }; cursor += 1
                }
                guard depth == 0 else { throw PDFSourceError.content }
            case 91:
                cursor += 1; whitespace()
                while cursor < bytes.count && bytes[cursor] != 93 { _ = try value(depth: depth+1); whitespace() }
                guard cursor < bytes.count else { throw PDFSourceError.content }; cursor += 1
            case 47:
                cursor += 1; _ = token()
            default:
                let first = token(); guard !first.isEmpty else { throw PDFSourceError.content }
                let end = cursor
                if Int(first) != nil { let second = token(); if Int(second) == nil || token() != "R" { cursor = end } }
            }
            return start..<cursor
        }
        mutating func dictionary(depth: Int = 0) throws -> [String: Range<Int>] {
            guard depth < 128 else { throw PDFSourceError.content }
            whitespace()
            guard cursor+1 < bytes.count && bytes[cursor] == 60 && bytes[cursor+1] == 60 else { throw PDFSourceError.content }
            cursor += 2; var values: [String: Range<Int>] = [:]
            while true {
                whitespace(); guard cursor+1 < bytes.count else { throw PDFSourceError.content }
                if bytes[cursor] == 62 && bytes[cursor+1] == 62 { cursor += 2; return values }
                guard bytes[cursor] == 47 else { throw PDFSourceError.content }; cursor += 1
                let key = token(); values[key] = try value(depth: depth+1)
            }
        }
        mutating func lastXref() throws -> Int {
            // startxref is the final ASCII trailer marker, after all streams.
            let tailStart = max(0,bytes.count-1024), tail = string(tailStart..<bytes.count)
            guard let range = tail.range(of: "startxref",options: .backwards) else { throw PDFSourceError.content }
            let after = tail[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first
            guard let after, let offset = Int(after), offset >= 0 && offset < bytes.count else { throw PDFSourceError.content }; return offset
        }
        mutating func objectOffsets(xref: Int) throws -> [Int:Int] {
            cursor = xref; guard token() == "xref" else { throw PDFSourceError.content }
            var offsets: [Int:Int] = [:]
            while true {
                let first = token(); if first == "trailer" { return offsets }
                guard let start = Int(first), let count = Int(token()), count >= 0 && count <= bytes.count else { throw PDFSourceError.content }
                for index in 0..<count {
                    guard let offset = Int(token()), Int(token()) != nil else { throw PDFSourceError.content }
                    let state = token(); if state == "n" { offsets[start+index] = offset }
                }
            }
        }
        mutating func trailer(xref: Int) throws -> [String:Range<Int>] { _ = try objectOffsets(xref: xref); return try dictionary() }
        mutating func objectDictionary(at offset: Int) throws -> (range: Range<Int>,values: [String:Range<Int>]) {
            guard offset >= 0 && offset < bytes.count else { throw PDFSourceError.content }; cursor = offset
            guard Int(token()) != nil, Int(token()) != nil, token() == "obj" else { throw PDFSourceError.content }
            whitespace(); let start = cursor; let values = try dictionary(); return (start..<cursor,values)
        }
        func reference(_ range: Range<Int>) -> (Int,Int)? {
            let tokens = string(range).split(whereSeparator: { $0.isWhitespace })
            guard tokens.count == 3, tokens[2] == "R", let id = Int(tokens[0]), let generation = Int(tokens[1]) else { return nil }; return (id,generation)
        }
        func references(_ range: Range<Int>) -> [(Int,Int)] {
            let text = string(range)
            let regex = try! NSRegularExpression(pattern: #"(\d+)\s+(\d+)\s+R"#)
            let ns = text as NSString
            return regex.matches(in: text,range: NSRange(location: 0,length: ns.length)).compactMap { match in
                guard let id = Int(ns.substring(with: match.range(at: 1))), let generation = Int(ns.substring(with: match.range(at: 2))) else { return nil }; return (id,generation)
            }
        }
    }
}

/// Process-scoped fonts; extracted programs stay alive while an editor can use them.
/// Unusable PDF subsets are listed but never silently chosen as another font.
@MainActor
enum PDFFontCatalog {
    private struct FontKey: Hashable { let url: URL; let size: CGFloat }
    private static var faceCache: [FontKey:CTFont] = [:]
    static func font(at url: URL,size: CGFloat) -> CTFont {
        let key = FontKey(url: url,size: size)
        if let cached = faceCache[key] { return cached }
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary),size,nil)
        if faceCache.count >= 128 { faceCache.removeAll(keepingCapacity: true) }
        faceCache[key] = font; return font
    }
    private static var embedded: [String: URL] = [:]
    private static var programs: [String: URL] = [:]
    private static var directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent("BotPlusFonts-"+UUID().uuidString,isDirectory: true)
    static func font(named name: String,size: CGFloat) -> NSFont? {
        if let url = embedded[name] {
            let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontURLAttribute: url] as CFDictionary)
            let font = CTFontCreateWithFontDescriptor(descriptor,size,nil)
            guard CTFontCopyTable(font,0x636d6170,CTFontTableOptions(rawValue: 0)) != nil else { return nil }
            return NSFont(name: CTFontCopyPostScriptName(font) as String,size: size)
        }
        if let exact = NSFont(name: name,size: size) { return exact }
        return NSFontManager.shared.font(withFamily: name,traits: [],weight: 5,size: size)
    }
    static func names(in data: Data) throws -> [String] {
        _ = PDFiumRuntime.ready
        let storage = data as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document) }
        var names = Set(NSFontManager.shared.availableFontFamilies+NSFontManager.shared.availableFonts)
        var seen = Set<String>()
        @MainActor func scan(_ object: FPDF_PAGEOBJECT,depth: Int) {
            guard depth < 32 else { return }
            if FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_FORM {
                for index in 0..<max(0,FPDFFormObj_CountObjects(object)) {
                    if let child = FPDFFormObj_GetObject(object,UInt(index)) { scan(child,depth: depth+1) }
                }
            }
            guard let font = FPDFTextObj_GetFont(object) else { return }
            let count = FPDFFont_GetBaseFontName(font,nil,0)
            guard count > 1 && count < 16_384 else { return }
            var buffer = [CChar](repeating: 0,count: count)
            _ = buffer.withUnsafeMutableBufferPointer { FPDFFont_GetBaseFontName(font,$0.baseAddress,count) }
            let full = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },as: UTF8.self)
            let name = full.split(separator: "+").last.map(String.init) ?? full
            names.insert(name)
            guard seen.insert(full).inserted,FPDFFont_GetIsEmbedded(font) == 1 else { return }
            var size = 0
            guard FPDFFont_GetFontData(font,nil,0,&size) != 0,size > 0,size < 64_000_000 else { return }
            var bytes = [UInt8](repeating: 0,count: size)
            guard bytes.withUnsafeMutableBufferPointer({ FPDFFont_GetFontData(font,$0.baseAddress,size,&size) }) != 0,
                  let provider = CGDataProvider(data: Data(bytes) as CFData),let graphics = CGFont(provider) else { return }
            // Some CAD subset fonts contain glyphs but no Unicode cmap. They
            // remain visible in the list; glyph validation prevents data loss.
            try? FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString+".otf")
            guard (try? Data(bytes).write(to: url)) != nil else { return }
            var error: Unmanaged<CFError>?
            if NSFont(name: name,size: 12) == nil { embedded[name] = url }
            if let ps = graphics.postScriptName as String? {
                if NSFont(name: ps,size: 12) == nil { embedded[ps] = url }
                names.insert(ps)
            }
            _ = CTFontManagerRegisterGraphicsFont(graphics,&error)
        }
        for index in 0..<max(0,FPDF_GetPageCount(document)) {
            guard let page = FPDF_LoadPage(document,index) else { continue }
            for objectIndex in 0..<max(0,FPDFPage_CountObjects(page)) {
                if let object = FPDFPage_GetObject(page,objectIndex) { scan(object,depth: 0) }
            }
            FPDF_ClosePage(page)
        }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    /// Export a single face from TTC/OTF/system fonts using public CoreText tables.
    static func url(for name: String) throws -> URL {
        if let cached = programs[name] { return cached }
        guard let nsFont = font(named: name,size: 12) else { throw PDFSourceError.font }
        let font = nsFont as CTFont
        guard let rawTags = CTFontCopyAvailableTables(font,CTFontTableOptions(rawValue: 0)),CFArrayGetCount(rawTags) > 0 else { throw PDFSourceError.font }
        // CoreText returns raw integer tags in this CFArray, not NSNumbers.
        let tags = (0..<CFArrayGetCount(rawTags)).map { UInt32(truncatingIfNeeded: UInt(bitPattern: CFArrayGetValueAtIndex(rawTags,$0))) }
        let tables: [(UInt32,Data)] = tags.compactMap { value in
            guard value != 0x44534947 else { return nil }
            guard let table = CTFontCopyTable(font,value,CTFontTableOptions(rawValue: 0)) else { return nil }
            var data = Data(Array(table as Data))
            if value == 0x68656164,data.count >= 12 { data.replaceSubrange(8..<12,with: [0,0,0,0]) }
            return (value,data)
        }.sorted { $0.0 < $1.0 }
        guard tables.count <= 4095 else { throw PDFSourceError.font }
        let cff = tables.contains { $0.0 == 0x43464620 || $0.0 == 0x43464632 }
        func u16(_ n: Int) -> [UInt8] { [UInt8((n >> 8)&255),UInt8(n&255)] }
        func u32(_ n: UInt32) -> [UInt8] { [UInt8((n >> 24)&255),UInt8((n >> 16)&255),UInt8((n >> 8)&255),UInt8(n&255)] }
        func checksum(_ data: Data) -> UInt32 {
            let b = Array(data); var sum: UInt32 = 0
            for i in stride(from: 0,to: b.count,by: 4) {
                var word: UInt32 = 0
                for j in 0..<4 { word = (word << 8) | (i+j < b.count ? UInt32(b[i+j]) : 0) }
                sum = sum &+ word
            }
            return sum
        }
        var power = 1,selector = 0
        while power*2 <= tables.count { power *= 2; selector += 1 }
        var result = Data(u32(cff ? 0x4f54544f : 0x00010000)+u16(tables.count)+u16(power*16)+u16(selector)+u16(tables.count*16-power*16))
        var payload = Data(),headOffset: Int?
        for (tag,data) in tables {
            let offset = 12+16*tables.count+payload.count
            result.append(contentsOf: u32(tag)+u32(checksum(data))+u32(UInt32(offset))+u32(UInt32(data.count)))
            if tag == 0x68656164 { headOffset = offset }
            payload.append(data)
            while payload.count%4 != 0 { payload.append(0) }
        }
        result.append(payload)
        if let offset = headOffset,offset+12 <= result.count {
            result.replaceSubrange(offset+8..<offset+12,with: u32(0xb1b0afba &- checksum(result)))
        }
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(UUID().uuidString+(cff ? ".otf" : ".ttf"))
        try result.write(to: url); programs[name] = url; programs[nsFont.fontName] = url
        // Keep CoreText family/face lookup consistent with the PDF embedding.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL,.process,nil)
        return url
    }
}

@MainActor
extension PDFSourceSession {
    static func insertingImage(data: Data,pageIndex: Int,image: CGImage,bounds: CGRect) throws -> Data {
        guard image.width > 0,image.height > 0,image.width <= 16_384,image.height <= 16_384 else { throw PDFSourceError.content }
        let handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
        let factor = min(1,4096/Double(max(image.width,image.height)))
        let pixelWidth = max(1,Int((Double(image.width)*factor).rounded())),pixelHeight = max(1,Int((Double(image.height)*factor).rounded()))
        guard let bitmap = FPDFBitmap_CreateEx(Int32(pixelWidth),Int32(pixelHeight),FPDFBitmap_BGRA,nil,0) else { throw PDFSourceError.content }
        defer { FPDFBitmap_Destroy(bitmap) }
        guard let buffer = FPDFBitmap_GetBuffer(bitmap),let context = CGContext(data: buffer,width: pixelWidth,height: pixelHeight,bitsPerComponent: 8,bytesPerRow: Int(FPDFBitmap_GetStride(bitmap)),space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue) else { throw PDFSourceError.content }
        context.clear(CGRect(x: 0,y: 0,width: pixelWidth,height: pixelHeight))
        context.draw(image,in: CGRect(x: 0,y: 0,width: pixelWidth,height: pixelHeight))
        // Quartz emits premultiplied bytes; the AGG PDFium bitmap format
        // requires independent color components. Preserve PNG edge alpha.
        let pixels = buffer.assumingMemoryBound(to: UInt8.self),stride = Int(FPDFBitmap_GetStride(bitmap))
        for row in 0..<pixelHeight { for column in 0..<pixelWidth {
            let offset = row*stride+column*4,alpha = Int(pixels[offset+3])
            if alpha > 0 && alpha < 255 { for channel in 0..<3 { pixels[offset+channel] = UInt8(min(255,(Int(pixels[offset+channel])*255+alpha/2)/alpha)) } }
        } }
        guard let object = FPDFPageObj_NewImageObj(handle.document) else { throw PDFSourceError.content }
        var page: FPDF_PAGE? = handle.page
        guard FPDFImageObj_SetBitmap(&page,1,object,bitmap) != 0,
              FPDFImageObj_SetMatrix(object,Double(bounds.width),0,0,Double(bounds.height),Double(bounds.minX),Double(bounds.minY)) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
        FPDFPage_InsertObject(handle.page,object)
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        var length = 0; guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&length),length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }; return Data(bytes: bytes,count: length)
    }
}

@MainActor
extension PDFSourceSession {
    static func validEmptyPageStreams(_ data: Data) throws -> Data {
        guard let provider = CGDataProvider(data: data as CFData),let reference = CGPDFDocument(provider) else { throw PDFSourceError.document }
        var empty: [Int] = []
        for index in 1...max(1,reference.numberOfPages) {
            guard let page = reference.page(at: index),let dictionary = page.dictionary else { continue }
            var array: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(dictionary,"Contents",&array),let array,CGPDFArrayGetCount(array) == 0 { empty.append(index-1) }
        }
        guard !empty.isEmpty else { return data }
        _ = PDFiumRuntime.ready; let storage = data as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document) }
        for index in empty {
            guard let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
            defer { FPDF_ClosePage(page) }
            guard let path = FPDFPageObj_CreateNewRect(0,0,0.01,0.01) else { throw PDFSourceError.content }
            _ = FPDFPageObj_SetFillColor(path,0,0,0,0); _ = FPDFPath_SetDrawMode(path,FPDF_FILLMODE_WINDING,0); FPDFPage_InsertObject(page,path)
            guard FPDFPage_GenerateContent(page) != 0 else { throw PDFSourceError.content }
        }
        var length = 0; guard let bytes = BotPlusPDFium_SaveDocument(document,&length),length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }; return Data(bytes: bytes,count: length)
    }
}

/// Reads the existing PDF text layer only. This reader never performs OCR and
/// does not require the source-content editing normalizer or editing rights.
@MainActor
enum PDFSourceTextReader {
    static func pages(data: Data,indices: [Int]? = nil) throws -> [String] {
        _ = PDFiumRuntime.ready
        let storage = data as NSData
        return try withExtendedLifetime(storage) {
            guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
            defer { FPDF_CloseDocument(document) }
            guard FPDF_GetDocPermissions(document) & (1 << 4) != 0 else { throw PDFSourceError.permission }
            let count = Int(FPDF_GetPageCount(document))
            return try (indices ?? Array(0..<count)).map { index in
                guard index >= 0,index < count,let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
                defer { FPDF_ClosePage(page) }
                guard let textPage = FPDFText_LoadPage(page) else { return "" }
                defer { FPDFText_ClosePage(textPage) }
                let characters = FPDFText_CountChars(textPage)
                guard characters >= 0,characters <= 10_000_000 else { throw PDFSourceError.content }
                guard characters > 0 else { return "" }
                // GetText uses UCS-2 and can omit non-BMP characters. GetUnicode
                // supplies the full scalar, including generated line breaks.
                var scalars = String.UnicodeScalarView()
                scalars.reserveCapacity(Int(characters))
                for index in 0..<characters {
                    if let scalar = UnicodeScalar(FPDFText_GetUnicode(textPage,index)),scalar.value != 0 { scalars.append(scalar) }
                }
                return String(scalars)
            }
        }
    }
}

/// A source-object transaction: the viewer is untouched until GenerateContent
/// and complete serialization succeed. Form XObjects are edited as groups, so
/// changing one invocation cannot rewrite another invocation's child resources.
struct PDFEngineeringSnap: Sendable {
    enum Kind: Int, Sendable { case intersection, endpoint, midpoint, extremum, curveMidpoint, nearest
        func title(russian: Bool) -> String { switch self { case .intersection: russian ? "Пересечение" : "Intersection"; case .endpoint: russian ? "Конец" : "Endpoint"; case .midpoint: russian ? "Середина" : "Midpoint"; case .extremum: russian ? "Экстремум кривой" : "Curve extremum"; case .curveMidpoint: russian ? "Половина длины кривой" : "Curve half-length"; case .nearest: russian ? "На кривой" : "On curve" } }
    }
    let point: CGPoint, kind: Kind
}
@MainActor
final class PDFContentSession {
    struct Style {
        var stroke: NSColor
        var fill: NSColor
        var width: CGFloat
        var opacity: CGFloat
        var strokeEnabled: Bool
        var fillEnabled: Bool
        var editStroke = true
        var editFill = true
        var editOpacity = true
    }
    struct Clipboard: Codable {
        let pdf: Data
        let bounds: CGRect
    }
    let data: Data
    let pageIndex: Int
    private let handle: PDFiumDocumentHandle
    private var used = false
    private var catalog: [PDFSourceSession.ContentObject]?
    private var snapPointCache: [CGPoint]?
    private var snapKindsCache: [PDFEngineeringSnap]?
    private var snapSegmentsCache: [(CGPoint,CGPoint)]?
    private var snapCurvesCache: [PDFBezierSegment]?
    private var snapArcMidpoints: [Int:CGPoint] = [:]
    private var snapArcMidpointMissing = Set<Int>()
    private(set) var result: PDFSourceSession.ContentObject?
    private static let identity = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 0,f: 0)
    init(data: Data,pageIndex: Int) throws {
        self.data = data; self.pageIndex = pageIndex
        handle = try PDFiumDocumentHandle(data: data,pageIndex: pageIndex)
    }
    var objects: [PDFSourceSession.ContentObject] {
        if let catalog { return catalog }
        let objects = (0..<max(0,FPDFPage_CountObjects(handle.page))).compactMap { info(Int($0)) }
        catalog = objects; return objects
    }
    private func object(_ index: Int) -> FPDF_PAGEOBJECT? {
        guard index >= 0,index < Int(FPDFPage_CountObjects(handle.page)) else { return nil }
        return FPDFPage_GetObject(handle.page,Int32(index))
    }
    func info(_ index: Int) -> PDFSourceSession.ContentObject? {
        guard let object = object(index) else { return nil }
        let kind: String
        switch FPDFPageObj_GetType(object) {
        case FPDF_PAGEOBJ_IMAGE: kind = "image"
        case FPDF_PAGEOBJ_PATH: kind = "path"
        case FPDF_PAGEOBJ_FORM: kind = "group"
        case FPDF_PAGEOBJ_SHADING: kind = "shading"
        case FPDF_PAGEOBJ_TEXT:
            let mode = FPDFTextObj_GetTextRenderMode(object)
            guard mode == FPDF_TEXTRENDERMODE_FILL || mode == FPDF_TEXTRENDERMODE_STROKE || mode == FPDF_TEXTRENDERMODE_FILL_STROKE else { return nil }
            kind = "text"
        default: return nil
        }
        var l: Float = 0,b: Float = 0,r: Float = 0,t: Float = 0
        guard FPDFPageObj_GetBounds(object,&l,&b,&r,&t) != 0,
              [l,b,r,t].allSatisfy({ $0.isFinite && abs($0) < 1_000_000_000 }) else { return nil }
        let bounds = CGRect(x: Double(l),y: Double(b),width: max(0.1,Double(r-l)),height: max(0.1,Double(t-b)))
        func color(_ stroke: Bool) -> NSColor? {
            var r: UInt32 = 0,g: UInt32 = 0,b: UInt32 = 0,a: UInt32 = 0
            let ok = stroke ? FPDFPageObj_GetStrokeColor(object,&r,&g,&b,&a) : FPDFPageObj_GetFillColor(object,&r,&g,&b,&a)
            guard ok != 0 else { return nil }
            return NSColor(calibratedRed: CGFloat(r)/255,green: CGFloat(g)/255,blue: CGFloat(b)/255,alpha: CGFloat(a)/255)
        }
        var fillMode: Int32 = 0,stroke: FPDF_BOOL = 0,width: Float = 1
        _ = FPDFPageObj_GetStrokeWidth(object,&width)
        if kind == "path" { _ = FPDFPath_GetDrawMode(object,&fillMode,&stroke) }
        var pixels: CGSize?
        if kind == "image" {
            var w: UInt32 = 0,h: UInt32 = 0
            if FPDFImageObj_GetImagePixelSize(object,&w,&h) != 0 { pixels = CGSize(width: Int(w),height: Int(h)) }
        }
        let strokeColor = color(true),fillColor = color(false)
        return PDFSourceSession.ContentObject(kind: kind,bounds: bounds,pixelSize: pixels,index: index,stroke: strokeColor,fill: fillColor,lineWidth: CGFloat(width),opacity: (fillMode != 0 || kind == "text" || kind == "image") ? (fillColor?.alphaComponent ?? 1) : (strokeColor?.alphaComponent ?? 1),strokeEnabled: stroke != 0,fillEnabled: kind == "text" || fillMode != 0,fillRule: fillMode)
    }
    func select(at point: CGPoint,tolerance: CGFloat) -> PDFSourceSession.ContentObject? {
        for info in objects.reversed() where info.bounds.insetBy(dx: -tolerance,dy: -tolerance).contains(point) {
            guard let object = object(info.index) else { continue }
            if info.kind != "path" { return info }
            guard let path = path(object) else { continue }
            var fillMode: Int32 = 0,stroke: FPDF_BOOL = 0
            _ = FPDFPath_GetDrawMode(object,&fillMode,&stroke)
            if fillMode != 0 && path.contains(point,using: fillMode == FPDF_FILLMODE_ALTERNATE ? .evenOdd : .winding) { return info }
            if stroke != 0 {
                var matrix = Self.identity; _ = FPDFPageObj_GetMatrix(object,&matrix)
                let scale = max(hypot(CGFloat(matrix.a),CGFloat(matrix.b)),hypot(CGFloat(matrix.c),CGFloat(matrix.d)))
                let outline = path.copy(strokingWithWidth: max(2*tolerance,info.lineWidth*scale),lineCap: .round,lineJoin: .round,miterLimit: 10)
                if outline.contains(point) { return info }
            }
        }
        return nil
    }
    private func path(_ object: FPDF_PAGEOBJECT) -> CGPath? {
        var matrix = Self.identity; guard FPDFPageObj_GetMatrix(object,&matrix) != 0 else { return nil }
        var affine = CGAffineTransform(a: CGFloat(matrix.a),b: CGFloat(matrix.b),c: CGFloat(matrix.c),d: CGFloat(matrix.d),tx: CGFloat(matrix.e),ty: CGFloat(matrix.f))
        let path = CGMutablePath(),count = max(0,FPDFPath_CountSegments(object))
        func segment(_ index: Int32) -> (CGPoint,Int32,Bool)? {
            guard let segment = FPDFPath_GetPathSegment(object,index) else { return nil }
            var x: Float = 0,y: Float = 0
            guard FPDFPathSegment_GetPoint(segment,&x,&y) != 0 else { return nil }
            return (CGPoint(x: Double(x),y: Double(y)),FPDFPathSegment_GetType(segment),FPDFPathSegment_GetClose(segment) != 0)
        }
        var index: Int32 = 0
        while index < count {
            guard let s = segment(index) else { return nil }
            if s.1 == FPDF_SEGMENT_MOVETO { path.move(to: s.0) }
            else if s.1 == FPDF_SEGMENT_LINETO { path.addLine(to: s.0) }
            else if s.1 == FPDF_SEGMENT_BEZIERTO,let second = segment(index+1),let third = segment(index+2),index+2 < count {
                path.addCurve(to: third.0,control1: s.0,control2: second.0)
                if third.2 { path.closeSubpath() }; index += 3; continue
            } else { return nil }
            if s.2 { path.closeSubpath() }; index += 1
        }
        return path.copy(using: &affine)
    }
    func applying(index: Int,bounds target: CGRect,rotation: CGFloat,style: Style? = nil,image: CGImage? = nil,delete: Bool = false) throws -> Data {
        guard !used,let object = object(index),let original = info(index) else { throw PDFSourceError.alreadyUsed }
        let values = [target.minX,target.minY,target.width,target.height,rotation]
        guard values.allSatisfy({ $0.isFinite && abs($0) < 1_000_000 }),target.width >= 0.1,target.height >= 0.1 else { throw PDFSourceError.content }
        used = true; handle.closeTextPage()
        if delete {
            guard FPDFPage_RemoveObject(handle.page,object) != 0 else { throw PDFSourceError.content }
            FPDFPageObj_Destroy(object)
        } else {
            let sx = target.width/original.bounds.width,sy = target.height/original.bounds.height
            let fit = CGAffineTransform(a: sx,b: 0,c: 0,d: sy,tx: target.minX-sx*original.bounds.minX,ty: target.minY-sy*original.bounds.minY)
            let c = cos(rotation),s = sin(rotation),center = CGPoint(x: target.midX,y: target.midY)
            let turn = CGAffineTransform(a: c,b: s,c: -s,d: c,tx: center.x-c*center.x+s*center.y,ty: center.y-s*center.x-c*center.y)
            let transform = fit.concatenating(turn)
            let matrix = FS_MATRIX(a: Float(transform.a),b: Float(transform.b),c: Float(transform.c),d: Float(transform.d),e: Float(transform.tx),f: Float(transform.ty))
            var mutableMatrix = matrix
            guard FPDFPageObj_TransformF(object,&mutableMatrix) != 0 else { throw PDFSourceError.content }
            if let style {
                guard style.width.isFinite,style.width >= 0,style.width <= 2000,style.opacity.isFinite,style.opacity >= 0,style.opacity <= 1 else { throw PDFSourceError.content }
                func rgba(_ color: NSColor) -> [UInt32] {
                    let rgb = color.usingColorSpace(.deviceRGB) ?? .black
                    return [rgb.redComponent,rgb.greenComponent,rgb.blueComponent,style.opacity].map { UInt32((min(1,max(0,$0))*255).rounded()) }
                }
                let fill = rgba(style.fill),stroke = rgba(style.stroke)
                if (original.kind == "path" || original.kind == "text" || original.kind == "image") && (style.editFill || (style.editOpacity && (original.fill != nil || original.kind == "image"))) {
                    guard FPDFPageObj_SetFillColor(object,fill[0],fill[1],fill[2],fill[3]) != 0 else { throw PDFSourceError.content }
                }
                if original.kind == "path" {
                    guard style.strokeEnabled || style.fillEnabled else { throw PDFSourceError.content }
                    if style.editStroke || (style.editOpacity && original.stroke != nil) { guard FPDFPageObj_SetStrokeColor(object,stroke[0],stroke[1],stroke[2],stroke[3]) != 0 else { throw PDFSourceError.content } }
                    guard FPDFPageObj_SetStrokeWidth(object,Float(style.width)) != 0,
                          FPDFPath_SetDrawMode(object,style.fillEnabled ? (original.fillRule == FPDF_FILLMODE_ALTERNATE ? FPDF_FILLMODE_ALTERNATE : FPDF_FILLMODE_WINDING) : FPDF_FILLMODE_NONE,style.strokeEnabled ? 1 : 0) != 0 else { throw PDFSourceError.content }
                }
            }
            if let image { guard original.kind == "image" else { throw PDFSourceError.content }; try replaceImage(image,object: object) }
            result = info(index)
        }
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        return try serialized()
    }
    private func replaceImage(_ image: CGImage,object: FPDF_PAGEOBJECT) throws {
        let factor = min(1,4096/Double(max(image.width,image.height)))
        let width = max(1,Int(Double(image.width)*factor)),height = max(1,Int(Double(image.height)*factor))
        guard let bitmap = FPDFBitmap_CreateEx(Int32(width),Int32(height),FPDFBitmap_BGRA,nil,0) else { throw PDFSourceError.content }
        defer { FPDFBitmap_Destroy(bitmap) }
        guard let memory = FPDFBitmap_GetBuffer(bitmap),let context = CGContext(data: memory,width: width,height: height,bitsPerComponent: 8,bytesPerRow: Int(FPDFBitmap_GetStride(bitmap)),space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue) else { throw PDFSourceError.content }
        context.clear(CGRect(x: 0,y: 0,width: width,height: height))
        context.draw(image,in: CGRect(x: 0,y: 0,width: width,height: height))
        let pixels = memory.assumingMemoryBound(to: UInt8.self),stride = Int(FPDFBitmap_GetStride(bitmap))
        for row in 0..<height { for column in 0..<width {
            let offset = row*stride+column*4,alpha = Int(pixels[offset+3])
            if alpha > 0 && alpha < 255 { for channel in 0..<3 { pixels[offset+channel] = UInt8(min(255,Int(pixels[offset+channel])*255/alpha)) } }
        } }
        var page: FPDF_PAGE? = handle.page
        guard FPDFImageObj_SetBitmap(&page,1,object,bitmap) != 0 else { throw PDFSourceError.content }
    }
    func clipboard(index: Int) throws -> Clipboard {
        guard let info = info(index) else { throw PDFSourceError.content }
        let copy = try PDFContentSession(data: data,pageIndex: pageIndex)
        copy.handle.closeTextPage()
        for i in 0..<max(0,FPDFPage_CountObjects(copy.handle.page)) where Int(i) != index {
            if let object = FPDFPage_GetObject(copy.handle.page,i) { guard FPDFPageObj_SetIsActive(object,0) != 0 else { throw PDFSourceError.content } }
        }
        for i in (0..<max(0,FPDFPage_GetAnnotCount(copy.handle.page))).reversed() { _ = FPDFPage_RemoveAnnot(copy.handle.page,i) }
        FPDFPage_SetRotation(copy.handle.page,0)
        FPDFPage_SetCropBox(copy.handle.page,Float(info.bounds.minX),Float(info.bounds.minY),Float(info.bounds.maxX),Float(info.bounds.maxY))
        FPDFPage_SetMediaBox(copy.handle.page,Float(info.bounds.minX),Float(info.bounds.minY),Float(info.bounds.maxX),Float(info.bounds.maxY))
        guard FPDFPage_GenerateContent(copy.handle.page) != 0,let target = FPDF_CreateNewDocument() else { throw PDFSourceError.content }
        defer { FPDF_CloseDocument(target) }
        var index = Int32(pageIndex)
        guard FPDF_ImportPagesByIndex(target,copy.handle.document,&index,1,0) != 0 else { throw PDFSourceError.content }
        var count = 0
        guard let memory = BotPlusPDFium_SaveDocument(target,&count),count > 0,count <= 64*1024*1024 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(memory) }
        return Clipboard(pdf: Data(bytes: memory,count: count),bounds: info.bounds)
    }
    func pasting(_ clipboard: Clipboard,at point: CGPoint) throws -> Data {
        guard !used,clipboard.pdf.count <= 64*1024*1024 else { throw PDFSourceError.content }
        let storage = clipboard.pdf as NSData
        guard let source = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(source) }
        guard let template = FPDF_NewXObjectFromPage(handle.document,source,0) else { throw PDFSourceError.content }
        defer { FPDF_CloseXObject(template) }
        guard let object = FPDF_NewFormObjectFromXObject(template) else { throw PDFSourceError.content }
        var initial = Self.identity
        guard FPDFPageObj_TransformF(object,&initial) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
        var l: Float = 0,b: Float = 0,r: Float = 0,t: Float = 0
        guard FPDFPageObj_GetBounds(object,&l,&b,&r,&t) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
        var matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: Float(point.x)-l,f: Float(point.y)-t)
        guard FPDFPageObj_TransformF(object,&matrix) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
        used = true; handle.closeTextPage()
        FPDFPage_InsertObject(handle.page,object)
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        result = info(Int(FPDFPage_CountObjects(handle.page))-1)
        return try serialized()
    }
    private func serialized() throws -> Data {
        if FPDFPage_CountObjects(handle.page) == 0 {
            guard let sentinel = FPDFPageObj_CreateNewRect(0,0,0.01,0.01) else { throw PDFSourceError.content }
            _ = FPDFPageObj_SetFillColor(sentinel,0,0,0,0); _ = FPDFPath_SetDrawMode(sentinel,FPDF_FILLMODE_WINDING,0)
            FPDFPage_InsertObject(handle.page,sentinel)
            guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        }
        var count = 0
        guard let bytes = BotPlusPDFium_SaveDocument(handle.document,&count),count > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }; return Data(bytes: bytes,count: count)
    }
}

/// Background objects are marked in the content stream and inserted at index 0,
/// so updating/removing our background never erases original page objects.
@MainActor
enum PDFPageBackgroundEngine {
    private static let markName = "BotPlusPageBackground_v1"
    static func change(data: Data, indices: [Int], color: PDFColorComponents,
                       image: CGImage?, placement: Int = 0, tileWidth: CGFloat = 144, remove: Bool, progress: (Double) -> Void) async throws -> Data {
        _ = PDFiumRuntime.ready
        var normalized = data
        for (position, index) in indices.enumerated() {
            try Task.checkCancellation()
            normalized = try PDFContentNormalizer.prepare(normalized, pageIndex: index)
            progress(Double(position + 1) / Double(max(1, indices.count)) * 0.2)
            await Task.yield()
        }
        let storage = normalized as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes, storage.length, nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document); _ = storage }
        guard FPDF_GetDocPermissions(document) & (1 << 3) != 0 else { throw PDFSourceError.permission }
        for (position, index) in indices.enumerated() {
            try Task.checkCancellation()
            try changePage(document: document, index: index, color: color, image: image, placement: placement,tileWidth: tileWidth, remove: remove)
            progress(0.2 + Double(position + 1) / Double(max(1, indices.count)) * 0.75)
            await Task.yield()
        }
        try Task.checkCancellation()
        var length = 0
        guard let bytes = BotPlusPDFium_SaveDocument(document, &length), length > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(bytes) }
        progress(1)
        return Data(bytes: bytes, count: length)
    }
    private static func owned(_ object: FPDF_PAGEOBJECT) -> Bool {
        for index in 0..<max(0, FPDFPageObj_CountMarks(object)) {
            guard let mark = FPDFPageObj_GetMark(object, UInt(index)) else { continue }
            var length: UInt = 0
            guard FPDFPageObjMark_GetName(mark, nil, 0, &length) != 0, length > 0, length < 4096 else { continue }
            var units = [UInt16](repeating: 0, count: Int(length / 2))
            _ = units.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetName(mark, $0.baseAddress, length, &length) }
            if String(decoding: units.prefix { $0 != 0 }, as: UTF16.self) == markName { return true }
        }
        return false
    }
    private static func insert(_ object: FPDF_PAGEOBJECT, page: FPDF_PAGE, index: Int) throws {
        guard markName.withCString({ FPDFPageObj_AddMark(object, $0) }) != nil,
              FPDFPage_InsertObjectAtIndex(page, object, index) != 0 else {
            FPDFPageObj_Destroy(object); throw PDFSourceError.content
        }
    }
    private static func changePage(document: FPDF_DOCUMENT, index: Int, color: PDFColorComponents,
                                   image: CGImage?, placement: Int, tileWidth: CGFloat, remove: Bool) throws {
        guard let page = FPDF_LoadPage(document, Int32(index)) else { throw PDFSourceError.page }
        defer { FPDF_ClosePage(page) }
        for objectIndex in stride(from: Int(FPDFPage_CountObjects(page)) - 1, through: 0, by: -1) {
            guard let object = FPDFPage_GetObject(page, Int32(objectIndex)), owned(object) else { continue }
            guard FPDFPage_RemoveObject(page, object) != 0 else { throw PDFSourceError.content }
            FPDFPageObj_Destroy(object)
        }
        if !remove {
            var left: Float = 0, bottom: Float = 0, right: Float = 0, top: Float = 0
            if FPDFPage_GetCropBox(page, &left, &bottom, &right, &top) == 0 {
                guard FPDFPage_GetMediaBox(page, &left, &bottom, &right, &top) != 0 else { throw PDFSourceError.page }
            }
            guard right > left, top > bottom else { throw PDFSourceError.page }
            func component(_ value: Double) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
            if image == nil {
                guard let fill = FPDFPageObj_CreateNewRect(left, bottom, right - left, top - bottom) else { throw PDFSourceError.content }
                guard FPDFPageObj_SetFillColor(fill, component(color.red), component(color.green), component(color.blue), component(color.alpha)) != 0,
                      FPDFPath_SetDrawMode(fill, FPDF_FILLMODE_WINDING, 0) != 0 else {
                    FPDFPageObj_Destroy(fill); throw PDFSourceError.content
                }
                try insert(fill, page: page, index: 0)
            }
            if let original = image {
                let image = try PDFBackgroundPlacement.composed(original,size: CGSize(width: CGFloat(right-left),height: CGFloat(top-bottom)),mode: placement,tileWidth: tileWidth)
                let width = image.width, height = image.height
                guard width > 0, height > 0, width * height <= 40_000_000,
                      let bitmap = FPDFBitmap_CreateEx(Int32(width), Int32(height), FPDFBitmap_BGRA, nil, 0) else { throw PDFSourceError.content }
                defer { FPDFBitmap_Destroy(bitmap) }
                guard let buffer = FPDFBitmap_GetBuffer(bitmap), let context = CGContext(data: buffer, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: Int(FPDFBitmap_GetStride(bitmap)), space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw PDFSourceError.content }
                context.clear(CGRect(x: 0, y: 0, width: width, height: height))
                context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                let pixels = buffer.assumingMemoryBound(to: UInt8.self), stride = Int(FPDFBitmap_GetStride(bitmap))
                for row in 0..<height { for column in 0..<width {
                    let offset = row * stride + column * 4, alpha = Int(pixels[offset + 3])
                    if alpha > 0 && alpha < 255 {
                        for channel in 0..<3 { pixels[offset + channel] = UInt8(min(255, (Int(pixels[offset + channel]) * 255 + alpha / 2) / alpha)) }
                    }
                    pixels[offset + 3] = UInt8((Double(alpha) * min(1, max(0, color.alpha))).rounded())
                } }
                guard let object = FPDFPageObj_NewImageObj(document) else { throw PDFSourceError.content }
                var visiblePage: FPDF_PAGE? = page
                guard FPDFImageObj_SetBitmap(&visiblePage, 1, object, bitmap) != 0,
                      FPDFImageObj_SetMatrix(object, Double(right - left), 0, 0, Double(top - bottom), Double(left), Double(bottom)) != 0 else {
                    FPDFPageObj_Destroy(object); throw PDFSourceError.content
                }
                try insert(object, page: page, index: 0)
            }
        }
        if FPDFPage_CountObjects(page) == 0 {
            guard let sentinel = FPDFPageObj_CreateNewRect(0, 0, 0.01, 0.01) else { throw PDFSourceError.content }
            _ = FPDFPageObj_SetFillColor(sentinel, 0, 0, 0, 0)
            _ = FPDFPath_SetDrawMode(sentinel, FPDF_FILLMODE_WINDING, 0)
            FPDFPage_InsertObject(page, sentinel)
        }
        guard FPDFPage_GenerateContent(page) != 0 else { throw PDFSourceError.content }
    }
}

struct PDFAttachmentEntry: Identifiable, Equatable { let index: Int, name: String; let size: Int; var id: Int { index } }
@MainActor enum PDFDocumentExtras {
    private static func open<T>(_ data: Data,_ body: (FPDF_DOCUMENT) throws -> T) throws -> T {
        _ = PDFiumRuntime.ready
        let storage = data as NSData
        return try withExtendedLifetime(storage) {
            guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
            defer { FPDF_CloseDocument(document) }; return try body(document)
        }
    }
    private static func save(_ document: FPDF_DOCUMENT) throws -> Data {
        var size = 0
        guard let buffer = BotPlusPDFium_SaveDocument(document,&size),size > 0 else { throw PDFSourceError.save }
        defer { BotPlusPDFium_Free(buffer) }; return Data(bytes: buffer,count: size)
    }
    private static func entries(_ document: FPDF_DOCUMENT) throws -> [PDFAttachmentEntry] {
        let count = FPDFDoc_GetAttachmentCount(document); guard count >= 0,count <= 10000 else { throw PDFSourceError.content }
        return try (0..<count).map { index in
            guard let entry = FPDFDoc_GetAttachment(document,index) else { throw PDFSourceError.content }
            let bytes = FPDFAttachment_GetName(entry,nil,0); guard bytes >= 2,bytes <= 131072 else { throw PDFSourceError.content }
            var text = [UInt16](repeating: 0,count: Int(bytes)/2)
            _ = text.withUnsafeMutableBufferPointer { FPDFAttachment_GetName(entry,$0.baseAddress,bytes) }
            var size: UInt = 0; _ = FPDFAttachment_GetFile(entry,nil,0,&size)
            guard size <= UInt(Int.max) else { throw PDFSourceError.content }
            return PDFAttachmentEntry(index: Int(index),name: String(decoding: text.prefix { $0 != 0 },as: UTF16.self),size: Int(size))
        }
    }
    static func attachments(_ data: Data) throws -> [PDFAttachmentEntry] { try open(data,entries) }
    private static func file(_ document: FPDF_DOCUMENT,index: Int) throws -> Data {
        guard index >= 0,index < Int(FPDFDoc_GetAttachmentCount(document)),let entry = FPDFDoc_GetAttachment(document,Int32(index)) else { throw PDFSourceError.content }
        var size: UInt = 0
        guard FPDFAttachment_GetFile(entry,nil,0,&size) != 0,size <= 256*1024*1024 else { throw PDFSourceError.content }
        if size == 0 { return Data() }
        var result = Data(count: Int(size))
        let ok = result.withUnsafeMutableBytes { FPDFAttachment_GetFile(entry,$0.baseAddress,size,&size) }
        guard ok != 0,size <= UInt(result.count) else { throw PDFSourceError.content }; return result.prefix(Int(size))
    }
    static func attachment(_ data: Data,index: Int) throws -> Data { try open(data) { try file($0,index: index) } }
    private static func add(_ document: FPDF_DOCUMENT,name: String,data: Data) throws {
        guard !name.isEmpty,name.utf16.count < 32000,data.count <= 256*1024*1024 else { throw PDFSourceError.content }
        let text = Array(name.utf16)+[0]
        guard let entry = text.withUnsafeBufferPointer({ FPDFDoc_AddAttachment(document,$0.baseAddress) }) else { throw PDFSourceError.content }
        guard data.withUnsafeBytes({ FPDFAttachment_SetFile(entry,document,$0.baseAddress,UInt(data.count)) }) != 0 else { throw PDFSourceError.save }
    }
    static func changeAttachment(_ data: Data,delete: Int? = nil,name: String? = nil,file: Data? = nil) throws -> Data {
        try open(data) { document in
            guard FPDF_GetDocPermissions(document) & (1 << 3) != 0 else { throw PDFSourceError.permission }
            if let delete { guard delete >= 0,delete < Int(FPDFDoc_GetAttachmentCount(document)),FPDFDoc_DeleteAttachment(document,Int32(delete)) != 0 else { throw PDFSourceError.content } }
            if let name,let file {
                let names = Set(try entries(document).map(\.name))
                var unique = name,number = 2
                let url = URL(fileURLWithPath: name),suffix = url.pathExtension,stem = url.deletingPathExtension().lastPathComponent
                while names.contains(unique) {
                    unique = stem+" (\(number))"+(suffix.isEmpty ? "" : "."+suffix); number += 1
                    guard number <= 10002 else { throw PDFSourceError.content }
                }
                try add(document,name: unique,data: file)
            }; return try save(document)
        }
    }
    // PDFKit page assembly doesn't carry the EmbeddedFiles name tree. Retain
    // it explicitly from the last complete document rather than dropping files.
    static func preserveAttachments(from source: Data,in output: Data) throws -> Data {
        try open(source) { original in
            let files = try entries(original); guard !files.isEmpty else { return output }
            guard files.reduce(0,{ $0+min($1.size,512*1024*1024) }) <= 512*1024*1024 else { throw PDFSourceError.content }
            return try open(output) { destination in
                let count = FPDFDoc_GetAttachmentCount(destination)
                for index in (0..<max(0,count)).reversed() { guard FPDFDoc_DeleteAttachment(destination,index) != 0 else { throw PDFSourceError.save } }
                for entry in files { try add(destination,name: entry.name,data: file(original,index: entry.index)) }
                return try save(destination)
            }
        }
    }
    static func resize(_ data: Data,indices: [Int],width: Double,height: Double,scale: Bool) throws -> Data {
        guard [width,height].allSatisfy({ $0.isFinite && (1...14400).contains($0) }) else { throw PDFSourceError.content }
        return try open(data) { document in
            guard FPDF_GetDocPermissions(document) & (1 << 3) != 0 else { throw PDFSourceError.permission }
            for index in indices {
                guard index >= 0,index < Int(FPDF_GetPageCount(document)),let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
                defer { FPDF_ClosePage(page) }
                var left: Float = 0,bottom: Float = 0,right: Float = 0,top: Float = 0
                guard FPDFPage_GetMediaBox(page,&left,&bottom,&right,&top) != 0,right > left,top > bottom else { throw PDFSourceError.page }
                if scale {
                    let sx = Float(width)/max(1,right-left),sy = Float(height)/max(1,top-bottom)
                    var matrix = FS_MATRIX(a: sx,b: 0,c: 0,d: sy,e: -left*sx,f: -bottom*sy)
                    var clip = FS_RECTF(left: 0,top: Float(height),right: Float(width),bottom: 0)
                    guard FPDFPage_TransFormWithClip(page,&matrix,&clip) != 0 else { throw PDFSourceError.content }
                    FPDFPage_TransformAnnots(page,Double(sx),0,0,Double(sy),Double(-left*sx),Double(-bottom*sy))
                }
                FPDFPage_SetMediaBox(page,0,0,Float(width),Float(height)); FPDFPage_SetCropBox(page,0,0,Float(width),Float(height))
            }
            return try save(document)
        }
    }
}

@MainActor extension PDFContentSession {
    var vectorSnapPoints: [CGPoint] {
        if let snapPointCache { return snapPointCache }
        var result: [CGPoint] = [],kinds: [PDFEngineeringSnap] = [],segments: [(CGPoint,CGPoint)] = [],curves: [PDFBezierSegment] = []
        var visited = 0
        func append(_ point: CGPoint,_ kind: PDFEngineeringSnap.Kind) {
            guard result.count < 20000,point.x.isFinite,point.y.isFinite else { return }
            result.append(point); kinds.append(PDFEngineeringSnap(point: point,kind: kind))
        }
        func collect(_ object: FPDF_PAGEOBJECT,parent: CGAffineTransform,depth: Int) {
            guard depth < 32,visited < 100000,result.count < 20000 else { return }; visited += 1
            let type = FPDFPageObj_GetType(object)
            if type == FPDF_PAGEOBJ_FORM {
                var m = Self.identity; guard FPDFPageObj_GetMatrix(object,&m) != 0 else { return }
                let q = CGAffineTransform(a: CGFloat(m.a),b: CGFloat(m.b),c: CGFloat(m.c),d: CGFloat(m.d),tx: CGFloat(m.e),ty: CGFloat(m.f)),p = parent
                let world = CGAffineTransform(a: p.a*q.a+p.c*q.b,b: p.b*q.a+p.d*q.b,c: p.a*q.c+p.c*q.d,d: p.b*q.c+p.d*q.d,tx: p.a*q.tx+p.c*q.ty+p.tx,ty: p.b*q.tx+p.d*q.ty+p.ty)
                guard [world.a,world.b,world.c,world.d,world.tx,world.ty].allSatisfy(\.isFinite) else { return }
                for index in 0..<max(0,FPDFFormObj_CountObjects(object)) {
                    guard visited < 100000 else { break }
                    if let child = FPDFFormObj_GetObject(object,UInt(index)) { collect(child,parent: world,depth: depth+1) }
                }
                return
            }
            guard type == FPDF_PAGEOBJ_PATH,let local = path(object) else { return }
            var transform = parent
            guard let path = local.copy(using: &transform) else { return }
            var previous: CGPoint?,first: CGPoint?
            func curve(_ segment: PDFBezierSegment) {
                guard segment.valid,curves.count < 20000 else { return }
                curves.append(segment); append(segment.p3,.endpoint)
                for point in segment.extrema { append(point,.extremum) }
            }
            path.applyWithBlock { element in
                switch element.pointee.type {
                case .moveToPoint: previous = element.pointee.points[0]; first = previous; append(element.pointee.points[0],.endpoint)
                case .addLineToPoint:
                    let p = element.pointee.points[0]; if let a = previous { append(CGPoint(x: (a.x+p.x)/2,y: (a.y+p.y)/2),.midpoint); if segments.count < 20000 { segments.append((a,p)) } }; append(p,.endpoint); previous = p
                case .addQuadCurveToPoint:
                    let c = element.pointee.points[0],p = element.pointee.points[1]
                    if let a = previous { curve(PDFBezierSegment(p0: a,p1: CGPoint(x: a.x+2*(c.x-a.x)/3,y: a.y+2*(c.y-a.y)/3),p2: CGPoint(x: p.x+2*(c.x-p.x)/3,y: p.y+2*(c.y-p.y)/3),p3: p)) }; previous = p
                case .addCurveToPoint:
                    let p = element.pointee.points[2]
                    if let a = previous { curve(PDFBezierSegment(p0: a,p1: element.pointee.points[0],p2: element.pointee.points[1],p3: p)) }; previous = p
                case .closeSubpath: if let a = previous,let b = first,segments.count < 20000 { segments.append((a,b)); append(CGPoint(x: (a.x+b.x)/2,y: (a.y+b.y)/2),.midpoint) }; previous = first
                default: break
                }
            }
        }
        for index in 0..<max(0,FPDFPage_CountObjects(handle.page)) {
            guard visited < 100000,result.count < 20000 else { break }
            if let object = FPDFPage_GetObject(handle.page,index) { collect(object,parent: .identity,depth: 0) }
        }
        snapPointCache = result; snapKindsCache = kinds; snapSegmentsCache = segments; snapCurvesCache = curves; return result
    }
}

@MainActor extension PDFDocumentExtras {
    static func overlay(_ data: Data,layer: Data,indices: [Int],markName: String? = nil,remove: Bool = false) throws -> Data {
        try open(data) { document in
            guard FPDF_GetDocPermissions(document) & (1<<3) != 0 else { throw PDFSourceError.permission }
            return try open(layer) { source in
                guard Int(FPDF_GetPageCount(source)) == indices.count else { throw PDFSourceError.content }
                for (sourceIndex,index) in indices.enumerated() {
                    guard index >= 0,index < Int(FPDF_GetPageCount(document)),let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
                    defer { FPDF_ClosePage(page) }
                    if let markName {
                        for i in stride(from: Int(FPDFPage_CountObjects(page))-1,through: 0,by: -1) {
                            guard let object = FPDFPage_GetObject(page,Int32(i)) else { continue }
                            var owned = false
                            for m in 0..<max(0,FPDFPageObj_CountMarks(object)) {
                                guard let mark = FPDFPageObj_GetMark(object,UInt(m)) else { continue }
                                var size: UInt = 0
                                guard FPDFPageObjMark_GetName(mark,nil,0,&size) != 0,size > 0,size < 4096 else { continue }
                                var units = [UInt16](repeating: 0,count: Int(size/2))
                                _ = units.withUnsafeMutableBufferPointer { FPDFPageObjMark_GetName(mark,$0.baseAddress,size,&size) }
                                if String(decoding: units.prefix { $0 != 0 },as: UTF16.self) == markName { owned = true }
                            }
                            if owned { guard FPDFPage_RemoveObject(page,object) != 0 else { throw PDFSourceError.content }; FPDFPageObj_Destroy(object) }
                        }
                    }
                    if remove { guard FPDFPage_GenerateContent(page) != 0 else { throw PDFSourceError.save }; continue }
                    guard let xobject = FPDF_NewXObjectFromPage(document,source,Int32(sourceIndex)) else { throw PDFSourceError.content }
                    defer { FPDF_CloseXObject(xobject) }
                    guard let object = FPDF_NewFormObjectFromXObject(xobject) else { throw PDFSourceError.content }
                    if let markName,markName.withCString({ FPDFPageObj_AddMark(object,$0) }) == nil { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
                    FPDFPage_InsertObject(page,object)
                    guard FPDFPage_GenerateContent(page) != 0 else { throw PDFSourceError.save }
                }
                return try save(document)
            }
        }
    }
}

struct PDFNamedTarget: Identifiable {
    var name: String, page: Int
    var x: Double?, y: Double?, zoom: Double?
    var viewExpression: String? = nil
    var originalName: String? = nil
    var id: String { name }
}
@MainActor extension PDFDocumentExtras {
    static func normalized(_ data: Data) throws -> Data { try open(data) { document in guard FPDF_GetDocPermissions(document)&(1<<3) != 0 else { throw PDFSourceError.permission }; return try save(document) } }
    static func namedTargets(_ data: Data) throws -> [PDFNamedTarget] {
        let expressions = try PDFContentNormalizer.namedExpressions(data)
        return try open(data) { document in
            let count = FPDF_CountNamedDests(document); guard count <= 100000 else { throw PDFSourceError.content }
            return try (0..<Int(count)).compactMap { index in
                var length = 0
                guard let destination = FPDF_GetNamedDest(document,Int32(index),nil,&length),length >= 2,length <= 131072 else { return nil }
                var name = [UInt16](repeating: 0,count: length/2)
                let ok = name.withUnsafeMutableBytes { FPDF_GetNamedDest(document,Int32(index),$0.baseAddress,&length) }
                guard ok != nil,length > 0 else { throw PDFSourceError.content }
                let page = Int(FPDFDest_GetDestPageIndex(document,destination)); guard page >= 0,page < Int(FPDF_GetPageCount(document)) else { return nil }
                var hasX: Int32 = 0,hasY: Int32 = 0,hasZoom: Int32 = 0,x: Float = 0,y: Float = 0,zoom: Float = 0
                _ = FPDFDest_GetLocationInPage(destination,&hasX,&hasY,&hasZoom,&x,&y,&zoom)
                let title = String(decoding: name.prefix { $0 != 0 },as: UTF16.self)
                return PDFNamedTarget(name: title,page: page,x: hasX != 0 ? Double(x) : nil,y: hasY != 0 ? Double(y) : nil,zoom: hasZoom != 0 ? Double(zoom) : nil,viewExpression: expressions[title],originalName: title)
            }
        }
    }
    static func writeNamedTargets(_ data: Data,targets: [PDFNamedTarget],bookmarks: [Int:String]) throws -> Data {
        let previous = try namedTargets(data)
        return try PDFContentNormalizer.namedTargets(data,targets: targets,bookmarks: bookmarks,previousTargets: previous)
    }
}
@MainActor private extension PDFContentNormalizer {
    static func namedTargets(_ data: Data,targets: [PDFNamedTarget],bookmarks: [Int:String],previousTargets: [PDFNamedTarget]) throws -> Data {
        guard targets.count <= 100000,Set(targets.map(\.name)).count == targets.count,targets.allSatisfy({ !$0.name.isEmpty && $0.name.utf16.count < 32000 && ($0.viewExpression == nil || PDFDestinationView(expression: $0.viewExpression!) != nil) }) else { throw PDFSourceError.content }
        let normalized = try PDFDocumentExtras.normalized(data)
        var syntax = Syntax(bytes: Array(normalized))
        let previous = try syntax.lastXref(),offsets = try syntax.objectOffsets(xref: previous),trailer = try syntax.trailer(xref: previous)
        guard trailer["Encrypt"] == nil,let rootRange = trailer["Root"],let rootRef = syntax.reference(rootRange),let rootOffset = offsets[rootRef.0] else { throw PDFSourceError.content }
        let catalog = try syntax.objectDictionary(at: rootOffset)
        guard let pagesRange = catalog.values["Pages"],let pagesRef = syntax.reference(pagesRange) else { throw PDFSourceError.content }
        var pages: [(Int,Int)] = [],visited = Set<Int>()
        func walk(_ reference: (Int,Int),depth: Int) throws {
            guard depth < 128,visited.insert(reference.0).inserted,let offset = offsets[reference.0] else { throw PDFSourceError.content }
            let dict = try syntax.objectDictionary(at: offset)
            if let type = dict.values["Type"],syntax.string(type) == "/Page" { pages.append(reference); return }
            guard let kids = dict.values["Kids"] else { throw PDFSourceError.content }
            for child in syntax.references(kids) { try walk(child,depth: depth+1) }
        }
        try walk(pagesRef,depth: 0)
        guard targets.allSatisfy({ pages.indices.contains($0.page) && [$0.x,$0.y,$0.zoom].compactMap { $0 }.allSatisfy(\.isFinite) }) else { throw PDFSourceError.content }
        func raw(_ range: Range<Int>) -> Data { Data(syntax.bytes[range]) }
        func pdfString(_ value: String) -> String { "<FEFF"+value.utf16.map { String(format: "%04X",UInt32($0)) }.joined()+">" }
        func destination(_ target: PDFNamedTarget) -> String {
            let page = pages[target.page]
            if let expression = target.viewExpression,PDFDestinationView(expression: expression) != nil { return "[\(page.0) \(page.1) R \(expression)]" }
            let expression = PDFDestinationView(mode: .XYZ,values: [target.x,target.y,target.zoom])!.expression
            return "[\(page.0) \(page.1) R \(expression)]"
        }
        let identities = targets.compactMap(\.originalName)
        guard Set(identities).count == identities.count else { throw PDFSourceError.content }
        let byOriginal = Dictionary(uniqueKeysWithValues: targets.compactMap { target in target.originalName.map { ($0,target) } })
        let byNewName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name,$0) })
        var replacements: [String:Data] = [:]
        for previous in previousTargets {
            let fallback = byNewName[previous.name].flatMap { $0.originalName == nil ? $0 : nil }
            let current = byOriginal[previous.name] ?? fallback
            if let current { if current.name != previous.name { replacements[previous.name] = Data(pdfString(current.name).utf8) } }
            else { replacements[previous.name] = Data(destination(previous).utf8) }
        }
        func decodedName(_ input: Range<Int>?) throws -> String? {
            guard var range = input else { return nil }; var seen = Set<Int>()
            while let reference = syntax.reference(range) {
                guard seen.count < 64,seen.insert(reference.0).inserted,let offset = offsets[reference.0] else { throw PDFSourceError.content }
                syntax.cursor = offset; _ = syntax.token(); _ = syntax.token(); guard syntax.token() == "obj" else { throw PDFSourceError.content }; range = try syntax.value()
            }
            let bytes = Array(syntax.bytes[range]); guard let first = bytes.first else { return nil }
            var result: [UInt8] = []
            if first == 47 {
                var index = 1
                while index < bytes.count {
                    if bytes[index] == 35,index+2 < bytes.count,let byte = UInt8(String(decoding: bytes[(index+1)...(index+2)],as: UTF8.self),radix: 16) { result.append(byte); index += 3 }
                    else { result.append(bytes[index]); index += 1 }
                }
            } else if first == 60,bytes.count > 1,bytes[1] != 60 {
                var digits = bytes.dropFirst().dropLast().filter { ![9,10,12,13,32].contains($0) }
                if digits.count%2 == 1 { digits.append(48) }
                for index in stride(from: 0,to: digits.count,by: 2) { guard let byte = UInt8(String(decoding: digits[index..<(index+2)],as: UTF8.self),radix: 16) else { throw PDFSourceError.content }; result.append(byte) }
            } else if first == 40 {
                var index = 1
                while index < bytes.count-1 {
                    let byte = bytes[index]; index += 1
                    guard byte == 92 else { result.append(byte); continue }
                    guard index < bytes.count-1 else { throw PDFSourceError.content }; let escaped = bytes[index]; index += 1
                    if escaped == 10 { continue }; if escaped == 13 { if index < bytes.count-1,bytes[index] == 10 { index += 1 }; continue }
                    if (48...55).contains(escaped) {
                        var value = Int(escaped-48),count = 1
                        while index < bytes.count-1,count < 3,(48...55).contains(bytes[index]) { value = value*8+Int(bytes[index]-48); index += 1; count += 1 }; result.append(UInt8(value & 255))
                    } else { result.append([110:10,114:13,116:9,98:8,102:12][escaped] ?? escaped) }
                }
            } else { return nil }
            if result.starts(with: [254,255]) { return String(data: Data(result.dropFirst(2)),encoding: .utf16BigEndian) }
            if result.starts(with: [255,254]) { return String(data: Data(result.dropFirst(2)),encoding: .utf16LittleEndian) }
            return String(bytes: result,encoding: .utf8) ?? String(bytes: result,encoding: .windowsCP1252)
        }
        func replacement(_ range: Range<Int>) throws -> Data? {
            guard !replacements.isEmpty,let name = try decodedName(range) else { return nil }; return replacements[name]
        }
        func edited(_ range: Range<Int>,edits: [(Range<Int>,Data)]) -> Data {
            var bytes = raw(range)
            for (span,value) in edits.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) { bytes.replaceSubrange((span.lowerBound-range.lowerBound)..<(span.upperBound-range.lowerBound),with: value) }
            return bytes
        }
        func rewriteReferences(_ range: Range<Int>,depth: Int = 0) throws -> Data? {
            guard depth < 64 else { throw PDFSourceError.content }
            guard !replacements.isEmpty else { return nil }
            syntax.cursor = range.lowerBound; syntax.whitespace(); let start = syntax.cursor
            guard start < range.upperBound else { return nil }
            if syntax.bytes[start] == 60,start+1 < range.upperBound,syntax.bytes[start+1] == 60 {
                let values = try syntax.dictionary(depth: depth),isGoTo = try decodedName(values["S"]) == "GoTo"
                let subtype = try decodedName(values["Subtype"])
                let hasDestination = values["Title"] != nil || subtype == "Link"
                var edits: [(Range<Int>,Data)] = []
                for (key,span) in values {
                    if (key == "D" && isGoTo) || (key == "Dest" && hasDestination),let value = try replacement(span) { edits.append((span,value)) }
                    else if let value = try rewriteReferences(span,depth: depth+1) { edits.append((span,value)) }
                }
                return edits.isEmpty ? nil : edited(range,edits: edits)
            }
            if syntax.bytes[start] == 91 {
                syntax.cursor = start+1; var spans: [Range<Int>] = []
                while syntax.cursor < range.upperBound { syntax.whitespace(); guard syntax.cursor < range.upperBound else { throw PDFSourceError.content }; if syntax.bytes[syntax.cursor] == 93 { break }; spans.append(try syntax.value(depth: depth+1)) }
                var edits: [(Range<Int>,Data)] = []
                for span in spans { if let value = try rewriteReferences(span,depth: depth+1) { edits.append((span,value)) } }
                return edits.isEmpty ? nil : edited(range,edits: edits)
            }
            return nil
        }
        var names: [String:Range<Int>] = [:]
        if let range = catalog.values["Names"] {
            if let reference = syntax.reference(range),let offset = offsets[reference.0] { names = try syntax.objectDictionary(at: offset).values }
            else { syntax.cursor = range.lowerBound; names = try syntax.dictionary() }
        }
        let next = max(offsets.keys.max() ?? 0,trailer["Size"].flatMap { Int(syntax.string($0)) } ?? 0)+1
        let destID = next,namesID = next+1
        var output = normalized; output.append(Data("\n".utf8)); var written: [(Int,Int,Int)] = [],pending: [Int:(Int,Data)] = [:]
        func object(_ id: Int,_ generation: Int,_ body: Data) {
            pending[id] = (generation,body)
        }
        if !replacements.isEmpty {
            for (id,offset) in offsets where id != rootRef.0 {
                syntax.cursor = offset; _ = syntax.token(); guard let generation = Int(syntax.token()),syntax.token() == "obj" else { continue }
                let body = try syntax.value()
                let afterBody = syntax.cursor; syntax.whitespace()
                if syntax.token() == "stream" { continue }; syntax.cursor = afterBody
                if let value = try rewriteReferences(body) { object(id,generation,value) }
            }
        }
        let entries = targets.sorted { Array($0.name.utf16).lexicographicallyPrecedes(Array($1.name.utf16)) }.map { pdfString($0.name)+" "+destination($0) }.joined(separator: "\n")
        object(destID,0,Data(("<< /Names ["+entries+"] >>").utf8))
        var nameBody = Data("<< ".utf8)
        for key in names.keys.sorted() where key != "Dests" { nameBody.append(Data(("/"+key+" ").utf8)); nameBody.append(raw(names[key]!)); nameBody.append(Data(" ".utf8)) }
        nameBody.append(Data("/Dests \(destID) 0 R >>".utf8)); object(namesID,0,nameBody)
        var rootBody = Data("<< ".utf8)
        for key in catalog.values.keys.sorted() where key != "Names" && key != "Dests" {
            let span = catalog.values[key]!
            var value: Data?
            if key == "OpenAction" { value = try replacement(span) }
            if value == nil { value = try rewriteReferences(span) }
            rootBody.append(Data(("/"+key+" ").utf8)); rootBody.append(value ?? raw(span)); rootBody.append(Data(" ".utf8))
        }
        rootBody.append(Data("/Names \(namesID) 0 R >>".utf8)); object(rootRef.0,rootRef.1,rootBody)
        if !bookmarks.isEmpty,let range = catalog.values["Outlines"],let reference = syntax.reference(range),let offset = offsets[reference.0] {
            let root = try syntax.objectDictionary(at: offset)
            var flattened: [(Int,Int)] = [],seen = Set<Int>()
            func outlines(_ reference: (Int,Int),depth: Int) throws {
                guard depth < 128,seen.insert(reference.0).inserted,let offset = offsets[reference.0] else { throw PDFSourceError.content }
                let node = try syntax.objectDictionary(at: offset); flattened.append(reference)
                if let first = node.values["First"].flatMap(syntax.reference) { try outlines(first,depth: depth+1) }
                if let next = node.values["Next"].flatMap(syntax.reference) { try outlines(next,depth: depth) }
            }
            if let first = root.values["First"].flatMap(syntax.reference) { try outlines(first,depth: 0) }
            for (index,name) in bookmarks {
                guard flattened.indices.contains(index),targets.contains(where: { $0.name == name }),let offset = offsets[flattened[index].0] else { throw PDFSourceError.content }
                let node = try syntax.objectDictionary(at: offset); var body = Data("<< ".utf8)
                for key in node.values.keys.sorted() where key != "Dest" && key != "A" { body.append(Data(("/"+key+" ").utf8)); body.append(try rewriteReferences(node.values[key]!) ?? raw(node.values[key]!)); body.append(Data(" ".utf8)) }
                body.append(Data(("/A << /S /GoTo /D "+pdfString(name)+" >> >>").utf8)); object(flattened[index].0,flattened[index].1,body)
            }
        }
        for (id,value) in pending.sorted(by: { $0.key < $1.key }) {
            written.append((id,value.0,output.count)); output.append(Data("\(id) \(value.0) obj\n".utf8)); output.append(value.1); output.append(Data("\nendobj\n".utf8))
        }
        let xref = output.count
        output.append(Data("xref\n".utf8))
        for entry in written.sorted(by: { $0.0 < $1.0 }) { output.append(Data("\(entry.0) 1\n".utf8)); output.append(Data(String(format: "%010lld %05d n \n",Int64(entry.2),Int32(entry.1)).utf8)) }
        output.append(Data("trailer\n<< /Size \(next+2) /Root \(rootRef.0) \(rootRef.1) R /Prev \(previous)".utf8))
        for key in ["Info","ID"] { if let range = trailer[key] { output.append(Data((" /"+key+" ").utf8)); output.append(raw(range)) } }
        output.append(Data(" >>\nstartxref\n\(xref)\n%%EOF\n".utf8)); return output
    }
}

// Catalog-only operations retain OCG/OCMD expressions and tagged-content IDs.
@MainActor private extension PDFContentNormalizer {
    @MainActor private struct CatalogFile {
        var syntax: Syntax
        let data: Data, previous: Int, offsets: [Int:Int], trailer: [String:Range<Int>], root: (Int,Int), catalog: [String:Range<Int>]
        init(_ input: Data,normalize: Bool = true) throws {
            guard input.count <= 512*1024*1024 else { throw PDFSourceError.content }
            data = normalize ? try PDFDocumentExtras.normalized(input) : input; syntax = Syntax(bytes: Array(data))
            previous = try syntax.lastXref(); offsets = try syntax.objectOffsets(xref: previous); trailer = try syntax.trailer(xref: previous)
            guard trailer["Encrypt"] == nil,let value = trailer["Root"],let ref = syntax.reference(value),let offset = offsets[ref.0] else { throw PDFSourceError.content }
            root = ref; catalog = try syntax.objectDictionary(at: offset).values
        }
        mutating func resolve(_ range: Range<Int>) throws -> Range<Int> {
            guard let ref = syntax.reference(range) else { return range }
            guard let offset = offsets[ref.0] else { throw PDFSourceError.content }
            syntax.cursor = offset; _ = syntax.token(); _ = syntax.token(); guard syntax.token() == "obj" else { throw PDFSourceError.content }
            return try syntax.value(depth: 0)
        }
        mutating func dictionary(_ range: Range<Int>?) throws -> [String:Range<Int>] {
            guard let range else { return [:] }; let value = try resolve(range)
            syntax.cursor = value.lowerBound; return try syntax.dictionary()
        }
        mutating func array(_ range: Range<Int>?) throws -> [Range<Int>] {
            guard let range else { return [] }; let value = try resolve(range); syntax.cursor = value.lowerBound; syntax.whitespace()
            guard syntax.cursor < syntax.bytes.count,syntax.bytes[syntax.cursor] == 91 else { return [] }; syntax.cursor += 1
            var result: [Range<Int>] = []
            while syntax.cursor < value.upperBound {
                syntax.whitespace(); guard syntax.cursor < value.upperBound else { throw PDFSourceError.content }; if syntax.bytes[syntax.cursor] == 93 { return result }
                result.append(try syntax.value(depth: 0)); guard result.count <= 100000 else { throw PDFSourceError.content }
            }; throw PDFSourceError.content
        }
        func raw(_ range: Range<Int>) -> Data { Data(syntax.bytes[range]) }
        func name(_ range: Range<Int>?) -> String { guard let range else { return "" }; return syntax.string(range).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        mutating func text(_ range: Range<Int>?) throws -> String {
            guard let range else { return "" }; let resolvedRange = try resolve(range),bytes = Array(syntax.bytes[resolvedRange])
            guard bytes.count >= 2 else { return "" }; var decoded: [UInt8] = []
            if bytes[0] == 60,bytes[1] != 60 {
                let digits = bytes.dropFirst().dropLast().filter { ![9,10,12,13,32].contains($0) }; var hex = String(decoding: digits,as: UTF8.self)
                if hex.count%2 != 0 { hex += "0" }; var i = hex.startIndex
                while i < hex.endIndex { let end = hex.index(i,offsetBy: 2); guard let byte = UInt8(hex[i..<end],radix: 16) else { throw PDFSourceError.content }; decoded.append(byte); i = end }
            } else if bytes[0] == 40 {
                var i = 1
                while i < bytes.count-1 {
                    let byte = bytes[i]; i += 1
                    if byte != 92 { decoded.append(byte); continue }
                    guard i < bytes.count-1 else { break }; let next = bytes[i]; i += 1
                    switch next {
                    case 110: decoded.append(10); case 114: decoded.append(13); case 116: decoded.append(9); case 98: decoded.append(8); case 102: decoded.append(12)
                    case 10: break
                    case 13: if i < bytes.count-1,bytes[i] == 10 { i += 1 }
                    case 48...55:
                        var number = Int(next-48),count = 1
                        while count < 3,i < bytes.count-1,(48...55).contains(bytes[i]) { number = number*8+Int(bytes[i]-48); count += 1; i += 1 }; decoded.append(UInt8(number & 255))
                    default: decoded.append(next)
                    }
                }
            } else { return "" }
            if decoded.starts(with: [254,255]) { return String(data: Data(decoded.dropFirst(2)),encoding: .utf16BigEndian) ?? "" }
            if decoded.starts(with: [255,254]) { return String(data: Data(decoded.dropFirst(2)),encoding: .utf16LittleEndian) ?? "" }
            return String(data: Data(decoded),encoding: .utf8) ?? String(data: Data(decoded),encoding: .windowsCP1252) ?? ""
        }
        func decodedName(_ range: Range<Int>) -> String {
            let raw = Array(name(range).utf8); var output: [UInt8] = [],i = 0
            while i < raw.count {
                if raw[i] == 35,i+2 < raw.count,let byte = UInt8(String(decoding: raw[(i+1)...(i+2)],as: UTF8.self),radix: 16) { output.append(byte); i += 3 }
                else { output.append(raw[i]); i += 1 }
            }
            return String(bytes: output,encoding: .utf8) ?? String(bytes: output,encoding: .windowsCP1252) ?? ""
        }
        mutating func pageReferences() throws -> [(Int,Int)] {
            guard let pages = catalog["Pages"] else { throw PDFSourceError.content }
            var result: [(Int,Int)] = [],seen = Set<Int>()
            func walk(_ range: Range<Int>,depth: Int) throws {
                guard depth < 128,let ref = syntax.reference(range),seen.insert(ref.0).inserted,seen.count <= 100000 else { throw PDFSourceError.content }
                let node = try dictionary(range)
                if name(node["Type"]) == "Page" { result.append(ref); return }
                guard name(node["Type"]) == "Pages",node["Kids"] != nil else { throw PDFSourceError.content }
                for kid in try array(node["Kids"]) { try walk(kid,depth: depth+1) }
            }
            try walk(pages,depth: 0); return result
        }
        mutating func structureChildren(_ range: Range<Int>?,parent: (Int,Int),minimumCount: Int = 2) throws -> [(Int,Int)]? {
            guard let parentOffset = offsets[parent.0] else { return nil }
            let owner = try syntax.objectDictionary(at: parentOffset).values
            guard name(owner["Type"]) == "StructTreeRoot" || !name(owner["S"]).isEmpty else { return nil }
            guard let range else { return minimumCount == 0 ? [] : nil }
            let resolved = try resolve(range)
            guard syntax.string(resolved).hasPrefix("[") else { return nil }
            let values = try array(resolved)
            guard values.count >= minimumCount,values.count <= 10000 else { return nil }
            let refs = values.compactMap { syntax.reference($0) }
            guard refs.count == values.count,Set(refs.map(\.0)).count == refs.count else { return nil }
            for (value,ref) in zip(values,refs) {
                let child = try dictionary(value)
                guard ["","StructElem"].contains(name(child["Type"])),!name(child["S"]).isEmpty,let p = child["P"].flatMap(syntax.reference),p.0 == parent.0,p.1 == parent.1,ref.0 != parent.0 else { return nil }
            }
            return refs
        }
        static func byteString(_ value: String) -> Data {
            var result = "("
            for byte in value.utf8 {
                if byte == 40 || byte == 41 || byte == 92 { result += "\\"+String(UnicodeScalar(byte)) }
                else if byte < 32 || byte >= 127 { result += String(format: "\\%03o",Int(byte)) }
                else { result += String(UnicodeScalar(byte)) }
            }
            return Data((result+")").utf8)
        }
        static func string(_ value: String) -> Data { Data(("<FEFF"+value.utf16.map { String(format: "%04X",UInt32($0)) }.joined()+">").utf8) }
        func rewrite(_ values: [String:Range<Int>],excluding: Set<String>,appending: [String:Data]) -> Data {
            var body = Data("<< ".utf8)
            for key in values.keys.sorted() where !excluding.contains(key) { body.append(Data(("/"+key+" ").utf8)); body.append(raw(values[key]!)); body.append(Data(" ".utf8)) }
            for key in appending.keys.sorted() { body.append(Data(("/"+key+" ").utf8)); body.append(appending[key]!); body.append(Data(" ".utf8)) }
            body.append(Data(">>".utf8)); return body
        }
        func write(_ objects: [(Int,Int,Data)]) throws -> Data {
            guard Set(objects.map { $0.0 }).count == objects.count else { throw PDFSourceError.content }
            var output = data; output.append(Data("\n".utf8)); var offsets: [(Int,Int,Int)] = []
            for (id,generation,body) in objects { offsets.append((id,generation,output.count)); output.append(Data("\(id) \(generation) obj\n".utf8)); output.append(body); output.append(Data("\nendobj\n".utf8)) }
            let xref = output.count; output.append(Data("xref\n".utf8))
            for (id,generation,offset) in offsets.sorted(by: { $0.0 < $1.0 }) { output.append(Data(String(format: "%d 1\n%010d %05d n \n",id,offset,generation).utf8)) }
            let size = max(self.offsets.keys.max() ?? 0,objects.map { $0.0 }.max() ?? 0)+1
            output.append(Data("trailer\n<< /Size \(size) /Root \(root.0) \(root.1) R /Prev \(previous) ".utf8))
            for key in ["Info","ID"] { if let value = trailer[key] { output.append(Data(("/"+key+" ").utf8)); output.append(raw(value)); output.append(Data(" ".utf8)) } }
            output.append(Data(">>\nstartxref\n\(xref)\n%%EOF\n".utf8)); return output
        }
    }
    // PDFKit shifts Rect/AP when normalizing a nonzero MediaBox origin but leaves
    // InkList in the old absolute coordinates. Repair only newly written output;
    // retain appearance streams, the original live document and all page content.
    static func repairWrittenInk(_ data: Data,originalOrigins: [Int:CGPoint]) throws -> Data {
        guard originalOrigins.values.contains(where: { $0 != .zero }) else { return data }
        var file = try CatalogFile(data,normalize: false)
        let pages = try file.pageReferences()
        guard let provider = CGDataProvider(data: data as CFData),let cg = CGPDFDocument(provider) else { throw PDFSourceError.document }
        var changes: [(Int,Int,Data)] = [],points = 0
        for (index,origin) in originalOrigins.sorted(by: { $0.key < $1.key }) {
            guard pages.indices.contains(index),let page = cg.page(at: index+1),let offset = file.offsets[pages[index].0] else { throw PDFSourceError.page }
            let written = page.getBoxRect(.mediaBox).origin,dx = written.x-origin.x,dy = written.y-origin.y
            guard dx.isFinite,dy.isFinite else { throw PDFSourceError.content }; if dx == 0 && dy == 0 { continue }
            let dictionary = try file.syntax.objectDictionary(at: offset).values
            var annotations: [Data] = [],directChanged = false
            for value in try file.array(dictionary["Annots"]) {
                let annotation = try file.dictionary(value)
                guard file.name(annotation["Subtype"]) == "Ink",let list = annotation["InkList"] else { annotations.append(file.raw(value)); continue }
                var strokes: [String] = []
                for stroke in try file.array(list) {
                    let values = try file.array(stroke); guard values.count >= 2,values.count%2 == 0 else { throw PDFSourceError.content }
                    points += values.count/2; guard points <= 1_000_000 else { throw PDFSourceError.content }
                    var coordinates: [String] = []
                    for (position,raw) in values.enumerated() {
                        let resolved = try file.resolve(raw)
                        guard let number = Double(file.syntax.string(resolved)) else { throw PDFSourceError.content }
                        let updated = number+(position%2 == 0 ? dx : dy); guard updated.isFinite,abs(updated) <= 1e9 else { throw PDFSourceError.content }
                        coordinates.append(String(format: "%.10f",locale: Locale(identifier: "en_US_POSIX"),updated))
                    }
                    strokes.append("["+coordinates.joined(separator: " ")+"]")
                }
                let body = file.rewrite(annotation,excluding: ["InkList"],appending: ["InkList":Data(("["+strokes.joined(separator: " ")+"]").utf8)])
                if let ref = file.syntax.reference(value) { changes.append((ref.0,ref.1,body)); annotations.append(file.raw(value)) }
                else { directChanged = true; annotations.append(body) }
            }
            if directChanged {
                var array = Data("[".utf8); for value in annotations { array.append(value); array.append(Data(" ".utf8)) }; array.append(Data("]".utf8))
                changes.append((pages[index].0,pages[index].1,file.rewrite(dictionary,excluding: ["Annots"],appending: ["Annots":array])))
            }
        }
        return changes.isEmpty ? data : try file.write(changes)
    }
    static let exchangeNamedActions = ["None","NextPage","PrevPage","FirstPage","LastPage","GoBack","GoForward","GoToPage","Find","Print","ZoomIn","ZoomOut"]
    static func bookmarkExchange(_ data: Data) throws -> [PDFBookmarkExchange] {
        var file = try CatalogFile(data)
        let pages = try file.pageReferences(),targets = try PDFDocumentExtras.namedTargets(file.data)
        guard Set(targets.map(\.name)).count == targets.count else { throw PDFSourceError.content }
        let named = Dictionary(uniqueKeysWithValues: targets.map { ($0.name,$0) })
        let outlines = try file.dictionary(file.catalog["Outlines"])
        var visited = Set<Int>(),total = 0
        func target(_ range: Range<Int>,remote: Bool) throws -> (Int?,String?,String?) {
            let value = try file.resolve(range),raw = file.syntax.string(value)
            if raw.hasPrefix("(") || (raw.hasPrefix("<") && !raw.hasPrefix("<<")) || raw.hasPrefix("/") {
                let name = raw.hasPrefix("/") ? file.decodedName(value) : try file.text(value)
                if remote { return (nil,nil,name) }
                guard let entry = named[name],let expression = entry.viewExpression,PDFDestinationView(expression: expression) != nil else { throw PDFSourceError.content }
                return (entry.page+1,expression,name)
            }
            let values = try file.array(value)
            guard values.count >= 2 else { throw PDFSourceError.content }
            let expression = values.dropFirst().map { file.syntax.string($0) }.joined(separator: " ")
            guard let view = PDFDestinationView(expression: expression) else { throw PDFSourceError.content }
            if remote { guard let page = Int(file.syntax.string(values[0])),(0..<1_000_000).contains(page) else { throw PDFSourceError.content }; return (page,view.expression,nil) }
            guard let ref = file.syntax.reference(values[0]),let index = pages.firstIndex(where: { $0.0 == ref.0 && $0.1 == ref.1 }) else { throw PDFSourceError.content }
            return (index+1,view.expression,nil)
        }
        var actionTotal = 0
        func readAction(_ actionRange: Range<Int>,depth: Int,ancestors: Set<Int>) throws -> PDFBookmarkExchange {
            guard depth < 16,actionTotal < 20000 else { throw PDFSourceError.content }; actionTotal += 1
            var active = ancestors
            if let ref = file.syntax.reference(actionRange) { guard active.insert(ref.0).inserted else { throw PDFSourceError.content } }
            var record = PDFBookmarkExchange(title: "",children: [])
            let action = try file.dictionary(actionRange),kind = file.name(action["S"])
            let allowed: Set<String>
            switch kind {
            case "GoTo": allowed = ["Type","S","D"]
            case "GoToR": allowed = ["Type","S","D","F","NewWindow"]
            case "URI": allowed = ["Type","S","URI"]
            case "Named": allowed = ["Type","S","N"]
            case "ResetForm": allowed = ["Type","S","Fields","Flags"]
            default: throw PDFSourceError.content
            }
            guard Set(action.keys).isSubset(of: allowed.union(["Next"])) else { throw PDFSourceError.content }
            switch kind {
            case "GoTo":
                guard let d = action["D"] else { throw PDFSourceError.content }
                let info = try target(d,remote: false); record.page = info.0; record.view = info.1; record.destinationName = info.2
            case "GoToR":
                guard let d = action["D"],let f = action["F"] else { throw PDFSourceError.content }
                let resolved = try file.resolve(f),raw = file.syntax.string(resolved)
                let path: String
                if raw.hasPrefix("<<") {
                    let spec = try file.dictionary(resolved)
                    guard Set(spec.keys).isSubset(of: ["Type","F","UF"]),let name = spec["UF"] ?? spec["F"] else { throw PDFSourceError.content }; path = try file.text(name)
                } else { path = try file.text(resolved) }
                guard !path.isEmpty else { throw PDFSourceError.content }
                let info = try target(d,remote: true)
                var remote = PDFBookmarkActionExchange(kind: "remoteGoTo",file: URL(fileURLWithPath: path).absoluteString,page: info.0)
                remote.view = info.1; remote.destinationName = info.2; remote.pdfFile = path
                if let window = action["NewWindow"] { guard ["true","false"].contains(file.syntax.string(window)) else { throw PDFSourceError.content }; remote.newWindow = file.syntax.string(window) == "true" }
                record.action = remote
            case "URI": record.url = try file.text(action["URI"])
            case "Named":
                guard let name = action["N"],let value = exchangeNamedActions.firstIndex(of: file.decodedName(name)) else { throw PDFSourceError.content }
                record.action = PDFBookmarkActionExchange(kind: "named",name: value)
            case "ResetForm":
                let flags: Int
                if let raw = action["Flags"] { guard let value = Int(file.syntax.string(raw)) else { throw PDFSourceError.content }; flags = value } else { flags = 0 }
                guard flags == 0 || flags == 1 else { throw PDFSourceError.content }
                let fields = try action["Fields"].map { range in try file.array(range).map { try file.text($0) } }
                guard fields?.allSatisfy({ !$0.isEmpty }) != false else { throw PDFSourceError.content }
                record.action = PDFBookmarkActionExchange(kind: "resetForm",fields: fields,included: flags == 0)
            default: break
            }
            if let next = action["Next"] {
                let resolved = try file.resolve(next),raw = file.syntax.string(resolved)
                let ranges: [Range<Int>]
                if raw.hasPrefix("[") { ranges = try file.array(resolved) }
                else { guard raw.hasPrefix("<<") else { throw PDFSourceError.content }; ranges = [next] }
                guard ranges.count <= 256 else { throw PDFSourceError.content }
                record.nextActions = try ranges.map { try readAction($0,depth: depth+1,ancestors: active) }
            }
            return record
        }
        func siblings(_ first: Range<Int>?,depth: Int) throws -> [PDFBookmarkExchange] {
            guard first != nil else { return [] }
            guard depth < 64 else { throw PDFSourceError.content }
            var result: [PDFBookmarkExchange] = [],cursor = first
            while let range = cursor {
                guard let ref = file.syntax.reference(range),visited.insert(ref.0).inserted,total < 20000 else { throw PDFSourceError.content }; total += 1
                let values = try file.dictionary(range)
                var record = PDFBookmarkExchange(title: try file.text(values["Title"]),children: [])
                record.isOpen = values["Count"].flatMap { Int(file.syntax.string($0)) }.map { $0 > 0 } ?? false
                if let color = values["C"] {
                    let components = try file.array(color)
                    let numbers = components.compactMap { Double(file.syntax.string($0)) }
                    guard numbers.count == components.count else { throw PDFSourceError.content }; record.color = numbers
                }
                if let style = values["F"] { guard let flags = Int(file.syntax.string(style)) else { throw PDFSourceError.content }; record.style = flags }
                if let dest = values["Dest"] {
                    guard values["A"] == nil else { throw PDFSourceError.content }
                    let info = try target(dest,remote: false); record.page = info.0; record.view = info.1; record.destinationName = info.2
                } else if let actionRange = values["A"] {
                    let decoded = try readAction(actionRange,depth: 0,ancestors: [])
                    record.page = decoded.page; record.view = decoded.view; record.destinationName = decoded.destinationName
                    record.url = decoded.url; record.action = decoded.action; record.nextActions = decoded.nextActions
                }
                record.children = try siblings(values["First"],depth: depth+1)
                guard record.valid(pageCount: pages.count) else { throw PDFSourceError.content }
                result.append(record); cursor = values["Next"]
            }
            return result
        }
        return try siblings(outlines["First"],depth: 0)
    }
    static func appendBookmarkExchange(_ input: Data,records: [PDFBookmarkExchange]) throws -> Data {
        guard !records.isEmpty else { throw PDFSourceError.content }
        var count = 0
        func check(_ rows: [PDFBookmarkExchange],depth: Int) throws {
            guard depth < 64 else { throw PDFSourceError.content }
            for row in rows { count += 1; guard count <= 20000 else { throw PDFSourceError.content }; if !row.children.isEmpty { try check(row.children,depth: depth+1) }; if let next = row.nextActions { try check(next,depth: depth+1) } }
        }
        try check(records,depth: 0)
        var data = input,file = try CatalogFile(input)
        let pageCount = try file.pageReferences().count
        guard records.allSatisfy({ $0.valid(pageCount: pageCount) }) else { throw PDFSourceError.content }
        var targets = try PDFDocumentExtras.namedTargets(data),changedNames = false
        func collectNames(_ rows: [PDFBookmarkExchange]) throws {
            for row in rows {
                if let name = row.destinationName,let page = row.page,let expression = row.view,let view = PDFDestinationView(expression: expression) {
                    if let existing = targets.first(where: { $0.name == name }) {
                        guard existing.page == page-1,existing.viewExpression.flatMap(PDFDestinationView.init(expression:)) == view else { throw PDFSourceError.alreadyUsed }
                    } else { targets.append(PDFNamedTarget(name: name,page: page-1,viewExpression: view.expression)); changedNames = true }
                }
                try collectNames(row.children)
                if let next = row.nextActions { try collectNames(next) }
            }
        }
        try collectNames(records)
        if changedNames { data = try PDFDocumentExtras.writeNamedTargets(data,targets: targets,bookmarks: [:]); file = try CatalogFile(data) }
        let pages = try file.pageReferences()
        guard let legacyDocument = PDFDocument(data: file.data) else { throw PDFSourceError.document }
        var nextID = max(file.offsets.keys.max() ?? 0,file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 0)+1
        func allocate() -> Int { defer { nextID += 1 }; return nextID }
        var objects: [(Int,Int,Data)] = []
        func ref(_ id: Int,_ generation: Int = 0) -> Data { Data("\(id) \(generation) R".utf8) }
        func number(_ value: Double?) -> String { value.map { NSDecimalNumber(value: $0).stringValue } ?? "null" }
        func baseAction(_ row: PDFBookmarkExchange) throws -> [String:Data] {
            if let name = row.destinationName { return ["Dest":CatalogFile.string(name)] }
            if let page = row.page {
                let target = pages[page-1]
                let expression: String
                if let value = row.view { expression = PDFDestinationView(expression: value)!.expression }
                else {
                    guard let legacyPage = legacyDocument.page(at: page-1) else { throw PDFSourceError.page }
                    let box = legacyPage.bounds(for: .cropBox)
                    let values = [row.x ?? Double(box.minX),row.y ?? Double(box.maxY),row.zoom].map { $0 == Double(kPDFDestinationUnspecifiedValue) ? nil : $0 }
                    guard let view = PDFDestinationView(mode: .XYZ,values: values) else { throw PDFSourceError.content }; expression = view.expression
                }
                return ["Dest":Data("[\(target.0) \(target.1) R \(expression)]".utf8)]
            }
            if let url = row.url { var body = Data("<< /S /URI /URI ".utf8); body.append(CatalogFile.byteString(url)); body.append(Data(" >>".utf8)); return ["A":body] }
            guard let a = row.action else { return [:] }
            var body = Data()
            switch a.kind {
            case "remoteGoTo":
                let path = a.pdfFile ?? URL(string: a.file!)!.path
                body.append(Data("<< /S /GoToR /F << /Type /Filespec /F ".utf8)); body.append(CatalogFile.byteString(path)); body.append(Data(" /UF ".utf8)); body.append(CatalogFile.string(path)); body.append(Data(" >> /D ".utf8))
                if let name = a.destinationName { body.append(CatalogFile.string(name)) }
                else { body.append(Data("[\(a.page!) \(a.view.flatMap { PDFDestinationView(expression: $0)?.expression } ?? "/XYZ \(number(a.x)) \(number(a.y)) null")]".utf8)) }
                if let window = a.newWindow { body.append(Data((window ? " /NewWindow true" : " /NewWindow false").utf8)) }; body.append(Data(" >>".utf8))
            case "named": body.append(Data("<< /S /Named /N /\(exchangeNamedActions[a.name!]) >>".utf8))
            case "resetForm":
                body.append(Data("<< /S /ResetForm /Flags \(a.included == false ? 1 : 0)".utf8))
                if let fields = a.fields { body.append(Data(" /Fields [".utf8)); for field in fields { body.append(CatalogFile.string(field)); body.append(Data(" ".utf8)) }; body.append(Data("]".utf8)) }; body.append(Data(" >>".utf8))
            default: throw PDFSourceError.content
            }
            return ["A":body]
        }
        func actionDictionary(_ fields: [String:Data]) throws -> Data {
            if let value = fields["A"] { return value }
            if let destination = fields["Dest"] { var body = Data("<< /S /GoTo /D ".utf8); body.append(destination); body.append(Data(" >>".utf8)); return body }
            throw PDFSourceError.content
        }
        func action(_ row: PDFBookmarkExchange) throws -> [String:Data] {
            let fields = try baseAction(row)
            guard let next = row.nextActions,!next.isEmpty else { return fields }
            var body = try actionDictionary(fields)
            guard body.suffix(2) == Data(">>".utf8) else { throw PDFSourceError.content }; body.removeLast(2)
            body.append(Data(" /Next [".utf8))
            for child in next { body.append(try actionDictionary(action(child))); body.append(Data(" ".utf8)) }
            body.append(Data("] >>".utf8)); return ["A":body]
        }
        let existingRange = file.catalog["Outlines"],existing = try file.dictionary(existingRange)
        let outlineRef: (Int,Int)
        if let range = existingRange { guard let value = file.syntax.reference(range) else { throw PDFSourceError.content }; outlineRef = value }
        else { outlineRef = (allocate(),0) }
        var seen = Set<Int>()
        func visibleExisting(_ range: Range<Int>?,depth: Int) throws -> Int {
            guard depth < 64 else { throw PDFSourceError.content }; var cursor = range,total = 0
            while let range = cursor {
                guard let ref = file.syntax.reference(range),seen.insert(ref.0).inserted,seen.count <= 100000 else { throw PDFSourceError.content }
                let node = try file.dictionary(range); total += 1
                if (node["Count"].flatMap { Int(file.syntax.string($0)) } ?? 0) > 0 { total += try visibleExisting(node["First"],depth: depth+1) }
                cursor = node["Next"]
            }; return total
        }
        let oldVisible = try visibleExisting(existing["First"],depth: 0)
        func writeRows(_ rows: [PDFBookmarkExchange],parent: (Int,Int),previous: (Int,Int)? = nil) throws -> (first: Int,last: Int,visible: Int) {
            let ids = rows.map { _ in allocate() }; var visible = 0
            for (i,row) in rows.enumerated() {
                var body = try action(row); body["Title"] = CatalogFile.string(row.title); body["Parent"] = ref(parent.0,parent.1)
                if let color = row.color { body["C"] = Data(("["+color.map { number($0) }.joined(separator: " ")+"]").utf8) }
                if let style = row.style { body["F"] = Data(String(style).utf8) }
                if i > 0 { body["Prev"] = ref(ids[i-1]) } else if let previous { body["Prev"] = ref(previous.0,previous.1) }
                if i+1 < ids.count { body["Next"] = ref(ids[i+1]) }
                visible += 1
                if !row.children.isEmpty {
                    let children = try writeRows(row.children,parent: (ids[i],0))
                    body["First"] = ref(children.first); body["Last"] = ref(children.last)
                    body["Count"] = Data("\(row.isOpen == true ? children.visible : -children.visible)".utf8)
                    if row.isOpen == true { visible += children.visible }
                }
                objects.append((ids[i],0,file.rewrite([:],excluding: [],appending: body)))
            }
            return (ids.first!,ids.last!,visible)
        }
        let oldLast = existing["Last"].flatMap(file.syntax.reference)
        guard (existing["First"] == nil) == (oldLast == nil) else { throw PDFSourceError.content }
        let added = try writeRows(records,parent: outlineRef,previous: oldLast)
        if let oldLast {
            guard let offset = file.offsets[oldLast.0] else { throw PDFSourceError.content }
            let last = try file.syntax.objectDictionary(at: offset).values
            guard last["Next"] == nil else { throw PDFSourceError.content }
            objects.append((oldLast.0,oldLast.1,file.rewrite(last,excluding: ["Next"],appending: ["Next":ref(added.first)])))
        }
        var rootExtra = ["Type":Data("/Outlines".utf8),"Last":ref(added.last),"Count":Data("\(oldVisible+added.visible)".utf8)]
        if existing["First"] == nil { rootExtra["First"] = ref(added.first) }
        objects.append((outlineRef.0,outlineRef.1,file.rewrite(existing,excluding: Set(rootExtra.keys),appending: rootExtra)))
        if existingRange == nil { objects.append((file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["Outlines"],appending: ["Outlines":ref(outlineRef.0,outlineRef.1)]))) }
        return try file.write(objects)
    }
    static func tabTraversal(_ data: Data,pageIndex: Int,setting: PDFTabTraversal? = nil) throws -> (String,Bool,Data?) {
        var file = try CatalogFile(data)
        guard pageIndex >= 0,let root = file.catalog["Pages"] else { throw PDFSourceError.content }
        var pages: [((Int,Int),[String:Range<Int>])] = [],visited = Set<Int>()
        func walk(_ range: Range<Int>,depth: Int) throws {
            guard depth < 128,let ref = file.syntax.reference(range),visited.insert(ref.0).inserted else { throw PDFSourceError.content }
            let values = try file.dictionary(range)
            if file.name(values["Type"]) == "Page" { pages.append((ref,values)); return }
            guard file.name(values["Type"]) == "Pages",values["Kids"] != nil else { throw PDFSourceError.content }
            for child in try file.array(values["Kids"]) { try walk(child,depth: depth+1) }
        }
        try walk(root,depth: 0)
        guard pages.indices.contains(pageIndex) else { throw PDFSourceError.content }
        let (ref,values) = pages[pageIndex]
        let current = file.name(values["Tabs"]),structured = file.catalog["StructTreeRoot"] != nil
        guard let setting else { return (current,structured,nil) }
        let extra: [String:Data] = setting == .unspecified ? [:] : ["Tabs":Data(("/"+setting.rawValue).utf8)]
        return (setting.rawValue,structured,try file.write([(ref.0,ref.1,file.rewrite(values,excluding: ["Tabs"],appending: extra))]))
    }
    static func layers(_ data: Data) throws -> [PDFLayerInfo] {
        try layerConfiguration(data).groups
    }
    static func membershipConfiguration(_ data: Data) throws -> PDFMembershipConfiguration {
        var file = try CatalogFile(data)
        guard file.offsets.count <= 100000 else { throw PDFSourceError.content }
        let props = try file.dictionary(file.catalog["OCProperties"]),ranges = try file.array(props["OCGs"])
        var generations: [Int:Int] = [:]
        for range in ranges {
            guard let ref = file.syntax.reference(range),generations[ref.0] == nil,let offset = file.offsets[ref.0] else { throw PDFSourceError.content }
            let dictionary = try file.syntax.objectDictionary(at: offset).values
            guard file.name(dictionary["Type"]) == "OCG" else { throw PDFSourceError.content }
            file.syntax.cursor = offset
            guard Int(file.syntax.token()) == ref.0,Int(file.syntax.token()) == ref.1,file.syntax.token() == "obj" else { throw PDFSourceError.content }
            generations[ref.0] = ref.1
        }
        let groups = try layers(file.data)
        var entries: [PDFMembershipInfo] = [],nextDirect = 1,visitedValues = 0
        func describe(_ values: [String:Range<Int>],id: Int,generation: Int,location: PDFMembershipLocation? = nil) throws -> PDFMembershipInfo {
            var members: [Int] = [],editable = true
            if let range = values["OCGs"] {
                do {
                let values: [Range<Int>]
                if let ref = file.syntax.reference(range),generations[ref.0] == ref.1 { values = [range] }
                else { let resolved = try file.resolve(range); if file.syntax.string(resolved).hasPrefix("[") { values = try file.array(resolved) } else { values = []; editable = false } }
                for value in values {
                    if let ref = file.syntax.reference(value),generations[ref.0] == ref.1,!members.contains(ref.0) { members.append(ref.0) }
                    else { editable = false }
                }
                } catch { editable = false }
            }
            let policy = values["P"].map { file.name($0) } ?? "AnyOn"
            if !["AllOn","AnyOn","AllOff","AnyOff"].contains(policy) { editable = false }
            var expression: String?
            if let range = values["VE"] {
                var visited = Set<Int>(),count = 0
                func decode(_ range: Range<Int>,depth: Int) throws -> PDFVisibilityExpression {
                    count += 1; guard depth < 64,count <= 4096 else { throw PDFSourceError.content }
                    let ref = file.syntax.reference(range)
                    if let ref,generations[ref.0] == ref.1 { return .group(ref.0) }
                    if let ref { guard visited.insert(ref.0).inserted else { throw PDFSourceError.content } }
                    defer { if let ref { visited.remove(ref.0) } }
                    let items = try file.array(range)
                    guard items.count >= 2,let first = items.first else { throw PDFSourceError.content }
                    let op = file.name(first),children = try items.dropFirst().map { try decode($0,depth: depth+1) }
                    switch op { case "And": return .and(children); case "Or": return .or(children); case "Not": guard children.count == 1 else { throw PDFSourceError.content }; return .not(children[0]); default: throw PDFSourceError.content }
                }
                do {
                    let value = try decode(range,depth: 0)
                    if case .group = value { throw PDFSourceError.content }; expression = value.text
                } catch { expression = "<unsupported>"; editable = false }
            }
            return PDFMembershipInfo(id: id,generation: generation,memberIDs: members,policy: policy,expression: expression,editable: editable,name: try file.text(values["BotPlusName"]),directLocation: location)
        }
        for (id,offset) in file.offsets.sorted(by: { $0.key < $1.key }) {
            guard let owner = try? membershipOwnerRange(file,offset: offset) else { continue }
            let values = file.syntax.bytes[owner.lowerBound] == 60 ? (try? file.dictionary(owner)) ?? [:] : [:]
            file.syntax.cursor = offset
            guard Int(file.syntax.token()) == id,let generation = Int(file.syntax.token()),file.syntax.token() == "obj" else { throw PDFSourceError.content }
            if file.name(values["Type"]) == "OCMD" { guard entries.count < 4096 else { throw PDFSourceError.content }; entries.append(try describe(values,id: id,generation: generation)) }
            let fingerprint = SHA256.hash(data: file.raw(owner)).map { String(format: "%02x",$0) }.joined()
            func walk(_ range: Range<Int>,path: [PDFMembershipPathPart],depth: Int) throws {
                visitedValues += 1; guard visitedValues <= 1000000,depth < 64 else { throw PDFSourceError.content }
                if file.syntax.reference(range) != nil { return }
                let first = file.syntax.bytes[range.lowerBound]
                if first == 60,range.count >= 2,file.syntax.bytes[range.lowerBound+1] == 60 {
                    let values = try file.dictionary(range)
                    if !path.isEmpty,file.name(values["Type"]) == "OCMD" {
                        guard entries.count < 4096 else { throw PDFSourceError.content }
                        let location = PDFMembershipLocation(ownerID: id,generation: generation,path: path,fingerprint: fingerprint)
                        var entry = try describe(values,id: -nextDirect,generation: generation,location: location); nextDirect += 1
                        if (try? membershipOwnerSuffixRange(&file,offset: offset)) == nil { entry = PDFMembershipInfo(id: entry.id,generation: entry.generation,memberIDs: entry.memberIDs,policy: entry.policy,expression: entry.expression,editable: false,name: entry.name,directLocation: location) }
                        entries.append(entry)
                    }
                    for key in values.keys.sorted() { try walk(values[key]!,path: path+[.key(key)],depth: depth+1) }
                } else if first == 91 {
                    for (index,value) in try file.array(range).enumerated() { try walk(value,path: path+[.index(index)],depth: depth+1) }
                }
            }
            try walk(owner,path: [],depth: 0)
        }

        return PDFMembershipConfiguration(groups: groups,entries: entries)
    }
    private static func membershipOwnerRange(_ file: CatalogFile,offset: Int) throws -> Range<Int> {
        var syntax = file.syntax; syntax.cursor = offset
        guard Int(syntax.token()) != nil,Int(syntax.token()) != nil,syntax.token() == "obj" else { throw PDFSourceError.content }; return try syntax.value(depth: 0)
    }
    private static func membershipOwnerSuffix(_ file: inout CatalogFile,offset: Int) throws -> Data {
        let range = try membershipOwnerSuffixRange(&file,offset: offset); return file.raw(range)
    }
    private static func membershipOwnerSuffixRange(_ file: inout CatalogFile,offset: Int) throws -> Range<Int> {
        var syntax = file.syntax
        let owner = try membershipOwnerRange(file,offset: offset); syntax.cursor = owner.upperBound
        let keyword = syntax.token()
        if keyword == "endobj" { return owner.upperBound..<owner.upperBound }
        guard keyword == "stream" else { throw PDFSourceError.content }
        let values = try file.dictionary(owner); guard let rawLength = values["Length"] else { throw PDFSourceError.content }
        let resolved = try file.resolve(rawLength)
        guard let length = Int(file.syntax.string(resolved)),length >= 0,length <= file.data.count else { throw PDFSourceError.content }
        var start = syntax.cursor
        guard start < syntax.bytes.count else { throw PDFSourceError.content }
        if syntax.bytes[start] == 13 { start += 1; if start < syntax.bytes.count,syntax.bytes[start] == 10 { start += 1 } }
        else if syntax.bytes[start] == 10 { start += 1 } else { throw PDFSourceError.content }
        guard length <= syntax.bytes.count-start else { throw PDFSourceError.content }; syntax.cursor = start+length
        guard syntax.token() == "endstream" else { throw PDFSourceError.content }; let end = syntax.cursor
        guard syntax.token() == "endobj" else { throw PDFSourceError.content }
        return owner.upperBound..<end
    }
    static func setMembership(_ data: Data,entry: PDFMembershipInfo,members: [Int],policy: String,expression: String?) throws -> Data {
        var file = try CatalogFile(data)
        let configuration = try membershipConfiguration(file.data)
        guard let current = configuration.entries.first(where: { $0.id == entry.id && $0.generation == entry.generation && $0.directLocation == entry.directLocation }),current.editable,current.memberIDs == entry.memberIDs,current.policy == entry.policy,current.expression == entry.expression else { throw PDFSourceError.alreadyUsed }
        let changes = try membershipValues(groups: configuration.groups,members: members,policy: policy,expression: expression)
        if let location = current.directLocation {
            guard !location.path.isEmpty,let offset = file.offsets[location.ownerID] else { throw PDFSourceError.alreadyUsed }
            let owner = try membershipOwnerRange(file,offset: offset)
            func rewrite(_ range: Range<Int>,at index: Int) throws -> Data {
                guard file.syntax.reference(range) == nil else { throw PDFSourceError.content }
                if index == location.path.count {
                    let values = try file.dictionary(range); guard file.name(values["Type"]) == "OCMD" else { throw PDFSourceError.content }
                    return file.rewrite(values,excluding: ["OCGs","P","VE"],appending: changes)
                }
                switch location.path[index] {
                case .key(let key):
                    let values = try file.dictionary(range); guard let child = values[key] else { throw PDFSourceError.alreadyUsed }
                    return file.rewrite(values,excluding: [key],appending: [key:try rewrite(child,at: index+1)])
                case .index(let position):
                    let values = try file.array(range); guard values.indices.contains(position) else { throw PDFSourceError.alreadyUsed }
                    var array = Data("[".utf8); for (offset,value) in values.enumerated() { array.append(try offset == position ? rewrite(value,at: index+1) : file.raw(value)); array.append(Data(" ".utf8)) }; array.append(Data("]".utf8)); return array
                }
            }
            var body = try rewrite(owner,at: 0); body.append(try membershipOwnerSuffix(&file,offset: offset))
            return try file.write([(location.ownerID,location.generation,body)])
        }
        guard let offset = file.offsets[entry.id] else { throw PDFSourceError.alreadyUsed }
        let values = try file.syntax.objectDictionary(at: offset).values
        return try file.write([(entry.id,entry.generation,file.rewrite(values,excluding: ["OCGs","P","VE"],appending: changes))])
    }
    private static func membershipValues(groups: [PDFLayerInfo],members: [Int],policy: String,expression: String?) throws -> [String:Data] {
        let generations = Dictionary(uniqueKeysWithValues: groups.map { ($0.id,$0.generation) })
        guard members.count <= 4096,Set(members).count == members.count,members.allSatisfy({ generations[$0] != nil }),["AllOn","AnyOn","AllOff","AnyOff"].contains(policy) else { throw PDFSourceError.content }
        var changes = ["OCGs":Data(("["+members.map { "\($0) \(generations[$0]!) R" }.joined(separator: " ")+"]").utf8),"P":Data(("/"+policy).utf8)]
        if let expression {
            let parsed = try PDFVisibilityExpression.parse(expression,allowed: Set(generations.keys))
            changes["VE"] = Data(try parsed.pdfValue(generations: generations).utf8)
        }
        return changes
    }
    static func createMembership(_ data: Data,name: String,members: [Int],policy: String,expression: String?) throws -> Data {
        var file = try CatalogFile(data)
        let configuration = try membershipConfiguration(file.data)
        guard !configuration.groups.isEmpty,configuration.entries.count < 4096,!name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,name.utf16.count <= 4096,!name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw PDFSourceError.content }
        let key = name.folding(options: [.caseInsensitive,.diacriticInsensitive],locale: Locale(identifier: "en_US_POSIX"))
        guard !configuration.entries.contains(where: { $0.name.folding(options: [.caseInsensitive,.diacriticInsensitive],locale: Locale(identifier: "en_US_POSIX")) == key }) else { throw PDFSourceError.alreadyUsed }
        var values = try membershipValues(groups: configuration.groups,members: members,policy: policy,expression: expression)
        values["Type"] = Data("/OCMD".utf8); values["BotPlusName"] = CatalogFile.string(name)
        let props = try file.dictionary(file.catalog["OCProperties"])
        if let range = props["BotPlusOCMDs"] { let raw = try file.resolve(range); guard file.syntax.string(raw).hasPrefix("[") else { throw PDFSourceError.content } }
        let registered = try file.array(props["BotPlusOCMDs"])
        var ids = Set<Int>(),registry: [Data] = []
        for value in registered {
            guard let ref = file.syntax.reference(value),ids.insert(ref.0).inserted,configuration.entries.contains(where: { $0.id == ref.0 && $0.generation == ref.1 }) else { throw PDFSourceError.content }; registry.append(file.raw(value))
        }
        let declaredSize = file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 0
        let id = max(file.offsets.keys.max() ?? 0,declaredSize-1)+1
        guard id > 0,id < 10000000 else { throw PDFSourceError.content }
        registry.append(Data("\(id) 0 R".utf8))
        var array = Data("[".utf8); for value in registry { array.append(value); array.append(Data(" ".utf8)) }; array.append(Data("]".utf8))
        let updated = file.rewrite(props,excluding: ["BotPlusOCMDs"],appending: ["BotPlusOCMDs":array])
        let catalog = file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":updated])
        // A private catalog anchor retains a newly created, not-yet-assigned
        // standard OCMD through save/reopen. It has no visibility effect.
        return try file.write([(id,0,file.rewrite([:],excluding: [],appending: values)),(file.root.0,file.root.1,catalog)])
    }
    private static func markedContentDepth(_ page: CGPDFPage) throws -> Int {
        let state = PDFMarkedContentScope()
        guard let table = CGPDFOperatorTableCreate() else { throw PDFSourceError.content }
        defer { CGPDFOperatorTableRelease(table) }
        CGPDFOperatorTableSetCallback(table,"BMC") { scanner,info in
            let state = Unmanaged<PDFMarkedContentScope>.fromOpaque(info!).takeUnretainedValue(); var tag: UnsafePointer<CChar>?
            if !CGPDFScannerPopName(scanner,&tag) { state.valid = false }; state.begin()
        }
        CGPDFOperatorTableSetCallback(table,"BDC") { scanner,info in
            let state = Unmanaged<PDFMarkedContentScope>.fromOpaque(info!).takeUnretainedValue(); var property: CGPDFObjectRef?,tag: UnsafePointer<CChar>?
            if !CGPDFScannerPopObject(scanner,&property) || !CGPDFScannerPopName(scanner,&tag) { state.valid = false }
            if let property { let type = CGPDFObjectGetType(property); if type != .name && type != .dictionary { state.valid = false } } else { state.valid = false }; state.begin()
        }
        CGPDFOperatorTableSetCallback(table,"EMC") { _,info in
            let state = Unmanaged<PDFMarkedContentScope>.fromOpaque(info!).takeUnretainedValue(); state.depth -= 1; state.operators += 1; if state.depth < 0 || state.operators > 1000000 { state.valid = false }
        }
        let content = CGPDFContentStreamCreateWithPage(page),scanner = CGPDFScannerCreate(content,table,Unmanaged.passUnretained(state).toOpaque())
        defer { CGPDFScannerRelease(scanner); CGPDFContentStreamRelease(content) }
        guard CGPDFScannerScan(scanner),state.valid,state.depth == 0 else { throw PDFSourceError.content }; return state.maximum
    }
    private static func inheritedResources(_ file: inout CatalogFile,page: [String:Range<Int>]) throws -> [String:Range<Int>] {
        var node = page,seen = Set<Int>()
        while node["Resources"] == nil {
            guard let parent = node["Parent"],let ref = file.syntax.reference(parent) else { return [:] }
            guard seen.count < 128,seen.insert(ref.0).inserted else { throw PDFSourceError.content }; node = try file.dictionary(parent)
        }; return try file.dictionary(node["Resources"])
    }
    private enum XObjectBindingError: Error { case foreign,changed,unsupported }
    private static func xObjectBase(_ file: inout CatalogFile,ref: (Int,Int)) throws -> (original: (Int,Int),values: [String:Range<Int>],suffix: Range<Int>,owned: Bool,condition: (Int,Int)?) {
        func header(_ reference: (Int,Int)) throws -> (values: [String:Range<Int>],suffix: Range<Int>) {
            guard let offset = file.offsets[reference.0] else { throw XObjectBindingError.unsupported }
            file.syntax.cursor = offset; guard Int(file.syntax.token()) == reference.0,Int(file.syntax.token()) == reference.1,file.syntax.token() == "obj" else { throw XObjectBindingError.changed }
            let values = try file.syntax.objectDictionary(at: offset).values
            guard file.name(values["Type"]) == "XObject",["Image","Form"].contains(file.name(values["Subtype"])),values["StructParents"] == nil,values["StructParent"] == nil else { throw XObjectBindingError.unsupported }
            let suffix = try membershipOwnerSuffixRange(&file,offset: offset); guard !suffix.isEmpty else { throw XObjectBindingError.unsupported }; return (values,suffix)
        }
        func hasOC(_ values: [String:Range<Int>]) throws -> Bool { guard let raw = values["OC"] else { return false }; let resolved = try file.resolve(raw); return file.syntax.string(resolved) != "null" }
        let current = try header(ref)
        guard let marker = current.values["BotPlusObjectOC"] else {
            guard try !hasOC(current.values) else { throw XObjectBindingError.foreign }; return (ref,current.values,current.suffix,false,nil)
        }
        let metadata = try file.dictionary(marker)
        guard metadata["Version"].map({ file.syntax.string($0) == "1" }) == true,let rawOriginal = metadata["Original"],let original = file.syntax.reference(rawOriginal),let rawCondition = metadata["Condition"],let condition = file.syntax.reference(rawCondition),let rawOC = current.values["OC"],let oc = file.syntax.reference(rawOC),condition.0 == oc.0,condition.1 == oc.1,original.0 != ref.0 else { throw XObjectBindingError.changed }
        let conditionValues = try file.dictionary(rawCondition); guard file.name(conditionValues["Type"]) == "OCMD" else { throw XObjectBindingError.changed }
        guard let conditionOffset = file.offsets[condition.0] else { throw XObjectBindingError.changed }
        file.syntax.cursor = conditionOffset; guard Int(file.syntax.token()) == condition.0,Int(file.syntax.token()) == condition.1,file.syntax.token() == "obj" else { throw XObjectBindingError.changed }
        let source = try header(original)
        guard source.values["BotPlusObjectOC"] == nil,try !hasOC(source.values),file.name(source.values["Subtype"]) == file.name(current.values["Subtype"]),
              file.rewrite(source.values,excluding: ["OC","BotPlusObjectOC"],appending: [:]) == file.rewrite(current.values,excluding: ["OC","BotPlusObjectOC"],appending: [:]),
              file.syntax.bytes[source.suffix].elementsEqual(file.syntax.bytes[current.suffix]) else { throw XObjectBindingError.changed }
        return (original,source.values,source.suffix,true,condition)
    }
    static func xObjectConditionTargets(_ data: Data,pageIndex: Int) throws -> [PDFXObjectConditionTarget] {
        var file = try CatalogFile(data)
        let pages = try file.pageReferences(); guard pages.indices.contains(pageIndex),let offset = file.offsets[pages[pageIndex].0] else { throw PDFSourceError.page }
        let page = try file.syntax.objectDictionary(at: offset).values,resources = try inheritedResources(&file,page: page),objects = try file.dictionary(resources["XObject"])
        guard objects.count <= 10000 else { throw PDFSourceError.content }
        var tagged = false
        if let value = file.catalog["StructTreeRoot"] { let resolved = try file.resolve(value); tagged = file.syntax.string(resolved) != "null" }
        var result: [PDFXObjectConditionTarget] = []
        func visit(_ objects: [String:Range<Int>],path: [String],ancestors: Set<Int>,chain: Data,blocked: Bool) throws {
            guard path.count < 32 else { return }
            for key in objects.keys.sorted() {
                guard result.count < 10000 else { throw PDFSourceError.content }
                let value = objects[key]!,ref = file.syntax.reference(value),header = (try? file.dictionary(value)) ?? [:],kind = file.name(header["Subtype"])
                var signature = chain; signature.append(file.rewrite(header,excluding: [],appending: [:]))
                let fingerprint = SHA256.hash(data: signature).map { String(format: "%02x",$0) }.joined()
                var owned = header["BotPlusObjectOC"] != nil,condition: Int?,editable = false,reason = ""
                let cycle = ref.map { ancestors.contains($0.0) } ?? false
                if tagged { reason = "Tagged PDF: только просмотр / read-only" }
                else if blocked { reason = "Родитель имеет неподдерживаемое или существующее OC / Parent has unsupported or existing OC" }
                else if cycle { reason = "Циклические ресурсы Form / Cyclic Form resources" }
                else if let ref {
                    do { let base = try xObjectBase(&file,ref: ref); owned = base.owned; condition = base.condition?.0; editable = true }
                    catch XObjectBindingError.foreign { reason = "У объекта уже есть исходное OC; используйте редактор условий / Existing OC: use the conditions editor" }
                    catch XObjectBindingError.changed { reason = "Сохранённое назначение изменено извне / Assignment changed externally" }
                    catch { reason = "Неподдерживаемый XObject / Unsupported XObject" }
                } else { reason = "Неподдерживаемая ссылка XObject / Unsupported XObject reference" }
                let fullPath = path+[key]
                result.append(PDFXObjectConditionTarget(pageIndex: pageIndex,key: key,kind: kind.isEmpty ? "XObject" : kind,objectID: ref?.0 ?? 0,generation: ref?.1 ?? 0,fingerprint: fingerprint,owned: owned,conditionID: condition,editable: editable,reason: reason,resourcePath: fullPath))
                if kind == "Form",!cycle,let ref,path.count+1 < 32 {
                    let childrenResources = try file.dictionary(header["Resources"]),children = try file.dictionary(childrenResources["XObject"])
                    try visit(children,path: fullPath,ancestors: ancestors.union([ref.0]),chain: signature,blocked: blocked || !editable || owned)
                }
            }
        }
        try visit(objects,path: [],ancestors: [],chain: file.rewrite(resources,excluding: [],appending: [:]),blocked: false)
        return result
    }
    static func bindXObjectCondition(_ data: Data,target: PDFXObjectConditionTarget,entry: PDFMembershipInfo?) throws -> Data {
        var file = try CatalogFile(data)
        guard target.editable,try xObjectConditionTargets(data,pageIndex: target.pageIndex).contains(target) else { throw PDFSourceError.alreadyUsed }
        if let entry {
            let conditions = try membershipConfiguration(file.data)
            guard entry.id > 0,entry.directLocation == nil,entry.editable,conditions.entries.contains(where: { $0.id == entry.id && $0.generation == entry.generation && $0.editable && $0.memberIDs == entry.memberIDs && $0.policy == entry.policy && $0.expression == entry.expression }) else { throw PDFSourceError.alreadyUsed }
        }
        let base = try xObjectBase(&file,ref: (target.objectID,target.generation))
        if entry == nil && !base.owned || base.owned && entry?.id == base.condition?.0 && entry?.generation == base.condition?.1 { return data }
        let pages = try file.pageReferences(); guard pages.indices.contains(target.pageIndex),let offset = file.offsets[pages[target.pageIndex].0] else { throw PDFSourceError.page }
        let page = try file.syntax.objectDictionary(at: offset).values,resources = try inheritedResources(&file,page: page),objects = try file.dictionary(resources["XObject"])
        let path = target.path
        guard !path.isEmpty,path.count <= 32 else { throw PDFSourceError.content }
        var parents: [(values: [String:Range<Int>],suffix: Range<Int>,resources: [String:Range<Int>],objects: [String:Range<Int>],childKey: String)] = []
        var currentObjects = objects
        for index in path.indices.dropLast() {
            guard let value = currentObjects[path[index]],let ref = file.syntax.reference(value) else { throw PDFSourceError.content }
            let parent = try xObjectBase(&file,ref: ref)
            guard !parent.owned,file.name(parent.values["Subtype"]) == "Form" else { throw PDFSourceError.content }
            let parentResources = try file.dictionary(parent.values["Resources"]),children = try file.dictionary(parentResources["XObject"])
            parents.append((parent.values,parent.suffix,parentResources,children,path[index+1])); currentObjects = children
        }
        guard let leafValue = currentObjects[path.last!],let leafRef = file.syntax.reference(leafValue),leafRef.0 == target.objectID,leafRef.1 == target.generation else { throw PDFSourceError.alreadyUsed }
        var changes: [(Int,Int,Data)] = [],reference = Data("\(base.original.0) \(base.original.1) R".utf8)
        let declared = file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 1
        var nextID = max(file.offsets.keys.max() ?? 0,declared-1)+1
        func newReference(_ body: Data) throws -> Data {
            guard nextID > 0,nextID < 10000000 else { throw PDFSourceError.content }
            let id = nextID; nextID += 1; changes.append((id,0,body)); return Data("\(id) 0 R".utf8)
        }
        if let entry {
            let condition = Data("\(entry.id) \(entry.generation) R".utf8),metadata = Data("<< /Version 1 /Original \(base.original.0) \(base.original.1) R /Condition \(entry.id) \(entry.generation) R >>".utf8)
            var body = file.rewrite(base.values,excluding: ["OC","BotPlusObjectOC"],appending: ["OC":condition,"BotPlusObjectOC":metadata]); body.append(file.raw(base.suffix)); reference = try newReference(body)
        }
        for parent in parents.reversed() {
            let children = file.rewrite(parent.objects,excluding: [parent.childKey],appending: [parent.childKey:reference]),localResources = file.rewrite(parent.resources,excluding: ["XObject"],appending: ["XObject":children])
            var body = file.rewrite(parent.values,excluding: ["Resources"],appending: ["Resources":localResources]); body.append(file.raw(parent.suffix)); reference = try newReference(body)
        }
        let updatedObjects = file.rewrite(objects,excluding: [path[0]],appending: [path[0]:reference]),updatedResources = file.rewrite(resources,excluding: ["XObject"],appending: ["XObject":updatedObjects])
        changes.append((pages[target.pageIndex].0,pages[target.pageIndex].1,file.rewrite(page,excluding: ["Resources"],appending: ["Resources":updatedResources])))
        return try file.write(changes)
    }
    static func transformFormResource(_ data: Data,target: PDFXObjectConditionTarget,options: PDFFormResourceTransformOptions) throws -> Data {
        guard target.editable,target.kind == "Form",!target.owned,try xObjectConditionTargets(data,pageIndex: target.pageIndex).contains(target),let linear = options.linear else { throw PDFSourceError.alreadyUsed }
        var file = try CatalogFile(data)
        let pages = try file.pageReferences(); guard pages.indices.contains(target.pageIndex),let pageOffset = file.offsets[pages[target.pageIndex].0] else { throw PDFSourceError.page }
        let page = try file.syntax.objectDictionary(at: pageOffset).values,resources = try inheritedResources(&file,page: page),rootObjects = try file.dictionary(resources["XObject"]),path = target.path
        guard !path.isEmpty,path.count <= 32 else { throw PDFSourceError.content }
        struct Node { let values: [String:Range<Int>],suffix: Range<Int>,resources: [String:Range<Int>],objects: [String:Range<Int>] }
        var nodes: [Node] = [],objects = rootObjects
        for key in path {
            guard let raw = objects[key],let ref = file.syntax.reference(raw) else { throw PDFSourceError.content }
            let base = try xObjectBase(&file,ref: ref)
            guard !base.owned,file.name(base.values["Subtype"]) == "Form" else { throw PDFSourceError.content }
            let local = try file.dictionary(base.values["Resources"]),children = try file.dictionary(local["XObject"])
            nodes.append(Node(values: base.values,suffix: base.suffix,resources: local,objects: children)); objects = children
        }
        let leaf = nodes.last!
        func numbers(_ raw: Range<Int>?,count: Int) throws -> [Double] {
            guard let raw else { throw PDFSourceError.content }; let values = try file.array(raw),numbers = values.compactMap { Double(file.syntax.string($0)) }
            guard values.count == count,numbers.count == count,numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { throw PDFSourceError.content }; return numbers
        }
        let old = try leaf.values["Matrix"].map { try numbers($0,count: 6) } ?? [1,0,0,1,0,0]
        guard abs(old[0]*old[3]-old[1]*old[2]) > 1e-8 else { throw PDFSourceError.content }
        let box = try numbers(leaf.values["BBox"],count: 4); guard box[2] > box[0],box[3] > box[1] else { throw PDFSourceError.content }
        if options.isIdentity { return data }
        let cx = options.centered ? old[0]*(box[0]+box[2])/2+old[2]*(box[1]+box[3])/2+old[4] : 0
        let cy = options.centered ? old[1]*(box[0]+box[2])/2+old[3]*(box[1]+box[3])/2+old[5] : 0
        let a = Double(linear.a),b = Double(linear.b),c = Double(linear.c),d = Double(linear.d),tx = cx-a*cx-c*cy+options.x,ty = cy-b*cx-d*cy+options.y
        let matrix = [a*old[0]+c*old[1],b*old[0]+d*old[1],a*old[2]+c*old[3],b*old[2]+d*old[3],a*old[4]+c*old[5]+tx,b*old[4]+d*old[5]+ty]
        guard matrix.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),abs(matrix[0]*matrix[3]-matrix[1]*matrix[2]) > 1e-8 else { throw PDFSourceError.content }
        var body = file.rewrite(leaf.values,excluding: ["Matrix"],appending: ["Matrix":Data(("["+matrix.map { NSDecimalNumber(value: $0).stringValue }.joined(separator: " ")+"]").utf8)])
        body.append(file.raw(leaf.suffix))
        var changes: [(Int,Int,Data)] = [],nextID = max(file.offsets.keys.max() ?? 0,(file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 1)-1)+1,reference = Data()
        for index in nodes.indices.reversed() {
            guard nextID > 0,nextID < 10000000 else { throw PDFSourceError.content }
            changes.append((nextID,0,body)); reference = Data("\(nextID) 0 R".utf8); nextID += 1
            if index > 0 {
                let parent = nodes[index-1],children = file.rewrite(parent.objects,excluding: [path[index]],appending: [path[index]:reference]),local = file.rewrite(parent.resources,excluding: ["XObject"],appending: ["XObject":children])
                body = file.rewrite(parent.values,excluding: ["Resources"],appending: ["Resources":local]); body.append(file.raw(parent.suffix))
            }
        }
        let rewrittenObjects = file.rewrite(rootObjects,excluding: [path[0]],appending: [path[0]:reference]),rewrittenResources = file.rewrite(resources,excluding: ["XObject"],appending: ["XObject":rewrittenObjects])
        changes.append((pages[target.pageIndex].0,pages[target.pageIndex].1,file.rewrite(page,excluding: ["Resources"],appending: ["Resources":rewrittenResources])))
        return try file.write(changes)
    }
    static func bindMembershipPages(_ data: Data,entry: PDFMembershipInfo?,indices: [Int]) throws -> Data {
        guard !indices.isEmpty,indices.count <= 512,Set(indices).count == indices.count else { throw PDFSourceError.content }
        var file = try CatalogFile(data)
        let configuration = try membershipConfiguration(file.data),pages = try file.pageReferences()
        guard indices.allSatisfy({ pages.indices.contains($0) }) else { throw PDFSourceError.page }
        if let entry {
            guard entry.directLocation == nil,entry.id > 0,entry.editable,configuration.entries.contains(where: { $0.id == entry.id && $0.generation == entry.generation && $0.editable && $0.memberIDs == entry.memberIDs && $0.policy == entry.policy && $0.expression == entry.expression }) else { throw PDFSourceError.alreadyUsed }
        }
        guard let provider = CGDataProvider(data: file.data as CFData),let cg = CGPDFDocument(provider) else { throw PDFSourceError.document }
        defer { withExtendedLifetime(cg) {} }
        func streamRef(_ value: Range<Int>) throws -> (Int,Int) {
            guard let ref = file.syntax.reference(value),let offset = file.offsets[ref.0] else { throw PDFSourceError.content }
            var syntax = file.syntax; syntax.cursor = offset
            guard Int(syntax.token()) == ref.0,Int(syntax.token()) == ref.1,syntax.token() == "obj" else { throw PDFSourceError.content }
            let dictionary = try syntax.objectDictionary(at: offset); syntax.cursor = dictionary.range.upperBound
            guard syntax.token() == "stream" else { throw PDFSourceError.content }; return ref
        }
        func streamRefs(_ value: Range<Int>?) throws -> [(Int,Int)] {
            guard let value else { return [] }; let resolved = try file.resolve(value),token = file.syntax.string(resolved)
            if token == "null" { return [] }
            if token.hasPrefix("[") { return try file.array(resolved).map(streamRef) }; return [try streamRef(value)]
        }
        func same(_ a: [(Int,Int)],_ b: [(Int,Int)]) -> Bool { a.count == b.count && zip(a,b).allSatisfy { $0.0.0 == $0.1.0 && $0.0.1 == $0.1.1 } }
        func refData(_ ref: (Int,Int)) -> Data { Data("\(ref.0) \(ref.1) R".utf8) }
        func arrayData(_ refs: [(Int,Int)]) -> Data { Data(("["+refs.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8) }
        var changes: [(Int,Int,Data)] = [],nextID = max(file.offsets.keys.max() ?? 0,(file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 1)-1)+1,totalBytes = 0
        func newStream(_ bytes: Data) throws -> (Int,Int) {
            guard nextID > 0,nextID < 10000000 else { throw PDFSourceError.content }; let id = nextID; nextID += 1
            var body = Data("<< /Length \(bytes.count) >>\nstream\n".utf8); body.append(bytes); body.append(Data("endstream".utf8)); changes.append((id,0,body)); return (id,0)
        }
        for index in indices.sorted() {
            guard let offset = file.offsets[pages[index].0],let cgPage = cg.page(at: index+1),let cgDictionary = cgPage.dictionary else { throw PDFSourceError.page }
            let page = try file.syntax.objectDictionary(at: offset).values,owned = page["BotPlusPageOC"] != nil
            if !owned && entry == nil { continue }
            let current = try streamRefs(page["Contents"])
            guard current.count <= 4098 else { throw PDFSourceError.content }
            // Decode only to bound scanner input. Original stream bytes and filters
            // are retained by reference; no reconstruction or rasterization.
            var pageBytes = 0,cgContents: CGPDFObjectRef?
            if CGPDFDictionaryGetObject(cgDictionary,"Contents",&cgContents),let cgContents {
                func size(_ stream: CGPDFStreamRef) throws -> Int { var format = CGPDFDataFormat.raw; guard let bytes = CGPDFStreamCopyData(stream,&format) else { throw PDFSourceError.content }; return CFDataGetLength(bytes) }
                if CGPDFObjectGetType(cgContents) == .array {
                    var array: CGPDFArrayRef?; guard CGPDFDictionaryGetArray(cgDictionary,"Contents",&array),let array else { throw PDFSourceError.content }
                    for at in 0..<CGPDFArrayGetCount(array) { var stream: CGPDFStreamRef?; guard CGPDFArrayGetStream(array,at,&stream),let stream else { throw PDFSourceError.content }; pageBytes += try size(stream); guard pageBytes <= 64*1024*1024 else { throw PDFSourceError.content } }
                } else if CGPDFObjectGetType(cgContents) == .stream { var stream: CGPDFStreamRef?; guard CGPDFDictionaryGetStream(cgDictionary,"Contents",&stream),let stream else { throw PDFSourceError.content }; pageBytes = try size(stream) }
                else if CGPDFObjectGetType(cgContents) != .null { throw PDFSourceError.content }
            }
            totalBytes += pageBytes; guard pageBytes <= 64*1024*1024,totalBytes <= 256*1024*1024 else { throw PDFSourceError.content }
            let maximum = try markedContentDepth(cgPage)
            let resourceValues = try inheritedResources(&file,page: page),metadata = owned ? try file.dictionary(page["BotPlusPageOC"]) : [:]
            var propertyValues = try file.dictionary(resourceValues["Properties"])
            var original = current,originalData = page["Contents"].map { file.raw($0) } ?? Data("null".utf8),hadContents = page["Contents"] != nil,propertyName = "",prefix: (Int,Int)?,suffix: (Int,Int)?
            if owned {
                guard metadata["Version"].map({ file.syntax.string($0) == "1" }) == true,let conditionValue = metadata["Condition"],let condition = file.syntax.reference(conditionValue),configuration.entries.contains(where: { $0.id == condition.0 && $0.generation == condition.1 }),let property = metadata["Property"],let source = metadata["OriginalContents"],let had = metadata["HadContents"] else { throw PDFSourceError.content }
                propertyName = file.name(property)
                guard propertyName.range(of: #"^BP_OCMD[0-9]{1,5}$"#,options: .regularExpression) != nil,let propertyValue = propertyValues[propertyName],let linked = file.syntax.reference(propertyValue),linked.0 == condition.0,linked.1 == condition.1 else { throw PDFSourceError.content }
                let boolean = file.syntax.string(had); guard ["true","false"].contains(boolean) else { throw PDFSourceError.content }; hadContents = boolean == "true"
                original = try streamRefs(source); originalData = file.raw(source)
                if !hadContents { let raw = try file.resolve(source); guard original.isEmpty,file.syntax.string(raw) == "null" else { throw PDFSourceError.alreadyUsed } }
                guard let prefixValue = metadata["Prefix"],let suffixValue = metadata["Suffix"] else { throw PDFSourceError.content }
                prefix = try streamRef(prefixValue); suffix = try streamRef(suffixValue)
                guard same(current,[prefix!]+original+[suffix!]) else { throw PDFSourceError.alreadyUsed }
                var cgMetadata: CGPDFDictionaryRef?,first: CGPDFStreamRef?,last: CGPDFStreamRef?,format = CGPDFDataFormat.raw
                guard CGPDFDictionaryGetDictionary(cgDictionary,"BotPlusPageOC",&cgMetadata),let cgMetadata,CGPDFDictionaryGetStream(cgMetadata,"Prefix",&first),let first,CGPDFDictionaryGetStream(cgMetadata,"Suffix",&last),let last,
                      let firstBytes = CGPDFStreamCopyData(first,&format),let lastBytes = CGPDFStreamCopyData(last,&format),firstBytes as Data == Data("/OC /\(propertyName) BDC\n".utf8),lastBytes as Data == Data("\nEMC\n".utf8) else { throw PDFSourceError.alreadyUsed }
                if let entry,condition.0 == entry.id && condition.1 == entry.generation { continue }
            } else {
                guard maximum < 128,original.count <= 4096 else { throw PDFSourceError.content }
                guard let slot = (0..<10000).first(where: { propertyValues["BP_OCMD\($0)"] == nil }) else { throw PDFSourceError.content }; propertyName = "BP_OCMD\(slot)"
            }
            var pageChanges: [String:Data] = [:],excluded: Set<String> = ["Resources","BotPlusPageOC"]
            if let entry {
                if !owned {
                    prefix = try newStream(Data("/OC /\(propertyName) BDC\n".utf8)); suffix = try newStream(Data("\nEMC\n".utf8))
                    pageChanges["Contents"] = arrayData([prefix!]+original+[suffix!]); excluded.insert("Contents")
                }
                propertyValues[propertyName] = nil
                let properties = file.rewrite(propertyValues,excluding: [],appending: [propertyName:refData((entry.id,entry.generation))])
                pageChanges["Resources"] = file.rewrite(resourceValues,excluding: ["Properties"],appending: ["Properties":properties])
                let fields = ["Version":Data("1".utf8),"Condition":refData((entry.id,entry.generation)),"Property":Data(("/"+propertyName).utf8),"OriginalContents":originalData,"HadContents":Data((hadContents ? "true" : "false").utf8),"Prefix":refData(prefix!),"Suffix":refData(suffix!)]
                pageChanges["BotPlusPageOC"] = file.rewrite(metadata,excluding: Set(fields.keys),appending: fields)
            } else {
                excluded.insert("Contents"); if hadContents { pageChanges["Contents"] = originalData }
                pageChanges["Resources"] = file.rewrite(resourceValues,excluding: ["Properties"],appending: ["Properties":file.rewrite(propertyValues,excluding: [propertyName],appending: [:])])
            }
            changes.append((pages[index].0,pages[index].1,file.rewrite(page,excluding: excluded,appending: pageChanges)))
        }
        return changes.isEmpty ? data : try file.write(changes)
    }
    static func layerStateReport(_ data: Data) throws -> PDFLayerStateReport {
        var file = try CatalogFile(data)
        let groups = try layers(file.data),refs = Dictionary(uniqueKeysWithValues: groups.map { ($0.id,$0.generation) })
        guard groups.count <= 10000 else { throw PDFSourceError.content }
        for group in groups {
            guard let offset = file.offsets[group.id] else { throw PDFSourceError.content }
            let values = try file.syntax.objectDictionary(at: offset).values
            guard file.name(values["Type"]) == "OCG" else { throw PDFSourceError.content }
            file.syntax.cursor = offset
            guard Int(file.syntax.token()) == group.id,Int(file.syntax.token()) == group.generation,file.syntax.token() == "obj" else { throw PDFSourceError.content }
        }
        let props = try file.dictionary(file.catalog["OCProperties"])
        var ranges: [(Int,Range<Int>)] = []
        if let value = props["D"] { ranges.append((-1,value)) }
        let alternatives = try file.array(props["Configs"]); guard alternatives.count <= 10000 else { throw PDFSourceError.content }
        ranges += alternatives.enumerated().map { ($0.offset,$0.element) }
        var configurations: [PDFLayerStateConfiguration] = []
        for (id,range) in ranges {
            let values = try file.dictionary(range),base = values["BaseState"].map { file.name($0) } ?? "ON"
            var editable = ["ON","OFF","Unchanged"].contains(base)
            func list(_ range: Range<Int>?) throws -> [Int] {
                guard let range else { return [] }; let resolved = try file.resolve(range)
                guard file.syntax.string(resolved).hasPrefix("[") else { throw PDFSourceError.content }
                let items = try file.array(resolved),ids = try items.map { item -> Int in
                    guard let ref = file.syntax.reference(item),refs[ref.0] == ref.1 else { throw PDFSourceError.content }; return ref.0
                }
                guard Set(ids).count == ids.count else { throw PDFSourceError.content }; return ids
            }
            var on: [Int] = [],off: [Int] = [],locked: [Int] = [],radios: [[Int]] = [],intents: [String] = []
            do {
                on = try list(values["ON"]); off = try list(values["OFF"]); locked = try list(values["Locked"])
                guard Set(on).isDisjoint(with: off) else { throw PDFSourceError.content }
                if let raw = values["RBGroups"] {
                    let resolved = try file.resolve(raw); guard file.syntax.string(resolved).hasPrefix("[") else { throw PDFSourceError.content }
                    for radio in try file.array(resolved) { radios.append(try list(radio)) }
                } else if id != -1,let primary = configurations.first(where: { $0.id == -1 }) {
                    guard primary.editable else { throw PDFSourceError.content }; radios = primary.radios
                }
                if let range = values["Intent"] {
                    let raw = try file.resolve(range),items: [Range<Int>]
                    if file.syntax.string(raw).hasPrefix("[") { items = try file.array(raw) } else { items = [raw] }
                    for item in items { guard file.syntax.string(item).hasPrefix("/") else { throw PDFSourceError.content }; intents.append(file.decodedName(item)) }
                } else { intents = ["View"] }
                guard !intents.isEmpty,intents.count <= 64,Set(intents).count == intents.count else { throw PDFSourceError.content }
                if id == -1 { guard base == "ON",intents == ["View"] else { throw PDFSourceError.content } }
            } catch { editable = false }
            configurations.append(PDFLayerStateConfiguration(id: id,name: try file.text(values["Name"]),base: base,intents: intents,on: on,off: off,locked: locked,radios: radios,editable: editable,radiosInherited: id != -1 && values["RBGroups"] == nil))
        }
        return PDFLayerStateReport(groups: groups,configurations: configurations)
    }
    static func setLayerState(_ data: Data,entry: PDFLayerStateConfiguration,base: String,intents: [String],on: [Int],off: [Int],locked: [Int]? = nil) throws -> Data {
        var file = try CatalogFile(data)
        let report = try layerStateReport(file.data)
        guard report.configurations.contains(entry),entry.editable,["ON","OFF","Unchanged"].contains(base),!intents.isEmpty,intents.count <= 64,Set(intents).count == intents.count,intents.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { throw PDFSourceError.content }
        guard entry.id != -1 || (base == "ON" && intents == ["View"]) else { throw PDFSourceError.content }
        let refs = Dictionary(uniqueKeysWithValues: report.groups.map { ($0.id,$0.generation) })
        guard Set(on).count == on.count,Set(off).count == off.count,Set(on).isDisjoint(with: off),(on+off).allSatisfy({ refs[$0] != nil }) else { throw PDFSourceError.content }
        let selectedLocks = locked ?? entry.locked
        guard Set(selectedLocks).count == selectedLocks.count,selectedLocks.allSatisfy({ refs[$0] != nil }) else { throw PDFSourceError.content }
        let previous = Dictionary(uniqueKeysWithValues: report.groups.map { ($0.id,$0.visible) })
        let changed = PDFLayerStateConfiguration(id: entry.id,name: entry.name,base: base,intents: intents,on: on,off: off,locked: entry.locked,radios: entry.radios,editable: true)
        let before = entry.states(previous: previous),after = changed.states(previous: previous)
        guard entry.locked.allSatisfy({ before[$0] == after[$0] }),entry.radios.allSatisfy({ group in group.filter { after[$0] == true }.count <= 1 }) else { throw PDFSourceError.permission }
        let props = try file.dictionary(file.catalog["OCProperties"]),alternatives = try file.array(props["Configs"])
        guard entry.id == -1 || alternatives.indices.contains(entry.id),let range = entry.id == -1 ? props["D"] : alternatives[entry.id] else { throw PDFSourceError.content }
        let values = try file.dictionary(range)
        func names(_ value: String) -> String { "/"+value.utf8.map { (33...126).contains($0) && !Array("()<>[]{}/%#".utf8).contains($0) ? String(UnicodeScalar($0)) : String(format: "#%02X",$0) }.joined() }
        func array(_ ids: [Int]) -> Data { Data(("["+ids.map { "\($0) \(refs[$0]!) R" }.joined(separator: " ")+"]").utf8) }
        let intent = entry.id == -1 ? "/View" : "["+intents.map(names).joined(separator: " ")+"]"
        var keys: Set<String> = ["BaseState","Intent","ON","OFF"],updates = ["BaseState":Data(("/"+base).utf8),"Intent":Data(intent.utf8),"ON":array(on),"OFF":array(off)]
        if locked != nil { keys.insert("Locked"); updates["Locked"] = array(selectedLocks) }
        let updated = file.rewrite(values,excluding: keys,appending: updates)
        let body: Data
        if entry.id == -1 { body = file.rewrite(props,excluding: ["D"],appending: ["D":updated]) }
        else {
            var configs = Data("[".utf8)
            for (index,item) in alternatives.enumerated() { configs.append(index == entry.id ? updated : file.raw(item)); configs.append(Data(" ".utf8)) }; configs.append(Data("]".utf8))
            body = file.rewrite(props,excluding: ["Configs"],appending: ["Configs":configs])
        }
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":body]))])
    }
    static func setLayerRadios(_ data: Data,entry: PDFLayerStateConfiguration,radios: [[Int]]?) throws -> Data {
        var file = try CatalogFile(data)
        let report = try layerStateReport(file.data)
        guard entry.editable,report.configurations.contains(entry),entry.id != -1 || radios != nil else { throw PDFSourceError.alreadyUsed }
        let refs = Dictionary(uniqueKeysWithValues: report.groups.map { ($0.id,$0.generation) })
        let effective = radios ?? report.configurations.first(where: { $0.id == -1 })?.radios ?? []
        guard effective.count <= 1000,effective.reduce(0,{ $0+$1.count }) <= 100000 else { throw PDFSourceError.content }
        var seen = Set<[Int]>()
        for group in effective {
            guard group.count >= 2,group.count <= 10000,Set(group).count == group.count,group.allSatisfy({ refs[$0] != nil }),seen.insert(group.sorted()).inserted else { throw PDFSourceError.content }
        }
        let previous = Dictionary(uniqueKeysWithValues: report.groups.map { ($0.id,$0.visible) })
        let affected = report.configurations.filter { $0.id == entry.id || entry.id == -1 && $0.radiosInherited }
        for configuration in affected {
            guard configuration.editable else { throw PDFSourceError.content }
            let states = configuration.states(previous: previous)
            guard effective.allSatisfy({ $0.filter { states[$0] == true }.count <= 1 }) else { throw PDFSourceError.permission }
        }
        if entry.radios == effective && entry.radiosInherited == (radios == nil) { return data }
        let props = try file.dictionary(file.catalog["OCProperties"]),alternatives = try file.array(props["Configs"])
        guard entry.id == -1 || alternatives.indices.contains(entry.id),let range = entry.id == -1 ? props["D"] : alternatives[entry.id] else { throw PDFSourceError.content }
        let values = try file.dictionary(range)
        let array = Data(("["+effective.map { "["+$0.map { "\($0) \(refs[$0]!) R" }.joined(separator: " ")+"]" }.joined(separator: " ")+"]").utf8)
        let updated = file.rewrite(values,excluding: ["RBGroups"],appending: radios == nil ? [:] : ["RBGroups":array])
        let body: Data
        if entry.id == -1 { body = file.rewrite(props,excluding: ["D"],appending: ["D":updated]) }
        else {
            var configs = Data("[".utf8); for (index,value) in alternatives.enumerated() { configs.append(index == entry.id ? updated : file.raw(value)); configs.append(Data(" ".utf8)) }; configs.append(Data("]".utf8))
            body = file.rewrite(props,excluding: ["Configs"],appending: ["Configs":configs])
        }
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":body]))])
    }
    static func layerPresets(_ data: Data) throws -> [PDFLayerPreset] {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"])
        var ranges: [(Int,Range<Int>)] = []
        if let current = props["D"] { ranges.append((-1,current)) }
        ranges += try file.array(props["Configs"]).enumerated().map { ($0.offset,$0.element) }
        return try ranges.map { index,range in
            let config = try file.dictionary(range),name = try file.text(config["Name"])
            let intent: [String]
            if let range = config["Intent"] {
                let value = try file.resolve(range)
                if file.name(value).hasPrefix("[") { intent = try file.array(value).map { file.decodedName($0) } }
                else { intent = [file.decodedName(value)] }
            } else { intent = ["View"] }
            return PDFLayerPreset(id: index,name: name,creator: try file.text(config["Creator"]),canMakeDefault: intent == ["View"])
        }
    }
    static func editLayerPreset(_ data: Data,operation: PDFLayerPresetOperation) throws -> Data {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),ranges = try file.array(props["Configs"])
        guard ranges.count <= 10000,let defaultRange = props["D"] else { throw PDFSourceError.content }
        let presets = try layerPresets(file.data)
        func validated(_ input: String,excluding id: Int?) throws -> String {
            let name = input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            guard !name.isEmpty,name.utf16.count <= 2000,!name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw PDFSourceError.content }
            func key(_ value: String) -> String { value.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive,locale: Locale(identifier: "en_US_POSIX")) }
            guard !presets.contains(where: { $0.id != id && key($0.name) == key(name) }) else { throw PDFSourceError.alreadyUsed }
            return name
        }
        var alternativeBodies = ranges.map { file.raw($0) },defaultBody: Data?
        switch operation {
        case .create(let input):
            guard ranges.count < 10000 else { throw PDFSourceError.content }
            let name = try validated(input,excluding: nil),values = try file.dictionary(defaultRange)
            alternativeBodies.append(file.rewrite(values,excluding: ["Name","Creator"],appending: ["Name":CatalogFile.string(name),"Creator":CatalogFile.string("BotPlus PDF Editor")]))
        case .rename(let id,let input):
            guard id == -1 || ranges.indices.contains(id) else { throw PDFSourceError.content }
            let name = try validated(input,excluding: id),values = try file.dictionary(id == -1 ? defaultRange : ranges[id])
            let body = file.rewrite(values,excluding: ["Name"],appending: ["Name":CatalogFile.string(name)])
            if id == -1 { defaultBody = body } else { alternativeBodies[id] = body }
        case .remove(let id):
            guard ranges.indices.contains(id) else { throw PDFSourceError.content }; alternativeBodies.remove(at: id)
        }
        var array = Data("[".utf8)
        for body in alternativeBodies { array.append(body); array.append(Data(" ".utf8)) }; array.append(Data("]".utf8))
        var extra = ["Configs":array]
        if let defaultBody { extra["D"] = defaultBody }
        let updated = file.rewrite(props,excluding: Set(extra.keys),appending: extra)
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":updated]))])
    }
    static func makeLayerPresetDefault(_ data: Data,index: Int) throws -> Data {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),ranges = try file.array(props["Configs"])
        guard ranges.indices.contains(index),let oldRange = props["D"] else { throw PDFSourceError.content }
        let presets = try layerPresets(file.data)
        guard presets.first(where: { $0.id == index })?.canMakeDefault == true else { throw PDFSourceError.content }
        let old = try file.dictionary(oldRange),chosen = try file.dictionary(ranges[index])
        let references = try file.array(props["OCGs"]).map { range -> (Int,Int) in guard let ref = file.syntax.reference(range) else { throw PDFSourceError.content }; return ref }
        let ids = Set(references.map(\.0))
        guard ids.count == references.count else { throw PDFSourceError.content }
        func groupIDs(_ key: String) throws -> Set<Int> {
            let refs = try file.array(chosen[key]).map { range -> Int in guard let ref = file.syntax.reference(range),ids.contains(ref.0) else { throw PDFSourceError.content }; return ref.0 }
            return Set(refs)
        }
        let on = try groupIDs("ON"),off = try groupIDs("OFF"),base = file.name(chosen["BaseState"])
        guard on.isDisjoint(with: off),["","ON","OFF","Unchanged"].contains(base) else { throw PDFSourceError.content }
        let oldOn = Set(try file.array(old["ON"]).compactMap { file.syntax.reference($0)?.0 }),oldOff = Set(try file.array(old["OFF"]).compactMap { file.syntax.reference($0)?.0 })
        let oldBase = file.name(old["BaseState"]) != "OFF"
        var hidden: [(Int,Int)] = []
        for ref in references {
            let previous = oldOff.contains(ref.0) ? false : oldOn.contains(ref.0) ? true : oldBase
            let initial = base == "Unchanged" ? previous : base != "OFF"
            if off.contains(ref.0) || (!on.contains(ref.0) && !initial) { hidden.append(ref) }
        }
        let offBody = Data(("["+hidden.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8)
        let inheritedValues = Dictionary(uniqueKeysWithValues: ["RBGroups","Order"].map { ($0,old[$0].map { file.raw($0) } ?? Data("[]".utf8)) })
        var selectedValues = ["BaseState":Data("/ON".utf8),"OFF":offBody]
        for (key,value) in inheritedValues where chosen[key] == nil { selectedValues[key] = value }
        let selected = file.rewrite(chosen,excluding: Set(["BaseState","ON","OFF"]).union(selectedValues.keys),appending: selectedValues)
        var alternatives = Data("[".utf8)
        for (offset,range) in ranges.enumerated() {
            let values = offset == index ? old : try file.dictionary(range)
            let additions = inheritedValues.filter { values[$0.key] == nil }
            alternatives.append(!additions.isEmpty || offset == index ? file.rewrite(values,excluding: [],appending: additions) : file.raw(range)); alternatives.append(Data(" ".utf8))
        }
        alternatives.append(Data("]".utf8))
        let updatedProps = file.rewrite(props,excluding: ["D","Configs"],appending: ["D":selected,"Configs":alternatives])
        let catalog = file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":updatedProps])
        return try file.write([(file.root.0,file.root.1,catalog)])
    }
    private struct OrderTree {
        var label: Data? = nil
        var title = ""
        var nodes: [OrderNode] = []
        var encoded: Data {
            var data = Data("[".utf8); if let label { data.append(label); data.append(Data(" ".utf8)) }
            for node in nodes { data.append(node.encoded); data.append(Data(" ".utf8)) }; data.append(Data("]".utf8)); return data
        }
    }
    private struct OrderNode {
        var reference: Data? = nil
        var layerID: Int?
        var title: String
        var children: OrderTree? = nil
        var encoded: Data {
            if let reference { var data = reference; if let children { data.append(Data(" ".utf8)); data.append(children.encoded) }; return data }
            return children?.encoded ?? Data("[]".utf8)
        }
    }
    private static func readOrder(_ file: inout CatalogFile,range: Range<Int>?,known: [Int:PDFLayerInfo],depth: Int = 0,count: inout Int,stack: inout Set<Int>) throws -> OrderTree {
        guard let range else { return OrderTree() }; guard depth < 64 else { throw PDFSourceError.content }
        let ref = file.syntax.reference(range)
        if let ref { guard stack.insert(ref.0).inserted else { throw PDFSourceError.content } }; defer { if let ref { stack.remove(ref.0) } }
        let resolved = try file.resolve(range); guard file.syntax.string(resolved).hasPrefix("[") else { throw PDFSourceError.content }
        var values = try file.array(resolved),tree = OrderTree()
        func textToken(_ value: String) -> Bool { value.hasPrefix("(") || value.hasPrefix("<") && !value.hasPrefix("<<") }
        if let first = values.first {
            let raw = try file.resolve(first)
            if textToken(file.syntax.string(raw)) { tree.label = file.raw(first); tree.title = try file.text(first); values.removeFirst() }
        }
        var index = 0
        while index < values.count {
            count += 1; guard count <= 10000 else { throw PDFSourceError.content }
            let value = values[index]
            if let ref = file.syntax.reference(value),let group = known[ref.0],group.generation == ref.1 {
                var node = OrderNode(reference: file.raw(value),layerID: group.id,title: group.name)
                if index+1 < values.count {
                    let next = try file.resolve(values[index+1])
                    if file.syntax.string(next).hasPrefix("[") {
                        let items = try file.array(next)
                        let labeled: Bool
                        if let first = items.first { let raw = try file.resolve(first); labeled = textToken(file.syntax.string(raw)) } else { labeled = false }
                        if !labeled { node.children = try readOrder(&file,range: values[index+1],known: known,depth: depth+1,count: &count,stack: &stack); index += 1 }
                    }
                }
                tree.nodes.append(node)
            } else {
                let nested = try readOrder(&file,range: value,known: known,depth: depth+1,count: &count,stack: &stack)
                tree.nodes.append(OrderNode(layerID: nil,title: nested.title,children: nested))
            }
            index += 1
        }
        return tree
    }
    static func layerOrderConfigurations(_ data: Data) throws -> [PDFLayerOrderConfiguration] {
        // Inspect the original graph before PDFium can normalize away a dangling
        // reference or cyclic array. Such an Order must not become editable.
        guard let provider = CGDataProvider(data: data as CFData),let cg = CGPDFDocument(provider),let catalog = cg.catalog else { throw PDFSourceError.document }
        var cgProps: CGPDFDictionaryRef?,cgDefault: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog,"OCProperties",&cgProps),let cgProps,CGPDFDictionaryGetDictionary(cgProps,"D",&cgDefault),let cgDefault else { throw PDFSourceError.content }
        func safeOrder(_ dictionary: CGPDFDictionaryRef) -> Bool? {
            var object: CGPDFObjectRef?
            guard CGPDFDictionaryGetObject(dictionary,"Order",&object) else { return nil }
            var root: CGPDFArrayRef?
            guard CGPDFDictionaryGetArray(dictionary,"Order",&root),let root else { return false }
            var stack = Set<UInt>(),count = 0
            func walk(_ array: CGPDFArrayRef,_ depth: Int) -> Bool {
                guard depth < 64,stack.insert(UInt(bitPattern: array.rawValue)).inserted else { return false }
                defer { stack.remove(UInt(bitPattern: array.rawValue)) }
                for index in 0..<CGPDFArrayGetCount(array) {
                    count += 1; guard count <= 10000 else { return false }
                    var value: CGPDFObjectRef?; guard CGPDFArrayGetObject(array,index,&value),let value else { return false }
                    switch CGPDFObjectGetType(value) {
                    case .string: guard index == 0 else { return false }
                    case .array:
                        var nested: CGPDFArrayRef?; guard CGPDFArrayGetArray(array,index,&nested),let nested,walk(nested,depth+1) else { return false }
                    case .dictionary:
                        var group: CGPDFDictionaryRef?,name: UnsafePointer<CChar>?
                        guard CGPDFArrayGetDictionary(array,index,&group),let group,CGPDFDictionaryGetName(group,"Type",&name),let name,String(cString: name) == "OCG" else { return false }
                    default: return false
                    }
                }
                return true
            }; return walk(root,0)
        }
        let defaultSafe = safeOrder(cgDefault) ?? true
        var originalSafety = [-1:defaultSafe],cgAlternatives: CGPDFArrayRef?
        if CGPDFDictionaryGetArray(cgProps,"Configs",&cgAlternatives),let cgAlternatives {
            for index in 0..<CGPDFArrayGetCount(cgAlternatives) {
                var value: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(cgAlternatives,index,&value),let value { originalSafety[index] = safeOrder(value) ?? defaultSafe }
                else { originalSafety[index] = false }
            }
        }
        var file = try CatalogFile(data)
        let groups = try layerConfiguration(file.data,includingOrder: false).groups,known = Dictionary(uniqueKeysWithValues: groups.map { ($0.id,$0) })
        for group in groups {
            guard let offset = file.offsets[group.id] else { throw PDFSourceError.content }
            let values = try file.syntax.objectDictionary(at: offset).values
            guard file.name(values["Type"]) == "OCG" else { throw PDFSourceError.content }
        }
        let props = try file.dictionary(file.catalog["OCProperties"])
        guard let primaryRange = props["D"] else { throw PDFSourceError.content }
        let primary = try file.dictionary(primaryRange),alternatives = try file.array(props["Configs"])
        var result: [PDFLayerOrderConfiguration] = []
        for (id,range) in [(-1,primaryRange)]+alternatives.enumerated().map({ ($0.offset,$0.element) }) {
            let values = try file.dictionary(range),inherited = id != -1 && values["Order"] == nil
            var rows: [PDFLayerOrderEntry] = [],rootTitle = "",editable = originalSafety[id] == true
            do {
                guard editable else { throw PDFSourceError.content }
                var count = 0,stack = Set<Int>()
                let tree = try readOrder(&file,range: inherited ? primary["Order"] : values["Order"],known: known,count: &count,stack: &stack); rootTitle = tree.title
                func walk(_ tree: OrderTree,path: [Int],depth: Int) {
                    for (index,node) in tree.nodes.enumerated() {
                        let location = path+[index]
                        rows.append(PDFLayerOrderEntry(path: location,title: node.title,layerID: node.layerID,depth: depth,canMoveUp: index > 0,canMoveDown: index+1 < tree.nodes.count,canRemove: node.children?.nodes.isEmpty ?? true))
                        if let children = node.children { walk(children,path: location,depth: depth+1) }
                    }
                }; walk(tree,path: [],depth: 0)
            } catch { editable = false; rows = [] }
            result.append(PDFLayerOrderConfiguration(id: id,name: try file.text(values["Name"]),rootTitle: rootTitle,rows: rows,inherited: inherited,editable: editable))
        }
        return result
    }
    static func editLayerOrder(_ data: Data,entry: PDFLayerOrderConfiguration,operation: PDFLayerOrderOperation) throws -> Data {
        var file = try CatalogFile(data)
        guard entry.editable,try layerOrderConfigurations(data).contains(entry) else { throw PDFSourceError.alreadyUsed }
        let props = try file.dictionary(file.catalog["OCProperties"]),primary = try file.dictionary(props["D"]),alternatives = try file.array(props["Configs"])
        guard entry.id == -1 || alternatives.indices.contains(entry.id),let range = entry.id == -1 ? props["D"] : alternatives[entry.id] else { throw PDFSourceError.content }
        let values = try file.dictionary(range)
        var additions: [String:Data] = [:]
        if case .inherit = operation {
            guard entry.id != -1 else { throw PDFSourceError.content }; if entry.inherited { return data }
        } else {
            let groups = try layerConfiguration(file.data,includingOrder: false).groups,known = Dictionary(uniqueKeysWithValues: groups.map { ($0.id,$0) })
            var count = 0,stack = Set<Int>(),tree = try readOrder(&file,range: entry.inherited ? primary["Order"] : values["Order"],known: known,count: &count,stack: &stack)
            func validPath(_ path: [Int]) -> Bool { !path.isEmpty && path.count <= 64 && entry.rows.contains(where: { $0.path == path }) }
            func title(_ text: String) throws -> String {
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,text.utf16.count <= 4096,!text.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw PDFSourceError.content }; return text
            }
            func changeChildren(_ tree: inout OrderTree,parent: [Int]?,depth: Int = 0,action: (inout OrderTree) throws -> Void) throws {
                guard let parent else { try action(&tree); return }
                let index = parent[depth]; guard tree.nodes.indices.contains(index) else { throw PDFSourceError.content }
                var children = tree.nodes[index].children ?? OrderTree()
                if depth+1 == parent.count { try action(&children) }
                else { try changeChildren(&children,parent: parent,depth: depth+1,action: action) }; tree.nodes[index].children = children
            }
            switch operation {
            case .move(let path,let direction):
                guard validPath(path),[-1,1].contains(direction) else { throw PDFSourceError.content }
            func move(_ tree: inout OrderTree,at depth: Int) throws {
                let index = path[depth]; guard tree.nodes.indices.contains(index) else { throw PDFSourceError.content }
                if depth == path.count-1 { let target = index+direction; guard tree.nodes.indices.contains(target) else { throw PDFSourceError.content }; tree.nodes.swapAt(index,target) }
                else { guard var children = tree.nodes[index].children else { throw PDFSourceError.content }; try move(&children,at: depth+1); tree.nodes[index].children = children }
                }; try move(&tree,at: 0)
            case .addSection(let parent,let name):
                guard parent == nil || validPath(parent!) else { throw PDFSourceError.content }; let name = try title(name)
                try changeChildren(&tree,parent: parent) { $0.nodes.append(OrderNode(layerID: nil,title: name,children: OrderTree(label: CatalogFile.string(name),title: name))) }
            case .renameSection(let path,let name):
                guard validPath(path),let row = entry.rows.first(where: { $0.path == path }),row.layerID == nil else { throw PDFSourceError.content }; let name = try title(name)
                if name == row.title { return data }
                let parent = path.count == 1 ? nil : Array(path.dropLast()),index = path.last!
                try changeChildren(&tree,parent: parent) { branch in
                    guard branch.nodes[index].reference == nil,var children = branch.nodes[index].children else { throw PDFSourceError.content }
                    children.label = CatalogFile.string(name); children.title = name; branch.nodes[index].title = name; branch.nodes[index].children = children
                }
            case .addLayer(let parent,let id):
                guard parent == nil || validPath(parent!),let layer = known[id] else { throw PDFSourceError.content }
                try changeChildren(&tree,parent: parent) { $0.nodes.append(OrderNode(reference: Data("\(layer.id) \(layer.generation) R".utf8),layerID: layer.id,title: layer.name)) }
            case .removeLeaf(let path):
                guard validPath(path) else { throw PDFSourceError.content }
                let parent = path.count == 1 ? nil : Array(path.dropLast()),index = path.last!
                try changeChildren(&tree,parent: parent) { branch in
                    guard branch.nodes[index].children?.nodes.isEmpty != false else { throw PDFSourceError.content }; branch.nodes.remove(at: index)
                }
            case .reparent(let path,let parent):
                guard validPath(path),parent == nil || validPath(parent!) else { throw PDFSourceError.content }
                if let parent { guard !parent.starts(with: path) else { throw PDFSourceError.content } }
                let prefix = Array(path.dropLast()),oldParent = prefix.isEmpty ? nil : prefix,index = path.last!
                if oldParent == parent { return data }
                var moving: OrderNode?
                try changeChildren(&tree,parent: oldParent) { moving = $0.nodes.remove(at: index) }
                var destination = parent
                // Removing one sibling changes only the path component at its
                // parent's depth. Adjust the destination before descending.
                if var target = destination,target.count > prefix.count,Array(target.prefix(prefix.count)) == prefix,target[prefix.count] > index {
                    target[prefix.count] -= 1; destination = target
                }
                guard let moving else { throw PDFSourceError.content }
                try changeChildren(&tree,parent: destination) { $0.nodes.append(moving) }
            case .inherit: throw PDFSourceError.content
            }
            var elements = 0
            func validate(_ branch: OrderTree,depth: Int) throws {
                guard depth < 64 else { throw PDFSourceError.content }; if branch.label != nil { elements += 1 }
                for (index,node) in branch.nodes.enumerated() {
                    elements += 1; guard elements <= 10000 else { throw PDFSourceError.content }
                    // Removing/reordering an entry must not attach a following
                    // anonymous array to a different OCG on the next parse.
                    if node.reference != nil,node.children == nil,index+1 < branch.nodes.count {
                        let next = branch.nodes[index+1]
                        guard next.reference != nil || next.children?.label != nil else { throw PDFSourceError.content }
                    }
                    if let children = node.children { if node.reference != nil { elements += 1 }; try validate(children,depth: depth+1) }
                }; guard elements <= 10000 else { throw PDFSourceError.content }
            }; try validate(tree,depth: 0); additions["Order"] = tree.encoded
        }
        let updated = file.rewrite(values,excluding: ["Order"],appending: additions),body: Data
        if entry.id == -1 { body = file.rewrite(props,excluding: ["D"],appending: ["D":updated]) }
        else {
            var configs = Data("[".utf8); for (index,value) in alternatives.enumerated() { configs.append(index == entry.id ? updated : file.raw(value)); configs.append(Data(" ".utf8)) }; configs.append(Data("]".utf8))
            body = file.rewrite(props,excluding: ["Configs"],appending: ["Configs":configs])
        }
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":body]))])
    }
    static func layerConfiguration(_ data: Data,includingOrder: Bool = true) throws -> PDFLayerConfiguration {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),groups = try file.array(props["OCGs"]),config = try file.dictionary(props["D"])
        let off = Set(config["OFF"].map { file.syntax.references($0).map(\.0) } ?? []),on = Set(config["ON"].map { file.syntax.references($0).map(\.0) } ?? []),locked = Set(config["Locked"].map { file.syntax.references($0).map(\.0) } ?? [])
        let base = file.name(config["BaseState"]) != "OFF"
        let entries: [PDFLayerInfo] = try groups.compactMap { range in
            guard let ref = file.syntax.reference(range) else { return nil }; let group = try file.dictionary(range)
            let usage = try file.dictionary(group["Usage"]),view = try file.dictionary(usage["View"]),print = try file.dictionary(usage["Print"])
            func state(_ name: String) -> Bool? { name == "ON" ? true : name == "OFF" ? false : nil }
            var intent = try file.array(group["Intent"]).map { file.decodedName($0) }
            if intent.isEmpty { intent = [group["Intent"].map { file.decodedName($0) } ?? "View"] }
            return PDFLayerInfo(id: ref.0,generation: ref.1,name: try file.text(group["Name"]),visible: off.contains(ref.0) ? false : on.contains(ref.0) ? true : base,locked: locked.contains(ref.0),viewState: state(file.name(view["ViewState"])),printState: state(file.name(print["PrintState"])),intent: intent)
        }
        guard Set(entries.map(\.id)).count == entries.count else { throw PDFSourceError.content }
        if !includingOrder { return PDFLayerConfiguration(groups: entries,rows: [],hasOrder: config["Order"] != nil) }
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id,$0) }); var rows: [PDFLayerRow] = [],stack = Set<Int>()
        func walk(_ values: [Range<Int>],depth: Int,path: String) throws {
            guard depth < 128,rows.count <= 100000 else { throw PDFSourceError.content }
            for (index,value) in values.enumerated() {
                let key = path+".\(index)"
                if let ref = file.syntax.reference(value),let group = byID[ref.0] { rows.append(PDFLayerRow(id: key,layerID: group.id,title: group.name,depth: depth)); continue }
                let reference = file.syntax.reference(value)
                if let reference { guard stack.insert(reference.0).inserted else { throw PDFSourceError.content } }
                defer { if let reference { stack.remove(reference.0) } }
                let raw = try file.resolve(value)
                guard file.syntax.string(raw).hasPrefix("[") else { continue }
                let nested = try file.array(raw)
                if let first = nested.first {
                    let firstRaw = try file.resolve(first),token = file.syntax.string(firstRaw)
                    if token.hasPrefix("(") || (token.hasPrefix("<") && !token.hasPrefix("<<")) {
                        rows.append(PDFLayerRow(id: key+".label",layerID: nil,title: try file.text(first),depth: depth))
                        try walk(Array(nested.dropFirst()),depth: depth+1,path: key); continue
                    }
                }
                try walk(nested,depth: depth+1,path: key)
            }
        }
        if let order = config["Order"] { try walk(file.array(order),depth: 0,path: "order") }
        return PDFLayerConfiguration(groups: entries,rows: rows,hasOrder: config["Order"] != nil)
    }
    static func layerExtendedUsage(_ data: Data,entry: PDFLayerInfo) throws -> PDFLayerExtendedUsage {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),groups = try file.array(props["OCGs"])
        guard let range = groups.first(where: { file.syntax.reference($0)?.0 == entry.id }),file.syntax.reference(range)?.1 == entry.generation else { throw PDFSourceError.alreadyUsed }
        let group = try file.dictionary(range),usage = try file.dictionary(group["Usage"])
        guard try file.text(group["Name"]) == entry.name else { throw PDFSourceError.alreadyUsed }
        let export = try file.dictionary(usage["Export"]),zoom = try file.dictionary(usage["Zoom"]),language = try file.dictionary(usage["Language"])
        func state(_ value: Range<Int>?) throws -> Bool? {
            guard let value else { return nil }; let name = file.name(value); guard ["ON","OFF"].contains(name) else { throw PDFSourceError.content }; return name == "ON"
        }
        func number(_ value: Range<Int>?) throws -> Double? {
            guard let value else { return nil }; let resolved = try file.resolve(value)
            guard let number = Double(file.syntax.string(resolved)),number.isFinite else { throw PDFSourceError.content }; return number
        }
        let creator = try file.dictionary(usage["CreatorInfo"]),user = try file.dictionary(usage["User"]),element = try file.dictionary(usage["PageElement"]),printUsage = try file.dictionary(usage["Print"])
        func metadataName(_ value: Range<Int>) throws -> String {
            let resolved = try file.resolve(value); guard file.syntax.string(resolved).hasPrefix("/") else { throw PDFSourceError.content }; return file.decodedName(resolved)
        }
        var metadata = PDFLayerUsageMetadata()
        if usage["CreatorInfo"] != nil {
            guard creator["Creator"] != nil,let subtype = creator["Subtype"] else { throw PDFSourceError.content }
            metadata.creatorEnabled = true; metadata.creator = try file.text(creator["Creator"]); metadata.creatorSubtype = try metadataName(subtype)
        }
        if usage["User"] != nil {
            guard let type = user["Type"],let names = user["Name"] else { throw PDFSourceError.content }
            metadata.userType = try metadataName(type)
            let resolved = try file.resolve(names)
            if file.syntax.string(resolved).hasPrefix("[") { metadata.userNames = try file.array(resolved).map { try file.text($0) } }
            else { metadata.userNames = [try file.text(resolved)] }
            guard !metadata.userType.isEmpty else { throw PDFSourceError.content }
        }
        if usage["PageElement"] != nil { guard let subtype = element["Subtype"] else { throw PDFSourceError.content }; metadata.pageElement = try metadataName(subtype); guard !metadata.pageElement.isEmpty else { throw PDFSourceError.content } }
        if let subtype = printUsage["Subtype"] { metadata.printSubtype = try metadataName(subtype) }
        let result = PDFLayerExtendedUsage(exportState: try state(export["ExportState"]),zoomEnabled: usage["Zoom"] != nil,minZoom: try number(zoom["min"]),maxZoom: try number(zoom["max"]),language: try file.text(language["Lang"]),preferred: try state(language["Preferred"]),metadata: metadata)
        guard result.valid,usage["Language"] == nil || !result.language.isEmpty else { throw PDFSourceError.content }; return result
    }
    static func setLayerUsage(_ data: Data,entry: PDFLayerInfo,viewState: Bool?,printState: Bool?,intents: [String]? = nil,extended: PDFLayerExtendedUsage? = nil,name: String? = nil) throws -> Data {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),config = try file.dictionary(props["D"]),groups = try file.array(props["OCGs"])
        guard let value = groups.first(where: { file.syntax.reference($0)?.0 == entry.id }),let ref = file.syntax.reference(value),ref.1 == entry.generation else { throw PDFSourceError.alreadyUsed }
        let group = try file.dictionary(value)
        guard try file.text(group["Name"]) == entry.name else { throw PDFSourceError.alreadyUsed }
        guard !Set(config["Locked"].map { file.syntax.references($0).map(\.0) } ?? []).contains(entry.id) else { throw PDFSourceError.permission }
        let usage = try file.dictionary(group["Usage"])
        var categories: [String:Data] = [:]
        for (category,key,state) in [("View","ViewState",viewState),("Print","PrintState",printState)] {
            let original = try file.dictionary(usage[category])
            var excluding: Set<String> = [key],values = state.map { [key:Data(($0 ? "/ON" : "/OFF").utf8)] } ?? [:]
            if category == "Print",let metadata = extended?.metadata { excluding.insert("Subtype"); if !metadata.printSubtype.isEmpty { values["Subtype"] = PDFLayerUsageMetadata.encodedName(metadata.printSubtype) } }
            if !values.isEmpty || original.keys.contains(where: { !excluding.contains($0) }) { categories[category] = file.rewrite(original,excluding: excluding,appending: values) }
        }
        var usageKeys: Set<String> = ["View","Print"]
        if let extended {
            guard extended.valid else { throw PDFSourceError.content }
            usageKeys.formUnion(["Export","Zoom","Language"])
            let export = try file.dictionary(usage["Export"])
            if extended.exportState != nil { categories["Export"] = file.rewrite(export,excluding: ["ExportState"],appending: extended.exportState.map { ["ExportState":Data(($0 ? "/ON" : "/OFF").utf8)] } ?? [:]) }
            let zoom = try file.dictionary(usage["Zoom"])
            var zoomValues: [String:Data] = [:]
            if extended.zoomEnabled {
                for (key,value) in [("min",extended.minZoom),("max",extended.maxZoom)] { if let value { zoomValues[key] = Data(String(format: "%.8f",locale: Locale(identifier: "en_US_POSIX"),value).utf8) } }
                if zoomValues.isEmpty { zoomValues["min"] = Data("0".utf8) }
            }
            if extended.zoomEnabled { categories["Zoom"] = file.rewrite(zoom,excluding: ["min","max"],appending: zoomValues) }
            let language = try file.dictionary(usage["Language"])
            var languageValues: [String:Data] = [:]
            if !extended.language.isEmpty {
                languageValues["Lang"] = CatalogFile.string(extended.language)
                if let preferred = extended.preferred { languageValues["Preferred"] = Data((preferred ? "/ON" : "/OFF").utf8) }
            }
            if !extended.language.isEmpty { categories["Language"] = file.rewrite(language,excluding: ["Lang","Preferred"],appending: languageValues) }
            if let metadata = extended.metadata {
                usageKeys.formUnion(["CreatorInfo","User","PageElement"])
                let creator = try file.dictionary(usage["CreatorInfo"]),user = try file.dictionary(usage["User"]),element = try file.dictionary(usage["PageElement"])
                if metadata.creatorEnabled { categories["CreatorInfo"] = file.rewrite(creator,excluding: ["Creator","Subtype"],appending: ["Creator":CatalogFile.string(metadata.creator),"Subtype":PDFLayerUsageMetadata.encodedName(metadata.creatorSubtype)]) }
                if !metadata.userType.isEmpty {
                    var names = Data("[".utf8)
                    for name in metadata.userNames { names.append(CatalogFile.string(name)); names.append(Data(" ".utf8)) }; names.append(Data("]".utf8))
                    categories["User"] = file.rewrite(user,excluding: ["Type","Name"],appending: ["Type":PDFLayerUsageMetadata.encodedName(metadata.userType),"Name":metadata.userNames.count == 1 ? CatalogFile.string(metadata.userNames[0]) : names])
                }
                if !metadata.pageElement.isEmpty { categories["PageElement"] = file.rewrite(element,excluding: ["Subtype"],appending: ["Subtype":PDFLayerUsageMetadata.encodedName(metadata.pageElement)]) }
            }
        }
        let updatedUsage = file.rewrite(usage,excluding: usageKeys,appending: categories)
        var groupChanges = ["Usage":updatedUsage],excluded: Set<String> = ["Usage"]
        if let name,name != entry.name {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,name.utf16.count <= 4096,!name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw PDFSourceError.content }
            excluded.insert("Name"); groupChanges["Name"] = CatalogFile.string(name)
        }
        if let intents {
            guard intents.count <= 64,Set(intents).count == intents.count,intents.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 && !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { throw PDFSourceError.content }
            excluded.insert("Intent")
            if !intents.isEmpty {
                let names = intents.map { name in "/"+name.utf8.map { (33...126).contains($0) && !Array("()<>[]{}/%#".utf8).contains($0) ? String(UnicodeScalar($0)) : String(format: "#%02X",$0) }.joined() }
                groupChanges["Intent"] = Data(("["+names.joined(separator: " ")+"]").utf8)
            }
        }
        let updatedGroup = file.rewrite(group,excluding: excluded,appending: groupChanges)
        var applications: [Data] = []
        if let raw = config["AS"] { let resolved = try file.resolve(raw); guard file.syntax.string(resolved).hasPrefix("[") else { throw PDFSourceError.content } }
        for item in try file.array(config["AS"]) {
            let application = try file.dictionary(item),event = file.name(application["Event"]),ocgs = try file.array(application["OCGs"]),categories = try file.array(application["Category"])
            let category = categories.count == 1 ? file.name(categories[0]) : ""
            let controlled = category == "View" && event == "View" || category == "Print" && event == "Print" || extended != nil && ((category == "Export" && event == "Export") || (category == "Zoom" && event == "View"))
            let exactlyThis = Set(application.keys).isSubset(of: ["Event","OCGs","Category"]) && ocgs.count == 1 && file.syntax.reference(ocgs[0])?.0 == entry.id && controlled
            let ownedLanguage = extended != nil && Set(application.keys).isSubset(of: ["Event","OCGs","Category","BotPlusLanguage"]) && application["BotPlusLanguage"].map({ file.syntax.string($0) == "true" }) == true && event == "View" && category == "Language"
            if !exactlyThis && !ownedLanguage { applications.append(file.raw(item)) }
        }
        for (event,state) in [("View",viewState),("Print",printState)] where state != nil {
            applications.append(Data("<< /Event /\(event) /OCGs [\(ref.0) \(ref.1) R] /Category [/\(event)] >>".utf8))
        }
        if let extended {
            for (event,category,enabled) in [("Export","Export",extended.exportState != nil),("View","Zoom",extended.zoomEnabled)] where enabled { applications.append(Data("<< /Event /\(event) /OCGs [\(ref.0) \(ref.1) R] /Category [/\(category)] >>".utf8)) }
            // Language selection compares exact/partial matches across all groups
            // in one application dictionary, not isolated one-group rules.
            var languageRefs: [(Int,Int)] = []
            for range in groups {
                guard let other = file.syntax.reference(range) else { continue }
                let hasLanguage: Bool
                if other.0 == entry.id { hasLanguage = !extended.language.isEmpty }
                else { let values = try file.dictionary(range),u = try file.dictionary(values["Usage"]),l = try file.dictionary(u["Language"]); hasLanguage = try !file.text(l["Lang"]).isEmpty }
                if hasLanguage { languageRefs.append(other) }
            }
            if !languageRefs.isEmpty { applications.append(Data(("<< /Event /View /Category [/Language] /OCGs ["+languageRefs.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"] /BotPlusLanguage true >>").utf8)) }
        }
        var asArray = Data("[".utf8); for item in applications { asArray.append(item); asArray.append(Data(" ".utf8)) }; asArray.append(Data("]".utf8))
        let updated = file.rewrite(config,excluding: ["AS"],appending: ["AS":asArray])
        let oc = file.rewrite(props,excluding: ["D"],appending: ["D":updated])
        let catalog = file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":oc])
        return try file.write([(ref.0,ref.1,updatedGroup),(file.root.0,file.root.1,catalog)])
    }
    static func setLayerLocked(_ data: Data,entry: PDFLayerInfo,locked: Bool) throws -> Data {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),config = try file.dictionary(props["D"]),groups = try file.array(props["OCGs"])
        let refs = groups.compactMap { file.syntax.reference($0) }
        guard refs.count == groups.count,Set(refs.map(\.0)).count == refs.count,
              let value = groups.first(where: { file.syntax.reference($0)?.0 == entry.id }),let ref = file.syntax.reference(value),ref.1 == entry.generation else { throw PDFSourceError.alreadyUsed }
        let group = try file.dictionary(value)
        guard try file.text(group["Name"]) == entry.name else { throw PDFSourceError.alreadyUsed }
        if let raw = config["Locked"] { let resolved = try file.resolve(raw); guard file.syntax.string(resolved).hasPrefix("[") else { throw PDFSourceError.content } }
        let values = try file.array(config["Locked"]),locks = values.compactMap { file.syntax.reference($0) }
        guard locks.count == values.count,Set(locks.map(\.0)).count == locks.count,locks.allSatisfy({ lock in refs.contains { $0.0 == lock.0 && $0.1 == lock.1 } }),locks.contains(where: { $0.0 == entry.id }) == entry.locked else { throw PDFSourceError.alreadyUsed }
        var updatedLocks = locks.filter { $0.0 != entry.id }; if locked { updatedLocks.append(ref) }
        let updated = file.rewrite(config,excluding: ["Locked"],appending: ["Locked":Data(("["+updatedLocks.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8)])
        let oc = file.rewrite(props,excluding: ["D"],appending: ["D":updated])
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":oc]))])
    }
    static func setLayer(_ data: Data,entry: PDFLayerInfo,visible: Bool) throws -> Data {
        var file = try CatalogFile(data)
        let props = try file.dictionary(file.catalog["OCProperties"]),config = try file.dictionary(props["D"]),groups = try file.array(props["OCGs"])
        let refs = groups.compactMap { file.syntax.reference($0) }
        guard refs.contains(where: { $0.0 == entry.id }),let value = groups.first(where: { file.syntax.reference($0)?.0 == entry.id }) else { throw PDFSourceError.content }
        let group = try file.dictionary(value)
        guard try file.text(group["Name"]) == entry.name else { throw PDFSourceError.alreadyUsed }
        let locked = Set(config["Locked"].map { file.syntax.references($0).map(\.0) } ?? [])
        guard !locked.contains(entry.id) else { throw PDFSourceError.permission }
        let off = Set(config["OFF"].map { file.syntax.references($0).map(\.0) } ?? []),on = Set(config["ON"].map { file.syntax.references($0).map(\.0) } ?? []),base = file.name(config["BaseState"]) != "OFF"
        var states: [Int:Bool] = [:]
        for ref in refs { states[ref.0] = off.contains(ref.0) ? false : on.contains(ref.0) ? true : base }; states[entry.id] = visible
        if visible { for range in try file.array(config["RBGroups"]) { let radio = file.syntax.references(range).map(\.0); if radio.contains(entry.id) { for id in radio where id != entry.id { guard !locked.contains(id) || states[id] != true else { throw PDFSourceError.permission }; states[id] = false } } } }
        func array(_ value: Bool) -> Data { Data(("["+refs.filter { states[$0.0] == value }.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8) }
        let updated = file.rewrite(config,excluding: ["ON","OFF","BaseState"],appending: ["BaseState":Data("/ON".utf8),"ON":array(true),"OFF":array(false)])
        let oc = file.rewrite(props,excluding: ["D"],appending: ["D":updated])
        return try file.write([(file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["OCProperties"],appending: ["OCProperties":oc]))])
    }
    static func structure(_ data: Data,russian: Bool) throws -> PDFStructureReport {
        var file = try CatalogFile(data)
        let root = try file.dictionary(file.catalog["StructTreeRoot"]),mark = try file.dictionary(file.catalog["MarkInfo"]),language = try file.text(file.catalog["Lang"])
        let marked = mark["Marked"].map { file.syntax.string($0) == "true" } ?? false
        var nodes: [PDFStructureNode] = [],seen = Set<Int>(),issues: [String] = [],movement: [Int:(Bool,Bool)] = [:],reparentable = Set<Int>()
        func label(_ en: String,_ ru: String) -> String { russian ? ru : en }
        if !marked { issues.append(label("The catalog does not declare marked content.","Каталог не объявляет размеченное содержимое.")) }
        if root.isEmpty { issues.append(label("No structure tree. This PDF requires tagging before reading-order or alternative-text editing.","Дерево структуры отсутствует. Для редактирования порядка чтения и описаний сначала требуется разметка PDF.")) }
        if language.isEmpty { issues.append(label("Document language is missing.","Не указан язык документа.")) }
        func visit(_ value: Range<Int>,depth: Int,parent: (Int,Int)?) throws {
            guard nodes.count < 100000 else { throw PDFSourceError.content }
            if let ref = file.syntax.reference(value),!seen.insert(ref.0).inserted { return }
            let resolved = try file.resolve(value),raw = file.syntax.string(resolved)
            if raw.hasPrefix("[") {
                if depth >= 128 { guard try file.array(resolved).isEmpty else { throw PDFSourceError.content } }
                if let parent,let siblings = try file.structureChildren(resolved,parent: parent,minimumCount: 1) { for (index,ref) in siblings.enumerated() { movement[ref.0] = (index > 0,index+1 < siblings.count); reparentable.insert(ref.0) } }
                for child in try file.array(resolved) { try visit(child,depth: depth,parent: parent) }; return
            }
            guard raw.hasPrefix("<<") else { return }
            guard depth < 128 else { throw PDFSourceError.content }
            let dict = try file.dictionary(resolved),role = file.name(dict["S"])
            if !role.isEmpty {
                let ref = file.syntax.reference(value),alt = try file.text(dict["Alt"]),actual = try file.text(dict["ActualText"])
                nodes.append(PDFStructureNode(id: nodes.count,objectID: ref?.0,generation: ref?.1 ?? 0,depth: depth,role: role,alternative: alt,actual: actual,hasActual: dict["ActualText"] != nil,title: try file.text(dict["T"]),language: try file.text(dict["Lang"]),expansion: try file.text(dict["E"]),parentObjectID: dict["P"].flatMap(file.syntax.reference)?.0,canAcceptChildren: ref.flatMap { try? file.structureChildren(dict["K"],parent: $0,minimumCount: 0) } != nil))
                if ["Figure","Formula"].contains(role),alt.isEmpty,actual.isEmpty { issues.append(label("Missing alternative text: ","Нет альтернативного описания: ")+role+" #\(nodes.count)") }
            }
            if let children = dict["K"] { try visit(children,depth: depth+1,parent: file.syntax.reference(value)) }
        }
        if let children = root["K"] { try visit(children,depth: 0,parent: file.catalog["StructTreeRoot"].flatMap(file.syntax.reference)) }
        if issues.isEmpty { issues.append(label("Basic catalog/structure checks found no issues. Full PDF/UA validation remains necessary.","Базовая проверка каталога и структуры не выявила проблем. Полная проверка PDF/UA всё равно необходима.")) }
        for index in nodes.indices { if let id = nodes[index].objectID,let can = movement[id] { nodes[index].canMoveUp = can.0; nodes[index].canMoveDown = can.1; nodes[index].canReparent = reparentable.contains(id) } }
        let rootID = file.catalog["StructTreeRoot"].flatMap(file.syntax.reference)?.0
        let roles = Dictionary(nodes.compactMap { node in node.objectID.map { ($0,node.role) } },uniquingKeysWith: { first,_ in first })
        for index in nodes.indices {
            let parentRole = nodes[index].parentObjectID == rootID ? "StructTreeRoot" : nodes[index].parentObjectID.flatMap { roles[$0] } ?? ""
            nodes[index].canWrap = nodes[index].canReparent && nodes[index].role != "Document" && ["StructTreeRoot","Document","Part","Art","Sect","Div","NonStruct"].contains(parentRole)
            let hasChildren = index+1 < nodes.count && nodes[index+1].depth > nodes[index].depth
            nodes[index].canDeleteEmpty = nodes[index].canWrap && nodes[index].canAcceptChildren && !hasChildren && !nodes[index].hasActual && nodes[index].alternative.isEmpty
        }
        var report = PDFStructureReport(language: language,marked: marked,nodes: nodes,issues: issues)
        if let ref = file.catalog["StructTreeRoot"].flatMap(file.syntax.reference) {
            report.rootObjectID = ref.0; report.rootCanAcceptChildren = try file.structureChildren(root["K"],parent: ref,minimumCount: 0) != nil
        }
        return report
    }
    static func deleteEmptyStructure(_ data: Data,node: PDFStructureNode) throws -> Data {
        var file = try CatalogFile(data)
        guard file.offsets.count <= 100000,let id = node.objectID,let offset = file.offsets[id] else { throw PDFSourceError.content }
        let report = try structure(file.data,russian: false)
        guard report.nodes.contains(where: { $0.objectID == id && $0.generation == node.generation && $0.role == node.role && $0.canDeleteEmpty }) else { throw PDFSourceError.alreadyUsed }
        let values = try file.syntax.objectDictionary(at: offset).values
        guard ["","StructElem"].contains(file.name(values["Type"])),values["ID"] == nil,values["ActualText"] == nil,values["Alt"] == nil,let parent = values["P"].flatMap(file.syntax.reference),let parentOffset = file.offsets[parent.0] else { throw PDFSourceError.content }
        if let children = values["K"] {
            let range = try file.resolve(children)
            guard file.syntax.string(range).hasPrefix("["),try file.array(range).isEmpty else { throw PDFSourceError.content }
        }
        let parentValues = try file.syntax.objectDictionary(at: parentOffset).values
        guard let kids = parentValues["K"],file.syntax.string(kids).hasPrefix("["),var siblings = try file.structureChildren(kids,parent: parent,minimumCount: 1),let index = siblings.firstIndex(where: { $0.0 == id && $0.1 == node.generation }) else { throw PDFSourceError.content }
        func referencesTarget(_ range: Range<Int>,depth: Int = 0) throws -> Bool {
            guard depth < 64 else { throw PDFSourceError.content }
            if let ref = file.syntax.reference(range) { return ref.0 == id }
            let token = file.syntax.string(range)
            if token.hasPrefix("<<") { for value in try file.dictionary(range).values { if try referencesTarget(value,depth: depth+1) { return true } } }
            else if token.hasPrefix("[") { for value in try file.array(range) { if try referencesTarget(value,depth: depth+1) { return true } } }
            return false
        }
        for (objectID,at) in file.offsets {
            if objectID == parent.0 {
                for (key,range) in parentValues where key != "K" { guard try !referencesTarget(range) else { throw PDFSourceError.content } }
            } else {
                file.syntax.cursor = at; _ = file.syntax.token(); _ = file.syntax.token(); guard file.syntax.token() == "obj" else { throw PDFSourceError.content }
                let range = try file.syntax.value(depth: 0)
                guard try !referencesTarget(range) else { throw PDFSourceError.content }
            }
        }
        siblings.remove(at: index)
        let children = Data(("["+siblings.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8)
        return try file.write([(parent.0,parent.1,file.rewrite(parentValues,excluding: ["K"],appending: ["K":children]))])
    }
    static func wrapStructure(_ data: Data,node: PDFStructureNode,title: String) throws -> Data {
        guard title.utf16.count <= 32000 else { throw PDFSourceError.content }
        var file = try CatalogFile(data)
        let report = try structure(file.data,russian: false)
        guard report.nodes.count < 100000,let id = node.objectID,report.nodes.contains(where: { $0.objectID == id && $0.generation == node.generation && $0.role == node.role && $0.canWrap }),let offset = file.offsets[id] else { throw PDFSourceError.alreadyUsed }
        guard let selectedIndex = report.nodes.firstIndex(where: { $0.objectID == id }) else { throw PDFSourceError.content }
        let selectedDepth = report.nodes[selectedIndex].depth
        let descendants = report.nodes.dropFirst(selectedIndex+1).prefix { $0.depth > selectedDepth }
        guard max(selectedDepth,descendants.map(\.depth).max() ?? selectedDepth) < 127 else { throw PDFSourceError.content }
        let child = try file.syntax.objectDictionary(at: offset).values
        guard let parent = child["P"].flatMap(file.syntax.reference),let parentOffset = file.offsets[parent.0] else { throw PDFSourceError.content }
        let parentValues = try file.syntax.objectDictionary(at: parentOffset).values
        guard var children = try file.structureChildren(parentValues["K"],parent: parent,minimumCount: 1),let index = children.firstIndex(where: { $0.0 == id && $0.1 == node.generation }) else { throw PDFSourceError.content }
        let newID = max(file.offsets.keys.max() ?? 0,file.trailer["Size"].flatMap { Int(file.syntax.string($0)) } ?? 0)+1
        children[index] = (newID,0)
        let parentBody = file.rewrite(parentValues,excluding: ["K"],appending: ["K":Data(("["+children.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8)])
        let childBody = file.rewrite(child,excluding: ["P"],appending: ["P":Data("\(newID) 0 R".utf8)])
        var container: [String:Data] = ["Type":Data("/StructElem".utf8),"S":Data("/Div".utf8),"P":Data("\(parent.0) \(parent.1) R".utf8),"K":Data("[\(id) \(node.generation) R]".utf8),"BotPlusContainer":Data("true".utf8)]
        if !title.isEmpty { container["T"] = CatalogFile.string(title) }
        return try file.write([(parent.0,parent.1,parentBody),(id,node.generation,childBody),(newID,0,file.rewrite([:],excluding: [],appending: container))])
    }
    static func reparentStructure(_ data: Data,node: PDFStructureNode,parent: PDFStructureNode?) throws -> Data {
        var file = try CatalogFile(data)
        let report = try structure(file.data,russian: false)
        guard let id = node.objectID,let selected = report.nodes.first(where: { $0.objectID == id && $0.generation == node.generation && $0.role == node.role }),selected.canReparent,
              let selectedIndex = report.nodes.firstIndex(where: { $0.id == selected.id }),let offset = file.offsets[id] else { throw PDFSourceError.alreadyUsed }
        let child = try file.syntax.objectDictionary(at: offset).values
        guard let oldParent = child["P"].flatMap(file.syntax.reference),let oldOffset = file.offsets[oldParent.0] else { throw PDFSourceError.content }
        let subtree = report.nodes.dropFirst(selectedIndex+1).prefix { $0.depth > selected.depth }
        let height = (subtree.map(\.depth).max() ?? selected.depth)-selected.depth
        let newParent: (Int,Int),newDepth: Int
        if let parent {
            guard let parentID = parent.objectID,let target = report.nodes.first(where: { $0.objectID == parentID && $0.generation == parent.generation && $0.role == parent.role }),target.canAcceptChildren else { throw PDFSourceError.content }
            let descendants = report.nodes.dropFirst(selectedIndex+1).prefix { $0.depth > selected.depth }
            guard parentID != id,!descendants.contains(where: { $0.objectID == parentID }) else { throw PDFSourceError.content }
            newParent = (parentID,parent.generation); newDepth = target.depth+1
        } else {
            guard report.rootCanAcceptChildren,let root = file.catalog["StructTreeRoot"].flatMap(file.syntax.reference) else { throw PDFSourceError.content }; newParent = root; newDepth = 0
        }
        guard newDepth+height < 128 else { throw PDFSourceError.content }
        guard newParent.0 != oldParent.0,let newOffset = file.offsets[newParent.0] else { throw PDFSourceError.content }
        let oldValues = try file.syntax.objectDictionary(at: oldOffset).values,newValues = try file.syntax.objectDictionary(at: newOffset).values
        guard var oldChildren = try file.structureChildren(oldValues["K"],parent: oldParent,minimumCount: 1),let index = oldChildren.firstIndex(where: { $0.0 == id && $0.1 == node.generation }),var newChildren = try file.structureChildren(newValues["K"],parent: newParent,minimumCount: 0),newChildren.count < 10000 else { throw PDFSourceError.content }
        oldChildren.remove(at: index); newChildren.append((id,node.generation))
        func array(_ refs: [(Int,Int)]) -> Data { Data(("["+refs.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8) }
        let oldBody = file.rewrite(oldValues,excluding: ["K"],appending: ["K":array(oldChildren)]),newBody = file.rewrite(newValues,excluding: ["K"],appending: ["K":array(newChildren)])
        var childExtra = ["P":Data("\(newParent.0) \(newParent.1) R".utf8)]
        if child["Pg"] == nil {
            var ancestor: (Int,Int)? = oldParent,visited = Set<Int>()
            while let ref = ancestor {
                guard visited.count < 128,visited.insert(ref.0).inserted,let at = file.offsets[ref.0] else { throw PDFSourceError.content }
                let values = try file.syntax.objectDictionary(at: at).values
                if let pg = values["Pg"] {
                    guard let page = file.syntax.reference(pg),let pageOffset = file.offsets[page.0] else { throw PDFSourceError.content }
                    let pageValues = try file.syntax.objectDictionary(at: pageOffset).values
                    guard file.name(pageValues["Type"]) == "Page" else { throw PDFSourceError.content }
                    childExtra["Pg"] = file.raw(pg); break
                }
                if file.name(values["Type"]) == "StructTreeRoot" { break }
                ancestor = values["P"].flatMap(file.syntax.reference)
            }
        }
        let childBody = file.rewrite(child,excluding: Set(childExtra.keys),appending: childExtra)
        return try file.write([(oldParent.0,oldParent.1,oldBody),(newParent.0,newParent.1,newBody),(id,node.generation,childBody)])
    }
    static func reorderStructure(_ data: Data,node: PDFStructureNode,direction: Int) throws -> Data {
        guard [-1,1].contains(direction),let id = node.objectID else { throw PDFSourceError.content }
        var file = try CatalogFile(data)
        guard try structure(file.data,russian: false).nodes.contains(where: { $0.objectID == id && $0.generation == node.generation && $0.role == node.role }),let offset = file.offsets[id] else { throw PDFSourceError.alreadyUsed }
        let child = try file.syntax.objectDictionary(at: offset).values
        guard let parent = child["P"].flatMap(file.syntax.reference),let parentOffset = file.offsets[parent.0] else { throw PDFSourceError.content }
        let container = try file.syntax.objectDictionary(at: parentOffset).values
        guard file.name(container["Type"]) == "StructTreeRoot" || !file.name(container["S"]).isEmpty else { throw PDFSourceError.content }
        guard var siblings = try file.structureChildren(container["K"],parent: parent),let index = siblings.firstIndex(where: { $0.0 == id && $0.1 == node.generation }),siblings.indices.contains(index+direction) else { throw PDFSourceError.content }
        siblings.swapAt(index,index+direction)
        let body = Data(("["+siblings.map { "\($0.0) \($0.1) R" }.joined(separator: " ")+"]").utf8)
        return try file.write([(parent.0,parent.1,file.rewrite(container,excluding: ["K"],appending: ["K":body]))])
    }
    static func setStructure(_ data: Data,language: String,node: PDFStructureNode?,alternative: String,actualText: PDFStructureTextChange = .preserve,properties: PDFStructureProperties = PDFStructureProperties()) throws -> Data {
        guard language.count <= 80,alternative.utf16.count <= 32000,language.isEmpty || language.range(of: #"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"#,options: .regularExpression) != nil else { throw PDFSourceError.content }
        guard [properties.title,properties.expansion].allSatisfy({ ($0?.utf16.count ?? 0) <= 32000 }) else { throw PDFSourceError.content }
        if let lang = properties.language { guard lang.count <= 80,lang.isEmpty || lang.range(of: #"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"#,options: .regularExpression) != nil else { throw PDFSourceError.content } }
        if !properties.isEmpty { guard node?.objectID != nil else { throw PDFSourceError.content } }
        if case .set(let text) = actualText { guard text.utf16.count <= 32000 else { throw PDFSourceError.content } }
        if case .preserve = actualText { } else { guard node?.objectID != nil else { throw PDFSourceError.content } }
        var file = try CatalogFile(data),objects: [(Int,Int,Data)] = []
        if let node,let id = node.objectID {
            guard let offset = file.offsets[id],try structure(file.data,russian: false).nodes.contains(where: { $0.objectID == id && $0.generation == node.generation && $0.role == node.role }) else { throw PDFSourceError.alreadyUsed }
            let dict = try file.syntax.objectDictionary(at: offset)
            guard file.name(dict.values["S"]) == node.role else { throw PDFSourceError.alreadyUsed }
            var excluded: Set<String> = ["Alt"],extra: [String:Data] = alternative.isEmpty ? [:] : ["Alt":CatalogFile.string(alternative)]
            switch actualText {
            case .preserve: break
            case .set(let text): excluded.insert("ActualText"); extra["ActualText"] = CatalogFile.string(text)
            case .remove: excluded.insert("ActualText")
            }
            for (key,value) in [("T",properties.title),("Lang",properties.language),("E",properties.expansion)] {
                if let value { excluded.insert(key); if !value.isEmpty { extra[key] = CatalogFile.string(value) } }
            }
            objects.append((id,node.generation,file.rewrite(dict.values,excluding: excluded,appending: extra)))
        }
        objects.append((file.root.0,file.root.1,file.rewrite(file.catalog,excluding: ["Lang"],appending: language.isEmpty ? [:] : ["Lang":CatalogFile.string(language)])))
        return try file.write(objects)
    }
}
@MainActor extension PDFDocumentExtras {
    static func bookmarkExchange(_ data: Data) throws -> [PDFBookmarkExchange] { try PDFContentNormalizer.bookmarkExchange(data) }
    static func appendBookmarkExchange(_ data: Data,records: [PDFBookmarkExchange]) throws -> Data { try PDFContentNormalizer.appendBookmarkExchange(data,records: records) }
    static func tabTraversal(_ data: Data,pageIndex: Int) throws -> (value: String,hasStructure: Bool) {
        let result = try PDFContentNormalizer.tabTraversal(data,pageIndex: pageIndex); return (result.0,result.1)
    }
    static func setTabTraversal(_ data: Data,pageIndex: Int,mode: PDFTabTraversal) throws -> Data {
        guard let output = try PDFContentNormalizer.tabTraversal(data,pageIndex: pageIndex,setting: mode).2 else { throw PDFSourceError.content }; return output
    }
    static func layerStateReport(_ data: Data) throws -> PDFLayerStateReport { try PDFContentNormalizer.layerStateReport(data) }
    static func layerOrderConfigurations(_ data: Data) throws -> [PDFLayerOrderConfiguration] { try PDFContentNormalizer.layerOrderConfigurations(data) }
    static func layerCatalogGroups(_ data: Data) throws -> [PDFLayerInfo] { try PDFContentNormalizer.layerConfiguration(data,includingOrder: false).groups }
    static func editLayerOrder(_ data: Data,entry: PDFLayerOrderConfiguration,operation: PDFLayerOrderOperation) throws -> Data { try PDFContentNormalizer.editLayerOrder(data,entry: entry,operation: operation) }
    static func setLayerRadios(_ data: Data,entry: PDFLayerStateConfiguration,radios: [[Int]]?) throws -> Data { try PDFContentNormalizer.setLayerRadios(data,entry: entry,radios: radios) }
    static func setLayerState(_ data: Data,entry: PDFLayerStateConfiguration,base: String,intents: [String],on: [Int],off: [Int],locked: [Int]? = nil) throws -> Data { try PDFContentNormalizer.setLayerState(data,entry: entry,base: base,intents: intents,on: on,off: off,locked: locked) }
    static func membershipConfiguration(_ data: Data) throws -> PDFMembershipConfiguration { try PDFContentNormalizer.membershipConfiguration(data) }
    static func bindMembershipPages(_ data: Data,entry: PDFMembershipInfo?,indices: [Int]) throws -> Data { try PDFContentNormalizer.bindMembershipPages(data,entry: entry,indices: indices) }
    static func xObjectConditionTargets(_ data: Data,pageIndex: Int) throws -> [PDFXObjectConditionTarget] { try PDFContentNormalizer.xObjectConditionTargets(data,pageIndex: pageIndex) }
    static func bindXObjectCondition(_ data: Data,target: PDFXObjectConditionTarget,entry: PDFMembershipInfo?) throws -> Data { try PDFContentNormalizer.bindXObjectCondition(data,target: target,entry: entry) }
    static func transformFormResource(_ data: Data,target: PDFXObjectConditionTarget,options: PDFFormResourceTransformOptions) throws -> Data { try PDFContentNormalizer.transformFormResource(data,target: target,options: options) }
    static func createMembership(_ data: Data,name: String,members: [Int],policy: String,expression: String?) throws -> Data { try PDFContentNormalizer.createMembership(data,name: name,members: members,policy: policy,expression: expression) }
    static func setMembership(_ data: Data,entry: PDFMembershipInfo,members: [Int],policy: String,expression: String?) throws -> Data { try PDFContentNormalizer.setMembership(data,entry: entry,members: members,policy: policy,expression: expression) }
    static func layers(_ data: Data) throws -> [PDFLayerInfo] { try PDFContentNormalizer.layers(data) }
    static func layerPresets(_ data: Data) throws -> [PDFLayerPreset] { try PDFContentNormalizer.layerPresets(data) }
    static func editLayerPreset(_ data: Data,operation: PDFLayerPresetOperation) throws -> Data { try PDFContentNormalizer.editLayerPreset(data,operation: operation) }
    static func makeLayerPresetDefault(_ data: Data,index: Int) throws -> Data { try PDFContentNormalizer.makeLayerPresetDefault(data,index: index) }
    static func layerConfiguration(_ data: Data) throws -> PDFLayerConfiguration { try PDFContentNormalizer.layerConfiguration(data) }
    static func layerExtendedUsage(_ data: Data,entry: PDFLayerInfo) throws -> PDFLayerExtendedUsage { try PDFContentNormalizer.layerExtendedUsage(data,entry: entry) }
    static func setLayerUsage(_ data: Data,entry: PDFLayerInfo,viewState: Bool?,printState: Bool?,intents: [String]? = nil,extended: PDFLayerExtendedUsage? = nil,name: String? = nil) throws -> Data { try PDFContentNormalizer.setLayerUsage(data,entry: entry,viewState: viewState,printState: printState,intents: intents,extended: extended,name: name) }
    static func repairWrittenInk(_ data: Data,originalOrigins: [Int:CGPoint]) throws -> Data { try PDFContentNormalizer.repairWrittenInk(data,originalOrigins: originalOrigins) }
    static func setLayerLocked(_ data: Data,entry: PDFLayerInfo,locked: Bool) throws -> Data { try PDFContentNormalizer.setLayerLocked(data,entry: entry,locked: locked) }
    static func setLayer(_ data: Data,entry: PDFLayerInfo,visible: Bool) throws -> Data { try PDFContentNormalizer.setLayer(data,entry: entry,visible: visible) }
    static func structure(_ data: Data,russian: Bool) throws -> PDFStructureReport { try PDFContentNormalizer.structure(data,russian: russian) }
    static func deleteEmptyStructure(_ data: Data,node: PDFStructureNode) throws -> Data { try PDFContentNormalizer.deleteEmptyStructure(data,node: node) }
    static func wrapStructure(_ data: Data,node: PDFStructureNode,title: String) throws -> Data { try PDFContentNormalizer.wrapStructure(data,node: node,title: title) }
    static func reparentStructure(_ data: Data,node: PDFStructureNode,parent: PDFStructureNode?) throws -> Data { try PDFContentNormalizer.reparentStructure(data,node: node,parent: parent) }
    static func reorderStructure(_ data: Data,node: PDFStructureNode,direction: Int) throws -> Data { try PDFContentNormalizer.reorderStructure(data,node: node,direction: direction) }
    static func setStructure(_ data: Data,language: String,node: PDFStructureNode?,alternative: String,actualText: PDFStructureTextChange = .preserve,properties: PDFStructureProperties = PDFStructureProperties()) throws -> Data { try PDFContentNormalizer.setStructure(data,language: language,node: node,alternative: alternative,actualText: actualText,properties: properties) }
}

@MainActor extension PDFContentSession {
    func pathNodes(index: Int) throws -> [PDFPathNode] {
        guard let object = object(index),let path = path(object),FPDFPageObj_GetType(object) == FPDF_PAGEOBJ_PATH else { throw PDFSourceError.content }
        var nodes: [PDFPathNode] = []
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: nodes.append(PDFPathNode(kind: .move,point: element.points[0]))
            case .addLineToPoint: nodes.append(PDFPathNode(kind: .line,point: element.points[0]))
            case .addQuadCurveToPoint: break
            case .addCurveToPoint: nodes.append(PDFPathNode(kind: .curve,point: element.points[2],control1: element.points[0],control2: element.points[1]))
            case .closeSubpath: nodes.append(PDFPathNode(kind: .close))
            @unknown default: break
            }
        }; return nodes
    }
    func reorder(index: Int,direction: Int) throws -> (Data,Int) {
        guard !used,let object = object(index) else { throw PDFSourceError.alreadyUsed }
        let count = Int(FPDFPage_CountObjects(handle.page)),target = direction == -2 ? 0 : direction == 2 ? count-1 : min(count-1,max(0,index+direction))
        guard target != index else { return (data,index) }
        used = true; handle.closeTextPage()
        guard FPDFPage_RemoveObject(handle.page,object) != 0 else { throw PDFSourceError.content }
        guard FPDFPage_InsertObjectAtIndex(handle.page,object,target) != 0 else { FPDFPageObj_Destroy(object); throw PDFSourceError.content }
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }
        return (try serialized(),target)
    }
    func replacePath(index: Int,nodes: [PDFPathNode]) throws -> Data {
        guard !used,let old = object(index),let info = info(index),info.kind == "path",nodes.count >= 2,nodes.count <= 20000,nodes.first?.kind == .move,
              FPDFPageObj_CountMarks(old) == 0,FPDFPageObj_HasTransparency(old) == 0,(!info.fillEnabled || info.fill != nil),(!info.strokeEnabled || info.stroke != nil) else { throw PDFSourceError.content }
        if let clip = FPDFPageObj_GetClipPath(old),FPDFClipPath_CountPaths(clip) > 0 { throw PDFSourceError.content }
        var matrix = Self.identity
        guard FPDFPageObj_GetMatrix(old,&matrix) != 0 else { throw PDFSourceError.content }
        let affine = CGAffineTransform(a: CGFloat(matrix.a),b: CGFloat(matrix.b),c: CGFloat(matrix.c),d: CGFloat(matrix.d),tx: CGFloat(matrix.e),ty: CGFloat(matrix.f))
        guard abs(affine.a*affine.d-affine.b*affine.c) > 1e-12 else { throw PDFSourceError.content }
        let inverse = affine.inverted()
        for node in nodes { for point in [node.point,node.control1,node.control2] { guard point.x.isFinite,point.y.isFinite,abs(point.x) < 1e6,abs(point.y) < 1e6 else { throw PDFSourceError.content } } }
        let start = nodes[0].point.applying(inverse)
        guard let object = FPDFPageObj_CreateNewPath(Float(start.x),Float(start.y)) else { throw PDFSourceError.content }
        var inserted = false; defer { if !inserted { FPDFPageObj_Destroy(object) } }
        for node in nodes.dropFirst() {
            let p = node.point.applying(inverse),a = node.control1.applying(inverse),b = node.control2.applying(inverse)
            let ok: FPDF_BOOL
            switch node.kind {
            case .move: ok = FPDFPath_MoveTo(object,Float(p.x),Float(p.y))
            case .line: ok = FPDFPath_LineTo(object,Float(p.x),Float(p.y))
            case .curve: ok = FPDFPath_BezierTo(object,Float(a.x),Float(a.y),Float(b.x),Float(b.y),Float(p.x),Float(p.y))
            case .close: ok = FPDFPath_Close(object)
            }; guard ok != 0 else { throw PDFSourceError.content }
        }
        func copyColor(_ stroke: Bool) throws {
            var r: UInt32 = 0,g: UInt32 = 0,b: UInt32 = 0,a: UInt32 = 0
            let ok = stroke ? FPDFPageObj_GetStrokeColor(old,&r,&g,&b,&a) : FPDFPageObj_GetFillColor(old,&r,&g,&b,&a)
            guard ok != 0 else { return }
            guard (stroke ? FPDFPageObj_SetStrokeColor(object,r,g,b,a) : FPDFPageObj_SetFillColor(object,r,g,b,a)) != 0 else { throw PDFSourceError.content }
        }
        try copyColor(true); try copyColor(false)
        guard FPDFPageObj_SetStrokeWidth(object,Float(info.lineWidth)) != 0,FPDFPath_SetDrawMode(object,info.fillRule,info.strokeEnabled ? 1 : 0) != 0,FPDFPageObj_SetMatrix(object,&matrix) != 0 else { throw PDFSourceError.content }
        _ = FPDFPageObj_SetLineCap(object,FPDFPageObj_GetLineCap(old)); _ = FPDFPageObj_SetLineJoin(object,FPDFPageObj_GetLineJoin(old))
        let count = FPDFPageObj_GetDashCount(old)
        if count > 0,count < 4096 {
            var dash = [Float](repeating: 0,count: Int(count)),phase: Float = 0
            guard FPDFPageObj_GetDashPhase(old,&phase) != 0,dash.withUnsafeMutableBufferPointer({ FPDFPageObj_GetDashArray(old,$0.baseAddress,Int(count)) }) != 0,
                  dash.withUnsafeBufferPointer({ FPDFPageObj_SetDashArray(object,$0.baseAddress,Int(count),phase) }) != 0 else { throw PDFSourceError.content }
        }
        used = true; handle.closeTextPage()
        guard FPDFPage_RemoveObject(handle.page,old) != 0 else { throw PDFSourceError.content }; FPDFPageObj_Destroy(old)
        guard FPDFPage_InsertObjectAtIndex(handle.page,object,index) != 0 else { throw PDFSourceError.content }; inserted = true
        guard FPDFPage_GenerateContent(handle.page) != 0 else { throw PDFSourceError.content }; return try serialized()
    }
}

@MainActor private extension PDFContentNormalizer {
    static func namedExpressions(_ data: Data) throws -> [String:String] {
        var file = try CatalogFile(data),result: [String:String] = [:],visited = Set<Int>()
        func expression(_ range: Range<Int>) throws -> String? {
            var resolved = try file.resolve(range)
            if file.syntax.string(resolved).hasPrefix("<<") { let dict = try file.dictionary(resolved); guard let d = dict["D"] else { return nil }; resolved = try file.resolve(d) }
            let values = try file.array(resolved); guard values.count >= 2 else { return nil }
            return values.dropFirst().map { file.syntax.string($0) }.joined(separator: " ")
        }
        func walk(_ range: Range<Int>,depth: Int) throws {
            guard depth < 128,result.count <= 100000 else { throw PDFSourceError.content }
            if let ref = file.syntax.reference(range),!visited.insert(ref.0).inserted { return }
            let dict = try file.dictionary(range),names = try file.array(dict["Names"])
            guard names.count%2 == 0 else { throw PDFSourceError.content }
            for i in stride(from: 0,to: names.count,by: 2) { let name = try file.text(names[i]); if let value = try expression(names[i+1]) { result[name] = value } }
            for kid in try file.array(dict["Kids"]) { try walk(kid,depth: depth+1) }
        }
        let names = try file.dictionary(file.catalog["Names"])
        if let dests = names["Dests"] { try walk(dests,depth: 0) }
        let legacy = try file.dictionary(file.catalog["Dests"])
        for (name,value) in legacy {
            var bytes: [UInt8] = [],index = 0; let raw = Array(name.utf8)
            while index < raw.count {
                if raw[index] == 35,index+2 < raw.count,let value = UInt8(String(decoding: raw[(index+1)...(index+2)],as: UTF8.self),radix: 16) { bytes.append(value); index += 3 }
                else { bytes.append(raw[index]); index += 1 }
            }
            let decoded = String(bytes: bytes,encoding: .utf8) ?? String(bytes: bytes,encoding: .windowsCP1252) ?? name
            if let value = try expression(value) { result[decoded] = value }
        }
        return result
    }
}

@MainActor extension PDFContentSession {
    func snapPoint(near point: CGPoint,tolerance: CGFloat) -> CGPoint? {
        snapCandidate(near: point,tolerance: tolerance)?.point
    }
    func snapCandidate(near point: CGPoint,tolerance: CGFloat) -> PDFEngineeringSnap? {
        guard tolerance.isFinite,tolerance > 0 else { return nil }
        _ = vectorSnapPoints
        var candidates = (snapKindsCache ?? []).filter { hypot($0.point.x-point.x,$0.point.y-point.y) <= tolerance }
        let segments = Array((snapSegmentsCache ?? []).filter { a,b in CGRect(x: min(a.x,b.x),y: min(a.y,b.y),width: abs(b.x-a.x),height: abs(b.y-a.y)).insetBy(dx: -tolerance,dy: -tolerance).contains(point) }.prefix(96))
        for i in segments.indices { for j in segments.indices where j > i {
            let a = segments[i].0,b = segments[i].1,c = segments[j].0,d = segments[j].1
            let r = CGPoint(x: b.x-a.x,y: b.y-a.y),s = CGPoint(x: d.x-c.x,y: d.y-c.y),denominator = r.x*s.y-r.y*s.x
            guard abs(denominator) > 1e-10 else { continue }
            let u = ((c.x-a.x)*r.y-(c.y-a.y)*r.x)/denominator,t = ((c.x-a.x)*s.y-(c.y-a.y)*s.x)/denominator
            guard u >= 0,u <= 1,t >= 0,t <= 1 else { continue }
            let intersection = CGPoint(x: a.x+t*r.x,y: a.y+t*r.y)
            if hypot(intersection.x-point.x,intersection.y-point.y) <= tolerance { candidates.append(PDFEngineeringSnap(point: intersection,kind: .intersection)) }
        } }
        let indexedCurves = Array((snapCurvesCache ?? []).enumerated().filter { $0.element.bounds.insetBy(dx: -tolerance,dy: -tolerance).contains(point) }.prefix(96))
        let nearbyCurves = indexedCurves.map(\.element)
        for (index,curve) in indexedCurves {
            if snapArcMidpoints[index] == nil && !snapArcMidpointMissing.contains(index) {
                if let midpoint = curve.arcMidpoint() { snapArcMidpoints[index] = midpoint } else { snapArcMidpointMissing.insert(index) }
            }
            if let midpoint = snapArcMidpoints[index],hypot(midpoint.x-point.x,midpoint.y-point.y) <= tolerance { candidates.append(PDFEngineeringSnap(point: midpoint,kind: .curveMidpoint)) }
        }
        for curve in nearbyCurves {
            for (a,b) in segments {
                for intersection in curve.intersections(from: a,to: b) where hypot(intersection.x-point.x,intersection.y-point.y) <= tolerance {
                    candidates.append(PDFEngineeringSnap(point: intersection,kind: .intersection))
                }
            }
        }
        // Bound work per pointer event on dense drawings. Existing endpoint and
        // line snaps still use the full nearby candidate lists.
        let crossingCurves = Array(nearbyCurves.prefix(32))
        let region = CGRect(x: point.x-tolerance,y: point.y-tolerance,width: 2*tolerance,height: 2*tolerance)
        for i in crossingCurves.indices { for j in crossingCurves.indices where j > i {
            for intersection in crossingCurves[i].intersections(with: crossingCurves[j],in: region) where hypot(intersection.x-point.x,intersection.y-point.y) <= tolerance {
                candidates.append(PDFEngineeringSnap(point: intersection,kind: .intersection))
            }
        } }
        if candidates.isEmpty {
            for curve in nearbyCurves {
                if let nearest = curve.nearest(to: point,tolerance: tolerance) { candidates.append(PDFEngineeringSnap(point: nearest,kind: .nearest)) }
            }
        }
        return candidates.min {
            let a = hypot($0.point.x-point.x,$0.point.y-point.y),b = hypot($1.point.x-point.x,$1.point.y-point.y)
            return abs(a-b) > 0.000001 ? a < b : $0.kind.rawValue < $1.kind.rawValue
        }
    }
}

@MainActor extension PDFSourceTextReader {
    /// Keeps one PDFium document open and yields between pages so cancellation
    /// and AppKit events can be delivered without concurrently using PDFium.
    static func enumeratePages(data: Data,visit: (Int,String,Int) -> Bool) async throws {
        _ = PDFiumRuntime.ready
        let storage = data as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { FPDF_CloseDocument(document); withExtendedLifetime(storage) {} }
        guard FPDF_GetDocPermissions(document)&(1<<4) != 0 else { throw PDFSourceError.permission }
        let count = Int(FPDF_GetPageCount(document)); guard count >= 0 else { throw PDFSourceError.document }
        for index in 0..<count {
            try Task.checkCancellation()
            let text: String = try autoreleasepool {
                guard let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
                defer { FPDF_ClosePage(page) }
                guard let text = FPDFText_LoadPage(page) else { return "" }
                defer { FPDFText_ClosePage(text) }
                let length = FPDFText_CountChars(text); guard length >= 0,length <= 20_000_000 else { throw PDFSourceError.content }
                var scalars = String.UnicodeScalarView(); scalars.reserveCapacity(Int(length))
                for position in 0..<length { if let scalar = UnicodeScalar(FPDFText_GetUnicode(text,position)),scalar.value != 0 { scalars.append(scalar) } }
                return String(scalars)
            }
            if !visit(index,text,count) { break }
            await Task.yield()
        }
    }
}

/// Structural fingerprints of source paths/images. This is not a rendering or
/// accessibility semantic tree; clipping/complex graphics are reported unknown.
@MainActor enum PDFSourceGraphicReader {
    static func pages(data: Data) async throws -> [PDFGraphicPage] {
        try Task.checkCancellation()
        guard data.count <= 512*1024*1024 else { throw PDFSourceError.content }
        _ = PDFiumRuntime.ready; let storage = data as NSData
        guard let document = FPDF_LoadMemDocument64(storage.bytes,storage.length,nil) else { throw PDFSourceError.document }
        defer { withExtendedLifetime(storage) { FPDF_CloseDocument(document) } }
        guard FPDF_GetDocPermissions(document)&(1<<4) != 0 else { throw PDFSourceError.permission }
        let count = Int(FPDF_GetPageCount(document)); guard count <= 1000 else { throw PDFSourceError.content }
        var output: [PDFGraphicPage] = [],imageBytes = 0,totalObjects = 0
        func number(_ value: CGFloat) -> String { String(format: "%.3f",locale: Locale(identifier: "en_US_POSIX"),abs(value) < 0.0005 ? 0 : Double(value)) }
        func hash(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x",$0) }.joined() }
        for index in 0..<count {
            try Task.checkCancellation(); await Task.yield()
            guard let page = FPDF_LoadPage(document,Int32(index)) else { throw PDFSourceError.page }
            defer { FPDF_ClosePage(page) }
            var report = PDFGraphicPage(),visited = 0,ancestors = Set<UInt>()
            func walk(_ object: FPDF_PAGEOBJECT,parent: CGAffineTransform,id: String,depth: Int) throws {
                try Task.checkCancellation(); visited += 1
                guard visited <= 5000,report.objects.count < 1000,totalObjects < 50000,depth < 32 else { report.truncated = true; return }
                let kind = FPDFPageObj_GetType(object)
                if kind == FPDF_PAGEOBJ_TEXT { return }
                var matrix = FS_MATRIX(a: 1,b: 0,c: 0,d: 1,e: 0,f: 0)
                guard FPDFPageObj_GetMatrix(object,&matrix) != 0 else { report.unsupported += 1; return }
                let local = CGAffineTransform(a: CGFloat(matrix.a),b: CGFloat(matrix.b),c: CGFloat(matrix.c),d: CGFloat(matrix.d),tx: CGFloat(matrix.e),ty: CGFloat(matrix.f)),transform = local.concatenating(parent)
                guard [transform.a,transform.b,transform.c,transform.d,transform.tx,transform.ty].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }) else { report.unsupported += 1; return }
                if let clip = FPDFPageObj_GetClipPath(object),FPDFClipPath_CountPaths(clip) > 0 { report.unsupported += 1; return }
                if kind == FPDF_PAGEOBJ_FORM {
                    guard ancestors.insert(UInt(bitPattern: object)).inserted else { report.unsupported += 1; return }
                    defer { ancestors.remove(UInt(bitPattern: object)) }
                    let children = Int(FPDFFormObj_CountObjects(object)); guard children >= 0,children <= 5000 else { report.truncated = true; return }
                    for child in 0..<children { if let value = FPDFFormObj_GetObject(object,UInt(child)) { try walk(value,parent: transform,id: id+"."+String(child),depth: depth+1) }; if report.truncated { break } }; return
                }
                var x0: Float = 0,y0: Float = 0,x1: Float = 0,y1: Float = 0
                guard FPDFPageObj_GetBounds(object,&x0,&y0,&x1,&y1) != 0 else { report.unsupported += 1; return }
                let bounds = CGRect(x: Double(x0),y: Double(y0),width: Double(x1-x0),height: Double(y1-y0)).applying(parent)
                guard [bounds.minX,bounds.minY,bounds.width,bounds.height].allSatisfy({ $0.isFinite && abs($0) <= 1e9 }) else { report.unsupported += 1; return }
                if kind == FPDF_PAGEOBJ_PATH {
                    let segments = Int(FPDFPath_CountSegments(object)); guard segments > 0,segments <= 4096 else { report.unsupported += 1; return }
                    var shape: [String] = [],anchor: CGPoint?
                    for segment in 0..<segments {
                        guard let value = FPDFPath_GetPathSegment(object,Int32(segment)) else { report.unsupported += 1; return }
                        var x: Float = 0,y: Float = 0; guard FPDFPathSegment_GetPoint(value,&x,&y) != 0 else { report.unsupported += 1; return }
                        let point = CGPoint(x: Double(x),y: Double(y)).applying(transform)
                        guard point.x.isFinite,point.y.isFinite,abs(point.x) <= 1e9,abs(point.y) <= 1e9 else { report.unsupported += 1; return }
                        if anchor == nil { anchor = point }
                        shape.append("\(FPDFPathSegment_GetType(value)):\(number(point.x-anchor!.x)),\(number(point.y-anchor!.y)):\(FPDFPathSegment_GetClose(value))")
                    }
                    var fillMode: Int32 = 0,stroke: Int32 = 0,width: Float = 0
                    guard FPDFPath_GetDrawMode(object,&fillMode,&stroke) != 0,FPDFPageObj_GetStrokeWidth(object,&width) != 0,width.isFinite else { report.unsupported += 1; return }
                    func color(_ fill: Bool) -> String? {
                        var r: UInt32 = 0,g: UInt32 = 0,b: UInt32 = 0,a: UInt32 = 0
                        let success = fill ? FPDFPageObj_GetFillColor(object,&r,&g,&b,&a) : FPDFPageObj_GetStrokeColor(object,&r,&g,&b,&a)
                        return success != 0 ? "\(r),\(g),\(b),\(a)" : nil
                    }
                    guard let fill = fillMode != 0 ? color(true) : "-",let line = stroke != 0 ? color(false) : "-" else { report.unsupported += 1; return }
                    let dashCount = stroke != 0 ? Int(FPDFPageObj_GetDashCount(object)) : 0; guard (0...64).contains(dashCount) else { report.unsupported += 1; return }
                    var dash = [Float](repeating: 0,count: dashCount),phase: Float = 0
                    if dashCount > 0 { guard dash.withUnsafeMutableBufferPointer({ FPDFPageObj_GetDashArray(object,$0.baseAddress,dashCount) }) != 0,FPDFPageObj_GetDashPhase(object,&phase) != 0 else { report.unsupported += 1; return } }
                    let style = "\(fillMode):\(stroke):\(fill):\(line):\(number(stroke != 0 ? CGFloat(width) : 0)):\(stroke != 0 ? FPDFPageObj_GetLineJoin(object) : 0):\(stroke != 0 ? FPDFPageObj_GetLineCap(object) : 0):\(dash.map { number(CGFloat($0)) }.joined(separator: ",")):\(number(CGFloat(phase)))"
                    report.objects.append(PDFGraphicSnapshot(id: id,kind: "path",geometry: hash(Data(shape.joined(separator: ";").utf8)),style: style,bounds: bounds)); totalObjects += 1; return
                }
                if kind == FPDF_PAGEOBJ_IMAGE {
                    var metadata = FPDF_IMAGEOBJ_METADATA()
                    guard FPDFImageObj_GetImageMetadata(object,page,&metadata) != 0,metadata.width > 0,metadata.height > 0,metadata.width <= 10000,metadata.height <= 10000,(1...3).contains(metadata.colorspace),UInt64(metadata.width)*UInt64(metadata.height)*UInt64(max(8,metadata.bits_per_pixel))/8 <= 8*1024*1024 else { report.unsupported += 1; return }
                    let length = FPDFImageObj_GetImageDataDecoded(object,nil,0)
                    guard length > 0,length <= 8*1024*1024,imageBytes+Int(length) <= 128*1024*1024 else { report.unsupported += 1; return }
                    var bytes = Data(count: Int(length))
                    guard bytes.withUnsafeMutableBytes({ FPDFImageObj_GetImageDataDecoded(object,$0.baseAddress,UInt($0.count)) }) == length else { report.unsupported += 1; return }; imageBytes += Int(length)
                    let geometry = "\(metadata.width)x\(metadata.height):\(metadata.bits_per_pixel):\(metadata.colorspace):"+hash(bytes)+":"+[transform.a,transform.b,transform.c,transform.d].map(number).joined(separator: ",")
                    report.objects.append(PDFGraphicSnapshot(id: id,kind: "image",geometry: geometry,style: "",bounds: bounds)); totalObjects += 1; return
                }
                report.unsupported += 1
            }
            let objects = Int(FPDFPage_CountObjects(page)); guard objects >= 0 else { throw PDFSourceError.content }
            for objectIndex in 0..<min(objects,5000) { if let object = FPDFPage_GetObject(page,Int32(objectIndex)) { try walk(object,parent: .identity,id: String(objectIndex),depth: 0) }; if report.truncated { break } }
            if objects > 5000 { report.truncated = true }; output.append(report)
        }
        return output
    }
}
