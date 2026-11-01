// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import CoreText

struct PDFTOCOptions: Equatable {
    var title = "СОДЕРЖАНИЕ", range = "all", numberPrefix = ""
    var columns = 1, paper = 0, font = 0, leaders = 0, numbering = 0, numberOffset = 0, maximumLevel = 9
    var fontSize = 11.0, marginMM = 18.0
    var landscape = false
}
struct PDFTOCEntry {
    let title: String, depth: Int, page: PDFPage, point: CGPoint, sourceIndex: Int, logicalLabel: String
}
struct PDFTOCLink { let pageIndex: Int, bounds: CGRect, target: PDFTOCEntry }
struct PDFTOCResult { let data: Data, pageCount: Int, entryCount: Int, links: [PDFTOCLink] }
enum PDFTOCError: LocalizedError {
    case options, empty, layout
    var errorDescription: String? {
        switch self {
        case .options: return "Проверьте диапазон, поля и размер шрифта / Check page range, margins and font size"
        case .empty: return "Нет закладок с подходящими локальными целями / No bookmarks with matching local targets"
        case .layout: return "Не удалось разместить содержание. Измените параметры / Could not lay out the table of contents. Adjust options"
        }
    }
}
@MainActor enum PDFTOCRenderer {
    static func entries(document: PDFDocument,options: PDFTOCOptions) throws -> [PDFTOCEntry] {
        guard let indices = PDFPageRange.parse(options.range,count: document.pageCount) else { throw PDFTOCError.options }
        let pages = Set(indices)
        var rows: [PDFTOCEntry] = []
        func visit(_ node: PDFOutline,depth: Int) {
            guard depth < min(64,options.maximumLevel) else { return }
            for index in 0..<node.numberOfChildren {
                guard let child = node.child(at: index) else { continue }
                if let destination = child.destination ?? (child.action as? PDFActionGoTo)?.destination,let page = destination.page {
                    let at = document.index(for: page)
                    if pages.contains(at) { rows.append(PDFTOCEntry(title: child.label ?? "",depth: depth,page: page,point: destination.point,sourceIndex: at,logicalLabel: page.label ?? String(at+1))) }
                }
                visit(child,depth: depth+1)
            }
        }
        if let root = document.outlineRoot { visit(root,depth: 0) }
        guard !rows.isEmpty else { throw PDFTOCError.empty }
        return rows
    }
    static func render(entries: [PDFTOCEntry],options: PDFTOCOptions) throws -> PDFTOCResult {
        guard (1...3).contains(options.columns),(0...1).contains(options.paper),(0...2).contains(options.font),
              (0...2).contains(options.leaders),(0...1).contains(options.numbering),(1...9).contains(options.maximumLevel),
              options.fontSize.isFinite,(8...22).contains(options.fontSize),options.marginMM.isFinite,(5...60).contains(options.marginMM),
              (-100000...100000).contains(options.numberOffset),options.title.utf16.count <= 300,options.numberPrefix.utf16.count <= 100 else { throw PDFTOCError.options }
        guard !entries.isEmpty else { throw PDFTOCError.empty }
        guard entries.count <= 20000 else { throw PDFTOCError.layout }
        var size = options.paper == 0 ? CGSize(width: 595.276,height: 841.89) : CGSize(width: 612,height: 792)
        if options.landscape { size = CGSize(width: size.height,height: size.width) }
        let margin = options.marginMM*72/25.4,gap = 18.0,header = 42.0
        let width = (size.width-2*margin-Double(options.columns-1)*gap)/Double(options.columns)
        let top = size.height-margin-header,bottom = margin+20
        guard width >= 90,top-bottom >= 100 else { throw PDFTOCError.options }
        func font(_ depth: Int) -> NSFont {
            let pointSize = options.fontSize*(depth == 0 ? 1.08 : 1)
            if options.font == 1 { return NSFont(name: depth == 0 ? "TimesNewRomanPS-BoldMT" : "TimesNewRomanPSMT",size: pointSize) ?? .systemFont(ofSize: pointSize) }
            if options.font == 2 { return .monospacedSystemFont(ofSize: pointSize,weight: depth == 0 ? .semibold : .regular) }
            return .systemFont(ofSize: pointSize,weight: depth == 0 ? .semibold : .regular)
        }
        struct Fragment { let entry: PDFTOCEntry, page: Int, x: Double, y: Double, lines: [CTLine], lineHeight: Double, final: Bool, width: Double, numberWidth: Double }
        var fragments: [Fragment] = [],pageIndex = 0,column = 0,y = top
        func nextColumn() { column += 1; if column == options.columns { column = 0; pageIndex += 1 }; y = top }
        for entry in entries {
            let rowFont = font(entry.depth),lineHeight = ceil(rowFont.ascender-rowFont.descender+rowFont.leading+3)
            let indent = min(width*0.25,Double(entry.depth)*10),numberWidth = min(65,width*0.3)
            let textWidth = width-indent-numberWidth-8
            guard textWidth >= 20,entry.title.utf16.count <= 20000 else { throw PDFTOCError.layout }
            let title = entry.title.isEmpty ? "—" : entry.title.replacingOccurrences(of: "\n",with: " ")
            let attributed = NSAttributedString(string: title,attributes: [.font: rowFont,.foregroundColor: NSColor.black])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed as CFAttributedString)
            var lines: [CTLine] = [],offset = 0
            while offset < attributed.length {
                let length = CTTypesetterSuggestLineBreak(typesetter,offset,textWidth)
                guard length > 0 else { throw PDFTOCError.layout }
                lines.append(CTTypesetterCreateLine(typesetter,CFRange(location: offset,length: length))); offset += length
            }
            var consumed = 0
            while consumed < lines.count {
                if y-lineHeight < bottom { nextColumn() }
                let capacity = Int(floor((y-bottom)/lineHeight)),count = min(capacity,lines.count-consumed)
                guard count > 0,pageIndex < 2000 else { throw PDFTOCError.layout }
                let subset = Array(lines[consumed..<(consumed+count)])
                let final = consumed+count == lines.count
                fragments.append(Fragment(entry: entry,page: pageIndex,x: margin+Double(column)*(width+gap)+indent,y: y,lines: subset,lineHeight: lineHeight,final: final,width: width-indent,numberWidth: numberWidth))
                y -= Double(count)*lineHeight; consumed += count
                if !final { nextColumn() } else { y -= 6 }
            }
        }
        let count = pageIndex+1,data = NSMutableData()
        var box = CGRect(origin: .zero,size: size)
        guard let consumer = CGDataConsumer(data: data),let context = CGContext(consumer: consumer,mediaBox: &box,nil) else { throw PDFTOCError.layout }
        var links: [PDFTOCLink] = []
        func draw(_ line: CTLine,x: Double,y: Double,maxWidth: Double) {
            let measured = CTLineGetTypographicBounds(line,nil,nil,nil)
            context.saveGState(); context.translateBy(x: x,y: y)
            if measured > maxWidth { context.scaleBy(x: maxWidth/measured,y: 1) }
            context.textMatrix = .identity; context.textPosition = .zero; CTLineDraw(line,context); context.restoreGState()
        }
        for page in 0..<count {
            context.beginPDFPage(nil); context.setFillColor(NSColor.white.cgColor); context.fill(box)
            let heading = CTLineCreateWithAttributedString(NSAttributedString(string: options.title,attributes: [.font: NSFont.boldSystemFont(ofSize: 20),.foregroundColor: NSColor.black]) as CFAttributedString)
            draw(heading,x: margin,y: size.height-margin-22,maxWidth: size.width-2*margin)
            for fragment in fragments where fragment.page == page {
                var baseline = fragment.y-fragment.lineHeight+4
                for line in fragment.lines { draw(line,x: fragment.x,y: baseline,maxWidth: fragment.width-fragment.numberWidth-8); baseline -= fragment.lineHeight }
                let lastBaseline = baseline+fragment.lineHeight
                if fragment.final {
                    let label = options.numbering == 1 ? fragment.entry.logicalLabel : String(fragment.entry.sourceIndex+count+1+options.numberOffset)
                    let number = CTLineCreateWithAttributedString(NSAttributedString(string: options.numberPrefix+label,attributes: [.font: font(fragment.entry.depth),.foregroundColor: NSColor.black]) as CFAttributedString)
                    let measured = min(fragment.numberWidth,CTLineGetTypographicBounds(number,nil,nil,nil))
                    let numberX = fragment.x+fragment.width-measured
                    draw(number,x: numberX,y: lastBaseline,maxWidth: fragment.numberWidth)
                    if let last = fragment.lines.last,options.leaders != 2 {
                        let start = fragment.x+CTLineGetTypographicBounds(last,nil,nil,nil)+5,end = numberX-5
                        if end > start {
                            context.saveGState(); context.setStrokeColor(NSColor.gray.cgColor); context.setLineWidth(0.5)
                            if options.leaders == 0 { context.setLineDash(phase: 0,lengths: [1,2]) }
                            context.move(to: CGPoint(x: start,y: lastBaseline+1)); context.addLine(to: CGPoint(x: end,y: lastBaseline+1)); context.strokePath(); context.restoreGState()
                        }
                    }
                }
                links.append(PDFTOCLink(pageIndex: page,bounds: CGRect(x: fragment.x,y: fragment.y-Double(fragment.lines.count)*fragment.lineHeight,width: fragment.width,height: Double(fragment.lines.count)*fragment.lineHeight),target: fragment.entry))
            }
            let footer = CTLineCreateWithAttributedString(NSAttributedString(string: "\(page+1) / \(count)",attributes: [.font: NSFont.systemFont(ofSize: 9),.foregroundColor: NSColor.gray]) as CFAttributedString)
            draw(footer,x: margin,y: margin,maxWidth: size.width-2*margin)
            context.endPDFPage()
        }
        context.closePDF()
        guard PDFDocument(data: data as Data)?.pageCount == count else { throw PDFTOCError.layout }
        return PDFTOCResult(data: data as Data,pageCount: count,entryCount: entries.count,links: links)
    }
}
@MainActor struct PDFTOCRequest: Identifiable {
    let id = UUID(), russian: Bool
    let load: (PDFTOCOptions) throws -> PDFTOCResult
    let apply: (PDFTOCResult) -> String?
}
struct PDFTOCEditor: View {
    let request: PDFTOCRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PDFTOCOptions()
    @State private var result: PDFTOCResult?
    @State private var preview: PDFDocument?
    @State private var page = 0
    @State private var image: NSImage?
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("Table of contents from bookmarks","Содержание из закладок")).font(.title2)
            HStack(alignment: .top,spacing: 20) {
                Form {
                    TextField(label("Title","Заголовок"),text: $options.title)
                    TextField(label("Target pages","Целевые страницы"),text: $options.range)
                    Picker(label("Paper","Бумага"),selection: $options.paper) { Text("A4").tag(0); Text("Letter").tag(1) }
                    Toggle(label("Landscape","Альбомная"),isOn: $options.landscape)
                    Stepper(label("Columns: ","Колонки: ")+String(options.columns),value: $options.columns,in: 1...3)
                    TextField(label("Margins, mm","Поля, мм"),value: $options.marginMM,format: .number)
                    Picker(label("Font","Шрифт"),selection: $options.font) { Text(label("System","Системный")).tag(0); Text("Times").tag(1); Text(label("Monospaced","Моноширинный")).tag(2) }
                    TextField(label("Font size, pt","Шрифт, пт"),value: $options.fontSize,format: .number)
                    Picker(label("Leaders","Лидеры"),selection: $options.leaders) { Text("····").tag(0); Text("——").tag(1); Text(label("None","Нет")).tag(2) }
                    Picker(label("Page numbers","Номера страниц"),selection: $options.numbering) { Text(label("Physical after insertion","Физические после вставки")).tag(0); Text(label("PDF labels","Метки PDF")).tag(1) }
                    if options.numbering == 0 { TextField(label("Number offset","Смещение номеров"),value: $options.numberOffset,format: .number) }
                    TextField(label("Number prefix","Префикс номера"),text: $options.numberPrefix)
                    Stepper(label("Levels: ","Уровни: ")+String(options.maximumLevel),value: $options.maximumLevel,in: 1...9)
                    Button(label("Build preview","Построить предпросмотр")) { rebuild() }
                }.frame(width: 340)
                VStack {
                    if let image { Image(nsImage: image).resizable().scaledToFit().frame(width: 380,height: 480) }
                    else { Text(label("Build the preview to check the layout.","Постройте предпросмотр для проверки оформления.")).frame(width: 380,height: 480) }
                    if let preview { Stepper("\(page+1) / \(preview.pageCount)",value: $page,in: 0...max(0,preview.pageCount-1)).frame(width: 170) }
                }
            }
            if let result { Text(label("Entries: ","Строк: ")+String(result.entryCount)+label(" · Pages to insert: "," · Страниц для вставки: ")+String(result.pageCount)).font(.caption) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Insert at start","Вставить в начало")) {
                guard let result else { return }; error = request.apply(result); if error == nil { dismiss() }
            }.disabled(result == nil).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 800)
            .onAppear { if !request.russian { options.title = "TABLE OF CONTENTS" } }
            .onChange(of: options) { _,_ in result = nil; preview = nil; image = nil; error = nil }
            .onChange(of: page) { _,_ in updateImage() }
    }
    private func rebuild() {
        do { let built = try request.load(options); result = built; preview = PDFDocument(data: built.data); page = 0; updateImage(); error = nil }
        catch { result = nil; preview = nil; image = nil; self.error = error.localizedDescription }
    }
    private func updateImage() { image = preview?.page(at: page)?.thumbnail(of: CGSize(width: 760,height: 960),for: .mediaBox) }
}

struct RibbonCatalogTab: Identifiable {
    let id: String, title: String
    let groups: [Group]
    struct Group: Identifiable { let id: String, title: String; let commands: [Command] }
    struct Command: Identifiable { let id: String, title: String }
}
@MainActor enum PDFFormOrder {
    static func sorted(_ fields: [PDFAnnotation],page: PDFPage,columns: Bool) -> [PDFAnnotation] {
        let box = page.bounds(for: .cropBox),rotated = page.rotation%180 != 0
        let transform = PDFFormattingGeometry.transform(page,box: .cropBox,target: CGRect(x: 0,y: 0,width: rotated ? box.height : box.width,height: rotated ? box.width : box.height))
        return fields.enumerated().sorted { left,right in
            let a = left.element.bounds.applying(transform),b = right.element.bounds.applying(transform)
            if columns {
                if abs(a.minX-b.minX) > max(4,min(a.width,b.width)*0.4) { return a.minX < b.minX }
                if a.maxY != b.maxY { return a.maxY > b.maxY }
            } else {
                if abs(a.maxY-b.maxY) > max(4,min(a.height,b.height)*0.4) { return a.maxY > b.maxY }
                if a.minX != b.minX { return a.minX < b.minX }
            }
            return left.offset < right.offset
        }.map(\.element)
    }
    static func apply(_ fields: [PDFAnnotation],page: PDFPage) -> Bool {
        let originals = page.annotations,widgets = originals.filter { $0.type == "Widget" }
        guard fields.count == widgets.count,Set(fields.map(ObjectIdentifier.init)) == Set(widgets.map(ObjectIdentifier.init)) else { return false }
        var index = 0
        let ordered = originals.map { annotation -> PDFAnnotation in
            guard annotation.type == "Widget" else { return annotation }
            defer { index += 1 }; return fields[index]
        }
        for annotation in originals { page.removeAnnotation(annotation) }
        for annotation in ordered { page.addAnnotation(annotation) }
        return true
    }
}
@MainActor struct PDFFormValuesRequest: Identifiable {
    let id = UUID(), russian: Bool, multiple: Bool
    let choices: [String], values: [String], selected: [String]
    let apply: ([String]) -> String?
}
struct PDFFormRule: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable { case any, integer, decimal, date, email; var id: Self { self } }
    var kind = Kind.any
    var minimum: Double?, maximum: Double?
    func issue(_ value: String,russian: Bool) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        func label(_ en: String,_ ru: String) -> String { russian ? ru : en }
        switch kind {
        case .any: return nil
        case .integer,.decimal:
            if kind == .integer,text.range(of: #"^[+-]?\d+$"#,options: .regularExpression) == nil { return label("An integer is required","Требуется целое число") }
            guard let number = Double(text.replacingOccurrences(of: ",",with: ".")),number.isFinite else { return label("A finite number is required","Требуется конечное число") }
            if let minimum,number < minimum { return label("Below minimum: ","Меньше минимума: ")+String(minimum) }
            if let maximum,number > maximum { return label("Above maximum: ","Больше максимума: ")+String(maximum) }
        case .date:
            guard text.range(of: #"^\d{4}-\d{2}-\d{2}$"#,options: .regularExpression) != nil else { return label("Use YYYY-MM-DD","Используйте ГГГГ-ММ-ДД") }
            let values = text.split(separator: "-").compactMap { Int($0) },calendar = Calendar(identifier: .gregorian)
            guard values.count == 3,let date = calendar.date(from: DateComponents(year: values[0],month: values[1],day: values[2])),calendar.component(.year,from: date) == values[0],calendar.component(.month,from: date) == values[1],calendar.component(.day,from: date) == values[2] else { return label("Invalid calendar date","Некорректная календарная дата") }
        case .email:
            guard text.utf16.count <= 320,text.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#,options: .regularExpression) != nil else { return label("Invalid email address","Некорректный адрес почты") }
        }
        return nil
    }
}
@MainActor struct PDFFormRuleRequest: Identifiable {
    let id = UUID(), russian: Bool, value: String
    let initial: PDFFormRule
    let apply: (PDFFormRule) -> String?
}
struct PDFFormRuleEditor: View {
    let request: PDFFormRuleRequest
    @Environment(\.dismiss) private var dismiss
    @State private var kind: PDFFormRule.Kind
    @State private var minimum: String
    @State private var maximum: String
    @State private var error: String?
    init(request: PDFFormRuleRequest) { self.request = request; _kind = State(initialValue: request.initial.kind); _minimum = State(initialValue: request.initial.minimum.map { String($0) } ?? ""); _maximum = State(initialValue: request.initial.maximum.map { String($0) } ?? "") }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Field validation rule","Правило проверки поля")).font(.title2)
            Picker(label("Value type","Тип значения"),selection: $kind) {
                Text(label("Any text","Любой текст")).tag(PDFFormRule.Kind.any); Text(label("Integer","Целое число")).tag(PDFFormRule.Kind.integer)
                Text(label("Decimal","Дробное число")).tag(PDFFormRule.Kind.decimal); Text(label("Date YYYY-MM-DD","Дата ГГГГ-ММ-ДД")).tag(PDFFormRule.Kind.date); Text("Email").tag(PDFFormRule.Kind.email)
            }
            if kind == .integer || kind == .decimal { TextField(label("Minimum (optional)","Минимум (необязательно)"),text: $minimum); TextField(label("Maximum (optional)","Максимум (необязательно)"),text: $maximum) }
            Text(label("Rules are saved as BotPlus metadata and used by explicit form validation and FDF import. Native typing and external PDF viewers do not enforce them.","Правила сохраняются в метаданных BotPlus и используются явной проверкой формы и импортом FDF. Нативный ввод и внешние PDF-просмотрщики их не контролируют.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button(label("Check current value","Проверить текущее значение")) { guard let rule = rule() else { return }; error = rule.issue(request.value,russian: request.russian) ?? label("Value is valid","Значение допустимо") }
                Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { guard let rule = rule() else { return }; error = request.apply(rule); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 620)
    }
    private func rule() -> PDFFormRule? {
        let lo = minimum.trimmingCharacters(in: .whitespaces),hi = maximum.trimmingCharacters(in: .whitespaces)
        let a = Double(lo.replacingOccurrences(of: ",",with: ".")),b = Double(hi.replacingOccurrences(of: ",",with: "."))
        guard (lo.isEmpty || a?.isFinite == true),(hi.isEmpty || b?.isFinite == true),a == nil || b == nil || a! <= b! else { error = label("Check numeric limits","Проверьте числовые границы"); return nil }
        return PDFFormRule(kind: kind,minimum: a,maximum: b)
    }
}
struct PDFFormIssue: Identifiable { let id = UUID(); let page: Int, name: String, message: String }
@MainActor struct PDFFormValidationRequest: Identifiable { let id = UUID(), russian: Bool; let issues: [PDFFormIssue] }
struct PDFFormValidationPanel: View {
    let request: PDFFormValidationRequest
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(request.russian ? "Проверка формы" : "Form validation").font(.title2)
            if request.issues.isEmpty { Text(request.russian ? "Нарушений проверяемых правил не найдено." : "No violations of the checked rules.") }
            List(request.issues) { issue in VStack(alignment: .leading) { Text("\(issue.page+1) · \(issue.name)").bold(); Text(issue.message) } }
            HStack { Spacer(); Button(request.russian ? "Закрыть" : "Close") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 650,height: 500)
    }
}
struct PDFFormValuesEditor: View {
    let request: PDFFormValuesRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selected = Set<String>()
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Selected form values","Выбранные значения формы")).font(.title2)
            List(request.choices.indices,id: \.self) { index in
                Toggle(request.choices[index]+" · "+request.values[index],isOn: Binding(get: { selected.contains(request.values[index]) },set: { on in
                    if on { if !request.multiple { selected.removeAll() }; selected.insert(request.values[index]) } else { selected.remove(request.values[index]) }
                }))
            }
            if request.multiple { Text(label("All selections are retained for FDF exchange. PDFKit displays the first value; BotPlus metadata keeps the full selection.","Для обмена FDF сохраняются все выбранные значения. PDFKit отображает первое; полный набор хранится в метаданных BotPlus.")).font(.caption) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button(label("Clear","Снять всё")) { selected.removeAll() }; Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                error = request.apply(request.values.filter(selected.contains)); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600,height: 480).onAppear { selected = Set(request.selected) }
    }
}
enum PDFTabTraversal: String, CaseIterable, Identifiable {
    case unspecified = "", rows = "R", columns = "C", structure = "S"
    var id: String { rawValue }
    func title(russian: Bool) -> String {
        switch self {
        case .unspecified: return russian ? "Не задано (правило просмотрщика)" : "Unspecified (viewer default)"
        case .rows: return russian ? "По строкам" : "By rows"
        case .columns: return russian ? "По колонкам" : "By columns"
        case .structure: return russian ? "По структуре документа" : "By document structure"
        }
    }
}
@MainActor struct PDFTabTraversalRequest: Identifiable {
    let id = UUID(), russian: Bool, current: String
    let hasStructure: Bool
    let apply: (PDFTabTraversal) -> String?
}
struct PDFTabTraversalEditor: View {
    let request: PDFTabTraversalRequest
    @Environment(\.dismiss) private var dismiss
    @State private var mode = PDFTabTraversal.unspecified
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Page Tab traversal rule","Правило обхода Tab на странице")).font(.title2)
            Picker(label("Rule","Правило"),selection: $mode) {
                ForEach(PDFTabTraversal.allCases) { Text($0.title(russian: request.russian)).tag($0) }
            }
            if PDFTabTraversal(rawValue: request.current) == nil {
                Text(label("The page uses another Tabs value: /","На странице другое значение Tabs: /")+request.current).font(.caption)
            }
            Text(label("Applies to the current page's annotations, including links and form fields. Viewer support determines keyboard behavior. Manual field order is a separate command.","Действует на аннотации текущей страницы, включая ссылки и поля формы. Клавиатурный обход зависит от поддержки просмотрщиком. Ручной порядок полей задаётся отдельной командой.")).font(.caption)
            if mode == .structure && !request.hasStructure {
                Text(label("No logical structure tree found. This rule does not create tags or a reading order.","Дерево логической структуры не найдено. Это правило не создаёт теги или порядок чтения.")).foregroundStyle(.orange)
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                error = request.apply(mode); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600).onAppear { mode = PDFTabTraversal(rawValue: request.current) ?? .unspecified }
    }
}
@MainActor struct PDFFormOrderRequest: Identifiable {
    let id = UUID(), russian: Bool, page: PDFPage
    let apply: ([PDFAnnotation]) -> String?
}
struct PDFFormOrderEditor: View {
    let request: PDFFormOrderRequest
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [PDFAnnotation] = []
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Field order on current page (Tab)","Порядок полей текущей страницы (Tab)")).font(.title2)
            Text(label("Sets widget order in the page's annotation array. Explicit PDF Tabs/structure rules and the viewer can affect keyboard traversal.","Задаёт порядок Widget в массиве аннотаций страницы. Правила Tabs/структуры PDF и просмотрщик могут влиять на клавиатурный обход.")).font(.caption)
            HStack { Button(label("By rows","По строкам")) { fields = PDFFormOrder.sorted(fields,page: request.page,columns: false) }; Button(label("By columns","По колонкам")) { fields = PDFFormOrder.sorted(fields,page: request.page,columns: true) }; Button(label("Reverse","Обратить")) { fields.reverse() } }
            List(Array(fields.enumerated()),id: \.element) { index,field in
                HStack {
                    Text(String(index+1)).monospacedDigit().frame(width: 35)
                    Text(field.fieldName ?? label("Unnamed field","Поле без имени")); Spacer()
                    Button { fields.swapAt(index,index-1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0)
                    Button { fields.swapAt(index,index+1) } label: { Image(systemName: "arrow.down") }.disabled(index+1 == fields.count)
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(fields); if error == nil { dismiss() } }.disabled(fields.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 660,height: 520).onAppear { fields = request.page.annotations.filter { $0.type == "Widget" } }
    }
}
@MainActor final class RibbonProfile: ObservableObject {
    static let shared = RibbonProfile()
    struct State: Codable { var hidden = Set<String>(); var order: [String:[String]] = [:] }
    @Published private(set) var state: State
    init() { state = UserDefaults.standard.data(forKey: "BotPlus.ribbonProfile").flatMap { try? JSONDecoder().decode(State.self,from: $0) } ?? State() }
    func visible(_ id: String) -> Bool { !state.hidden.contains(id) }
    func setVisible(_ id: String,_ value: Bool) { if value { state.hidden.remove(id) } else { state.hidden.insert(id) }; save() }
    func ordered(_ ids: [String],scope: String) -> [String] { let preferred = state.order[scope] ?? []; return preferred.filter(ids.contains)+ids.filter { !preferred.contains($0) } }
    func move(_ id: String,by delta: Int,ids: [String],scope: String) { var values = ordered(ids,scope: scope); guard let i = values.firstIndex(of: id), values.indices.contains(i+delta) else { return }; values.swapAt(i,i+delta); state.order[scope] = values; save() }
    func reset() { state = State(); save() }
    private func save() { if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data,forKey: "BotPlus.ribbonProfile") } }
}
struct RibbonCustomizationView: View {
    let tabs: [RibbonCatalogTab], russian: Bool
    let close: () -> Void
    @ObservedObject var profile = RibbonProfile.shared
    @State private var selected = "home"
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(russian ? "Настройка ленты" : "Customize Ribbon").font(.title2)
            Picker(russian ? "Вкладка" : "Tab",selection: $selected) { ForEach(tabs) { Text($0.title).tag($0.id) } }
            ScrollView {
                if let tab = tabs.first(where: { $0.id == selected }) {
                    ForEach(profile.ordered(tab.groups.map(\.id),scope: tab.id),id: \.self) { id in
                        if let group = tab.groups.first(where: { $0.id == id }) {
                            VStack(alignment: .leading) {
                                HStack {
                                    Toggle(group.title,isOn: Binding(get: { profile.visible(tab.id+"/"+id) },set: { profile.setVisible(tab.id+"/"+id,$0) })).font(.headline)
                                    Spacer()
                                    Button { profile.move(id,by: -1,ids: tab.groups.map(\.id),scope: tab.id) } label: { Image(systemName: "arrow.up") }
                                    Button { profile.move(id,by: 1,ids: tab.groups.map(\.id),scope: tab.id) } label: { Image(systemName: "arrow.down") }
                                }
                                ForEach(profile.ordered(group.commands.map(\.id),scope: tab.id+"/"+id),id: \.self) { commandID in
                                    if let command = group.commands.first(where: { $0.id == commandID }) {
                                        HStack {
                                            Toggle(command.title,isOn: Binding(get: { profile.visible(tab.id+"/"+id+"/"+commandID) },set: { profile.setVisible(tab.id+"/"+id+"/"+commandID,$0) }))
                                            Spacer()
                                            Button { profile.move(commandID,by: -1,ids: group.commands.map(\.id),scope: tab.id+"/"+id) } label: { Image(systemName: "arrow.up") }
                                            Button { profile.move(commandID,by: 1,ids: group.commands.map(\.id),scope: tab.id+"/"+id) } label: { Image(systemName: "arrow.down") }
                                        }.padding(.leading,20)
                                    }
                                }
                            }.padding(12).background(.quaternary,in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack { Button(russian ? "Сбросить всё" : "Reset all") { profile.reset() }; Spacer(); Button(russian ? "Готово" : "Done",action: close).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620,height: 620)
    }
}

enum PageGeometryUnit: String, CaseIterable, Identifiable {
    case pt, mm, inch
    var id: Self { self }
    var factor: Double { self == .pt ? 1 : self == .mm ? 72/25.4 : 72 }
    var title: String { self == .inch ? "in" : rawValue }
}
struct PageGeometryOptions {
    var range = "all", unit = PageGeometryUnit.mm
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0
    var width = 210.0, height = 297.0, scaleContent = false
}
@MainActor struct PageGeometryRequest: Identifiable {
    let id = UUID(), document: PDFDocument, index: Int, crop: Bool, russian: Bool
    var initialRange = "all"
    let apply: (PageGeometryOptions) -> String?
}
struct PageGeometryEditor: View {
    let request: PageGeometryRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PageGeometryOptions()
    @State private var error: String?
    @State private var preview: NSImage?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(request.crop ? label("Crop pages","Обрезка страниц") : label("Resize pages","Размер страниц")).font(.title2)
            HStack(alignment: .top,spacing: 20) {
                Form {
                    TextField(label("Pages","Страницы"),text: $options.range)
                    Picker(label("Units","Единицы"),selection: $options.unit) { ForEach(PageGeometryUnit.allCases) { Text($0.title).tag($0) } }
                    if request.crop {
                        number(label("Left","Слева"),$options.left); number(label("Right","Справа"),$options.right)
                        number(label("Top","Сверху"),$options.top); number(label("Bottom","Снизу"),$options.bottom)
                        Text(label("CropBox changes visibility; hidden content is retained.","Изменяется CropBox. Содержимое за рамкой остаётся в PDF.")).font(.caption)
                    } else {
                        number(label("Width","Ширина"),$options.width); number(label("Height","Высота"),$options.height)
                        Toggle(label("Scale content and annotations","Масштабировать содержимое и аннотации"),isOn: $options.scaleContent)
                    }
                    Button(label("Update preview","Обновить предпросмотр")) { updatePreview() }
                }.frame(width: 310)
                if request.crop, let page = request.document.page(at: request.index) {
                    InteractiveCropPreview(page: page, options: $options).frame(width: 360,height: 410)
                } else if let preview { Image(nsImage: preview).resizable().scaledToFit().frame(width: 360,height: 410).background(.gray.opacity(0.3)) }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(options); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760).onAppear {
            options.range = request.initialRange
            if let box = request.document.page(at: request.index)?.bounds(for: .mediaBox) { options.width = box.width/options.unit.factor; options.height = box.height/options.unit.factor }
            updatePreview()
        }.onChange(of: options.unit) { old,new in
            let ratio = old.factor/new.factor
            options.left *= ratio; options.right *= ratio; options.top *= ratio; options.bottom *= ratio; options.width *= ratio; options.height *= ratio
        }
    }
    private func number(_ title: String,_ value: Binding<Double>) -> some View { TextField(title,value: value,format: .number.precision(.fractionLength(0...3))) }
    private func updatePreview() {
        guard let source = request.document.page(at: request.index),let page = source.copy() as? PDFPage else { return }
        let box = page.bounds(for: .mediaBox), f = options.unit.factor
        let rect = request.crop ? CGRect(x: box.minX+options.left*f,y: box.minY+options.bottom*f,width: box.width-(options.left+options.right)*f,height: box.height-(options.top+options.bottom)*f) : CGRect(x: 0,y: 0,width: options.width*f,height: options.height*f)
        guard rect.width > 1,rect.height > 1, [rect.minX,rect.minY,rect.width,rect.height].allSatisfy(\.isFinite) else { return }
        if request.crop { page.setBounds(rect,for: .cropBox) } else { page.setBounds(rect,for: .mediaBox); page.setBounds(rect,for: .cropBox) }
        preview = page.thumbnail(of: CGSize(width: 700,height: 820),for: .cropBox)
    }
}

enum PDFBookmarkTextOperation { case affix, replace, letterCase, zoom, clearActions, sort, merge }
struct PDFBookmarkTextOptions: Equatable {
    var range = "all", first = "", second = ""
    var letterCase = 0
    var zoom = 100.0, sortMode = 0
    var recursive = true
}
enum PDFBookmarkMutation { case title, zoom(CGFloat), clearActions, order([PDFOutline]), merge([PDFBookmarkMergeGroup]) }
struct PDFBookmarkMergeGroup { let keeper: PDFOutline; var duplicates: [PDFOutline] }
private enum PDFBookmarkMergeTarget: Hashable {
    case page(Int,Double,Double,Double), url(String), named(Int), remote(String,Int,Double,Double), reset([String]?,Bool), section
}
private struct PDFBookmarkMergeKey: Hashable { let title: String, target: PDFBookmarkMergeTarget }
@MainActor private func bookmarkMergeKey(_ node: PDFOutline,document: PDFDocument) -> PDFBookmarkMergeKey? {
    let target: PDFBookmarkMergeTarget
    if let action = node.action as? PDFActionRemoteGoTo {
        guard let url = action.safeFileURL else { return nil }
        target = .remote(url.absoluteString,action.pageIndex,action.point.x,action.point.y)
    } else if let action = node.action as? PDFActionURL,let url = action.url { target = .url(url.absoluteString) }
    else if let action = node.action as? PDFActionNamed { target = .named(Int(action.name.rawValue)) }
    else if let action = node.action as? PDFActionResetForm { target = .reset(action.fields,action.fieldsIncludedAreCleared) }
    else if let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination,let page = destination.page {
        let index = document.index(for: page)
        guard (0..<document.pageCount).contains(index),destination.point.x.isFinite,destination.point.y.isFinite,destination.zoom.isFinite else { return nil }
        target = .page(index,destination.point.x,destination.point.y,destination.zoom)
    } else if node.action == nil,node.destination == nil { target = .section }
    else { return nil }
    return PDFBookmarkMergeKey(title: node.label ?? "",target: target)
}
struct PDFBookmarkTextChange: Identifiable {
    var id: ObjectIdentifier { ObjectIdentifier(node) }
    let node: PDFOutline
    let before: String, after: String
    let page: Int?
    var mutation: PDFBookmarkMutation = .title
}
@MainActor enum PDFBookmarkTextPlan {
    static func make(nodes: [PDFOutline],document: PDFDocument,operation: PDFBookmarkTextOperation,options: PDFBookmarkTextOptions,russian: Bool = false) -> [PDFBookmarkTextChange]? {
        guard let pages = PDFPageRange.parse(options.range,count: document.pageCount) else { return nil }
        if operation == .zoom, !options.zoom.isFinite || !(1...6400).contains(options.zoom) { return nil }
        let all = ["all","все","*"].contains(options.range.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        let indices = Set(pages)
        func label(_ en: String,_ ru: String) -> String { russian ? ru : en }
        func pageIndex(_ node: PDFOutline) -> Int? {
            let target = node.destination ?? (node.action as? PDFActionGoTo)?.destination
            let index = target?.page.map { document.index(for: $0) }
            return index.flatMap { (0..<document.pageCount).contains($0) ? $0 : nil }
        }
        let scope = (operation == .sort || operation == .merge) && !options.recursive ? Array(nodes.prefix(1)) : nodes
        return scope.compactMap { node in
            if operation == .merge {
                let children = (0..<node.numberOfChildren).compactMap { node.child(at: $0) }
                var groups: [PDFBookmarkMergeGroup] = [],positions: [PDFBookmarkMergeKey:Int] = [:]
                for child in children {
                    guard all || pageIndex(child).map(indices.contains) == true,let key = bookmarkMergeKey(child,document: document) else { continue }
                    if let index = positions[key] { groups[index].duplicates.append(child) }
                    else { positions[key] = groups.count; groups.append(PDFBookmarkMergeGroup(keeper: child,duplicates: [])) }
                }
                groups.removeAll { $0.duplicates.isEmpty }
                guard !groups.isEmpty else { return nil }
                let before = groups.map { "\($0.keeper.label ?? "") × \($0.duplicates.count+1)" }.joined(separator: "\n")
                let after = groups.map { "\($0.keeper.label ?? "") × 1" }.joined(separator: "\n")
                return PDFBookmarkTextChange(node: node,before: before,after: after,page: pageIndex(node).map { $0+1 },mutation: .merge(groups))
            }
            if operation == .sort {
                let children = (0..<node.numberOfChildren).compactMap { node.child(at: $0) }
                let slots = children.indices.filter { all || pageIndex(children[$0]).map(indices.contains) == true }
                let eligible = slots.map { children[$0] }
                let sorted = eligible.enumerated().sorted { left,right in
                    if options.sortMode == 2 {
                        let a = pageIndex(left.element) ?? Int.max,b = pageIndex(right.element) ?? Int.max
                        return a == b ? left.offset < right.offset : a < b
                    }
                    let comparison = (left.element.label ?? "").compare(right.element.label ?? "",options: [.numeric,.caseInsensitive],locale: Locale(identifier: russian ? "ru_RU" : "en_US"))
                    if comparison == .orderedSame { return left.offset < right.offset }
                    return comparison == (options.sortMode == 1 ? .orderedDescending : .orderedAscending)
                }.map(\.element)
                var ordered = children
                for (slot,child) in zip(slots,sorted) { ordered[slot] = child }
                guard children.map(ObjectIdentifier.init) != ordered.map(ObjectIdentifier.init) else { return nil }
                func listing(_ values: [PDFOutline]) -> String { values.enumerated().map { "\($0.offset+1). \($0.element.label ?? "")" }.joined(separator: "\n") }
                return PDFBookmarkTextChange(node: node,before: listing(children),after: listing(ordered),page: pageIndex(node).map { $0+1 },mutation: .order(ordered))
            }
            let page = pageIndex(node)
            guard all || page.map(indices.contains) == true else { return nil }
            if operation == .zoom {
                guard page != nil,let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination,
                      destination.zoom != CGFloat(options.zoom/100) else { return nil }
                let old = destination.zoom == 0 || destination.zoom == kPDFDestinationUnspecifiedValue ? label("Inherit zoom","Сохранить текущий масштаб") : "\(destination.zoom*100)%"
                return PDFBookmarkTextChange(node: node,before: old,after: "\(options.zoom)%",page: page.map { $0+1 },mutation: .zoom(CGFloat(options.zoom/100)))
            }
            if operation == .clearActions {
                guard node.action != nil || node.destination != nil else { return nil }
                return PDFBookmarkTextChange(node: node,before: node.action?.type ?? label("Page destination","Переход на страницу"),after: label("No action","Без действия"),page: page.map { $0+1 },mutation: .clearActions)
            }
            let before = node.label ?? "",after: String
            switch operation {
            case .affix: after = options.first+before+options.second
            case .replace: after = options.first.isEmpty ? before : before.replacingOccurrences(of: options.first,with: options.second)
            case .letterCase:
                after = options.letterCase == 1 ? before.lowercased() : options.letterCase == 2 ? before.capitalized : before.uppercased()
            case .zoom,.clearActions,.sort,.merge: return nil
            }
            guard before != after else { return nil }
            return PDFBookmarkTextChange(node: node,before: before,after: after,page: page.map { $0+1 })
        }
    }
    static func apply(_ changes: [PDFBookmarkTextChange]) {
        // Process descendant groups first, before a parent merge moves their children.
        for change in changes.reversed() {
            switch change.mutation {
            case .title: change.node.label = change.after
            case .clearActions:
                // PDFKit's destination setter creates a GoTo action even for nil.
                change.node.destination = nil; change.node.action = nil
            case .zoom(let zoom):
                guard let original = change.node.destination ?? (change.node.action as? PDFActionGoTo)?.destination,let page = original.page else { continue }
                // Destinations may be shared by multiple bookmarks. Replace only this node's destination.
                let destination = PDFDestination(page: page,at: original.point); destination.zoom = zoom
                if change.node.action is PDFActionGoTo { change.node.action = PDFActionGoTo(destination: destination) }
                else { change.node.destination = destination }
            case .order(let children):
                children.forEach { $0.removeFromParent() }
                for child in children { change.node.insertChild(child,at: change.node.numberOfChildren) }
            case .merge(let groups):
                for group in groups {
                    for duplicate in group.duplicates {
                        let children = (0..<duplicate.numberOfChildren).compactMap { duplicate.child(at: $0) }
                        for child in children { child.removeFromParent(); group.keeper.insertChild(child,at: group.keeper.numberOfChildren) }
                        duplicate.removeFromParent()
                    }
                }
            }
        }
    }
}
@MainActor struct PDFBookmarkTextRequest: Identifiable {
    let id = UUID(), russian: Bool, operation: PDFBookmarkTextOperation
    var initialZoom = 100.0
    let load: (PDFBookmarkTextOptions) -> [PDFBookmarkTextChange]?
    let apply: ([PDFBookmarkTextChange]) -> String?
}
struct PDFBookmarkTextEditor: View {
    let request: PDFBookmarkTextRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PDFBookmarkTextOptions()
    @State private var changes: [PDFBookmarkTextChange] = []
    @State private var selection = Set<ObjectIdentifier>()
    @State private var error: String?
    init(request: PDFBookmarkTextRequest) {
        self.request = request
        var initial = PDFBookmarkTextOptions(); initial.zoom = request.initialZoom
        _options = State(initialValue: initial)
    }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(title).font(.title2)
            Text(label("Scope: selected bookmark and descendants, or all bookmarks when none is selected.","Область: выбранная закладка и вложенные; без выделения — все закладки.")).font(.caption)
            TextField(label("Target pages: all / 1-3,5","Целевые страницы: all / 1-3,5"),text: $options.range)
            switch request.operation {
            case .affix:
                HStack { TextField(label("Prefix","Префикс"),text: $options.first); TextField(label("Suffix","Суффикс"),text: $options.second) }
            case .replace:
                HStack { TextField(label("Find (literal, case sensitive)","Найти (с учётом регистра)"),text: $options.first); TextField(label("Replace with","Заменить на"),text: $options.second) }
            case .letterCase:
                Picker(label("Case","Регистр"),selection: $options.letterCase) {
                    Text(label("UPPER","ВЕРХНИЙ")).tag(0); Text(label("lower","нижний")).tag(1); Text(label("Title","Заглавные")).tag(2)
                }
            case .zoom:
                TextField(label("Zoom, % (1–6400)","Масштаб, % (1–6400)"),value: $options.zoom,format: .number)
            case .clearActions:
                Text(label("Selected bookmarks keep their titles and children and lose their navigation actions.","Выбранные закладки сохранят названия и вложенные разделы; действия перехода будут удалены.")).font(.caption)
            case .sort:
                Picker(label("Order","Порядок"),selection: $options.sortMode) {
                    Text(label("Title A–Z","Название А–Я")).tag(0); Text(label("Title Z–A","Название Я–А")).tag(1); Text(label("Target page","Целевая страница")).tag(2)
                }
                Toggle(label("Include nested levels","Включая вложенные уровни"),isOn: $options.recursive)
                Text(label("Each row is a sibling group. A page range reorders matching children within their existing slots.","Каждая строка — группа одного уровня. Диапазон страниц переставляет подходящие закладки только в их прежних позициях.")).font(.caption)
            case .merge:
                Toggle(label("Include nested levels","Включая вложенные уровни"),isOn: $options.recursive)
                Text(label("Only sibling bookmarks with identical titles and supported actions/targets are merged. All children are retained. Preview again to find duplicates brought together by this pass.","Объединяются только закладки одного уровня с одинаковыми названиями и поддерживаемыми действиями/целями. Все вложенные закладки сохраняются. Повторный предпросмотр найдёт дубликаты, оказавшиеся рядом после объединения.")).font(.caption)
            }
            HStack {
                Button(label("Update preview","Обновить предпросмотр")) { preview() }
                Button(label("Select all","Выбрать всё")) { selection = Set(changes.map(\.id)) }
                Button(label("Clear","Снять")) { selection.removeAll() }
                Spacer(); Text("\(selection.count) / \(changes.count)").monospacedDigit()
            }
            ScrollView {
                LazyVStack(alignment: .leading,spacing: 12) {
                    ForEach(changes) { change in
                        Toggle(isOn: Binding(get: { selection.contains(change.id) },set: { if $0 { selection.insert(change.id) } else { selection.remove(change.id) } })) {
                            VStack(alignment: .leading,spacing: 4) {
                                if request.operation == .sort || request.operation == .merge || request.operation == .zoom || request.operation == .clearActions { Text(change.node.label ?? label("Document root","Корень документа")).font(.headline) }
                                Text(change.before.isEmpty ? label("(empty)","(пусто)") : change.before).foregroundStyle(.secondary)
                                Text("→ "+change.after)
                                if let page = change.page { Text(label("Page ","Страница ")+String(page)).font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity,alignment: .leading)
                        }.toggleStyle(.checkbox)
                        Divider()
                    }
                }.frame(maxWidth: .infinity,alignment: .leading)
            }.frame(minHeight: 260)
            if changes.isEmpty,error == nil { Text(label("No changes. Adjust the options and update the preview.","Изменений нет. Задайте параметры и обновите предпросмотр.")).font(.caption) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply selected","Применить выбранное")) {
                error = request.apply(changes.filter { selection.contains($0.id) })
                if error == nil { dismiss() }
            }.disabled(selection.isEmpty).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 740,height: 610)
            .onAppear { preview() }
            .onChange(of: options) { _,_ in changes = []; selection.removeAll(); error = nil }
    }
    private var title: String {
        switch request.operation {
        case .zoom: return label("Bookmark zoom","Масштаб переходов закладок")
        case .clearActions: return label("Remove bookmark actions","Удаление действий закладок")
        case .sort: return label("Sort bookmarks","Сортировка закладок")
        case .merge: return label("Merge duplicate bookmarks","Объединение дубликатов закладок")
        default: return label("Modify bookmark titles","Изменение названий закладок")
        }
    }
    private func preview() {
        guard let rows = request.load(options) else {
            changes = []; selection.removeAll(); error = label("Invalid page range or document changed. Reopen this command if needed.","Некорректный диапазон или документ изменён. При необходимости откройте команду заново."); return
        }
        changes = rows; selection = Set(rows.map(\.id)); error = nil
    }
}

enum PDFBookmarkTargetStatus { case valid, invalid, external, other, noTarget }
struct PDFBookmarkValidationRow: Identifiable {
    let id = UUID(), node: PDFOutline
    let path: String, status: PDFBookmarkTargetStatus, detail: String
    let page: Int?
}
@MainActor enum PDFBookmarkValidator {
    static func rows(document: PDFDocument,russian: Bool) -> [PDFBookmarkValidationRow] {
        guard let root = document.outlineRoot else { return [] }
        func label(_ en: String,_ ru: String) -> String { russian ? ru : en }
        var result: [PDFBookmarkValidationRow] = []
        func visit(_ parent: PDFOutline,path: String,depth: Int) {
            guard depth < 64 else { return }
            for index in 0..<parent.numberOfChildren {
                guard let node = parent.child(at: index) else { continue }
                let title = node.label ?? label("(untitled)","(без названия)")
                let fullPath = path.isEmpty ? title : path+" / "+title
                let status: PDFBookmarkTargetStatus,detail: String
                var page: Int?
                if let remote = node.action as? PDFActionRemoteGoTo {
                    let valid = !remote.url.absoluteString.isEmpty && remote.pageIndex >= 0 && remote.pageIndex != NSNotFound
                    status = valid ? .external : .invalid
                    detail = valid ? label("External PDF; target existence not checked: ","Внешний PDF; существование цели не проверялось: ")+remote.url.lastPathComponent+" · \(remote.pageIndex+1)" : label("Missing external file or invalid page index","Не задан внешний файл или некорректный номер страницы")
                } else if let uri = node.action as? PDFActionURL {
                    let value = uri.url?.absoluteString ?? ""
                    status = value.isEmpty ? .invalid : .external
                    detail = value.isEmpty ? label("Missing URL","Не задан URL") : label("External URL; availability not checked: ","Внешний URL; доступность не проверялась: ")+value
                } else if node.action is PDFActionGoTo || node.destination != nil {
                    let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination
                    let index = destination?.page.map { document.index(for: $0) }
                    if let destination,let index,(0..<document.pageCount).contains(index),
                       destination.point.x.isFinite,destination.point.y.isFinite,destination.zoom.isFinite,
                       destination.zoom >= 0 || destination.zoom == kPDFDestinationUnspecifiedValue {
                        status = .valid; page = index
                        detail = label("Page ","Страница ")+String(index+1)
                    } else { status = .invalid; detail = label("Missing page or invalid destination coordinates/zoom","Страница отсутствует или некорректны координаты/масштаб перехода") }
                } else if let action = node.action {
                    status = .other; detail = label("Action without a local page target: ","Действие без локальной страницы: ")+action.type
                } else {
                    status = .noTarget
                    detail = node.numberOfChildren > 0 ? label("Section without a navigation target","Раздел без перехода") : label("Bookmark without a navigation target","Закладка без перехода")
                }
                result.append(PDFBookmarkValidationRow(node: node,path: fullPath,status: status,detail: detail,page: page))
                visit(node,path: fullPath,depth: depth+1)
            }
        }
        visit(root,path: "",depth: 0); return result
    }
}
@MainActor struct PDFBookmarkValidationRequest: Identifiable {
    let id = UUID(), russian: Bool
    let load: () -> [PDFBookmarkValidationRow]
    let navigate: (PDFBookmarkValidationRow) -> Void
}
struct PDFBookmarkValidationPanel: View {
    let request: PDFBookmarkValidationRequest
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [PDFBookmarkValidationRow] = []
    @State private var onlyInvalid = false
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Bookmark target validation","Проверка целей закладок")).font(.title2)
            Text(label("Bookmarks: ","Закладок: ")+String(rows.count)+label(" · Invalid targets: "," · Повреждённых целей: ")+String(rows.filter { $0.status == .invalid }.count))
            Toggle(label("Only invalid targets","Только повреждённые цели"),isOn: $onlyInvalid)
            ScrollView {
                LazyVStack(alignment: .leading,spacing: 12) {
                    ForEach(rows.filter { !onlyInvalid || $0.status == .invalid }) { row in
                        VStack(alignment: .leading,spacing: 4) {
                            Text(row.path).font(.headline)
                            Text(row.detail).foregroundStyle(row.status == .invalid ? Color.orange : Color.secondary).textSelection(.enabled)
                            if row.page != nil { Button(label("Go to page","Перейти на страницу")) { request.navigate(row); dismiss() } }
                        }.frame(maxWidth: .infinity,alignment: .leading)
                        Divider()
                    }
                }
            }
            Text(label("External URLs and PDF files are listed separately. No network requests or external files are opened during validation.","Внешние URL и PDF указаны отдельно. При проверке сетевые запросы не выполняются и внешние файлы не открываются.")).font(.caption)
            HStack { Button(label("Refresh","Обновить")) { rows = request.load() }; Spacer(); Button(label("Close","Закрыть")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760,height: 590).onAppear { rows = request.load() }
    }
}

extension PDFActionRemoteGoTo {
    // PDFKit may return nil for valid remote named/Fit destinations despite its
    // nonnull URL declaration. KVC keeps the Objective-C result optional.
    var safeFileURL: URL? { value(forKey: "URL") as? URL }
}
struct PDFBookmarkActionExchange: Codable {
    let kind: String
    var file: String?, page: Int?, x: Double?, y: Double?, name: Int?, fields: [String]?, included: Bool?
    var view: String?, destinationName: String?, pdfFile: String?, newWindow: Bool?
}
struct PDFBookmarkExchange: Codable {
    var title: String
    var page: Int?
    var x: Double?, y: Double?, zoom: Double?
    var url: String?
    var children: [PDFBookmarkExchange]
    var action: PDFBookmarkActionExchange?, isOpen: Bool?, unsupportedAction: String?
    var view: String?, destinationName: String?
    var color: [Double]?, style: Int?
    var nextActions: [PDFBookmarkExchange]? = nil
    @MainActor static func read(_ node: PDFOutline,document: PDFDocument,depth: Int = 0) -> Self {
        let destination = node.destination ?? (node.action as? PDFActionGoTo)?.destination
        let index = destination?.page.map { document.index(for: $0) }
        var record = Self(title: node.label ?? "",page: index.flatMap { $0 >= 0 && $0 < document.pageCount ? $0+1 : nil },x: destination.map { Double($0.point.x) },y: destination.map { Double($0.point.y) },zoom: destination.map { Double($0.zoom) },url: (node.action as? PDFActionURL)?.url?.absoluteString,children: depth < 63 ? (0..<node.numberOfChildren).compactMap { node.child(at: $0).map { read($0,document: document,depth: depth+1) } } : [])
        record.isOpen = node.isOpen
        if let action = node.action as? PDFActionRemoteGoTo {
            if let url = action.safeFileURL { record.action = PDFBookmarkActionExchange(kind: "remoteGoTo",file: url.absoluteString,page: action.pageIndex,x: action.point.x,y: action.point.y) }
            else { record.unsupportedAction = "UnresolvedRemoteGoTo" }
        }
        else if let action = node.action as? PDFActionNamed { record.action = PDFBookmarkActionExchange(kind: "named",name: Int(action.name.rawValue)) }
        else if let action = node.action as? PDFActionResetForm { record.action = PDFBookmarkActionExchange(kind: "resetForm",fields: action.fields,included: action.fieldsIncludedAreCleared) }
        else if let action = node.action,!(action is PDFActionGoTo),!(action is PDFActionURL) { record.unsupportedAction = action.type }
        if node.action is PDFActionGoTo,record.page == nil { record.unsupportedAction = "UnresolvedGoTo" }
        if node.action is PDFActionURL,record.url == nil { record.unsupportedAction = "InvalidURL" }
        if depth >= 63,node.numberOfChildren > 0 { record.unsupportedAction = "DepthLimit" }
        return record
    }
    func valid(pageCount: Int,depth: Int = 0,actionDepth: Int = 0) -> Bool {
        guard depth < 64,actionDepth < 16,title.utf16.count <= 20000,unsupportedAction == nil,children.count <= 20000,
              children.allSatisfy({ $0.valid(pageCount: pageCount,depth: depth+1) }) else { return false }
        if let nextActions {
            guard nextActions.count <= 256,(page != nil || url != nil || action != nil),nextActions.allSatisfy({
                $0.title.isEmpty && $0.children.isEmpty && $0.color == nil && $0.style == nil && $0.isOpen == nil && ($0.page != nil || $0.url != nil || $0.action != nil) && $0.valid(pageCount: pageCount,depth: depth+1,actionDepth: actionDepth+1)
            }) else { return false }
        }
        if let color { guard color.count == 3,color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return false } }
        if let style { guard (0...3).contains(style) else { return false } }
        guard !(action != nil && (page != nil || url != nil || view != nil || destinationName != nil)), !(url != nil && (page != nil || view != nil || destinationName != nil)) else { return false }
        if let destinationName { guard !destinationName.isEmpty,destinationName.utf16.count < 32000,page != nil,view != nil else { return false } }
        if let view { guard page != nil,PDFDestinationView(expression: view) != nil else { return false } }
        if let action {
            switch action.kind {
            case "remoteGoTo":
                guard let file = action.file,let link = URL(string: file),link.isFileURL,(action.pdfFile?.utf16.count ?? 0) < 32000 else { return false }
                if let name = action.destinationName { guard !name.isEmpty,name.utf16.count < 32000,action.page == nil,action.view == nil else { return false } }
                else { guard let page = action.page,(0..<1_000_000).contains(page),action.view == nil || PDFDestinationView(expression: action.view!) != nil else { return false } }
                return [action.x,action.y].allSatisfy { $0?.isFinite != false }
            case "named": return action.name.flatMap { (0...11).contains($0) ? PDFActionNamedName(rawValue: $0) : nil } != nil
            case "resetForm": return (action.fields?.count ?? 0) <= 10000 && (action.fields ?? []).allSatisfy { $0.utf16.count <= 20000 }
            default: return false
            }
        }
        if let page { return pageCount > 0 && (1...pageCount).contains(page) && url == nil && [x,y,zoom].allSatisfy { $0?.isFinite != false } && (zoom == nil || zoom! >= 0 || zoom == Double(kPDFDestinationUnspecifiedValue)) }
        if let url { return URL(string: url).flatMap { ["http","https","mailto"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil } != nil }
        return true
    }
    @MainActor func outline(document: PDFDocument,depth: Int = 0) -> PDFOutline? {
        guard valid(pageCount: document.pageCount,depth: depth),nextActions?.isEmpty != false,color == nil,style == nil,view == nil,destinationName == nil,action?.view == nil,action?.destinationName == nil else { return nil }
        let node = PDFOutline(); node.label = title; node.isOpen = isOpen ?? false
        if let action {
            if action.kind == "remoteGoTo",let file = action.file,let link = URL(string: file),let page = action.page { node.action = PDFActionRemoteGoTo(pageIndex: page,at: CGPoint(x: action.x ?? 0,y: action.y ?? 0),fileURL: link) }
            else if action.kind == "named",let value = action.name,let name = PDFActionNamedName(rawValue: value) { node.action = PDFActionNamed(name: name) }
            else if action.kind == "resetForm" { let reset = PDFActionResetForm(); reset.fields = action.fields; reset.fieldsIncludedAreCleared = action.included ?? true; node.action = reset }
        } else if let page, let target = document.page(at: page-1) {
            let point = CGPoint(x: x.flatMap { $0.isFinite ? $0 : nil } ?? target.bounds(for: .cropBox).minX,y: y.flatMap { $0.isFinite ? $0 : nil } ?? target.bounds(for: .cropBox).maxY)
            let destination = PDFDestination(page: target,at: point); if let zoom { destination.zoom = zoom }; node.destination = destination
        } else if let url, let link = URL(string: url),["https","http","mailto"].contains(link.scheme?.lowercased() ?? "") { node.action = PDFActionURL(url: link) }
        for child in children { guard let nested = child.outline(document: document,depth: depth+1) else { return nil }; node.insertChild(nested,at: node.numberOfChildren) }
        return node
    }
    static func plain(_ text: String,count: Int) -> [Self] {
        struct Row { var depth: Int; var title: String; var page: Int }
        let rows: [Row] = text.components(separatedBy: .newlines).enumerated().compactMap { offset,line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let parts = line.split(separator: "\t",maxSplits: 1,omittingEmptySubsequences: false)
            let page = parts.count == 2 ? Int(parts[0]) ?? 0 : offset+1
            guard (1...count).contains(page) else { return nil }
            let value = parts.count == 2 ? String(parts[1]) : line
            let spaces = value.prefix { $0 == " " }.count
            return Row(depth: min(63,spaces/2),title: value.trimmingCharacters(in: .whitespaces),page: page)
        }
        var cursor = 0
        func level(_ depth: Int) -> [Self] {
            var result: [Self] = []
            while cursor < rows.count && rows[cursor].depth >= depth {
                let row = rows[cursor]; cursor += 1
                let children = cursor < rows.count && rows[cursor].depth > row.depth ? level(rows[cursor].depth) : []
                result.append(Self(title: row.title,page: row.page,children: children))
            }
            return result
        }
        return rows.isEmpty ? [] : level(rows[0].depth)
    }
    func html(pdf: String) -> String {
        func escape(_ s: String) -> String { s.replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: ">",with: "&gt;").replacingOccurrences(of: "\"",with: "&quot;") }
        let label = escape(title), target = page.map { "<a href=\""+escape(pdf)+"#page=\($0)\">"+label+"</a>" } ?? label
        return "<li>"+target+(children.isEmpty ? "" : "<ul>"+children.map { $0.html(pdf: pdf) }.joined()+"</ul>")+"</li>"
    }
}

struct PDFSpellIssue: Identifiable { let id = UUID(); let page: Int, word: String; let suggestions: [String] }
@MainActor struct PDFSpellRequest: Identifiable { let id = UUID(); let issues: [PDFSpellIssue]; let russian: Bool; let select: (PDFSpellIssue) -> Void }
struct PDFSpellResults: View {
    let request: PDFSpellRequest
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            Text(request.russian ? "Проверка орфографии" : "Spelling").font(.title2)
            Text(request.russian ? "Выберите слово, затем исправьте его редактором текста PDF. Автоматические замены не выполняются." : "Locate a word, then edit the PDF text. No automatic replacements are applied.").font(.caption)
            List(request.issues) { issue in
                Button { request.select(issue); dismiss() } label: { VStack(alignment: .leading) { Text("\(issue.page+1): \(issue.word)").bold(); Text(issue.suggestions.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary) } }.buttonStyle(.plain)
            }
            if request.issues.isEmpty { Text(request.russian ? "Ошибок не найдено" : "No spelling errors found") }
            HStack { Spacer(); Button(request.russian ? "Закрыть" : "Close") { dismiss() } }
        }.padding(24).frame(width: 560,height: 540)
    }
}

struct PDFPrintOptions: Codable {
    var range = "all", parity = 0, reverse = false, copies = 1, collate = true
    var scaling = 1, percent = 100.0, center = true, autoRotate = true, annotations = true, raster = false, dpi = 300
    var paper = "A4", landscape = false, margin = 10.0
    var paperSize: CGSize {
        let size: CGSize
        switch paper {
        case "A3": size = CGSize(width: 841.89,height: 1190.55)
        case "Letter": size = CGSize(width: 612,height: 792)
        case "Legal": size = CGSize(width: 612,height: 1008)
        default: size = CGSize(width: 595.28,height: 841.89)
        }
        return landscape ? CGSize(width: size.height,height: size.width) : size
    }
    var marginPoints: CGFloat { (margin.isFinite ? min(100,max(0,margin)) : 10)*72/25.4 }
}
@MainActor struct PDFPrintRequest: Identifiable {
    let id = UUID(), document: PDFDocument, current: Int, selected: [Int], russian: Bool
    let run: (PDFPrintOptions,[Int]) -> Void
}
struct PDFPrintEditor: View {
    let request: PDFPrintRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = UserDefaults.standard.data(forKey: "BotPlus.printProfile").flatMap { try? JSONDecoder().decode(PDFPrintOptions.self,from: $0) } ?? PDFPrintOptions()
    @State private var error: String?
    @State private var preview = 0
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var pages: [Int] {
        let source = options.range == "selected" ? request.selected : options.range == "current" ? [request.current] : PDFPageRange.parse(options.range,count: request.document.pageCount) ?? []
        let filtered = source.filter { options.parity == 0 || ($0+1)%2 == (options.parity == 1 ? 1 : 0) }
        return options.reverse ? filtered.reversed().map { $0 } : filtered
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Advanced Print","Параметры печати")).font(.title2)
            HStack(alignment: .top,spacing: 24) {
                Form {
                    HStack { Button(label("All","Все")) { options.range = "all" }; Button(label("Current","Текущая")) { options.range = "current" }; Button(label("Selected","Выбранные")) { options.range = "selected" }.disabled(request.selected.isEmpty) }
                    TextField(label("Page range","Диапазон"),text: $options.range)
                    Picker(label("Subset","Подмножество"),selection: $options.parity) { Text(label("All","Все")).tag(0); Text(label("Odd","Нечётные")).tag(1); Text(label("Even","Чётные")).tag(2) }
                    Toggle(label("Reverse order","Обратный порядок"),isOn: $options.reverse)
                    Stepper(label("Copies: \(options.copies)","Копии: \(options.copies)"),value: $options.copies,in: 1...999)
                    Toggle(label("Collate","Сортировать копии"),isOn: $options.collate)
                    Picker(label("Scale","Масштаб"),selection: $options.scaling) { Text("100%").tag(0); Text(label("Fit","Вписать")).tag(1); Text(label("Shrink","Уменьшать большие")).tag(2); Text(label("Custom","Произвольный")).tag(3) }
                    if options.scaling == 3 { TextField("%",value: $options.percent,format: .number) }
                    Picker(label("Paper","Бумага"),selection: $options.paper) { ForEach(["A4","A3","Letter","Legal"],id: \.self) { Text($0).tag($0) } }
                    Toggle(label("Landscape paper","Альбомная бумага"),isOn: $options.landscape)
                    TextField(label("Margins, mm","Поля, мм"),value: $options.margin,format: .number)
                    Toggle(label("Center","Центрировать"),isOn: $options.center)
                    Toggle(label("Auto-rotate","Автоповорот"),isOn: $options.autoRotate)
                    Toggle(label("Print annotations","Печатать комментарии"),isOn: $options.annotations)
                    Toggle(label("Print as image","Печатать как изображение"),isOn: $options.raster)
                    if options.raster { Picker("DPI",selection: $options.dpi) { ForEach([72,150,300,600],id: \.self) { Text(String($0)).tag($0) } } }
                }.frame(width: 340)
                VStack {
                    if !pages.isEmpty,let page = request.document.page(at: pages[min(preview,pages.count-1)]) { PDFPrintPaperPreview(page: page,options: options).frame(width: 330,height: 430) }
                    HStack { Button("‹") { preview = max(0,preview-1) }; Text("\(min(preview+1,pages.count)) / \(pages.count)"); Button("›") { preview = min(max(0,pages.count-1),preview+1) } }
                    Text(label("Printer and duplex options appear in the macOS print panel.","Принтер и двусторонняя печать настраиваются в следующем системном диалоге.")).font(.caption).frame(width: 330)
                    if options.scaling == 0 || options.scaling == 3 { Text(label("Check paper size and margins: content may be clipped.","Проверьте бумагу и поля: содержимое может выходить за область печати.")).font(.caption).foregroundStyle(.orange).frame(width: 330) }
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Print…","Печать…")) {
                guard !pages.isEmpty, options.percent.isFinite,(1...1000).contains(options.percent), options.margin.isFinite,(0...100).contains(options.margin) else { error = label("Check page range, scale and margins.","Проверьте диапазон, масштаб и поля."); return }
                if let data = try? JSONEncoder().encode(options) { UserDefaults.standard.set(data,forKey: "BotPlus.printProfile") }
                request.run(options,pages); dismiss()
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760).onAppear {
            if !request.selected.isEmpty { options.range = "selected" }
            else if options.range == "selected" { options.range = "all" }
        }
    }
}

@MainActor final class PDFPrintCanvas: NSView {
    private let document: PDFDocument, options: PDFPrintOptions, initialArea: CGSize
    private var area: CGSize {
        guard let info = NSPrintOperation.current?.printInfo else { return initialArea }
        return CGSize(width: max(1,info.paperSize.width-info.leftMargin-info.rightMargin),height: max(1,info.paperSize.height-info.topMargin-info.bottomMargin))
    }
    init(document: PDFDocument,options: PDFPrintOptions,area: CGSize) {
        self.document = document; self.options = options; self.initialArea = area
        super.init(frame: CGRect(x: 0,y: 0,width: area.width,height: area.height*CGFloat(document.pageCount)))
    }
    required init?(coder: NSCoder) { nil }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool { setFrameSize(CGSize(width: area.width,height: area.height*CGFloat(document.pageCount))); range.pointee = NSRange(location: 1,length: document.pageCount); return true }
    override func rectForPage(_ page: Int) -> NSRect { CGRect(x: 0,y: CGFloat(page-1)*area.height,width: area.width,height: area.height) }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        for index in 0..<document.pageCount {
            let cell = rectForPage(index+1)
            guard cell.intersects(dirtyRect),let page = document.page(at: index) else { continue }
            PDFPrintPageRenderer.draw(page: page,options: options,cell: cell,context: context)
        }
    }
}

enum EngineeringKind: String, Codable { case distance, perimeter, area, calibration }
enum EngineeringDistanceAxis: String, Codable, CaseIterable, Identifiable {
    case aligned, horizontal, vertical, custom
    var id: Self { self }
    func title(russian: Bool) -> String {
        switch self { case .aligned: return russian ? "Длина отрезка" : "Segment length"; case .horizontal: return russian ? "Проекция X" : "X projection"; case .vertical: return russian ? "Проекция Y" : "Y projection"; case .custom: return russian ? "Заданный угол…" : "Custom angle…" }
    }
}
enum EngineeringLeaderAnchor: String, Codable, CaseIterable, Identifiable {
    case midpoint, dimensionStart, dimensionEnd, measuredStart, measuredEnd
    var id: Self { self }
    func title(russian: Bool) -> String {
        switch self {
        case .midpoint: return russian ? "Середина размера" : "Dimension midpoint"
        case .dimensionStart: return russian ? "Начало размера" : "Dimension start"
        case .dimensionEnd: return russian ? "Конец размера" : "Dimension end"
        case .measuredStart: return russian ? "Первая измеренная точка" : "First measured point"
        case .measuredEnd: return russian ? "Вторая измеренная точка" : "Second measured point"
        }
    }
}
enum EngineeringUnit: String, Codable, CaseIterable, Identifiable {
    case mm, m, inch, foot
    var id: String { rawValue }
    var millimeters: Double { switch self { case .mm: 1; case .m: 1000; case .inch: 25.4; case .foot: 304.8 } }
}
struct EngineeringScale: Codable {
    var millimetersPerPoint = 25.4/72
    var unit = EngineeringUnit.m
    var valid: Bool { millimetersPerPoint.isFinite && millimetersPerPoint > 0 && millimetersPerPoint <= 1e12 }
}
struct EngineeringScaleOptions {
    var range = "current", denominator = 1.0, unit = EngineeringUnit.m
    var selectedOnly = false, updateExisting = true
    var dimensionLines = true, dimensionOffset = 12.0
}
@MainActor enum EngineeringCalibration {
    static let prefix = "BotPlus engineering calibration v1:"
    static func read(_ page: PDFPage) -> EngineeringScale? {
        guard let text = page.annotations.first(where: { ($0.contents ?? "").hasPrefix(prefix) })?.contents,
              let data = Data(base64Encoded: String(text.dropFirst(prefix.count))),let scale = try? JSONDecoder().decode(EngineeringScale.self,from: data),scale.valid else { return nil }
        return scale
    }
    static func write(_ scale: EngineeringScale,page: PDFPage) throws {
        guard scale.valid else { throw PDFSourceError.content }
        let data = try JSONEncoder().encode(scale)
        for marker in page.annotations where (marker.contents ?? "").hasPrefix(prefix) { page.removeAnnotation(marker) }
        let box = page.bounds(for: .cropBox),marker = PDFAnnotation(bounds: CGRect(x: box.minX,y: box.minY,width: 1,height: 1),forType: .freeText,withProperties: nil)
        marker.contents = prefix+data.base64EncodedString(); marker.shouldDisplay = false; marker.shouldPrint = false; page.addAnnotation(marker)
    }
}
@MainActor struct EngineeringScaleRequest: Identifiable {
    let id = UUID(), russian: Bool, hasSelection: Bool
    let initial: EngineeringScaleOptions
    let apply: (EngineeringScaleOptions) -> String?
}
struct EngineeringScaleEditor: View {
    let request: EngineeringScaleRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options: EngineeringScaleOptions
    @State private var error: String?
    init(request: EngineeringScaleRequest) { self.request = request; _options = State(initialValue: request.initial) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Measurement scale","Масштаб измерений")).font(.title2)
            HStack { Text("1 :"); TextField(label("Denominator","Знаменатель"),value: $options.denominator,format: .number) }
            Picker(label("Display units","Единицы результата"),selection: $options.unit) { ForEach(EngineeringUnit.allCases) { Text($0.rawValue).tag($0) } }
            if request.hasSelection { Toggle(label("Selected measurement only","Только выбранное измерение"),isOn: $options.selectedOnly) }
            if !options.selectedOnly {
                TextField(label("Pages: current / all / 1-3","Страницы: current / all / 1-3"),text: $options.range)
                Toggle(label("Recalculate existing measurements","Пересчитать существующие измерения"),isOn: $options.updateExisting)
            }
            Toggle(label("Dimension arrows for distance measurements","Размерные стрелки для измерений расстояния"),isOn: $options.dimensionLines)
            if options.dimensionLines { TextField(label("Dimension line offset, pt","Отступ размерной линии, пт"),value: $options.dimensionOffset,format: .number) }
            Text(label("Changes calibration and measurement labels. Page geometry and drawing points remain unchanged.","Меняет калибровку и значения измерений. Геометрия страницы и точки чертежа сохраняются.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(options); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 550)
    }
}
struct EngineeringMeasure: Codable {
    var kind: EngineeringKind
    var points: [CGPoint]
    var scale: EngineeringScale
    var dimensionOffset: Double?
    var distanceAxis: EngineeringDistanceAxis? = nil
    var directionDegrees: Double? = nil
    var labelOffset: CGPoint? = nil
    var labelLeader: Bool? = nil
    var leaderElbow: CGPoint? = nil
    var leaderWaypoints: [CGPoint]? = nil
    var leaderAnchor: EngineeringLeaderAnchor? = nil
    var effectiveLeaderAnchor: EngineeringLeaderAnchor { leaderAnchor ?? .midpoint }
    func leaderAnchorPoint(dimensionStart: CGPoint,dimensionEnd: CGPoint) -> CGPoint {
        switch effectiveLeaderAnchor {
        case .midpoint: return CGPoint(x: (dimensionStart.x+dimensionEnd.x)/2,y: (dimensionStart.y+dimensionEnd.y)/2)
        case .dimensionStart: return dimensionStart
        case .dimensionEnd: return dimensionEnd
        case .measuredStart: return points.first ?? dimensionStart
        case .measuredEnd: return points.last ?? dimensionEnd
        }
    }
    var contourLeaderMidpoint: CGPoint? {
        guard [.perimeter,.area].contains(kind),points.count >= (kind == .area ? 3 : 2),points.count <= 20000,points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }) else { return nil }
        let contour = kind == .area ? points+[points[0]] : points
        let lengths = zip(contour,contour.dropFirst()).map { hypot($0.1.x-$0.0.x,$0.1.y-$0.0.y) },total = lengths.reduce(0,+)
        guard total.isFinite,total > 0.000001 else { return nil }
        var remaining = total/2
        for index in lengths.indices where lengths[index] > 0 {
            if remaining <= lengths[index] {
                let t = remaining/lengths[index],a = contour[index],b = contour[index+1]
                return CGPoint(x: a.x+(b.x-a.x)*t,y: a.y+(b.y-a.y)*t)
            }
            remaining -= lengths[index]
        }
        return contour.last
    }
    var effectiveLeaderWaypoints: [CGPoint] { leaderWaypoints ?? leaderElbow.map { [$0] } ?? [] }
    var validLabelPlacement: Bool {
        guard (leaderWaypoints?.count ?? 0) <= 32 else { return false }
        return ([labelOffset,leaderElbow].compactMap { $0 }+(leaderWaypoints ?? [])).allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 10000 && abs($0.y) <= 10000 }
    }
    func labelLeaderPoints(midpoint: CGPoint,labelBounds: CGRect,anchor: CGPoint? = nil) -> [CGPoint] {
        let origin = anchor ?? midpoint
        guard validLabelPlacement,(labelOffset ?? .zero) != .zero,labelLeader != false,!labelBounds.contains(origin) else { return [] }
        let knees = effectiveLeaderWaypoints.map { CGPoint(x: midpoint.x+$0.x,y: midpoint.y+$0.y) },last = knees.last ?? origin
        let end = CGPoint(x: min(max(last.x,labelBounds.minX),labelBounds.maxX),y: min(max(last.y,labelBounds.minY),labelBounds.maxY))
        var result = [origin]
        for next in knees+[end] {
            let start = result.last!,dx = next.x-start.x,dy = next.y-start.y
            guard hypot(dx,dy) > 0.000001 else { continue }
            // Stop at the first intersection with the label, even if an elbow
            // lies inside it or the first leg crosses the entire label.
            var lower: CGFloat = 0,upper: CGFloat = 1,intersects = true
            for (origin,delta,minimum,maximum) in [(start.x,dx,labelBounds.minX,labelBounds.maxX),(start.y,dy,labelBounds.minY,labelBounds.maxY)] {
                if abs(delta) < 1e-12 { if origin < minimum || origin > maximum { intersects = false; break } }
                else { let a = (minimum-origin)/delta,b = (maximum-origin)/delta; lower = max(lower,min(a,b)); upper = min(upper,max(a,b)); if lower > upper { intersects = false; break } }
            }
            if intersects { result.append(CGPoint(x: start.x+dx*lower,y: start.y+dy*lower)); break }
            result.append(next)
        }
        return result
    }
    static func normalizedDirection(_ degrees: Double) -> Double? {
        guard degrees.isFinite,abs(degrees) <= 1_000_000 else { return nil }
        let angle = degrees.truncatingRemainder(dividingBy: 180)
        return angle < 0 ? angle+180 : (angle == 0 ? 0 : angle)
    }
    var direction: Double? { directionDegrees.flatMap(Self.normalizedDirection) }
    var axis: EngineeringDistanceAxis { kind == .distance ? distanceAxis ?? .aligned : .aligned }
    var dimensionBaseline: (CGPoint,CGPoint)? {
        guard kind == .distance,points.count == 2 else { return nil }
        let a = points[0],b = points[1]
        switch axis { case .aligned: return (a,b); case .horizontal: return (a,CGPoint(x: b.x,y: a.y)); case .vertical: return (a,CGPoint(x: a.x,y: b.y))
        case .custom:
            guard let degrees = direction else { return nil }
            let radians = degrees*Double.pi/180,u = CGPoint(x: degrees == 90 ? 0 : cos(radians),y: degrees == 0 ? 0 : sin(radians))
            let dx = b.x-a.x,dy = b.y-a.y,projection = dx*u.x+dy*u.y
            let length = abs(projection) <= hypot(dx,dy)*1e-12 ? 0 : projection
            return (a,CGPoint(x: a.x+u.x*length,y: a.y+u.y*length))
        }
    }
    var value: Double {
        guard points.count > 1,scale.valid else { return 0 }
        if axis == .custom && direction == nil { return .nan }
        let ratio = scale.millimetersPerPoint/scale.unit.millimeters
        if kind == .area {
            guard points.count > 2 else { return 0 }
            let sum = points.indices.reduce(0.0) { value,i in let a = points[i],b = points[(i+1)%points.count]; return value+Double(a.x*b.y-b.x*a.y) }
            return abs(sum)*0.5*ratio*ratio
        }
        if let (a,b) = dimensionBaseline,axis != .aligned { return hypot(Double(b.x-a.x),Double(b.y-a.y))*ratio }
        let length = zip(points,points.dropFirst()).reduce(0.0) { $0+hypot(Double($1.1.x-$1.0.x),Double($1.1.y-$1.0.y)) }
        return length*ratio
    }
    func label(russian: Bool) -> String { value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: russian ? "ru_RU" : "en_US")))+" "+scale.unit.rawValue+(kind == .area ? "²" : "")+(axis == .horizontal ? " · X" : axis == .vertical ? " · Y" : axis == .custom ? " · "+(direction ?? 0).formatted(.number.precision(.fractionLength(0...3)).locale(Locale(identifier: "en_US")))+"°" : "") }
}

struct PDFAnnotationVertex: Identifiable { let id = UUID(); var x: Double, y: Double; var point: CGPoint { CGPoint(x: x,y: y) } }
struct PDFAnnotationVertexPath: Identifiable { let id = UUID(); var vertices: [PDFAnnotationVertex]; var closed = false }
@MainActor enum PDFAnnotationVertexGeometry {
    static func read(_ annotation: PDFAnnotation) throws -> [PDFAnnotationVertexPath] {
        let origin = annotation.bounds.origin
        func vertex(_ point: CGPoint) -> PDFAnnotationVertex { PDFAnnotationVertex(x: point.x+origin.x,y: point.y+origin.y) }
        if annotation.type == "Line" { return [PDFAnnotationVertexPath(vertices: [vertex(annotation.startPoint),vertex(annotation.endPoint)])] }
        guard annotation.type == "Ink",let paths = annotation.paths else { throw PDFSourceError.content }
        var result: [PDFAnnotationVertexPath] = []
        func finish(_ source: PDFAnnotationVertexPath) -> PDFAnnotationVertexPath {
            var path = source
            if path.vertices.count > 2,let first = path.vertices.first,let last = path.vertices.last,hypot(first.x-last.x,first.y-last.y) < 0.000001 {
                path.closed = true; path.vertices.removeLast()
            }
            return path
        }
        for path in paths {
            var current = PDFAnnotationVertexPath(vertices: [])
            var trailingMoveAfterClose = false
            for index in 0..<path.elementCount {
                var points = [NSPoint](repeating: .zero,count: 3)
                let kind = points.withUnsafeMutableBufferPointer { path.element(at: index,associatedPoints: $0.baseAddress!) }
                if kind != .moveTo && kind != .lineTo && kind != .closePath { throw PDFSourceError.content }
                if kind == .moveTo {
                    if !current.vertices.isEmpty {
                        guard current.vertices.count >= 2 else { throw PDFSourceError.content }
                        trailingMoveAfterClose = current.closed; result.append(finish(current)); current = PDFAnnotationVertexPath(vertices: [])
                    }
                    current.vertices.append(vertex(points[0]))
                } else if kind == .lineTo { trailingMoveAfterClose = false; current.vertices.append(vertex(points[0])) }
                else if kind == .closePath { current.closed = true }
            }
            if current.vertices.count >= 2 { result.append(finish(current)) }
            else if !current.vertices.isEmpty && !trailingMoveAfterClose { throw PDFSourceError.content }
        }
        guard !result.isEmpty,result.reduce(0,{ $0+$1.vertices.count }) <= 20000 else { throw PDFSourceError.content }
        return result
    }
    static func apply(_ paths: [PDFAnnotationVertexPath],to annotation: PDFAnnotation) -> Bool {
        guard ["Line","Ink"].contains(annotation.type ?? ""),!paths.isEmpty,
              paths.allSatisfy({ $0.vertices.count >= 2 && $0.vertices.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e9 && abs($0.y) <= 1e9 } }),
              paths.reduce(0,{ $0+$1.vertices.count }) <= 20000 else { return false }
        if annotation.type == "Line",paths.count != 1 || paths[0].vertices.count != 2 { return false }
        let points = paths.flatMap { $0.vertices.map(\.point) }
        let minX = points.map(\.x).min()!,maxX = points.map(\.x).max()!,minY = points.map(\.y).min()!,maxY = points.map(\.y).max()!
        let padding = max(2,annotation.border?.lineWidth ?? 1)
        let box = CGRect(x: minX-padding,y: minY-padding,width: max(1,maxX-minX)+2*padding,height: max(1,maxY-minY)+2*padding)
        if annotation.type == "Ink" { for old in annotation.paths ?? [] { annotation.remove(old) } }
        annotation.bounds = box
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x-box.minX,y: point.y-box.minY) }
        if annotation.type == "Line" { annotation.startPoint = local(points[0]); annotation.endPoint = local(points[1]) }
        else {
            for subpath in paths {
                let path = NSBezierPath()
                for (index,vertex) in subpath.vertices.enumerated() { if index == 0 { path.move(to: local(vertex.point)) } else { path.line(to: local(vertex.point)) } }
                if subpath.closed { path.close() }; annotation.add(path)
            }
        }
        annotation.removeValue(forAnnotationKey: .appearanceDictionary); return true
    }
}
@MainActor struct PDFAnnotationVertexRequest: Identifiable {
    let id = UUID(), russian: Bool, line: Bool
    let initial: [PDFAnnotationVertexPath]
    let apply: ([PDFAnnotationVertexPath]) -> String?
}
struct PDFAnnotationVertexEditor: View {
    let request: PDFAnnotationVertexRequest
    @Environment(\.dismiss) private var dismiss
    @State private var paths: [PDFAnnotationVertexPath]
    @State private var component = 0
    @State private var error: String?
    init(request: PDFAnnotationVertexRequest) { self.request = request; _paths = State(initialValue: request.initial) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Annotation vertices","Вершины аннотации")).font(.title2)
            Text(label("Absolute PDF page coordinates, in points.","Абсолютные координаты страницы PDF, в пунктах.")).font(.caption)
            if paths.count > 1 { Picker(label("Stroke","Штрих"),selection: $component) { ForEach(paths.indices,id: \.self) { Text(String($0+1)).tag($0) } } }
            ScrollView {
                LazyVStack {
                    ForEach(paths[component].vertices.indices,id: \.self) { index in
                        HStack {
                            Text(String(index+1)).frame(width: 30)
                            TextField("X",value: $paths[component].vertices[index].x,format: .number)
                            TextField("Y",value: $paths[component].vertices[index].y,format: .number)
                            if !request.line { Button { paths[component].vertices.remove(at: index) } label: { Image(systemName: "minus.circle") }.disabled(paths[component].vertices.count <= 2) }
                        }
                    }
                }
            }
            if !request.line {
                Toggle(label("Closed path","Замкнутый контур"),isOn: $paths[component].closed)
                Button(label("Append vertex","Добавить вершину")) { let last = paths[component].vertices.last!; paths[component].vertices.append(PDFAnnotationVertex(x: last.x+10,y: last.y)) }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(paths); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600,height: 540)
    }
}

struct PDFSecurityOptions {
    var owner = "", user = "", confirmation = ""
    var printing = true, copying = true, changes = false, assembly = false, comments = true, forms = true, accessibility = true
}
@MainActor struct PDFSecurityRequest: Identifiable { let id = UUID(); let russian: Bool; let export: (PDFSecurityOptions) -> Void }
struct PDFSecurityEditor: View {
    let request: PDFSecurityRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PDFSecurityOptions()
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("PDF passwords and permissions","Пароли и разрешения PDF")).font(.title2)
            SecureField(label("Owner password","Пароль владельца"),text: $options.owner)
            SecureField(label("Confirm owner password","Повторите пароль владельца"),text: $options.confirmation)
            SecureField(label("Password to open (optional)","Пароль открытия (необязательно)"),text: $options.user)
            Toggle(label("Printing","Печать"),isOn: $options.printing); Toggle(label("Copying","Копирование"),isOn: $options.copying)
            Toggle(label("Content changes","Изменение содержимого"),isOn: $options.changes); Toggle(label("Page assembly","Операции со страницами"),isOn: $options.assembly)
            Toggle(label("Commenting","Комментарии"),isOn: $options.comments); Toggle(label("Fill forms","Заполнение форм"),isOn: $options.forms)
            Toggle(label("Accessibility extraction","Извлечение для доступности"),isOn: $options.accessibility)
            Text(label("Exports an encrypted copy using Apple's PDF writer. Passwords are not retained. Permissions rely on the PDF viewer honoring them.","Сохраняется зашифрованная копия средствами Apple. Пароли не сохраняются. Соблюдение разрешений зависит от PDF-просмотрщика.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Export encrypted PDF…","Сохранить защищённую копию…")) {
                guard options.owner.count >= 8,options.owner == options.confirmation,options.owner != options.user else { error = label("Owner password: at least 8 characters, matching confirmation, different from the user password.","Пароль владельца: от 8 символов, совпадает с повтором и отличается от пароля открытия."); return }
                request.export(options); dismiss()
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 540)
    }
}

struct PDFHeadingOptions: Equatable {
    var range = "current", minimumFont = 12.0, offset = 0, columns = 0, scheme = 0
    var logicalLabels = true
}
struct PDFTOCTextLine { let text: String, bounds: CGRect, fontSize: Double; var sourceIndex: Int? = nil }
@MainActor enum PDFTOCRecognizer {
    static func columns(_ lines: [PDFTOCTextLine],bounds: CGRect,count: Int) -> [[PDFTOCTextLine]] {
        let valid = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.bounds.isEmpty }
        let anchors: [Double]
        if count > 0 { anchors = (0..<count).map { bounds.minX+Double($0)*bounds.width/Double(count) } }
        else {
            let starts = valid.filter { $0.text.rangeOfCharacter(from: .letters) != nil && $0.text.range(of: #"^[ivxlcdm]+$"#,options: [.regularExpression,.caseInsensitive]) == nil }.map { Double($0.bounds.minX) }.sorted()
            var found: [Double] = []
            for value in starts {
                if let previous = found.last { if value-previous > bounds.width*0.26,found.count < 3 { found.append(value) } }
                else { found.append(value) }
            }
            anchors = found.isEmpty ? [Double(bounds.minX)] : found
        }
        var groups = [[PDFTOCTextLine]](repeating: [],count: anchors.count)
        for line in valid {
            let index = anchors.lastIndex { $0 <= line.bounds.minX+5 } ?? 0
            groups[index].append(line)
        }
        return groups.map { $0.sorted { abs($0.bounds.midY-$1.bounds.midY) > max(2,min($0.bounds.height,$1.bounds.height)*0.4) ? $0.bounds.midY > $1.bounds.midY : $0.bounds.minX < $1.bounds.minX } }
    }
    static func candidates(lines: [PDFTOCTextLine],bounds: CGRect,document: PDFDocument,options: PDFHeadingOptions) -> [PDFHeadingCandidate] {
        var labels: [String:[Int]] = [:]
        for index in 0..<document.pageCount { if let label = document.page(at: index)?.label { labels[label.lowercased(),default: []].append(index) } }
        func target(_ token: String) -> Int? {
            let trimmed = token.trimmingCharacters(in: CharacterSet(charactersIn: ".()[]"))
            if options.logicalLabels,let matches = labels[trimmed.lowercased()],matches.count == 1 { return matches[0]+options.offset }
            if let number = Int(trimmed),number > 0,number <= 1_000_000 { return number-1+options.offset }
            guard trimmed.range(of: #"^(?i:[ivxlcdm]+)$"#,options: .regularExpression) != nil else { return nil }
            let values: [Character:Int] = ["I":1,"V":5,"X":10,"L":50,"C":100,"D":500,"M":1000]
            var total = 0,previous = 0
            for character in trimmed.uppercased().reversed() { let value = values[character] ?? 0; total += value < previous ? -value : value; previous = value }
            return total > 0 ? total-1+options.offset : nil
        }
        var result: [PDFHeadingCandidate] = []
        for column in columns(lines,bounds: bounds,count: options.columns) {
            var rows: [PDFTOCTextLine] = []
            for line in column {
                if let last = rows.last,abs(last.bounds.midY-line.bounds.midY) <= max(2,min(last.bounds.height,line.bounds.height)*0.4) {
                    rows[rows.count-1] = PDFTOCTextLine(text: last.text+"  "+line.text,bounds: last.bounds.union(line.bounds),fontSize: max(last.fontSize,line.fontSize))
                } else { rows.append(line) }
            }
            var pending = "",previous: CGRect?,pendingCount = 0
            let left = rows.map { $0.bounds.minX }.min() ?? bounds.minX
            for row in rows {
                let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if let previous,previous.minY-row.bounds.maxY > max(8,row.bounds.height*1.7) { pending = ""; pendingCount = 0 }
                previous = row.bounds
                if ["СОДЕРЖАНИЕ","ОГЛАВЛЕНИЕ","CONTENTS","TABLE OF CONTENTS"].contains(text.uppercased()) { pending = ""; continue }
                let parts = text.split(whereSeparator: { $0.isWhitespace })
                guard let last = parts.last else { continue }
                let token = String(last),destination = target(token)
                var prefix = String(text.dropLast(token.count)).trimmingCharacters(in: .whitespaces)
                prefix = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " .·…_–—-\t"))
                // A number may be attached directly to a leader (Title......12).
                var resolved = destination
                if resolved == nil,let range = text.range(of: #"(?:[.·…_]{2,}|\s)([0-9]+|[ivxlcdm]+)$"#,options: [.regularExpression,.caseInsensitive]) {
                    let suffix = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: " .·…_\t"))
                    resolved = target(suffix); prefix = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                }
                if let resolved,!(0..<document.pageCount).contains(resolved) { pending = ""; pendingCount = 0; continue }
                if let at = resolved,(0..<document.pageCount).contains(at),let page = document.page(at: at),!prefix.isEmpty || !pending.isEmpty {
                    let title = [pending,prefix].filter { !$0.isEmpty }.joined(separator: " ")
                    let numbered = title.prefix { $0.isNumber || $0 == "." }.split(separator: ".").count
                    let indent = Int(max(0,(row.bounds.minX-left)/max(8,row.fontSize*1.4)).rounded())
                    result.append(PDFHeadingCandidate(title: title,page: at,point: CGPoint(x: page.bounds(for: .cropBox).minX,y: page.bounds(for: .cropBox).maxY),level: min(8,numbered > 0 ? numbered-1 : indent)))
                    pending = ""; pendingCount = 0
                } else if text.rangeOfCharacter(from: .letters) != nil,pendingCount < 3,text.count < 600 {
                    pending = pending.isEmpty ? text : pending+" "+text; pendingCount += 1
                } else { pending = ""; pendingCount = 0 }
            }
        }
        return result
    }
}
struct PDFHeadingCandidate: Identifiable {
    let id = UUID(), page: Int, point: CGPoint
    var title: String
    var level: Int, selected = true
    init(title: String,page: Int,point: CGPoint,level: Int,selected: Bool = true) { self.title = title; self.page = page; self.point = point; self.level = level; self.selected = selected }
}
@MainActor struct PDFHeadingRequest: Identifiable {
    let id = UUID(); let russian: Bool, fromTOC: Bool
    let load: (PDFHeadingOptions) throws -> [PDFHeadingCandidate]
    let apply: ([PDFHeadingCandidate]) -> String?
}
struct PDFHeadingEditor: View {
    let request: PDFHeadingRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PDFHeadingOptions()
    @State private var candidates: [PDFHeadingCandidate] = []
    @State private var message: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(request.fromTOC ? label("Bookmarks from TOC","Закладки из содержания") : label("Bookmarks from headings","Закладки из заголовков")).font(.title2)
            HStack { TextField(label("Pages: current / all / 1-3","Страницы: current / all / 1-3"),text: $options.range); if request.fromTOC { TextField(label("Page offset","Смещение страниц"),value: $options.offset,format: .number).frame(width: 150) } else { TextField(label("Minimum font, pt","Мин. шрифт, pt"),value: $options.minimumFont,format: .number).frame(width: 150) } }
            Picker(label("Columns","Колонки"),selection: $options.columns) { Text(label("Auto","Авто")).tag(0); Text("1").tag(1); Text("2").tag(2); Text("3").tag(3) }
            if request.fromTOC { Toggle(label("Match PDF page labels","Сопоставлять метки страниц PDF"),isOn: $options.logicalLabels) }
            else { Picker(label("Heading scheme","Схема заголовков"),selection: $options.scheme) { Text(label("Font size","Размер шрифта")).tag(0); Text(label("Numbered","Нумерованные")).tag(1); Text(label("Bold fonts","Полужирный шрифт")).tag(2) } }
            Button(label("Find candidates","Найти заголовки")) { do { candidates = try request.load(options); message = candidates.isEmpty ? label("No matching headings found.","Подходящие заголовки не найдены.") : nil } catch { message = label("Check range and options.","Проверьте диапазон и параметры.") } }
            List($candidates) { $entry in
                HStack { Toggle("",isOn: $entry.selected).labelsHidden(); Text("\(entry.page+1)").frame(width: 45); TextField(label("Title","Название"),text: $entry.title); Spacer(); Stepper("\(entry.level+1)",value: $entry.level,in: 0...8).frame(width: 90) }
            }
            if let message { Text(message).foregroundStyle(.orange) }
            HStack { Button(label("Select all","Выбрать всё")) { for i in candidates.indices { candidates[i].selected = true } }; Button(label("Clear","Снять")) { for i in candidates.indices { candidates[i].selected = false } }; Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Create bookmarks","Создать закладки")) { message = request.apply(candidates.filter(\.selected)); if message == nil { dismiss() } }.disabled(!candidates.contains(where: \.selected)).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 780,height: 620).onChange(of: options) { _,_ in candidates = []; message = nil }
    }
}

// The editor owns its events; no gesture recognizer is installed on PDFView.
struct InteractiveCropPreview: NSViewRepresentable {
    let page: PDFPage
    @Binding var options: PageGeometryOptions
    var displayBox: PDFDisplayBox = .mediaBox
    func makeNSView(context: Context) -> CropView { let view = CropView(); configure(view); return view }
    func updateNSView(_ view: CropView,context: Context) { configure(view) }
    private func configure(_ view: CropView) {
        view.page = page; view.options = options; view.displayBox = displayBox
        view.changed = { options = $0 }; view.needsDisplay = true
    }
    @MainActor final class CropView: NSView {
        var page: PDFPage?, options = PageGeometryOptions(), changed: ((PageGeometryOptions) -> Void)?
        private var start: CGPoint?, initial = CGRect.zero, handle = -1
        var displayBox: PDFDisplayBox = .mediaBox
        private var media: CGRect { page?.bounds(for: displayBox) ?? .zero }
        private var transform: CGAffineTransform {
            guard let page else { return .identity }
            return PDFFormattingGeometry.transform(page,box: displayBox,target: bounds.insetBy(dx: 16,dy: 16))
        }
        private var crop: CGRect {
            let f = options.unit.factor, box = media
            return CGRect(x: box.minX+options.left*f,y: box.minY+options.bottom*f,width: box.width-(options.left+options.right)*f,height: box.height-(options.top+options.bottom)*f)
        }
        private func vertices(_ rect: CGRect) -> [CGPoint] {
            [CGPoint(x: rect.minX,y: rect.minY),CGPoint(x: rect.midX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.minY),CGPoint(x: rect.maxX,y: rect.midY),CGPoint(x: rect.maxX,y: rect.maxY),CGPoint(x: rect.midX,y: rect.maxY),CGPoint(x: rect.minX,y: rect.maxY),CGPoint(x: rect.minX,y: rect.midY)]
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds,cursor: .crosshair) }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(calibratedWhite: 0.13,alpha: 1).setFill(); bounds.fill()
            guard let page,let context = NSGraphicsContext.current?.cgContext,media.width > 0,media.height > 0 else { return }
            let t = transform
            context.saveGState(); context.concatenate(t); context.clip(to: media)
            context.setFillColor(NSColor.white.cgColor); context.fill(media)
            if let reference = page.pageRef { context.drawPDFPage(reference) }
            for annotation in page.annotations where annotation.shouldDisplay && !(annotation.contents ?? "").hasPrefix("BotPlus PDF Editor metadata v1:") { annotation.draw(with: displayBox,in: context) }
            if crop.width > 0,crop.height > 0 {
                context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
                let mask = CGMutablePath(); mask.addRect(media); mask.addRect(crop); context.addPath(mask); context.fillPath(using: .evenOdd)
                context.setStrokeColor(NSColor.systemYellow.cgColor); context.setLineWidth(1.5/max(0.001,hypot(t.a,t.b))); context.stroke(crop)
            }
            context.restoreGState()
            for point in vertices(crop).map({ $0.applying(t) }) {
                let box = CGRect(x: point.x-4,y: point.y-4,width: 8,height: 8)
                NSColor.systemYellow.setFill(); box.fill(); NSColor.black.setStroke(); NSBezierPath(rect: box).stroke()
            }
        }
        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow,from: nil)
            guard media.width > 1,media.height > 1,crop.width > 0,crop.height > 0 else { return }
            handle = vertices(crop).map { $0.applying(transform) }.firstIndex { hypot($0.x-point.x,$0.y-point.y) <= 10 } ?? -1
            let pdf = point.applying(transform.inverted())
            guard handle >= 0 || crop.contains(pdf) else { return }
            start = pdf; initial = crop
        }
        override func mouseDragged(with event: NSEvent) {
            guard let start else { return }
            let point = convert(event.locationInWindow,from: nil).applying(transform.inverted())
            let delta = CGPoint(x: point.x-start.x,y: point.y-start.y), box = media
            var x0 = initial.minX,x1 = initial.maxX,y0 = initial.minY,y1 = initial.maxY
            if handle == -1 {
                let dx = min(box.maxX-x1,max(box.minX-x0,delta.x)),dy = min(box.maxY-y1,max(box.minY-y0,delta.y))
                x0 += dx; x1 += dx; y0 += dy; y1 += dy
            } else {
                if [0,6,7].contains(handle) { x0 = max(box.minX,min(x1-1,initial.minX+delta.x)) }
                if [2,3,4].contains(handle) { x1 = min(box.maxX,max(x0+1,initial.maxX+delta.x)) }
                if [0,1,2].contains(handle) { y0 = max(box.minY,min(y1-1,initial.minY+delta.y)) }
                if [4,5,6].contains(handle) { y1 = min(box.maxY,max(y0+1,initial.maxY+delta.y)) }
            }
            let f = options.unit.factor
            options.left = (x0-box.minX)/f; options.right = (box.maxX-x1)/f
            options.top = (box.maxY-y1)/f; options.bottom = (y0-box.minY)/f
            changed?(options); needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) { start = nil }
    }
}

enum PDFInkEraser {
    static func erase(_ paths: [NSBezierPath],center: CGPoint,radius: CGFloat) -> (paths: [NSBezierPath],changed: Bool) {
        var result: [NSBezierPath] = [],changed = false
        func outside(_ a: CGPoint,_ b: CGPoint) -> [(CGPoint,CGPoint)] {
            let dx = b.x-a.x,dy = b.y-a.y,ox = a.x-center.x,oy = a.y-center.y
            let aa = dx*dx+dy*dy,bb = 2*(ox*dx+oy*dy),cc = ox*ox+oy*oy-radius*radius
            if aa < 0.000001 { return cc > 0 ? [(a,b)] : [] }
            var values: [CGFloat] = [0,1]
            let d = bb*bb-4*aa*cc
            if d >= 0 { for t in [(-bb-sqrt(d))/(2*aa),(-bb+sqrt(d))/(2*aa)] where t > 0 && t < 1 { values.append(t) } }
            values.sort()
            func point(_ t: CGFloat) -> CGPoint { CGPoint(x: a.x+dx*t,y: a.y+dy*t) }
            return zip(values,values.dropFirst()).compactMap { lo,hi in
                let p = point((lo+hi)/2)
                return hypot(p.x-center.x,p.y-center.y) >= radius ? (point(lo),point(hi)) : nil
            }
        }
        for source in paths {
            var segments: [(CGPoint,CGPoint)] = [],last = CGPoint.zero,first = CGPoint.zero
            var points = [CGPoint](repeating: .zero,count: 3)
            for i in 0..<source.elementCount {
                let kind = source.element(at: i,associatedPoints: &points)
                switch kind {
                case .moveTo: last = points[0]; first = last
                case .lineTo: segments.append((last,points[0])); last = points[0]
                case .quadraticCurveTo:
                    let a = last,b = points[0],c = points[1]
                    for sample in 1...24 {
                        let t = CGFloat(sample)/24,u = 1-t
                        let p = CGPoint(x: u*u*a.x+2*u*t*b.x+t*t*c.x,y: u*u*a.y+2*u*t*b.y+t*t*c.y)
                        segments.append((last,p)); last = p
                    }
                case .cubicCurveTo:
                    let a = last,b = points[0],c = points[1],d = points[2]
                    for sample in 1...24 { let t = CGFloat(sample)/24,u = 1-t; let p = CGPoint(x: u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,y: u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y); segments.append((last,p)); last = p }
                case .closePath: segments.append((last,first)); last = first
                @unknown default: break
                }
            }
            var pieces: [NSBezierPath] = [],path: NSBezierPath?,end: CGPoint?,modified = false
            for (a,b) in segments {
                let kept = outside(a,b)
                if kept.count != 1 || kept.first?.0 != a || kept.first?.1 != b { modified = true }
                for (from,to) in kept {
                    if let previous = end,hypot(previous.x-from.x,previous.y-from.y) < 0.001,let current = path { current.line(to: to) }
                    else { let current = NSBezierPath(); current.move(to: from); current.line(to: to); pieces.append(current); path = current }
                    end = to
                }
                if kept.isEmpty { end = nil; path = nil }
            }
            if modified { result.append(contentsOf: pieces); changed = true } else { result.append(source) }
        }
        return (result,changed)
    }
}

struct PDFDestinationView: Equatable {
    enum Mode: String, CaseIterable, Identifiable { case XYZ, Fit, FitH, FitV, FitR, FitB, FitBH, FitBV; var id: Self { self }
        var fields: [String] { switch self { case .XYZ: ["X","Y","Zoom"]; case .FitH,.FitBH: ["Top"]; case .FitV,.FitBV: ["Left"]; case .FitR: ["Left","Bottom","Right","Top"]; case .Fit,.FitB: [] } }
    }
    let mode: Mode, values: [Double?]
    init?(mode: Mode,values: [Double?]) {
        guard values.count == mode.fields.count,values.allSatisfy({ $0?.isFinite != false && ($0 == nil || abs($0!) <= 1e15) }) else { return nil }
        if mode == .FitR {
            guard values.allSatisfy({ $0 != nil }),values[2]! > values[0]!,values[3]! > values[1]! else { return nil }
        }
        if mode == .XYZ,let zoom = values[2],zoom < 0 { return nil }
        self.mode = mode; self.values = values
    }
    init?(expression: String) {
        let parts = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first,first.hasPrefix("/"),let mode = Mode(rawValue: String(first.dropFirst())),parts.count == mode.fields.count+1 else { return nil }
        var values: [Double?] = []
        for part in parts.dropFirst() { if part == "null" { values.append(nil) } else if let number = Double(part),number.isFinite { values.append(number) } else { return nil } }
        self.init(mode: mode,values: values)
    }
    var expression: String { "/"+mode.rawValue+(values.isEmpty ? "" : " "+values.map { $0.map { NSDecimalNumber(value: $0).stringValue } ?? "null" }.joined(separator: " ")) }
}
@MainActor struct PDFNamedRequest: Identifiable {
    let id = UUID(); let targets: [PDFNamedTarget], currentPage: Int, point: CGPoint, pageCount: Int, russian: Bool
    let apply: ([PDFNamedTarget]) -> String?
}
struct PDFNamedEditor: View {
    let request: PDFNamedRequest
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [PDFNamedTarget] = []
    @State private var selected: String?
    @State private var name = ""
    @State private var page = 1
    @State private var mode = PDFDestinationView.Mode.XYZ
    @State private var fields = [String](repeating: "",count: 4)
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Named destinations","Именованные назначения")).font(.title2)
            HStack {
                List(targets,selection: $selected) { target in Text(target.name+" · \(target.page+1)").tag(target.name) }.frame(width: 270,height: 330)
                Form {
                    TextField(label("Name","Имя"),text: $name)
                    Stepper(label("Page: \(page)","Страница: \(page)"),value: $page,in: 1...max(1,request.pageCount))
                    Picker(label("View mode","Режим перехода"),selection: Binding(get: { mode },set: { mode = $0; fields = [String](repeating: "",count: 4) })) { ForEach(PDFDestinationView.Mode.allCases) { Text($0.rawValue).tag($0) } }
                    ForEach(mode.fields.indices,id: \.self) { index in TextField(mode.fields[index]+(mode == .XYZ && index == 2 ? " (1 = 100%)" : " pt"),text: $fields[index]) }
                    Text(label("Empty values mean null; XYZ zoom 0 inherits the current zoom. FitR requires all rectangle coordinates. Renames update local references. Deleting a used name preserves navigation as an explicit destination.","Пустое значение означает null; масштаб XYZ = 0 сохраняет текущий масштаб. FitR требует все координаты прямоугольника. Переименование обновляет локальные ссылки. При удалении используемого имени переходы сохраняются как прямые.")).font(.caption).foregroundStyle(.secondary)
                    Button(label("Update selected","Обновить выбранное")) { update() }.disabled(selected == nil)
                }.frame(width: 330)
            }
            HStack {
                Button(label("Add current page","Добавить текущую страницу")) {
                    var name = "Destination",number = 1
                    while targets.contains(where: { $0.name == name }) { number += 1; name = "Destination-\(number)" }
                    targets.append(PDFNamedTarget(name: name,page: request.currentPage,x: request.point.x,y: request.point.y,zoom: nil)); selected = name
                }
                Button(label("Delete","Удалить")) { targets.removeAll { $0.name == selected }; selected = nil }.disabled(selected == nil)
                Spacer()
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { if selected != nil { update(); guard error == nil else { return } }; error = request.apply(targets); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 690).onAppear { targets = request.targets }.onChange(of: selected) { _,_ in load() }
    }
    private func load() {
        guard let value = targets.first(where: { $0.name == selected }) else { return }
        name = value.name; page = value.page+1
        let view = value.viewExpression.flatMap(PDFDestinationView.init(expression:)) ?? PDFDestinationView(mode: .XYZ,values: [value.x,value.y,value.zoom])!
        mode = view.mode; fields = [String](repeating: "",count: 4)
        for (index,value) in view.values.enumerated() { fields[index] = value.map { String($0) } ?? "" }
    }
    private func update() {
        guard let index = targets.firstIndex(where: { $0.name == selected }),!name.trimmingCharacters(in: .whitespaces).isEmpty,!targets.enumerated().contains(where: { $0.offset != index && $0.element.name == name }) else { error = label("Choose a unique nonempty name.","Укажите уникальное непустое имя."); return }
        var values: [Double?] = []
        for index in mode.fields.indices {
            let text = fields[index].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",",with: ".")
            if text.isEmpty || text == "null" { values.append(nil) }
            else if let value = Double(text),value.isFinite { values.append(value) }
            else { error = label("Invalid numeric value.","Проверьте числовые значения."); return }
        }
        guard let view = PDFDestinationView(mode: mode,values: values) else { error = label("Invalid view parameters; FitR requires a nonempty rectangle.","Некорректные параметры; FitR требует ненулевой прямоугольник."); return }
        let original = targets[index].originalName
        targets[index] = PDFNamedTarget(name: name,page: page-1,x: mode == .XYZ ? values[0] : nil,y: mode == .XYZ ? values[1] : nil,zoom: mode == .XYZ ? values[2] : nil,viewExpression: view.expression,originalName: original); selected = name; error = nil
    }
}


@MainActor enum PDFPrintPageRenderer {
    static func draw(page: PDFPage,options: PDFPrintOptions,cell: CGRect,context: CGContext,preview: Bool = false) {
        let crop = page.bounds(for: .cropBox),rotated = page.rotation%180 != 0
        let original = CGSize(width: rotated ? crop.height : crop.width,height: rotated ? crop.width : crop.height)
        guard original.width.isFinite,original.height.isFinite,original.width > 0,original.height > 0,cell.width > 0,cell.height > 0 else { return }
        let turn = options.autoRotate && (original.width > original.height) != (cell.width > cell.height)
        let size = turn ? CGSize(width: original.height,height: original.width) : original
        let fit = min(cell.width/size.width,cell.height/size.height)
        let percent = options.percent.isFinite ? max(0.01,min(10,options.percent/100)) : 1
        let scale = options.scaling == 1 ? fit : options.scaling == 2 ? min(1,fit) : options.scaling == 3 ? percent : 1
        let width = size.width*scale,height = size.height*scale
        let target = CGRect(x: cell.minX+(options.center ? (cell.width-width)/2 : 0),y: cell.minY+(options.center ? (cell.height-height)/2 : cell.height-height),width: width,height: height)
        context.saveGState(); context.clip(to: cell); defer { context.restoreGState() }
        let drawing: CGRect
        if turn { context.translateBy(x: target.maxX,y: target.minY); context.rotate(by: .pi/2); drawing = CGRect(x: 0,y: 0,width: original.width*scale,height: original.height*scale) }
        else { drawing = target }
        if options.raster {
            let factor = min(CGFloat(max(72,min(600,options.dpi)))/72,preview ? 1400/max(original.width,original.height) : .greatestFiniteMagnitude)
            guard original.width*original.height*factor*factor <= 40_000_000 else { return }
            let bitmap = page.thumbnail(of: CGSize(width: original.width*factor,height: original.height*factor),for: .cropBox)
            bitmap.draw(in: drawing,from: .zero,operation: .sourceOver,fraction: 1)
        } else {
            context.concatenate(PDFFormattingGeometry.transform(page,box: .cropBox,target: drawing))
            if let reference = page.pageRef { context.drawPDFPage(reference) }
            if options.annotations { for annotation in page.annotations where annotation.shouldPrint && !(annotation.contents ?? "").hasPrefix("BotPlus PDF Editor metadata v1:") { annotation.draw(with: .cropBox,in: context) } }
        }
    }
}
struct PDFPrintPaperPreview: NSViewRepresentable {
    let page: PDFPage,options: PDFPrintOptions
    func makeNSView(context: Context) -> PaperView { let view = PaperView(); view.configure(page: page,options: options); return view }
    func updateNSView(_ view: PaperView,context: Context) { view.configure(page: page,options: options) }
    @MainActor final class PaperView: NSView {
        private var source: ObjectIdentifier?,page: PDFPage?,showAnnotations: Bool?,options = PDFPrintOptions()
        func configure(page: PDFPage,options: PDFPrintOptions) {
            if source != ObjectIdentifier(page) || showAnnotations != options.annotations {
                self.page = page.copy() as? PDFPage; source = ObjectIdentifier(page); showAnnotations = options.annotations
                for annotation in self.page?.annotations ?? [] { annotation.shouldDisplay = options.annotations && annotation.shouldPrint }
            }
            self.options = options; needsDisplay = true
        }
        override func draw(_ rect: NSRect) {
            NSColor(calibratedWhite: 0.16,alpha: 1).setFill(); bounds.fill()
            guard let page,let context = NSGraphicsContext.current?.cgContext else { return }
            let size = options.paperSize,scale = min(max(1,bounds.width-24)/size.width,max(1,bounds.height-24)/size.height)
            let paper = CGRect(x: bounds.midX-size.width*scale/2,y: bounds.midY-size.height*scale/2,width: size.width*scale,height: size.height*scale)
            NSColor.white.setFill(); paper.fill()
            context.saveGState(); context.clip(to: paper); context.translateBy(x: paper.minX,y: paper.minY); context.scaleBy(x: scale,y: scale)
            let margin = options.marginPoints,cell = CGRect(x: margin,y: margin,width: max(1,size.width-2*margin),height: max(1,size.height-2*margin))
            PDFPrintPageRenderer.draw(page: page,options: options,cell: cell,context: context,preview: true)
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.55).cgColor); context.setLineWidth(0.6/scale); context.setLineDash(phase: 0,lengths: [3/scale,3/scale]); context.stroke(cell)
            context.restoreGState()
        }
    }
}

@MainActor struct PDFAnnotationScaleRequest: Identifiable {
    let id = UUID(),russian: Bool
    let width: Double,height: Double
    let apply: (Double,Double) -> String?
}
struct PDFAnnotationScaleEditor: View {
    let request: PDFAnnotationScaleRequest
    @Environment(\.dismiss) private var dismiss
    @State private var x = 100.0
    @State private var y = 100.0
    @State private var linked = true
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Scale selected geometry","Масштаб выбранной геометрии")).font(.title2)
            Text(String(format: "%.2f × %.2f pt",request.width,request.height)).font(.caption)
            Toggle(label("Keep proportions","Сохранять пропорции"),isOn: $linked).onChange(of: linked) { _,on in if on { y = x } }
            TextField(label("X scale, %","Масштаб X, %"),value: Binding(get: { x },set: { x = $0; if linked { y = $0 } }),format: .number)
            TextField(label("Y scale, %","Масштаб Y, %"),value: Binding(get: { y },set: { y = $0; if linked { x = $0 } }),format: .number)
            Text(label("10–1000%, around the common center. Supports Line, Ink, Square and Circle without measurements. Stroke widths are kept. The result must fit the page.","10–1000%, относительно общего центра. Поддерживаются Line, Ink, Square и Circle без измерений. Толщина линий сохраняется. Результат должен помещаться на странице.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(x,y); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 570)
    }
}

@MainActor struct PDFAnnotationRotationRequest: Identifiable {
    let id = UUID(),russian: Bool
    let apply: (Double) -> String?
}
struct PDFAnnotationRotationEditor: View {
    let request: PDFAnnotationRotationRequest
    @Environment(\.dismiss) private var dismiss
    @State private var degrees = 45.0
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Rotate selected geometry","Поворот выбранной геометрии")).font(.title2)
            TextField(label("Angle, degrees","Угол, градусы"),value: $degrees,format: .number)
            Text(label("−360…360°, positive counterclockwise in page coordinates, around the common center. Any angle for Line and Ink; Square and Circle require multiples of 90°. Measurements are excluded. Stroke widths are kept; the result must fit the page.","−360…360°, положительный угол — против часовой стрелки в координатах страницы, относительно общего центра. Line и Ink — любой угол; Square и Circle — кратный 90°. Измерения исключены. Толщина линий сохраняется, результат должен помещаться на странице.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(degrees); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 570)
    }
}

enum EngineeringTransformCenter: String, CaseIterable, Sendable { case individual, selection, custom }
struct EngineeringAffineOptions: Sendable {
    var degrees = 0.0,scaleX = 1.0,scaleY = 1.0,shearX = 0.0,shearY = 0.0
    var mirrorX = false,mirrorY = false,preservingValue = true
    var center = EngineeringTransformCenter.individual
    var customX = 0.0,customY = 0.0
    var offsetX = 0.0,offsetY = 0.0
    var linear: CGAffineTransform? {
        guard degrees.isFinite,(-360...360).contains(degrees),[scaleX,scaleY].allSatisfy({ $0.isFinite && (0.1...10).contains($0) }),[shearX,shearY].allSatisfy({ $0.isFinite && (-3...3).contains($0) }) else { return nil }
        let angle = degrees.truncatingRemainder(dividingBy: 360),quarter = angle/90,radians = angle*Double.pi/180
        let orthogonal = abs(quarter-quarter.rounded()) < 1e-10
        let cosine = orthogonal ? cos(radians).rounded() : cos(radians),sine = orthogonal ? sin(radians).rounded() : sin(radians)
        let x = mirrorX ? -scaleX : scaleX,y = mirrorY ? -scaleY : scaleY
        let a = x*(cosine-sine*shearY),b = x*(sine+cosine*shearY),c = y*(cosine*shearX-sine),d = y*(sine*shearX+cosine)
        let determinant = a*d-b*c,norm = a*a+b*b+c*c+d*d
        guard abs(determinant) >= max(1e-8,norm*1e-6) else { return nil }
        return CGAffineTransform(a: a,b: b,c: c,d: d,tx: 0,ty: 0)
    }
    var isIdentity: Bool { guard let linear else { return false }; return linear == .identity && offsetX == 0 && offsetY == 0 }
}
extension EngineeringMeasure {
    func transformed(degrees: Double,mirrorX: Bool,mirrorY: Bool,factor: Double = 1,preservingValue: Bool = true) -> Self? {
        var options = EngineeringAffineOptions(); options.degrees = degrees; options.mirrorX = mirrorX; options.mirrorY = mirrorY; options.scaleX = factor; options.scaleY = factor; options.preservingValue = preservingValue
        return transformed(options: options)
    }
    func transformed(options: EngineeringAffineOptions,selectionCenter: CGPoint? = nil) -> Self? {
        guard let matrix = options.linear,scale.valid,validLabelPlacement,[EngineeringKind.distance,.perimeter,.area].contains(kind),points.count >= (kind == .area ? 3 : 2),points.count <= 20000,points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),kind != .distance || points.count == 2 else { return nil }
        let center: CGPoint
        switch options.center {
        case .individual: center = CGPoint(x: (points.map(\.x).min()!+points.map(\.x).max()!)/2,y: (points.map(\.y).min()!+points.map(\.y).max()!)/2)
        case .selection: guard let selectionCenter else { return nil }; center = selectionCenter
        case .custom: center = CGPoint(x: options.customX,y: options.customY)
        }
        guard center.x.isFinite,center.y.isFinite,abs(center.x) <= 1_000_000,abs(center.y) <= 1_000_000,options.offsetX.isFinite,options.offsetY.isFinite,abs(options.offsetX) <= 1_000_000,abs(options.offsetY) <= 1_000_000 else { return nil }
        var result = self
        if let labelOffset { result.labelOffset = labelOffset.applying(matrix) }
        if let leaderElbow { result.leaderElbow = leaderElbow.applying(matrix) }
        if let leaderWaypoints { result.leaderWaypoints = leaderWaypoints.map { $0.applying(matrix) } }
        guard result.validLabelPlacement else { return nil }
        result.points = points.map { point in
            let local = CGPoint(x: point.x-center.x,y: point.y-center.y).applying(matrix)
            return CGPoint(x: center.x+local.x+options.offsetX,y: center.y+local.y+options.offsetY)
        }
        guard result.points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),result.value.isFinite else { return nil }
        let determinant = Double(matrix.a*matrix.d-matrix.b*matrix.c)
        let uniform = options.scaleX == options.scaleY && options.shearX == 0 && options.shearY == 0
        if let offset = dimensionOffset {
            let multiplier: Double
            if uniform { multiplier = options.scaleX*(determinant < 0 ? -1 : 1) }
            else if kind == .distance {
                let oldLength = hypot(points[1].x-points[0].x,points[1].y-points[0].y),newLength = hypot(result.points[1].x-result.points[0].x,result.points[1].y-result.points[0].y)
                multiplier = oldLength > 1e-12 && newLength > 1e-12 ? determinant*Double(oldLength/newLength) : (determinant < 0 ? -1 : 1)*sqrt(abs(determinant))
            } else { multiplier = (determinant < 0 ? -1 : 1)*sqrt(abs(determinant)) }
            let value = offset*multiplier; guard value.isFinite,abs(value) <= 14400 else { return nil }; result.dimensionOffset = value
        }
        if options.preservingValue {
            let oldValue = value,newValue = result.value
            if uniform && axis == .aligned { result.scale.millimetersPerPoint /= options.scaleX }
            else if oldValue > 0,newValue > 0 { result.scale.millimetersPerPoint *= kind == .area ? sqrt(oldValue/newValue) : oldValue/newValue }
            else { guard abs(oldValue-newValue) <= 0.000001 else { return nil } }
            guard result.scale.valid,result.value.isFinite,abs(result.value-oldValue) <= max(0.000001,abs(oldValue)*1e-8) else { return nil }
        }
        return result
    }
}
struct EngineeringTransferOptions {
    var pageIndex: Int
    var centered = false
    var useTargetScale = false
    var offsetX = 0.0
    var offsetY = 0.0
}
struct EngineeringCopyDestination: Identifiable { let id: UUID,title: String,pageCount: Int,currentPage: Int }
@MainActor struct EngineeringTransferRequest: Identifiable {
    let id = UUID(),russian: Bool,count: Int,pageCount: Int,sourcePage: Int
    let apply: (EngineeringTransferOptions) -> String?
    var destinations: [EngineeringCopyDestination] = []
    var applyToDocument: ((UUID,EngineeringTransferOptions) -> String?)? = nil
}
struct EngineeringTransferEditor: View {
    let request: EngineeringTransferRequest
    @Environment(\.dismiss) private var dismiss
    @State private var page: String
    @State private var destinationID: UUID?
    @State private var centered = false
    @State private var targetScale = false
    @State private var offsetX = "0"
    @State private var offsetY = "0"
    @State private var error: String?
    init(request: EngineeringTransferRequest) {
        self.request = request; _destinationID = State(initialValue: request.destinations.first?.id)
        _page = State(initialValue: String(request.destinations.first.map { $0.currentPage+1 } ?? (request.sourcePage+1 < request.pageCount ? request.sourcePage+2 : max(1,request.sourcePage))))
    }
    private var copying: Bool { request.applyToDocument != nil }
    private var pageCount: Int { request.destinations.first { $0.id == destinationID }?.pageCount ?? request.pageCount }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(copying ? label("Copy measurements to another PDF","Копировать измерения в другой PDF") : label("Move measurements to another page","Перенести измерения на другую страницу")).font(.title2)
            if copying {
                Picker(label("Destination PDF","Целевой PDF"),selection: $destinationID) { ForEach(request.destinations) { Text($0.title).tag(Optional($0.id)) } }
                Text(label("Originals remain in the source PDF. Undo applies in the destination PDF, which opens after copying.","Оригиналы сохраняются в исходном PDF. После копирования откроется целевой PDF; отмена выполняется в нём.")).font(.caption)
            }
            Text(label("Selected: ","Выбрано: ")+String(request.count)).font(.caption)
            TextField(label("Destination page (1–\(pageCount))","Целевая страница (1–\(pageCount))"),text: $page)
            Toggle(label("Center complete selection on destination","Поместить всё выделение в центр целевой страницы"),isOn: $centered)
            Text(label("Otherwise keeps offsets from the lower-left corner of CropBox. Uses PDF coordinates without adjusting for page rotation.","Иначе сохраняет отступы от нижнего левого угла CropBox. Используются координаты PDF без переориентации по повороту страницы.")).font(.caption)
            HStack { TextField(label("Additional X, pt","Дополнительно X, pt"),text: $offsetX); TextField(label("Additional Y, pt","Дополнительно Y, pt"),text: $offsetY) }
            Toggle(label("Use destination calibration and units","Использовать калибровку и единицы целевой страницы"),isOn: $targetScale)
            Text(label("Requires an explicit calibration on the destination. Otherwise each measurement keeps its own calibration and value. Labels and dimension lines move together; the entire result must fit CropBox.","Требует явной калибровки целевой страницы. Иначе каждое измерение сохраняет свою калибровку и значение. Подписи и размерные линии переносятся вместе; результат должен целиком помещаться в CropBox.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(copying ? label("Copy","Копировать") : label("Move","Перенести"),action: perform).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 600).onChange(of: destinationID) { _,id in
            if let destination = request.destinations.first(where: { $0.id == id }) { page = String(destination.currentPage+1) }; error = nil
        }
    }
    private func perform() {
        guard let number = Int(page.trimmingCharacters(in: .whitespaces)),pageCount > 0,(1...pageCount).contains(number),(copying || number-1 != request.sourcePage),
              let x = Double(offsetX.replacingOccurrences(of: ",",with: ".")),let y = Double(offsetY.replacingOccurrences(of: ",",with: ".")),x.isFinite,y.isFinite,abs(x) <= 1_000_000,abs(y) <= 1_000_000 else { error = label("Check destination page and offsets.","Проверьте целевую страницу и смещения."); return }
        let options = EngineeringTransferOptions(pageIndex: number-1,centered: centered,useTargetScale: targetScale,offsetX: x,offsetY: y)
        if copying { guard let id = destinationID,let apply = request.applyToDocument else { return }; error = apply(id,options) }
        else { error = request.apply(options) }
        if error == nil { dismiss() }
    }
}
@MainActor struct EngineeringTransformRequest: Identifiable {
    let id = UUID(),russian: Bool
    var count = 1
    var selectionCenter = CGPoint.zero
    var applyAffine: ((EngineeringAffineOptions) -> String?)? = nil
    let apply: (Double,Bool,Bool,Double,Bool) -> String?
}
struct EngineeringTransformEditor: View {
    let request: EngineeringTransformRequest
    @Environment(\.dismiss) private var dismiss
    @State private var degrees = 90.0
    @State private var mirrorX = false
    @State private var mirrorY = false
    @State private var percent = 100.0
    @State private var percentY = 100.0
    @State private var linked = true
    @State private var shearX = 0.0
    @State private var shearY = 0.0
    @State private var center = EngineeringTransformCenter.individual
    @State private var customX = 0.0
    @State private var customY = 0.0
    @State private var offsetX = 0.0
    @State private var offsetY = 0.0
    @State private var preservingValue = false
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Transform selected measurement","Преобразовать выбранное измерение")).font(.title2)
            ScrollView { VStack(alignment: .leading,spacing: 14) {
            Text(label("Measurements: ","Измерений: ")+String(request.count)).font(.caption)
            TextField(label("Angle, degrees","Угол, градусы"),value: $degrees,format: .number)
            Toggle(label("Keep axis proportions","Сохранять пропорции осей"),isOn: $linked).onChange(of: linked) { _,on in if on { percentY = percent } }
            TextField(label("X scale, %","Масштаб X, %"),value: Binding(get: { percent },set: { percent = $0; if linked { percentY = $0 } }),format: .number)
            TextField(label("Y scale, %","Масштаб Y, %"),value: Binding(get: { percentY },set: { percentY = $0; if linked { percent = $0 } }),format: .number).disabled(request.applyAffine == nil)
            if request.applyAffine != nil {
                TextField(label("X shear, %","Сдвиг X, %"),value: $shearX,format: .number)
                TextField(label("Y shear, %","Сдвиг Y, %"),value: $shearY,format: .number)
                Picker(label("Center","Центр"),selection: $center) { Text(label("Each measurement","Каждого измерения")).tag(EngineeringTransformCenter.individual); Text(label("Selection","Выделения")).tag(EngineeringTransformCenter.selection); Text(label("PDF point","Точка PDF")).tag(EngineeringTransformCenter.custom) }
                if center == .custom { HStack { TextField("X, pt",value: $customX,format: .number); TextField("Y, pt",value: $customY,format: .number) } }
                HStack { TextField(label("Move X, pt","Перенос X, pt"),value: $offsetX,format: .number); TextField(label("Move Y, pt","Перенос Y, pt"),value: $offsetY,format: .number) }
            }
            Toggle(label("Keep measured values (adjust selected calibration)","Сохранить значения (изменить калибровку выбранных)"),isOn: $preservingValue)
            Toggle(label("Mirror left/right first","Сначала отразить слева/справа"),isOn: $mirrorX)
            Toggle(label("Mirror top/bottom first","Сначала отразить сверху/снизу"),isOn: $mirrorY)
            Text(label("−360…360°, scale 10–1000%, around the chosen center in PDF coordinates. Labels stay upright. Keep calibration to recalculate values, or adjust selected calibration to keep values. Page calibration stays unchanged. The entire batch must fit the page.","−360…360°, масштаб 10–1000%, вокруг выбранного центра в координатах PDF. Подписи остаются горизонтальными. При сохранении калибровки значения пересчитываются; для сохранения значений меняется калибровка выбранных. Калибровка страницы неизменна. Весь пакет должен помещаться на странице.")).font(.caption)
            if request.applyAffine != nil { Text(label("Scale X/Y, then simultaneous shear (±300%), then rotation. Dimension lines are regenerated perpendicular to the new segment. Keeping a value adjusts the aggregate measurement calibration, not a directional scale field. Near-singular transforms are rejected.","Масштаб X/Y, затем одновременный сдвиг (±300%), затем поворот. Размерные линии пересоздаются перпендикулярно новому отрезку. Сохранение значения меняет калибровку итогового измерения, не задаёт масштаб по направлениям. Почти вырожденные преобразования отклоняются.")).font(.caption) }
            }.padding(.trailing,4) }.frame(maxHeight: 500)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                if let apply = request.applyAffine {
                    var options = EngineeringAffineOptions(); options.degrees = degrees; options.scaleX = percent/100; options.scaleY = percentY/100; options.shearX = shearX/100; options.shearY = shearY/100; options.mirrorX = mirrorX; options.mirrorY = mirrorY; options.preservingValue = preservingValue; options.center = center; options.customX = customX; options.customY = customY; options.offsetX = offsetX; options.offsetY = offsetY; error = apply(options)
                } else { error = request.apply(degrees,mirrorX,mirrorY,percent,preservingValue) }; if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 650,height: 700).onAppear { customX = request.selectionCenter.x; customY = request.selectionCenter.y }
    }
}


@MainActor struct EngineeringDirectionRequest: Identifiable {
    let id = UUID(),russian: Bool,degrees: Double
    let apply: (Double) -> String?
}
struct EngineeringDirectionEditor: View {
    let request: EngineeringDirectionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var degrees: String
    @State private var error: String?
    init(request: EngineeringDirectionRequest) { self.request = request; _degrees = State(initialValue: String(request.degrees)) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Distance projection direction","Направление проекции расстояния")).font(.title2)
            TextField(label("Angle from PDF X axis, degrees (−360…360)","Угол от оси X PDF, градусы (−360…360)"),text: $degrees)
            Text(label("Counterclockwise in PDF coordinates, independent of page rotation. Opposite directions describe the same axis; result is an absolute calibrated projection. Source points remain unchanged.","Против часовой стрелки в координатах PDF, независимо от поворота страницы. Противоположные направления задают одну ось; результат — абсолютная калиброванная проекция. Исходные точки сохраняются.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let value = Double(degrees.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",",with: ".")),value.isFinite,(-360...360).contains(value) else { error = label("Enter an angle from −360 to 360.","Введите угол от −360 до 360."); return }
                error = request.apply(value); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 570)
    }
}


struct EngineeringLabelOptions {
    var x = 0.0
    var y = 0.0
    var leader = true
    var elbow = false
    var elbowX = 40.0
    var elbowY = 20.0
    var waypoints: [CGPoint]? = nil
    var anchor = EngineeringLeaderAnchor.midpoint
}
@MainActor struct EngineeringLabelRequest: Identifiable {
    let id = UUID(),russian: Bool,initial: EngineeringLabelOptions
    let apply: (EngineeringLabelOptions) -> String?
    var contour = false
}
struct EngineeringLabelEditor: View {
    let request: EngineeringLabelRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options: EngineeringLabelOptions
    @State private var error: String?
    init(request: EngineeringLabelRequest) { self.request = request; _options = State(initialValue: request.initial) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private func coordinate(_ index: Int,_ key: WritableKeyPath<CGPoint,CGFloat>) -> Binding<Double> {
        Binding(get: {
            guard let points = options.waypoints,points.indices.contains(index) else { return 0 }; return Double(points[index][keyPath: key])
        },set: { value in
            guard var points = options.waypoints,points.indices.contains(index) else { return }; points[index][keyPath: key] = CGFloat(value); options.waypoints = points
        })
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(request.contour ? label("Contour measurement label and leader","Подпись измерения контура и выноска") : label("Dimension label and leader","Подпись размера и выноска")).font(.title2)
            TextField(label("Label offset X, pt","Смещение подписи X, пт"),value: $options.x,format: .number)
            TextField(label("Label offset Y, pt","Смещение подписи Y, пт"),value: $options.y,format: .number)
            Toggle(label("Connect measurement to label","Соединить измерение с подписью"),isOn: $options.leader)
            if options.leader {
                Picker(label("Leader attachment","Точка привязки выноски"),selection: $options.anchor) {
                    ForEach(request.contour ? [.midpoint,.measuredStart,.measuredEnd] : EngineeringLeaderAnchor.allCases) { anchor in
                        Text(request.contour && anchor == .midpoint ? label("Halfway along contour","Середина длины контура") : anchor.title(russian: request.russian)).tag(anchor)
                    }
                }
                Text(request.contour ? label("Waypoints are relative to halfway along the open perimeter or closed area boundary. The label offset is relative to its automatic position above the contour.","Вершины отсчитываются от середины длины открытого периметра или замкнутой границы площади. Подпись смещается от автоматического положения над контуром.") : label("Changing attachment moves only the route start; label and waypoint offsets stay relative to the dimension midpoint.","Смена привязки меняет только начало маршрута; смещения подписи и вершин сохраняются относительно середины размера.")).font(.caption)
                Toggle(label("Multiple elbows","Несколько колен"),isOn: Binding(get: { options.waypoints != nil },set: { enabled in
                    options.waypoints = enabled ? [CGPoint(x: options.elbowX,y: options.elbowY),CGPoint(x: 60,y: 40)] : nil
                }))
                if let points = options.waypoints {
                    Text(label("Waypoints from reference point, pt (up to 32)","Вершины от точки отсчёта, пт (до 32)")).font(.caption)
                    ScrollView {
                        VStack {
                            ForEach(points.indices,id: \.self) { index in
                                HStack {
                                    Text(String(index+1)).frame(width: 22)
                                    TextField("X",value: coordinate(index,\.x),format: .number)
                                    TextField("Y",value: coordinate(index,\.y),format: .number)
                                    Button("↑") { options.waypoints?.swapAt(index,index-1) }.disabled(index == 0)
                                    Button("↓") { options.waypoints?.swapAt(index,index+1) }.disabled(index+1 == points.count)
                                    Button("−") { options.waypoints?.remove(at: index) }
                                }
                            }
                        }
                    }.frame(height: 180)
                    Button(label("Add waypoint","Добавить вершину")) { options.waypoints?.append(CGPoint(x: 60,y: 40)) }.disabled(points.count >= 32)
                } else {
                    Toggle(label("Add an elbow","Добавить колено"),isOn: $options.elbow)
                    if options.elbow {
                        TextField(label("Elbow X from reference point, pt","Колено X от точки отсчёта, пт"),value: $options.elbowX,format: .number)
                        TextField(label("Elbow Y from reference point, pt","Колено Y от точки отсчёта, пт"),value: $options.elbowY,format: .number)
                    }
                }
                Text(label("The route stops at the first label boundary; it never draws through the label.","Линия заканчивается на первой границе подписи и не проходит сквозь неё.")).font(.caption)
            }
            Text(label("Offsets are relative to the automatic label position in PDF coordinates. All parts must fit the page. Measured points and calibration remain unchanged.","Смещения относительно автоматического положения подписи, в координатах PDF. Все части должны помещаться на странице. Измеренные точки и калибровка сохраняются.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button(label("Reset position","Сбросить положение")) { options = EngineeringLabelOptions() }; Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                error = request.apply(options); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 570)
    }
}
