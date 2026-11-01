// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import AppKit
import PDFKit
import ImageIO

@MainActor struct PDFComparisonRequest: Identifiable {
    let id = UUID()
    let left: Data, right: Data, leftName: String, rightName: String, russian: Bool
}
struct PDFVisualDifference: Identifiable, Sendable {
    var id: Int
    var leftPage: Int?, rightPage: Int?
    var changedFraction: Double
    var sizeChanged: Bool
    var image: Data
    var addedLines: [String] = [], removedLines: [String] = []
    var textTruncated = false
    var graphics: PDFGraphicDifference? = nil
}
enum PDFTextComparison {
    static func normalized(_ text: String) -> String { text.precomposedStringWithCanonicalMapping.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
    static func pairs(left: [String],right: [String]) -> [(Int?,Int?)] {
        let a = left.map(normalized),b = right.map(normalized),n = a.count,m = b.count
        guard n <= 1000,m <= 1000 else { return [] }
        var scores = [Int](repeating: 0,count: (n+1)*(m+1))
        if n > 0,m > 0 {
            for i in stride(from: n-1,through: 0,by: -1) { for j in stride(from: m-1,through: 0,by: -1) {
                scores[i*(m+1)+j] = !a[i].isEmpty && a[i] == b[j] ? 1+scores[(i+1)*(m+1)+j+1] : max(scores[(i+1)*(m+1)+j],scores[i*(m+1)+j+1])
            } }
        }
        var anchors: [(Int,Int)] = [],i = 0,j = 0
        while i < n,j < m {
            if !a[i].isEmpty,a[i] == b[j] { anchors.append((i,j)); i += 1; j += 1 }
            else if scores[(i+1)*(m+1)+j] >= scores[i*(m+1)+j+1] { i += 1 } else { j += 1 }
        }
        var result: [(Int?,Int?)] = [],ai = 0,bi = 0
        for (endA,endB) in anchors+[(n,m)] {
            let count = max(endA-ai,endB-bi)
            for offset in 0..<count { result.append((ai+offset < endA ? ai+offset : nil,bi+offset < endB ? bi+offset : nil)) }
            if endA < n,endB < m { result.append((endA,endB)) }; ai = endA+1; bi = endB+1
        }
        return result
    }
    static func changes(left: String,right: String) -> (added: [String],removed: [String],truncated: Bool) {
        let a = left.components(separatedBy: .newlines).map(normalized).filter { !$0.isEmpty },b = right.components(separatedBy: .newlines).map(normalized).filter { !$0.isEmpty }
        guard a != b else { return ([],[],false) }
        guard a.count <= 2000,b.count <= 2000,a.count*b.count <= 1_000_000 else { return (Array(b.prefix(200)),Array(a.prefix(200)),true) }
        var added: [(Int,String)] = [],removed: [(Int,String)] = []
        for change in b.difference(from: a) { switch change { case .insert(let at,let line,_): added.append((at,line)); case .remove(let at,let line,_): removed.append((at,line)) } }
        return (added.sorted { $0.0 < $1.0 }.map(\.1),removed.sorted { $0.0 < $1.0 }.map(\.1),false)
    }
    static func html(rows: [PDFVisualDifference],leftName: String,rightName: String) -> String {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: ">",with: "&gt;").replacingOccurrences(of: "\"",with: "&quot;") }
        let sections = rows.map { row in
            let pages = "\(row.leftPage.map { String($0+1) } ?? "—") ↔ \(row.rightPage.map { String($0+1) } ?? "—")"
            let deleted = row.removedLines.map { "<li>"+escape($0)+"</li>" }.joined(),added = row.addedLines.map { "<li>"+escape($0)+"</li>" }.joined()
            let graphics: String
            if let value = row.graphics {
                let items = value.changes.map { "<li>"+escape($0.description)+"</li>" }.joined()
                graphics = "<h3>Source graphics / Исходная графика</h3><p>Unchanged: \(value.unchanged) · Unsupported left/right: \(value.unsupportedLeft)/\(value.unsupportedRight) · Incomplete: \(value.truncated)</p><ul>"+items+"</ul>"
            } else { graphics = "" }
            return "<section><h2>"+pages+"</h2><p>Changed pixels: \(row.changedFraction*100)% · Size changed: \(row.sizeChanged)</p>"+(row.textTruncated ? "<p>Text listing truncated</p>" : "")+"<div class=columns><div><h3>Removed / Удалено</h3><ul>"+deleted+"</ul></div><div><h3>Added / Добавлено</h3><ul>"+added+"</ul></div></div>"+graphics+"<img alt='Visual differences' src='data:image/png;base64,"+row.image.base64EncodedString()+"'></section>"
        }.joined()
        return "<!doctype html><meta charset=utf-8><title>PDF comparison</title><style>body{font:16px system-ui;max-width:1100px;margin:40px auto;padding:20px}section{border-top:1px solid #ccc;padding:20px 0;break-inside:avoid}img{max-width:100%;max-height:800px}.columns{display:grid;grid-template-columns:1fr 1fr;gap:30px}li{white-space:pre-wrap;overflow-wrap:anywhere}</style><h1>"+escape(leftName)+" ↔ "+escape(rightName)+"</h1><p>Visual differences at preview resolution and existing text-layer changes. No OCR. Optional structural source-graphics analysis does not fully interpret clipping, masks, ICC, blend states, visibility or drawing order.</p>"+sections
    }
}
enum PDFVisualComparison {
    // This is a pixel comparison of ordered page pairs, not semantic change tracking.
    static func compare(left: Data,right: Data,offset: Int,tolerance: Int,leftText: [String] = [],rightText: [String] = [],alignText: Bool = false,leftGraphics: [PDFGraphicPage] = [],rightGraphics: [PDFGraphicPage] = [],progress: @Sendable (Double) -> Void) throws -> [PDFVisualDifference] {
        guard let a = PDFDocument(data: left),let b = PDFDocument(data: right),!a.isLocked,!b.isLocked,abs(offset) <= 500 else { throw PDFSourceError.document }
        let first = min(0,-offset),last = max(a.pageCount,b.pageCount-offset)
        guard last-first > 0,last-first <= 1000 else { throw PDFSourceError.content }
        let pairs: [(Int?,Int?)] = alignText && leftText.count == a.pageCount && rightText.count == b.pageCount ? PDFTextComparison.pairs(left: leftText,right: rightText) : (first..<last).map { position in
            ((0..<a.pageCount).contains(position) ? position : nil,(0..<b.pageCount).contains(position+offset) ? position+offset : nil)
        }
        var output: [PDFVisualDifference] = [], byteCount = 0
        for (position,pair) in pairs.enumerated() {
            try Task.checkCancellation()
            let row: PDFVisualDifference = try autoreleasepool {
                let ai = pair.0,bi = pair.1
                let pageA = ai.flatMap { a.page(at: $0) },pageB = bi.flatMap { b.page(at: $0) }
                func size(_ page: PDFPage?) -> CGSize {
                    guard let page else { return .zero }; let box = page.bounds(for: .cropBox)
                    return page.rotation%180 == 0 ? box.size : CGSize(width: box.height,height: box.width)
                }
                let sa = size(pageA),sb = size(pageB),canvas = CGSize(width: max(1,sa.width,sb.width),height: max(1,sa.height,sb.height))
                let scale = min(1,1000/max(canvas.width,canvas.height)),width = max(1,Int(ceil(canvas.width*scale))),height = max(1,Int(ceil(canvas.height*scale)))
                func pixels(_ page: PDFPage?,_ size: CGSize) throws -> [UInt8] {
                    var bytes = [UInt8](repeating: 255,count: width*height*4)
                    try bytes.withUnsafeMutableBytes { storage in
                        guard let context = CGContext(data: storage.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PDFSourceError.content }
                        if let page {
                            let target = CGRect(x: 0,y: CGFloat(height)-size.height*scale,width: size.width*scale,height: size.height*scale)
                            context.saveGState(); context.concatenate(PDFFormattingGeometry.transform(page,box: .cropBox,target: target))
                            if let ref = page.pageRef { context.drawPDFPage(ref) }
                            for annotation in page.annotations where annotation.shouldDisplay && !(annotation.contents ?? "").hasPrefix("BotPlus PDF Editor metadata v1:") { annotation.draw(with: .cropBox,in: context) }
                            context.restoreGState()
                        }
                    }
                    return bytes
                }
                let pa = try pixels(pageA,sa),pb = try pixels(pageB,sb)
                var result = pa,changed = 0
                for pixel in stride(from: 0,to: pa.count,by: 4) {
                    let difference = max(abs(Int(pa[pixel])-Int(pb[pixel])),abs(Int(pa[pixel+1])-Int(pb[pixel+1])),abs(Int(pa[pixel+2])-Int(pb[pixel+2])))
                    if difference > max(0,min(255,tolerance)) {
                        changed += 1; result[pixel] = 230; result[pixel+1] = 30; result[pixel+2] = 70
                    } else {
                        let gray = UInt8((Int(pa[pixel])+Int(pa[pixel+1])+Int(pa[pixel+2]))/3)
                        result[pixel] = gray; result[pixel+1] = gray; result[pixel+2] = gray
                    }
                    result[pixel+3] = 255
                }
                let png = try result.withUnsafeMutableBytes { storage -> Data in
                    guard let context = CGContext(data: storage.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),let image = context.makeImage() else { throw PDFSourceError.content }
                    let data = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(data,"public.png" as CFString,1,nil) else { throw PDFSourceError.content }
                    CGImageDestinationAddImage(destination,image,nil)
                    guard CGImageDestinationFinalize(destination) else { throw PDFSourceError.content }; return data as Data
                }
                byteCount += png.count; guard byteCount <= 128*1024*1024 else { throw PDFSourceError.content }
                let textA = ai.flatMap { leftText.indices.contains($0) ? leftText[$0] : nil } ?? "",textB = bi.flatMap { rightText.indices.contains($0) ? rightText[$0] : nil } ?? ""
                let changes = PDFTextComparison.changes(left: textA,right: textB)
                let graphics: PDFGraphicDifference?
                if leftGraphics.count == a.pageCount && rightGraphics.count == b.pageCount {
                    graphics = try PDFGraphicComparison.compare(left: ai.map { leftGraphics[$0] } ?? PDFGraphicPage(),right: bi.map { rightGraphics[$0] } ?? PDFGraphicPage())
                } else { graphics = nil }
                return PDFVisualDifference(id: position,leftPage: ai,rightPage: bi,changedFraction: Double(changed)/Double(width*height),sizeChanged: abs(sa.width-sb.width)>0.1 || abs(sa.height-sb.height)>0.1,image: png,addedLines: changes.added,removedLines: changes.removed,textTruncated: changes.truncated,graphics: graphics)
            }
            output.append(row); progress(Double(position+1)/Double(pairs.count))
        }
        return output
    }
}
@MainActor final class PDFComparisonScrollLink: ObservableObject {
    private var clips: [Int:NSClipView] = [:],tokens: [Int:NSObjectProtocol] = [:]
    private var syncing = false
    func connect(_ view: PDFView,side: Int) {
        guard let clip = view.documentView?.enclosingScrollView?.contentView,clips[side] !== clip else { return }
        disconnect(side)
        clips[side] = clip; clip.postsBoundsChangedNotifications = true
        tokens[side] = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,object: clip,queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.synchronize(side) }
        }
    }
    func disconnect(_ side: Int) { if let token = tokens.removeValue(forKey: side) { NotificationCenter.default.removeObserver(token) }; clips.removeValue(forKey: side) }
    private func synchronize(_ side: Int) {
        guard !syncing,let source = clips[side],let target = clips[1-side] else { return }
        let a = source.documentRect,b = target.documentRect
        let nx = max(0,min(1,(source.bounds.minX-a.minX)/max(1,a.width-source.bounds.width)))
        var ny = max(0,min(1,(source.bounds.minY-a.minY)/max(1,a.height-source.bounds.height)))
        if source.isFlipped != target.isFlipped { ny = 1-ny }
        let point = CGPoint(x: b.minX+nx*max(0,b.width-target.bounds.width),y: b.minY+ny*max(0,b.height-target.bounds.height))
        guard hypot(point.x-target.bounds.minX,point.y-target.bounds.minY) > 0.5 else { return }
        syncing = true; defer { syncing = false }
        target.scroll(to: point); target.enclosingScrollView?.reflectScrolledClipView(target)
    }
}
@MainActor final class PDFComparisonModel: ObservableObject {
    @Published var rows: [PDFVisualDifference] = []
    @Published var progress: Double?
    @Published var error: String?
    var task: Task<Void,Never>?
    func run(_ request: PDFComparisonRequest,offset: Int,tolerance: Int,alignText: Bool,graphics: Bool = false) {
        guard task == nil else { return }; progress = 0; rows = []; error = nil
        let left = request.left,right = request.right
        task = Task { [weak self] in
            defer { self?.task = nil; self?.progress = nil }
            do {
                let progressOwner = self
                let leftText = try PDFSourceTextReader.pages(data: left),rightText = try PDFSourceTextReader.pages(data: right)
                let leftGraphics: [PDFGraphicPage],rightGraphics: [PDFGraphicPage]
                if graphics { leftGraphics = try await PDFSourceGraphicReader.pages(data: left); rightGraphics = try await PDFSourceGraphicReader.pages(data: right) }
                else { leftGraphics = []; rightGraphics = [] }
                let worker = Task.detached(priority: .userInitiated) {
                    try PDFVisualComparison.compare(left: left,right: right,offset: offset,tolerance: tolerance,leftText: leftText,rightText: rightText,alignText: alignText,leftGraphics: leftGraphics,rightGraphics: rightGraphics) { value in
                        Task { @MainActor in progressOwner?.progress = value }
                    }
                }
                let rows = try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
                try Task.checkCancellation(); self?.rows = rows
            } catch is CancellationError {} catch { self?.error = error.localizedDescription }
        }
    }
    func cancel() { task?.cancel() }
}
struct PDFComparisonPanel: View {
    let request: PDFComparisonRequest
    @StateObject private var model = PDFComparisonModel()
    @StateObject private var scrollLink = PDFComparisonScrollLink()
    @Environment(\.dismiss) private var dismiss
    @State private var offset = 0
    @State private var tolerance = 20
    @State private var mode = 0
    @State private var selection: Int? = 0
    @State private var changedOnly = false
    @State private var alignText = false
    @State private var compareGraphics = false
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var visible: [PDFVisualDifference] { model.rows.filter { !changedOnly || $0.changedFraction > 0 || $0.sizeChanged || !$0.addedLines.isEmpty || !$0.removedLines.isEmpty || $0.graphics?.changes.isEmpty == false || $0.graphics?.truncated == true || ($0.graphics?.unsupportedLeft ?? 0) > 0 || ($0.graphics?.unsupportedRight ?? 0) > 0 || $0.leftPage == nil || $0.rightPage == nil } }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("PDF comparison","Сравнение PDF")).font(.title2)
            Text(request.leftName+" ↔ "+request.rightName).lineLimit(1)
            Text(label("Red pixels show preview-resolution changes. Optional text anchors match unchanged text pages and reveal inserted/deleted pages; ambiguous scans or substantially changed pages need manual pairing. Text changes use the existing text layer without OCR.","Красным показаны изменения на разрешении предпросмотра. Текстовые якоря сопоставляют неизменённые текстовые страницы и выявляют вставки/удаления; сканы и существенно изменённые страницы требуют ручной проверки. Текст сравнивается по существующему слою, без OCR.")).font(.caption).foregroundStyle(.secondary)
            Toggle(label("Match pages by unchanged text","Сопоставить страницы по совпадающему тексту"),isOn: $alignText)
            Toggle(label("Compare source paths and image data","Сравнить исходные контуры и данные изображений"),isOn: $compareGraphics)
            if compareGraphics { Text(label("Structural fingerprints, not full graphic semantics. Includes source objects regardless of visibility; clipping, masks, blend/group states, ICC and drawing order are not fully interpreted. Unsupported objects and limits are reported.","Структурные признаки, не полная семантика графики. Учитываются исходные объекты независимо от видимости; clipping, маски, смешивание/групповые состояния, ICC и порядок наложения интерпретируются не полностью. Неподдерживаемые объекты и ограничения отмечаются.")).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Stepper(label("Right page offset: \(offset)","Смещение справа: \(offset)"),value: $offset,in: -500...500).disabled(alignText)
                Stepper(label("Tolerance: \(tolerance)","Допуск: \(tolerance)"),value: $tolerance,in: 0...100)
                Button(label("Compare","Сравнить")) { selection = 0; model.run(request,offset: offset,tolerance: tolerance,alignText: alignText,graphics: compareGraphics) }.disabled(model.progress != nil)
                Toggle(label("Only changed","Только изменения"),isOn: $changedOnly)
            }
            if let progress = model.progress { HStack { ProgressView(value: progress); Button(label("Cancel","Отмена")) { model.cancel() } } }
            HStack(spacing: 12) {
                List(visible,selection: $selection) { row in
                    VStack(alignment: .leading) {
                        Text("\(row.leftPage.map { String($0+1) } ?? "—") ↔ \(row.rightPage.map { String($0+1) } ?? "—")")
                        Text(String(format: "%.2f%%",row.changedFraction*100)+(row.sizeChanged ? " · Δ size" : "")).font(.caption).foregroundStyle(row.changedFraction > 0 ? .orange : .secondary)
                    }.tag(row.id)
                }.frame(width: 150)
                VStack {
                    Picker(label("Preview","Предпросмотр"),selection: $mode) { Text(label("Differences","Различия")).tag(0); Text(label("Original pages","Исходные страницы")).tag(1); Text(label("Text changes","Изменения текста")).tag(2); Text(label("Source graphics","Исходная графика")).tag(3) }.pickerStyle(.segmented)
                    if let row = model.rows.first(where: { $0.id == selection }) {
                        if mode == 0,let image = NSImage(data: row.image) { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity,maxHeight: .infinity) }
                        else if mode == 1 { HStack { ComparisonPDFPreview(data: request.left,index: row.leftPage,scrollLink: scrollLink,side: 0); ComparisonPDFPreview(data: request.right,index: row.rightPage,scrollLink: scrollLink,side: 1) } }
                        else if mode == 3 { ScrollView { VStack(alignment: .leading,spacing: 8) {
                            if let graphics = row.graphics {
                                Text(label("Unchanged objects: ","Без изменений: ")+String(graphics.unchanged))
                                Text(label("Unsupported left/right: ","Не разобрано слева/справа: ")+"\(graphics.unsupportedLeft) / \(graphics.unsupportedRight)").font(.caption)
                                if graphics.truncated { Text(label("Object limits reached; listing is incomplete.","Достигнуты ограничения объектов; список неполный.")).foregroundStyle(.orange) }
                                if graphics.changes.isEmpty { Text(label("No differences in compared source properties","Различий в сравниваемых свойствах объектов нет")) }
                                ForEach(graphics.changes) { change in Text(change.description).font(.system(.caption,design: .monospaced)).textSelection(.enabled) }
                            } else { Text(label("Enable source graphics and run comparison.","Включите исходную графику и запустите сравнение.")) }
                        }.frame(maxWidth: .infinity,alignment: .leading) } }
                        else { ScrollView { VStack(alignment: .leading,spacing: 10) {
                            if row.textTruncated { Text(label("Large text listing truncated","Большой список текстовых изменений сокращён")).foregroundStyle(.orange) }
                            if row.addedLines.isEmpty && row.removedLines.isEmpty { Text(label("No text-layer changes","Изменений текстового слоя нет")) }
                            ForEach(Array(row.removedLines.enumerated()),id: \.offset) { _,text in Text("− "+text).foregroundStyle(.red).textSelection(.enabled) }
                            ForEach(Array(row.addedLines.enumerated()),id: \.offset) { _,text in Text("+ "+text).foregroundStyle(.green).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity,alignment: .leading) } }
                    } else { Spacer(); Text(label("Run comparison to see results.","Запустите сравнение для просмотра результатов.")); Spacer() }
                }
            }.frame(height: 450)
            if let error = model.error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button(label("Export report…","Экспорт отчёта…")) { exportReport() }.disabled(model.rows.isEmpty)
                Button(label("HTML report…","HTML-отчёт…")) { exportHTML() }.disabled(model.rows.isEmpty)
                Spacer(); Button(label("Done","Готово")) { model.cancel(); dismiss() }
            }
        }.padding(24).frame(width: 1040).onDisappear { model.cancel() }
    }
    private func exportReport() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Comparison.csv"
        panel.begin { response in
            guard response == .OK,let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let csv = "left_page,right_page,changed_percent,size_changed,graphic_changes,graphic_unchanged,unsupported_left,unsupported_right,graphics_truncated\n"+model.rows.map { row in
                let graphics = row.graphics
                return "\(row.leftPage.map { String($0+1) } ?? ""),\(row.rightPage.map { String($0+1) } ?? ""),\(String(format: "%.6f",locale: Locale(identifier: "en_US_POSIX"),row.changedFraction*100)),\(row.sizeChanged),\(graphics.map { String($0.changes.count) } ?? ""),\(graphics.map { String($0.unchanged) } ?? ""),\(graphics.map { String($0.unsupportedLeft) } ?? ""),\(graphics.map { String($0.unsupportedRight) } ?? ""),\(graphics.map { String($0.truncated) } ?? "")"
            }.joined(separator: "\n")
            do { try csv.write(to: url,atomically: true,encoding: .utf8) } catch { model.error = error.localizedDescription }
        }
    }
    private func exportHTML() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Comparison.html"
        let report = PDFTextComparison.html(rows: model.rows,leftName: request.leftName,rightName: request.rightName)
        panel.begin { response in
            guard response == .OK,let url = panel.url else { return }
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { try report.write(to: url,atomically: true,encoding: .utf8) } catch { model.error = error.localizedDescription }
        }
    }
}
struct ComparisonPDFPreview: NSViewRepresentable {
    let data: Data, index: Int?
    var scrollLink: PDFComparisonScrollLink? = nil
    var side = 0
    func makeNSView(context: Context) -> PDFView { let view = PDFView(); view.displaysPageBreaks = false; view.displayMode = .singlePage; view.enableDataDetectors = false; return view }
    func updateNSView(_ view: PDFView,context: Context) {
        if context.coordinator.data != data { view.document = PDFDocument(data: data); context.coordinator.data = data }
        view.isHidden = index == nil
        if let index,let page = view.document?.page(at: index),view.currentPage !== page { view.go(to: page); view.autoScales = true }
        context.coordinator.link = scrollLink; context.coordinator.side = side; scrollLink?.connect(view,side: side)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    static func dismantleNSView(_ view: PDFView,coordinator: Coordinator) { coordinator.link?.disconnect(coordinator.side) }
    @MainActor final class Coordinator { var data: Data?; var link: PDFComparisonScrollLink?; var side = 0 }
}

struct PDFGraphicSnapshot: Sendable {
    let id: String,kind: String,geometry: String,style: String,bounds: CGRect
}
struct PDFGraphicPage: Sendable {
    var objects: [PDFGraphicSnapshot] = []
    var unsupported = 0
    var truncated = false
}
struct PDFGraphicChange: Identifiable, Sendable {
    let id: Int,kind: String,objectKind: String,left: String?,right: String?
    var description: String { kind+" · "+objectKind+" · "+(left ?? "—")+" → "+(right ?? "—") }
}
struct PDFGraphicDifference: Sendable {
    var changes: [PDFGraphicChange] = []
    var unchanged = 0
    var unsupportedLeft = 0
    var unsupportedRight = 0
    var truncated = false
}
enum PDFGraphicComparison {
    static func compare(left: PDFGraphicPage,right: PDFGraphicPage) throws -> PDFGraphicDifference {
        var result = PDFGraphicDifference(unsupportedLeft: left.unsupported,unsupportedRight: right.unsupported,truncated: left.truncated || right.truncated)
        var unusedA = Set(left.objects.indices),unusedB = Set(right.objects.indices)
        func number(_ x: CGFloat) -> String { String(format: "%.2f",locale: Locale(identifier: "en_US_POSIX"),abs(x) < 0.005 ? 0 : Double(x)) }
        func position(_ value: PDFGraphicSnapshot) -> String { [value.bounds.minX,value.bounds.minY,value.bounds.width,value.bounds.height].map(number).joined(separator: ",") }
        let positionsA = left.objects.map(position),positionsB = right.objects.map(position)
        func identity(_ value: PDFGraphicSnapshot,_ position: String) -> String { value.kind+":"+value.geometry+":"+value.style+":"+position }
        var exact: [String:[Int]] = [:]
        for index in right.objects.indices { exact[identity(right.objects[index],positionsB[index]),default: []].append(index) }
        for index in left.objects.indices {
            try Task.checkCancellation()
            let key = identity(left.objects[index],positionsA[index])
            if let other = exact[key]?.popLast() { unusedA.remove(index); unusedB.remove(other); result.unchanged += 1 }
        }
        func add(_ kind: String,_ a: Int?,_ b: Int?) {
            result.changes.append(PDFGraphicChange(id: result.changes.count,kind: kind,objectKind: a.map { left.objects[$0].kind } ?? b.map { right.objects[$0].kind } ?? "",left: a.map { left.objects[$0].id },right: b.map { right.objects[$0].id }))
            if let a { unusedA.remove(a) }; if let b { unusedB.remove(b) }
        }
        for index in unusedA.sorted() {
            try Task.checkCancellation(); let a = left.objects[index]
            let candidates = unusedB.filter { right.objects[$0].kind == a.kind && right.objects[$0].geometry == a.geometry }
            if let match = candidates.min(by: {
                let b = right.objects[$0].bounds,c = right.objects[$1].bounds
                let db = hypot(b.midX-a.bounds.midX,b.midY-a.bounds.midY),dc = hypot(c.midX-a.bounds.midX,c.midY-a.bounds.midY)
                return db == dc ? $0 < $1 : db < dc
            }) {
                let b = right.objects[match],moved = positionsA[index] != positionsB[match],styled = a.style != b.style
                add(moved ? (styled ? "moved + style" : "moved") : "style",index,match)
            }
        }
        // A replacement at the same bounds is paired only when unambiguous on
        // both sides. Overlapping duplicates remain additions/removals.
        for index in unusedA.sorted() {
            try Task.checkCancellation()
            let a = left.objects[index],key = positionsA[index]
            let candidates = unusedB.filter { right.objects[$0].kind == a.kind && positionsB[$0] == key }
            if candidates.count == 1,unusedA.filter({ left.objects[$0].kind == a.kind && positionsA[$0] == key }).count == 1 { add("modified",index,candidates.first) }
        }
        for index in unusedA.sorted() { add("removed",index,nil) }
        for index in unusedB.sorted() { add("added",nil,index) }
        return result
    }
}
