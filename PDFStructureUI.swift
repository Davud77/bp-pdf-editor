// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import AppKit

struct PDFLayerInfo: Identifiable {
    var id: Int, generation: Int, name: String, visible: Bool, locked: Bool
    var viewState: Bool?, printState: Bool?
    var intent: [String] = []
}
struct PDFLayerRow: Identifiable { let id: String, layerID: Int?, title: String, depth: Int }
struct PDFLayerPreset: Identifiable { let id: Int,name: String,creator: String,canMakeDefault: Bool }
struct PDFLayerConfiguration { let groups: [PDFLayerInfo], rows: [PDFLayerRow], hasOrder: Bool }
enum PDFLayerPresetOperation { case create(String), rename(Int,String), remove(Int) }
@MainActor struct PDFLayerPresetRequest: Identifiable {
    let id = UUID(),russian: Bool
    let presets: [PDFLayerPreset]
    let apply: (PDFLayerPresetOperation) -> String?
}
struct PDFLayerPresetEditor: View {
    let request: PDFLayerPresetRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selected = -1
    @State private var name = ""
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Layer configurations","Конфигурации слоёв")).font(.title2)
            Picker(label("Configuration","Конфигурация"),selection: $selected) {
                ForEach(request.presets) { preset in Text((preset.id == -1 ? label("Default: ","Основная: ") : "")+(preset.name.isEmpty ? label("Unnamed","Без имени") : preset.name)).tag(preset.id) }
            }
            TextField(label("Name","Название"),text: $name)
            if let preset = request.presets.first(where: { $0.id == selected }),!preset.creator.isEmpty { Text("Creator: "+preset.creator).font(.caption) }
            Text(label("Save current as new copies the document's current default, including visibility, hierarchy and usage rules. Rename and remove operate on the selected entry. The default cannot be removed.","Сохранение текущей как новой копирует основную конфигурацию документа: видимость, иерархию и правила Usage. Переименование и удаление относятся к выбранной записи. Основную удалить нельзя.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button(label("Save current as new","Сохранить текущую как новую")) { perform(.create(name)) }
                Button(label("Rename","Переименовать")) { perform(.rename(selected,name)) }
                Button(label("Remove","Удалить")) { perform(.remove(selected)) }.disabled(selected < 0)
            }
            HStack { Spacer(); Button(label("Close","Закрыть")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(width: 650).onAppear { loadName() }.onChange(of: selected) { _,_ in loadName() }
    }
    private func loadName() { name = request.presets.first { $0.id == selected }?.name ?? ""; error = nil }
    private func perform(_ operation: PDFLayerPresetOperation) { error = request.apply(operation); if error == nil { dismiss() } }
}
@MainActor struct PDFLayerPolicyRequest: Identifiable {
    let id = UUID(), russian: Bool, entry: PDFLayerInfo
    var applyIntent: ((Bool?,Bool?,[String]) -> String?)? = nil
    var extended: PDFLayerExtendedUsage? = nil
    var applyExtended: ((Bool?,Bool?,[String],PDFLayerExtendedUsage) -> String?)? = nil
    var applyNamed: ((Bool?,Bool?,[String],PDFLayerExtendedUsage?,String) -> String?)? = nil
    let apply: (Bool?,Bool?) -> String?
}
struct PDFLayerPolicyEditor: View {
    let request: PDFLayerPolicyRequest
    @Environment(\.dismiss) private var dismiss
    @State private var viewState: Int
    @State private var name: String
    @State private var printState: Int
    @State private var intents: String
    @State private var exportState: Int
    @State private var zoomEnabled: Bool
    @State private var minimum: String
    @State private var maximum: String
    @State private var language: String
    @State private var preferred: Int
    @State private var creatorEnabled: Bool
    @State private var creator: String
    @State private var creatorSubtype: String
    @State private var userType: String
    @State private var userNames: String
    @State private var pageElement: String
    @State private var printSubtype: String
    @State private var error: String?
    init(request: PDFLayerPolicyRequest) {
        self.request = request
        _name = State(initialValue: request.entry.name)
        _viewState = State(initialValue: request.entry.viewState.map { $0 ? 1 : 2 } ?? 0); _printState = State(initialValue: request.entry.printState.map { $0 ? 1 : 2 } ?? 0); _intents = State(initialValue: request.entry.intent.joined(separator: "\n"))
        let extended = request.extended ?? PDFLayerExtendedUsage()
        _exportState = State(initialValue: extended.exportState.map { $0 ? 1 : 2 } ?? 0); _zoomEnabled = State(initialValue: extended.zoomEnabled)
        _minimum = State(initialValue: extended.minZoom.map { String($0*100) } ?? ""); _maximum = State(initialValue: extended.maxZoom.map { String($0*100) } ?? "")
        _language = State(initialValue: extended.language); _preferred = State(initialValue: extended.preferred.map { $0 ? 1 : 2 } ?? 0)
        let metadata = extended.metadata ?? PDFLayerUsageMetadata()
        _creatorEnabled = State(initialValue: metadata.creatorEnabled); _creator = State(initialValue: metadata.creator); _creatorSubtype = State(initialValue: metadata.creatorSubtype)
        _userType = State(initialValue: metadata.userType); _userNames = State(initialValue: metadata.userNames.joined(separator: "\n")); _pageElement = State(initialValue: metadata.pageElement); _printSubtype = State(initialValue: metadata.printSubtype)
    }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(request.entry.name).font(.title2)
            TextField(label("Layer name","Имя слоя"),text: $name).disabled(request.applyNamed == nil)
            ScrollView { VStack(alignment: .leading,spacing: 16) {
            Text(label("Intent names, one per line; empty restores View","Имена Intent, по одному на строке; пусто возвращает View")).font(.caption)
            TextEditor(text: $intents).font(.system(.body,design: .monospaced)).frame(height: 70).disabled(request.applyIntent == nil)
            policy(label("View usage","Правило просмотра"),$viewState)
            policy(label("Print usage","Правило печати"),$printState)
            if request.extended != nil {
                DisclosureGroup(label("Export, zoom and language","Экспорт, масштаб и язык")) {
                    VStack(alignment: .leading,spacing: 10) {
                        policy(label("Export usage","Правило экспорта"),$exportState)
                        Toggle(label("Apply zoom range","Применять диапазон масштаба"),isOn: $zoomEnabled)
                        HStack { TextField(label("Minimum, %","Минимум, %"),text: $minimum); TextField(label("Maximum, %","Максимум, %"),text: $maximum) }.disabled(!zoomEnabled)
                        Text(label("Empty limits mean 0 and infinity. Minimum included; maximum excluded.","Пустые границы означают 0 и бесконечность. Минимум включён, максимум исключён.")).font(.caption)
                        TextField(label("Language, e.g. ru-RU; empty disables","Язык, например ru-RU; пусто отключает"),text: $language)
                        policy(label("Preferred for partial language match","Предпочтительный при неполном совпадении"),$preferred)
                        Text(label("Language selection covers all catalog groups with Language usage. Existing complex AS rules are retained and may also affect the result.","Выбор языка учитывает все группы каталога с Language. Сложные существующие правила AS сохраняются и тоже могут влиять на результат.")).font(.caption)
                    }.padding(.top,8)
                }
                DisclosureGroup(label("Creator, audience and page role","Создатель, аудитория и роль на странице")) {
                    VStack(alignment: .leading,spacing: 10) {
                        Toggle(label("Record creating application","Указать приложение-создатель"),isOn: $creatorEnabled)
                        TextField(label("Application","Приложение"),text: $creator).disabled(!creatorEnabled)
                        TextField(label("Content type, e.g. Technical or Artwork","Тип содержимого, например Technical или Artwork"),text: $creatorSubtype).disabled(!creatorEnabled)
                        Picker(label("Audience","Аудитория"),selection: $userType) {
                            Text(label("Unspecified","Не указана")).tag(""); Text(label("Individuals","Люди")).tag("Ind"); Text(label("Positions","Должности")).tag("Ttl"); Text(label("Organizations","Организации")).tag("Org")
                        }
                        Text(label("Audience names, one per line","Имена аудитории, по одному на строке")).font(.caption)
                        TextEditor(text: $userNames).frame(height: 80).disabled(userType.isEmpty)
                        Picker(label("Page role","Роль на странице"),selection: $pageElement) {
                            Text(label("Unspecified","Не указана")).tag(""); Text(label("Header/footer","Колонтитул")).tag("HF"); Text(label("Foreground","Передний план")).tag("FG"); Text(label("Background","Фон")).tag("BG"); Text(label("Logo","Логотип")).tag("L")
                        }
                        TextField(label("Print content type; empty removes","Тип печатного содержимого; пусто удаляет"),text: $printSubtype)
                        Text(label("Descriptive metadata. Audience names do not restrict access. Existing automation rules remain in effect.","Описательные данные. Имена аудитории не ограничивают доступ. Существующие автоматические правила сохраняются.")).font(.caption)
                    }.padding(.top,8)
                }
            }
            Text(label("Writes OCG Usage and corresponding AS application entries. Other Usage categories, OCMD expressions and viewer support may affect the effective result. Inherit removes this category's explicit state.","Записывает Usage группы OCG и соответствующие правила AS. Другие категории Usage, выражения OCMD и поддержка просмотрщика могут влиять на результат. «Наследовать» удаляет явное состояние этой категории.")).font(.caption)
            }.padding(.trailing,4) }.frame(maxHeight: 450)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить"),action: perform).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 620,height: 680)
    }
    private func perform() {
        let view: Bool? = viewState == 0 ? nil : viewState == 1,print: Bool? = printState == 0 ? nil : printState == 1
        let names = intents.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if request.applyNamed != nil || request.applyExtended != nil && request.extended != nil {
            func zoom(_ text: String) throws -> Double? {
                let text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",",with: ".")
                guard !text.isEmpty else { return nil }; guard let value = Double(text),value.isFinite else { throw PDFSourceError.content }; return value/100
            }
            do {
                let metadata = PDFLayerUsageMetadata(creatorEnabled: creatorEnabled,creator: creator,creatorSubtype: creatorSubtype,userType: userType,userNames: userNames.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },pageElement: pageElement,printSubtype: printSubtype)
                let value = PDFLayerExtendedUsage(exportState: exportState == 0 ? nil : exportState == 1,zoomEnabled: zoomEnabled,minZoom: zoomEnabled ? try zoom(minimum) : nil,maxZoom: zoomEnabled ? try zoom(maximum) : nil,language: language.trimmingCharacters(in: .whitespacesAndNewlines),preferred: preferred == 0 ? nil : preferred == 1,metadata: metadata)
                guard request.extended == nil || value.valid else { error = label("Check zoom, language, creator and audience fields.","Проверьте масштаб, язык, создателя и аудиторию."); return }
                if let apply = request.applyNamed { error = apply(view,print,names,request.extended == nil ? nil : value,name) }
                else { error = request.applyExtended?(view,print,names,value) }
            } catch { self.error = label("Invalid zoom value.","Некорректное значение масштаба.") }
        } else if let apply = request.applyIntent { error = apply(view,print,names) }
        else { error = request.apply(view,print) }
        if error == nil { dismiss() }
    }
    private func policy(_ title: String,_ value: Binding<Int>) -> some View {
        Picker(title,selection: value) { Text(label("Inherit","Наследовать")).tag(0); Text("ON").tag(1); Text("OFF").tag(2) }
    }
}
struct PDFStructureNode: Identifiable { var id: Int, objectID: Int?, generation: Int, depth: Int, role: String, alternative: String, actual: String, hasActual: Bool = false, title: String = "", language: String = "", expansion: String = "", canMoveUp: Bool = false, canMoveDown: Bool = false, parentObjectID: Int? = nil, canAcceptChildren: Bool = false, canReparent: Bool = false, canWrap: Bool = false, canDeleteEmpty: Bool = false }
struct PDFStructureProperties {
    var title: String?,language: String?,expansion: String?
    var isEmpty: Bool { title == nil && language == nil && expansion == nil }
}
enum PDFStructureTextChange { case preserve, set(String), remove }
struct PDFStructureReport {
    var language: String, marked: Bool, nodes: [PDFStructureNode], issues: [String]
    var rootObjectID: Int? = nil
    var rootCanAcceptChildren = false
    var plainText: String {
        let rows = nodes.map { node in
            let fields: [String] = ["Title: "+String(reflecting: node.title),"Lang: "+(node.language.isEmpty ? "<inherit>" : String(reflecting: node.language)),"E: "+String(reflecting: node.expansion),"Alt: "+String(reflecting: node.alternative),"ActualText: "+(node.hasActual ? String(reflecting: node.actual) : "<absent>")]
            return String(repeating: "  ",count: min(128,node.depth))+node.role+" · "+fields.joined(separator: " · ")
        }
        return "BotPlus PDF structure report\nLanguage: "+language+"\nMarked: \(marked)\n\n"+issues.joined(separator: "\n")+"\n\n"+rows.joined(separator: "\n")
    }
}
@MainActor struct PDFStructureRequest: Identifiable {
    let id = UUID(); let report: PDFStructureReport, russian: Bool, editable: Bool
    var deleteEmpty: ((PDFStructureNode) -> String?)? = nil
    var wrap: ((PDFStructureNode,String) -> String?)? = nil
    var reparent: ((PDFStructureNode,PDFStructureNode?) -> String?)? = nil
    var reorder: ((PDFStructureNode,Int) -> String?)? = nil
    var applyProperties: ((String,PDFStructureNode?,String,PDFStructureTextChange,PDFStructureProperties) -> String?)? = nil
    let apply: (String,PDFStructureNode?,String,PDFStructureTextChange) -> String?
}
struct PDFStructurePanel: View {
    let request: PDFStructureRequest
    @Environment(\.dismiss) private var dismiss
    @State private var language = ""
    @State private var alternative = ""
    @State private var actual = ""
    @State private var useActual = false
    @State private var elementTitle = ""
    @State private var elementLanguage = ""
    @State private var expansion = ""
    @State private var selection: Int?
    @State private var choosingParent = false
    @State private var parentSelection = -1
    @State private var creatingContainer = false
    @State private var containerTitle = ""
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var node: PDFStructureNode? { request.report.nodes.first { $0.id == selection } }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("PDF structure and accessibility","Структура и доступность PDF")).font(.title2)
            Text(label("Edits tag properties and supported logical order, and creates Div containers around existing subtrees while retaining page content and identifiers. Full PDF/UA validation remains necessary.","Редактирует свойства и поддерживаемый логический порядок тегов, создаёт контейнеры Div вокруг существующих поддеревьев, сохраняя содержимое страниц и идентификаторы. Полная проверка PDF/UA остаётся необходимой.")).font(.caption).foregroundStyle(.secondary)
            TextField(label("Document language (BCP 47)","Язык документа (BCP 47)"),text: $language).disabled(!request.editable)
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text(label("Reading structure","Структура чтения")).font(.headline)
                    List(request.report.nodes,selection: $selection) { item in
                        VStack(alignment: .leading) { Text(String(repeating: "  ",count: min(12,item.depth))+item.role+(item.title.isEmpty ? "" : " · "+item.title)); if !item.alternative.isEmpty { Text(item.alternative).font(.caption).lineLimit(2) } }.tag(item.id)
                    }
                }.frame(width: 330)
                ScrollView { VStack(alignment: .leading,spacing: 10) {
                    Text(label("Findings","Результаты диагностики")).font(.headline)
                    ScrollView { VStack(alignment: .leading,spacing: 8) { ForEach(Array(request.report.issues.enumerated()),id: \.offset) { _,issue in Text(issue).textSelection(.enabled) } }.frame(maxWidth: .infinity,alignment: .leading) }.frame(height: 180)
                    if let node {
                        Text(label("Selected element: ","Выбранный элемент: ")+node.role).font(.headline)
                        HStack {
                            Button(label("Move up","Выше")) { move(-1) }.disabled(!request.editable || !node.canMoveUp || hasDraft || request.reorder == nil)
                            Button(label("Move down","Ниже")) { move(1) }.disabled(!request.editable || !node.canMoveDown || hasDraft || request.reorder == nil)
                            Button(label("Change parent…","Другой родитель…")) { error = nil; parentSelection = parentChoices.first?.id ?? -1; choosingParent = true }.disabled(!request.editable || !node.canReparent || hasDraft || request.reparent == nil || parentChoices.isEmpty)
                            Button(label("Wrap in Div…","В Div…")) { error = nil; containerTitle = label("Group","Группа"); creatingContainer = true }.disabled(!request.editable || !node.canWrap || hasDraft || request.wrap == nil)
                        }
                        Button(label("Delete empty tag","Удалить пустой тег")) {
                            guard let apply = request.deleteEmpty else { return }; error = apply(node); if error == nil { dismiss() }
                        }.disabled(!request.editable || !node.canDeleteEmpty || hasDraft || request.deleteEmpty == nil)
                        Text(label("Deletion requires an empty tag without ID, Alt/ActualText or other internal references; page content is retained. Undo is available.","Удаляется только пустой тег без ID, Alt/ActualText и других внутренних ссылок; содержимое страницы сохраняется. Доступна отмена.")).font(.caption)
                        Text(hasDraft ? label("Apply field edits before changing the order.","Примените изменения полей перед перестановкой.") : label("Moves among sibling tags. Mixed lists of tags and content items are read-only.","Перемещает среди соседних тегов. Смешанные списки тегов и элементов содержимого доступны только для чтения.")).font(.caption)

                        Group {
                            TextField(label("Element title","Название элемента"),text: $elementTitle)
                            TextField(label("Element language, e.g. en-US","Язык элемента, например en-US"),text: $elementLanguage)
                            TextField(label("Expanded abbreviation (E)","Расшифровка сокращения (E)"),text: $expansion)
                            Text(label("An empty language inherits from ancestors or the document. Empty title/expansion removes the corresponding entry.","Пустой язык наследуется от предков или документа. Пустые название/расшифровка удаляют соответствующую запись.")).font(.caption)
                        }.disabled(!request.editable || node.objectID == nil || request.applyProperties == nil)
                        Text(label("Alternative text","Альтернативное описание"))
                        TextEditor(text: $alternative).frame(height: 100).disabled(!request.editable || node.objectID == nil)
                        Toggle(label("Use replacement text (ActualText)","Использовать замещающий текст (ActualText)"),isOn: $useActual).disabled(!request.editable || node.objectID == nil)
                        if useActual {
                            TextEditor(text: $actual).frame(height: 100).disabled(!request.editable || node.objectID == nil)
                            Text(label("Replaces this element and its children for extraction and assistive technologies. An empty value remains an explicit empty string. Prefer the smallest matching element.","Заменяет этот элемент и его потомков при извлечении текста и для вспомогательных технологий. Пустое значение сохраняется как явная пустая строка. Выбирайте наименьший подходящий элемент.")).font(.caption)
                        }
                    }
                }.frame(maxWidth: .infinity,alignment: .leading) }
            }.frame(height: 400)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button(label("Export report…","Экспорт отчёта…")) { export() }; Spacer(); Button(label("Close","Закрыть")) { dismiss() }; Button(label("Apply","Применить")) { applyEdits() }.disabled(!request.editable).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 850).sheet(isPresented: $choosingParent) {
            VStack(alignment: .leading,spacing: 16) {
                Text(label("New parent element","Новый родитель элемента")).font(.title2)
                Picker(label("Parent","Родитель"),selection: $parentSelection) { ForEach(parentChoices) { choice in Text(choice.title).tag(choice.id) } }
                Text(label("Moves the complete subtree to the end of the chosen parent's tag list. Inherited language and other properties can change. Content identifiers remain intact.","Переносит всё поддерево в конец списка тегов выбранного родителя. Наследуемый язык и другие свойства могут измениться. Идентификаторы содержимого сохраняются.")).font(.caption)
                if let error { Text(error).foregroundStyle(.orange) }
                HStack { Spacer(); Button(label("Cancel","Отмена")) { choosingParent = false }; Button(label("Move","Перенести")) { changeParent() }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 590)
        }.sheet(isPresented: $creatingContainer) {
            VStack(alignment: .leading,spacing: 16) {
                Text(label("Create Div container","Создать контейнер Div")).font(.title2)
                TextField(label("Title","Название"),text: $containerTitle)
                Text(label("Places the existing element and its complete subtree inside a new Div at the same logical position. Page content and content identifiers remain intact.","Помещает существующий элемент со всем поддеревом в новый Div на той же логической позиции. Содержимое страниц и идентификаторы сохраняются.")).font(.caption)
                if let error { Text(error).foregroundStyle(.orange) }
                HStack { Spacer(); Button(label("Cancel","Отмена")) { creatingContainer = false }; Button(label("Create","Создать")) { createContainer() }.keyboardShortcut(.defaultAction) }
            }.padding(24).frame(width: 590)
        }.onAppear { language = request.report.language }.onChange(of: selection) { _,_ in alternative = node?.alternative ?? ""; actual = node?.actual ?? ""; useActual = node?.hasActual ?? false; elementTitle = node?.title ?? ""; elementLanguage = node?.language ?? ""; expansion = node?.expansion ?? "" }
    }
    private struct ParentChoice: Identifiable { let id: Int,title: String }
    private var parentChoices: [ParentChoice] {
        guard let node,let index = request.report.nodes.firstIndex(where: { $0.id == node.id }) else { return [] }
        var descendants = Set<Int>(); descendants.insert(node.id)
        for next in request.report.nodes.dropFirst(index+1) { if next.depth <= node.depth { break }; descendants.insert(next.id) }
        var choices: [ParentChoice] = []
        if request.report.rootCanAcceptChildren,request.report.rootObjectID != node.parentObjectID { choices.append(ParentChoice(id: -1,title: label("Structure root","Корень структуры"))) }
        for candidate in request.report.nodes where candidate.canAcceptChildren && !descendants.contains(candidate.id) && candidate.objectID != node.parentObjectID {
            choices.append(ParentChoice(id: candidate.id,title: candidate.role+(candidate.title.isEmpty ? "" : " · "+candidate.title)))
        }
        return choices
    }
    private func createContainer() {
        guard let node,let wrap = request.wrap,!hasDraft else { return }
        error = wrap(node,containerTitle)
        if error == nil { creatingContainer = false; dismiss() }
    }
    private func changeParent() {
        guard let node,let reparent = request.reparent,parentChoices.contains(where: { $0.id == parentSelection }) else { return }
        let parent = parentSelection == -1 ? nil : request.report.nodes.first { $0.id == parentSelection }
        error = reparent(node,parent)
        if error == nil { choosingParent = false; dismiss() }
    }
    private var hasDraft: Bool {
        guard let node else { return language != request.report.language }
        return language != request.report.language || alternative != node.alternative || useActual != node.hasActual || (useActual && actual != node.actual) || elementTitle != node.title || elementLanguage != node.language || expansion != node.expansion
    }
    private func move(_ direction: Int) {
        guard let node,let reorder = request.reorder,!hasDraft else { return }
        error = reorder(node,direction); if error == nil { dismiss() }
    }
    private func applyEdits() {
        let change: PDFStructureTextChange = node?.objectID == nil ? .preserve : useActual ? .set(actual) : .remove
        if let apply = request.applyProperties {
            let properties = node?.objectID == nil ? PDFStructureProperties() : PDFStructureProperties(title: elementTitle,language: elementLanguage,expansion: expansion)
            error = apply(language,node,alternative,change,properties)
        } else { error = request.apply(language,node,alternative,change) }
        if error == nil { dismiss() }
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Accessibility.txt"
        panel.begin { response in
            guard response == .OK,let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let text = request.report.plainText
            do { try text.write(to: url,atomically: true,encoding: .utf8) } catch { self.error = error.localizedDescription }
        }
    }
}

indirect enum PDFVisibilityExpression: Equatable, Sendable {
    case group(Int), and([Self]), or([Self]), not(Self)
    var text: String {
        switch self {
        case .group(let id): return "#\(id)"
        case .and(let values): return "And("+values.map(\.text).joined(separator: ", ")+")"
        case .or(let values): return "Or("+values.map(\.text).joined(separator: ", ")+")"
        case .not(let value): return "Not("+value.text+")"
        }
    }
    func evaluate(_ states: [Int:Bool]) -> Bool {
        switch self {
        case .group(let id): states[id] ?? false
        case .and(let values): values.allSatisfy { $0.evaluate(states) }
        case .or(let values): values.contains { $0.evaluate(states) }
        case .not(let value): !value.evaluate(states)
        }
    }
    func pdfValue(generations: [Int:Int]) throws -> String {
        switch self {
        case .group(let id): guard let generation = generations[id] else { throw PDFSourceError.content }; return "\(id) \(generation) R"
        case .and(let values): return "[/And "+(try values.map { try $0.pdfValue(generations: generations) }.joined(separator: " "))+"]"
        case .or(let values): return "[/Or "+(try values.map { try $0.pdfValue(generations: generations) }.joined(separator: " "))+"]"
        case .not(let value): return "[/Not "+(try value.pdfValue(generations: generations))+"]"
        }
    }
    static func parse(_ text: String,allowed: Set<Int>) throws -> Self {
        struct Parser {
            let bytes: [UInt8],allowed: Set<Int>
            var at = 0,count = 0
            mutating func space() { while at < bytes.count,[9,10,13,32].contains(bytes[at]) { at += 1 } }
            mutating func value(_ depth: Int) throws -> PDFVisibilityExpression {
                space(); count += 1
                guard depth < 64,count <= 4096,at < bytes.count else { throw PDFSourceError.content }
                if bytes[at] == 35 {
                    at += 1; let start = at
                    while at < bytes.count,(48...57).contains(bytes[at]) { at += 1 }
                    guard at > start,let id = Int(String(decoding: bytes[start..<at],as: UTF8.self)),allowed.contains(id) else { throw PDFSourceError.content }
                    return .group(id)
                }
                let start = at
                while at < bytes.count,(65...90).contains(bytes[at]) || (97...122).contains(bytes[at]) { at += 1 }
                let op = String(decoding: bytes[start..<at],as: UTF8.self).lowercased(); space()
                guard ["and","or","not"].contains(op),at < bytes.count,bytes[at] == 40 else { throw PDFSourceError.content }; at += 1
                var values: [PDFVisibilityExpression] = []
                while true {
                    values.append(try value(depth+1)); space(); guard at < bytes.count else { throw PDFSourceError.content }
                    if bytes[at] == 41 { at += 1; break }
                    guard bytes[at] == 44 else { throw PDFSourceError.content }; at += 1
                }
                if op == "not" { guard values.count == 1 else { throw PDFSourceError.content }; return .not(values[0]) }
                return op == "and" ? .and(values) : .or(values)
            }
        }
        guard text.utf8.count <= 65536 else { throw PDFSourceError.content }
        var parser = Parser(bytes: Array(text.utf8),allowed: allowed)
        let value = try parser.value(0); parser.space()
        guard parser.at == parser.bytes.count else { throw PDFSourceError.content }
        if case .group = value { throw PDFSourceError.content }
        return value
    }
}
enum PDFMembershipPathPart: Hashable { case key(String), index(Int) }
struct PDFMembershipLocation: Equatable {
    let ownerID: Int,generation: Int,path: [PDFMembershipPathPart],fingerprint: String
}
struct PDFMembershipInfo: Identifiable {
    let id: Int,generation: Int,memberIDs: [Int],policy: String,expression: String?,editable: Bool
    var name = ""
    var directLocation: PDFMembershipLocation? = nil
    func title(russian: Bool) -> String { if !name.isEmpty { return name }; if let location = directLocation { return (russian ? "Встроенный OCMD · #" : "Inline OCMD · #")+String(location.ownerID) }; return "OCMD #\(id)" }
    func visible(states: [Int:Bool]) -> Bool? {
        if let expression { return (try? PDFVisibilityExpression.parse(expression,allowed: Set(states.keys)))?.evaluate(states) }
        if memberIDs.isEmpty { return true }
        let values = memberIDs.map { states[$0] ?? false }
        switch policy { case "AllOn": return values.allSatisfy { $0 }; case "AnyOn": return values.contains(true); case "AllOff": return values.allSatisfy { !$0 }; case "AnyOff": return values.contains(false); default: return nil }
    }
}
struct PDFMembershipConfiguration { let groups: [PDFLayerInfo],entries: [PDFMembershipInfo] }
struct PDFXObjectConditionTarget: Identifiable, Equatable {
    let pageIndex: Int,key: String,kind: String,objectID: Int,generation: Int,fingerprint: String,owned: Bool,conditionID: Int?,editable: Bool,reason: String
    var resourcePath: [String] = []
    var path: [String] { resourcePath.isEmpty ? [key] : resourcePath }
    var id: String { "\(pageIndex):"+path.map { "\($0.utf8.count):"+$0 }.joined() }
}
@MainActor struct PDFXObjectConditionRequest: Identifiable {
    let id = UUID(),russian: Bool,pageIndex: Int,targets: [PDFXObjectConditionTarget],entries: [PDFMembershipInfo]
    let apply: (PDFXObjectConditionTarget,PDFMembershipInfo?) -> String?
}
struct PDFXObjectConditionEditor: View {
    let request: PDFXObjectConditionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var conditionID: Int?
    @State private var error: String?
    private var target: PDFXObjectConditionTarget? { request.targets.first { $0.id == selection } }
    private var conditions: [PDFMembershipInfo] { request.entries.filter { $0.editable && $0.directLocation == nil } }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Image and Form visibility","Видимость изображений и Form")).font(.title2)
            Text(label("Page ","Страница ")+String(request.pageIndex+1)).font(.caption)
            List(selection: $selection) { ForEach(request.targets) { value in Text(value.kind+" · /"+value.path.joined(separator: " → /")+(value.owned ? " · OCMD" : "")+(value.editable ? "" : " ⚠︎")).tag(value.id) } }.frame(height: 250)
            Picker(label("Condition","Условие"),selection: $conditionID) {
                Text(label("Remove this app's assignment","Снять назначение этой программы")).tag(nil as Int?)
                ForEach(conditions) { entry in Text(entry.title(russian: request.russian)).tag(Optional(entry.id)) }
            }.disabled(target?.editable != true)
            Text(label("Affects every use of the selected resource path on this page. Copies of the Form chain isolate other resource paths and pages; source stream bytes are preserved. Removal restores the original leaf reference.","Действует на все использования выбранного пути ресурсов на странице. Копии цепочки Form изолируют другие пути и страницы; байты потоков сохраняются. Снятие восстанавливает ссылку на исходный конечный объект.")).font(.caption)
            Text(label("Root and nested Image/Form resources are supported. Tagged PDF, foreign OC and descendants of objects with existing OC remain read-only. Edit existing OCMD through the conditions inspector.","Поддержаны корневые и вложенные Image/Form. Tagged PDF, чужие OC и потомки объектов с существующим OC доступны только для просмотра. Существующий OCMD можно изменить в редакторе условий.")).font(.caption)
            if request.targets.isEmpty { Text(label("No supported XObject resources on this page.","На странице нет ресурсов XObject.")) }
            if let target,!target.reason.isEmpty { Text(target.reason).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let target else { return }; let condition = conditions.first { $0.id == conditionID }
                guard conditionID == nil || condition != nil else { return }; error = request.apply(target,condition); if error == nil { dismiss() }
            }.disabled(target?.editable != true).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 700).onAppear { selection = request.targets.first(where: \.editable)?.id ?? request.targets.first?.id; load() }.onChange(of: selection) { _,_ in load() }
    }
    private func load() { if let id = target?.conditionID,conditions.contains(where: { $0.id == id }) { conditionID = id } else { conditionID = conditions.first?.id }; error = nil }
}
@MainActor struct PDFMembershipBindingRequest: Identifiable {
    let id = UUID(),russian: Bool,pageCount: Int,currentPage: Int,selectedPages: [Int],entries: [PDFMembershipInfo]
    let apply: (PDFMembershipInfo?,[Int]) -> String?
}
struct PDFMembershipBindingEditor: View {
    let request: PDFMembershipBindingRequest
    @Environment(\.dismiss) private var dismiss
    @State private var conditionID: Int?
    @State private var range: String
    @State private var error: String?
    init(request: PDFMembershipBindingRequest) { self.request = request; _range = State(initialValue: String(request.currentPage+1)); _conditionID = State(initialValue: request.entries.first { $0.editable && $0.directLocation == nil }?.id) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(label("Page content visibility condition","Условие видимости содержимого страниц")).font(.title2)
            Picker(label("Condition","Условие"),selection: $conditionID) {
                Text(label("Remove BotPlus page assignment","Снять назначение BotPlus со страниц")).tag(nil as Int?)
                ForEach(request.entries.filter { $0.editable && $0.directLocation == nil }) { entry in Text(entry.title(russian: request.russian)).tag(Optional(entry.id)) }
            }
            TextField(label("Pages, e.g. 1, 3-5 or all","Страницы, например 1, 3-5 или все"),text: $range)
            HStack {
                Button(label("Current","Текущая")) { range = String(request.currentPage+1) }
                Button(label("Selected","Выбранные")) { range = request.selectedPages.map { String($0+1) }.joined(separator: ",") }.disabled(request.selectedPages.isEmpty)
                Button(label("All","Все")) { range = "all" }
            }
            Text(label("Applies to all original graphics/text on each selected page. Annotations remain independent. Existing inner visibility conditions still apply. Up to 512 pages per operation.","Применяется ко всему исходному тексту и графике каждой выбранной страницы. Аннотации остаются независимыми. Вложенные условия видимости сохраняются. До 512 страниц за операцию.")).font(.caption)
            Text(label("Reassignment replaces the outer condition without nesting more wrappers. Removal restores the original content sequence and removes only this app's assignment. Manually changed wrappers are protected.","Повторное назначение заменяет внешнее условие без вложения новых обёрток. Снятие восстанавливает исходную последовательность содержимого и удаляет только назначение этой программы. Вручную изменённые обёртки защищены.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let pages = PDFPageRange.parse(range,count: request.pageCount),pages.count <= 512 else { error = label("Check page range (maximum 512 pages).","Проверьте диапазон (максимум 512 страниц)."); return }
                let condition = conditionID.flatMap { id in request.entries.first { $0.id == id } }
                guard conditionID == nil || condition?.editable == true else { return }; error = request.apply(condition,pages); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 660)
    }
}
@MainActor struct PDFMembershipRequest: Identifiable {
    let id = UUID(),russian: Bool,editable: Bool,configuration: PDFMembershipConfiguration
    var create: ((String,[Int],String,String?) -> String?)? = nil
    let apply: (PDFMembershipInfo,[Int],String,String?) -> String?
}
struct PDFMembershipEditor: View {
    let request: PDFMembershipRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int?
    @State private var members = Set<Int>()
    @State private var policy = "AnyOn"
    @State private var useExpression = false
    @State private var expression = ""
    @State private var error: String?
    @State private var creating = false
    @State private var name = ""
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var entry: PDFMembershipInfo? { request.configuration.entries.first { $0.id == selection } }
    private var preview: String {
        let value = PDFMembershipInfo(id: 0,generation: 0,memberIDs: members.sorted(),policy: policy,expression: useExpression ? expression : nil,editable: true)
        let states = Dictionary(uniqueKeysWithValues: request.configuration.groups.map { ($0.id,$0.visible) })
        guard let visible = value.visible(states: states) else { return label("Invalid expression","Некорректное выражение") }
        return visible ? "ON" : "OFF"
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("Content visibility conditions (OCMD)","Условия видимости содержимого (OCMD)")).font(.title2)
            HStack {
                Button(label("New condition","Новое условие")) { creating = true; selection = nil; name = ""; members = []; policy = "AnyOn"; useExpression = false; expression = ""; error = nil }.disabled(!request.editable || request.create == nil || request.configuration.groups.isEmpty || request.configuration.entries.count >= 4096)
                if creating { TextField(label("Condition name","Название условия"),text: $name) }
                else if let entry,!entry.name.isEmpty { Text(entry.name).font(.headline) }
            }
            HStack(alignment: .top) {
                List(request.configuration.entries,selection: $selection) { value in
                    Text(value.title(russian: request.russian)+" · "+(value.expression == nil ? value.policy : "VE")+(value.editable ? "" : " ⚠︎")).tag(value.id)
                }.frame(width: 190,height: 350)
                VStack(alignment: .leading,spacing: 10) {
                    Picker(label("Mode","Режим"),selection: $useExpression) { Text(label("Group policy","Политика групп")).tag(false); Text(label("Expression VE","Выражение VE")).tag(true) }.pickerStyle(.segmented)
                    Picker(label("Policy P","Политика P"),selection: $policy) {
                        ForEach(["AnyOn","AllOn","AnyOff","AllOff"],id: \.self) { Text($0).tag($0) }
                        if !["AnyOn","AllOn","AnyOff","AllOff"].contains(policy) { Text(policy).tag(policy) }
                    }.disabled(useExpression)
                    ScrollView { VStack(alignment: .leading) { ForEach(request.configuration.groups) { group in
                        Toggle("#\(group.id) · "+group.name,isOn: Binding(get: { members.contains(group.id) },set: { if $0 { members.insert(group.id) } else { members.remove(group.id) } }))
                    } } }.frame(height: 120).disabled(useExpression)
                    TextEditor(text: $expression).font(.system(.body,design: .monospaced)).frame(height: 90).disabled(!useExpression)
                    Text("And(#7, Not(#8)) · Or(#7, #8)").font(.caption).textSelection(.enabled)
                    Text(label("Current base OCG states: ","Текущие базовые состояния OCG: ")+preview).font(.headline)
                    Text(label("VE overrides the group policy. Empty membership without VE has no visibility effect. Usage rules and viewer support can change rendering.","VE имеет приоритет над политикой групп. Пустой состав без VE не влияет на видимость. Правила Usage и поддержка просмотрщика могут изменить отображение.")).font(.caption)
                }.disabled((creating ? request.create == nil : entry?.editable != true) || !request.editable)
            }
            if request.configuration.entries.isEmpty { Text(label("No OCMD dictionaries found.","Словари OCMD не найдены.")) }
            if let location = entry?.directLocation { Text(label("Embedded in object ","Встроено в объект ")+String(location.ownerID)+label(". All uses of that dictionary share the edit. Stream data is retained.",". Изменение действует во всех использованиях этого словаря. Данные потоков сохраняются.")).font(.caption) }
            if creating { Text(label("The new condition is saved without affecting visibility until assigned. The name is stored as BotPlus metadata; the OCMD and its expression use standard PDF syntax.","Новое условие сохраняется и не влияет на видимость до назначения. Название хранится в метаданных BotPlus; сам OCMD и выражение используют стандартный синтаксис PDF.")).font(.caption) }
            if entry?.editable == false { Text(label("This dictionary contains unsupported references, policy or expression and is read-only.","В словаре есть неподдерживаемые ссылки, политика или выражение; доступен только просмотр.")).font(.caption) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Close","Закрыть")) { dismiss() }; Button(creating ? label("Create","Создать") : label("Apply","Применить")) {
                if creating { error = request.create?(name,members.sorted(),policy,useExpression ? expression : nil) }
                else { guard let entry else { return }; error = request.apply(entry,members.sorted(),policy,useExpression ? expression : nil) }; if error == nil { dismiss() }
            }.disabled((creating ? request.create == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : entry?.editable != true) || !request.editable).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 790).onChange(of: selection) { _,_ in load() }.onAppear { selection = request.configuration.entries.first?.id }
    }
    private func load() {
        guard let entry else { return }; creating = false; name = entry.name; members = Set(entry.memberIDs); policy = entry.policy; useExpression = entry.expression != nil
        expression = entry.expression ?? "And("+entry.memberIDs.map { "#\($0)" }.joined(separator: ", ")+")"; error = nil
    }
}

struct PDFLayerStateConfiguration: Identifiable, Equatable {
    let id: Int,name: String,base: String,intents: [String],on: [Int],off: [Int],locked: [Int],radios: [[Int]],editable: Bool
    var radiosInherited = false
    func states(previous: [Int:Bool]) -> [Int:Bool] {
        previous.mapValues { base == "Unchanged" ? $0 : base == "ON" }.merging(Dictionary(on.map { ($0,true) },uniquingKeysWith: { a,_ in a })) { _,new in new }.merging(Dictionary(off.map { ($0,false) },uniquingKeysWith: { a,_ in a })) { _,new in new }
    }
}
struct PDFLayerStateReport { let groups: [PDFLayerInfo],configurations: [PDFLayerStateConfiguration] }
struct PDFLayerOrderEntry: Identifiable, Equatable {
    let path: [Int],title: String,layerID: Int?,depth: Int,canMoveUp: Bool,canMoveDown: Bool
    var canRemove = false
    var id: String { path.map(String.init).joined(separator: ".") }
}
struct PDFLayerOrderConfiguration: Identifiable, Equatable {
    let id: Int,name: String,rootTitle: String,rows: [PDFLayerOrderEntry],inherited: Bool,editable: Bool
}
enum PDFLayerOrderOperation {
    case move([Int],Int), inherit
    case addSection([Int]?,String), renameSection([Int],String), addLayer([Int]?,Int), removeLeaf([Int])
    case reparent([Int],[Int]?)
}
@MainActor struct PDFLayerOrderRequest: Identifiable {
    let id = UUID(),russian: Bool,configurations: [PDFLayerOrderConfiguration]
    var layers: [PDFLayerInfo] = []
    let apply: (PDFLayerOrderConfiguration,PDFLayerOrderOperation) -> String?
}
struct PDFLayerOrderEditor: View {
    let request: PDFLayerOrderRequest
    @Environment(\.dismiss) private var dismiss
    @State private var configurationID = -1
    @State private var selection: String?
    @State private var error: String?
    @State private var sectionTitle = ""
    @State private var layerID: Int?
    @State private var insertInside = false
    @State private var parentChoice = ""
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var configuration: PDFLayerOrderConfiguration? { request.configurations.first { $0.id == configurationID } }
    private var entry: PDFLayerOrderEntry? { configuration?.rows.first { $0.id == selection } }
    private var eligibleParents: [PDFLayerOrderEntry] { guard let entry else { return [] }; return (configuration?.rows ?? []).filter { !$0.path.starts(with: entry.path) } }
    private var canReparent: Bool { guard let entry else { return false }; return parentChoice != entry.path.dropLast().map(String.init).joined(separator: ".") }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Layer presentation order","Порядок отображения слоёв")).font(.title2)
            ScrollView { VStack(alignment: .leading,spacing: 14) {
            Picker(label("Configuration","Конфигурация"),selection: $configurationID) {
                ForEach(request.configurations) { value in Text((value.id == -1 ? label("Default: ","Основная: ") : "")+(value.name.isEmpty ? "#\(value.id)" : value.name)).tag(value.id) }
            }
            if let configuration,!configuration.rootTitle.isEmpty { Text(configuration.rootTitle).font(.headline) }
            List(selection: $selection) { ForEach(configuration?.rows ?? []) { row in
                HStack { Image(systemName: row.layerID == nil ? "folder" : "square.3.layers.3d"); Text(row.title.isEmpty ? label("Unnamed","Без имени") : row.title) }.padding(.leading,CGFloat(row.depth)*16).tag(row.id)
            } }.frame(height: 260)
            HStack {
                Button(label("Move up","Выше")) { move(-1) }.disabled(entry?.canMoveUp != true || configuration?.editable != true)
                Button(label("Move down","Ниже")) { move(1) }.disabled(entry?.canMoveDown != true || configuration?.editable != true)
                Spacer()
                if configurationID != -1 { Button(label("Inherit default order","Наследовать порядок основной")) { perform(.inherit) }.disabled(configuration?.inherited != false || configuration?.editable != true) }
            }
            HStack {
                Picker(label("New parent","Новый родитель"),selection: $parentChoice) {
                    Text(label("Root level","Корневой уровень")).tag("")
                    ForEach(eligibleParents) { row in Text(String(repeating: "  ",count: row.depth)+(row.title.isEmpty ? label("Unnamed","Без имени") : row.title)).tag(row.id) }
                }
                Button(label("Move subtree","Перенести поддерево")) {
                    guard let entry else { return }
                    let parent = parentChoice.isEmpty ? nil : eligibleParents.first { $0.id == parentChoice }?.path
                    guard parentChoice.isEmpty || parent != nil else { return }; perform(.reparent(entry.path,parent))
                }.disabled(!canReparent)
            }.disabled(configuration?.editable != true || entry == nil)
            Text(label("A parent change moves the complete subtree to the end of the destination. Descendants cannot become its parent; visibility and page content remain unchanged.","При смене родителя всё поддерево добавляется в конец целевой группы. Потомок не может стать его родителем; видимость и содержимое страниц сохраняются.")).font(.caption)
            VStack(alignment: .leading,spacing: 10) {
                Toggle(label("Insert inside selected entry","Добавлять внутрь выбранного элемента"),isOn: $insertInside).disabled(entry == nil)
                Text(insertInside && entry != nil ? label("Destination: ","Куда: ")+(entry?.title ?? "") : label("Destination: root level","Куда: корневой уровень")).font(.caption)
                HStack {
                    TextField(label("Section title","Название раздела"),text: $sectionTitle)
                    Button(label("New section","Новый раздел")) { perform(.addSection(insertInside ? entry?.path : nil,sectionTitle)) }.disabled(sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(label("Rename section","Переименовать раздел")) { guard let entry else { return }; perform(.renameSection(entry.path,sectionTitle)) }.disabled(entry == nil || entry?.layerID != nil || sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Picker(label("Existing layer","Существующий слой"),selection: $layerID) {
                        Text(label("Choose layer","Выберите слой")).tag(nil as Int?)
                        ForEach(request.layers) { group in Text(group.name.isEmpty ? "OCG #\(group.id)" : group.name).tag(Optional(group.id)) }
                    }
                    Button(label("Add occurrence","Добавить вхождение")) { guard let layerID else { return }; perform(.addLayer(insertInside ? entry?.path : nil,layerID)) }.disabled(layerID == nil)
                    Button(label("Remove leaf entry","Удалить пустой элемент")) { guard let entry else { return }; perform(.removeLeaf(entry.path)) }.disabled(entry?.canRemove != true)
                }
                Text(label("Adds references to existing layers, including repeated occurrences. Removal affects only a leaf entry in this panel; the OCG, graphics and visibility remain. Move children out before removing a parent.","Добавляются ссылки на существующие слои, включая повторные вхождения. Удаляется только элемент панели без потомков; OCG, графика и видимость сохраняются. Перед удалением родителя перенесите его дочерние элементы.")).font(.caption)
            }.disabled(configuration?.editable != true)
            Text(label("Moves entries among siblings. A layer moves together with its child array. This changes the panel order, not page graphics or layer visibility. The selected configuration is not activated.","Элементы переставляются среди соседей. Слой перемещается вместе с дочерним массивом. Меняется порядок панели; графика страниц и видимость слоёв сохраняются. Выбранная конфигурация не активируется.")).font(.caption)
            if configuration?.inherited == true { Text(label("This order is inherited. Moving an entry creates an independent Order for this configuration.","Порядок наследуется. Перестановка создаст собственный Order этой конфигурации.")).font(.caption) }
            if configuration?.editable == false { Text(label("Unsupported or cyclic Order; editing is disabled.","Неподдерживаемый или циклический Order; редактирование отключено.")).foregroundStyle(.orange) }
            } }.frame(maxHeight: 650)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Close","Закрыть")) { dismiss() } }
        }.padding(24).frame(width: 780,height: 780).onAppear { configurationID = request.configurations.first?.id ?? -1 }.onChange(of: configurationID) { _,_ in selection = nil; sectionTitle = ""; parentChoice = ""; error = nil }.onChange(of: selection) { _,_ in if entry?.layerID == nil { sectionTitle = entry?.title ?? "" }; parentChoice = entry?.path.dropLast().map(String.init).joined(separator: ".") ?? "" }
    }
    private func move(_ direction: Int) { guard let entry else { return }; perform(.move(entry.path,direction)) }
    private func perform(_ operation: PDFLayerOrderOperation) { guard let configuration else { return }; error = request.apply(configuration,operation); if error == nil { dismiss() } }
}
@MainActor struct PDFLayerRadioRequest: Identifiable {
    let id = UUID(),russian: Bool,report: PDFLayerStateReport
    let apply: (PDFLayerStateConfiguration,[[Int]]?) -> String?
}
struct PDFLayerRadioEditor: View {
    let request: PDFLayerRadioRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selectedConfiguration = -1
    @State private var selectedGroup: Int?
    @State private var groups: [[Int]] = []
    @State private var inherited = false
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var configuration: PDFLayerStateConfiguration? { request.report.configurations.first { $0.id == selectedConfiguration } }
    private var canEditMembers: Bool { selectedGroup.map { groups.indices.contains($0) } == true }
    private func summary(_ members: [Int]) -> String { members.map { id in request.report.groups.first { $0.id == id }?.name ?? "#\(id)" }.joined(separator: ", ") }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Mutually exclusive layer groups","Группы взаимоисключающих слоёв")).font(.title2)
            Picker(label("Configuration","Конфигурация"),selection: $selectedConfiguration) {
                ForEach(request.report.configurations) { entry in Text((entry.id == -1 ? label("Default: ","Основная: ") : "")+(entry.name.isEmpty ? "#\(entry.id)" : entry.name)).tag(entry.id) }
            }
            if selectedConfiguration != -1 { Toggle(label("Inherit groups from the default configuration","Наследовать группы основной конфигурации"),isOn: $inherited).disabled(configuration?.editable != true) }
            HStack(alignment: .top) {
                VStack {
                    List(selection: $selectedGroup) { ForEach(Array(groups.indices),id: \.self) { index in
                        VStack(alignment: .leading) { Text(label("Group ","Группа ")+String(index+1)); Text(summary(groups[index])).font(.caption).lineLimit(2) }.tag(index)
                    } }.frame(width: 260,height: 280)
                    HStack {
                        Button(label("Add","Добавить")) { groups.append([]); selectedGroup = groups.count-1; error = nil }.disabled(groups.count >= 1000)
                        Button(label("Remove","Удалить")) { guard let index = selectedGroup,groups.indices.contains(index) else { return }; groups.remove(at: index); selectedGroup = groups.isEmpty ? nil : min(index,groups.count-1); error = nil }.disabled(!canEditMembers)
                    }
                }
                ScrollView { VStack(alignment: .leading,spacing: 10) {
                    ForEach(request.report.groups) { group in
                        Toggle(group.name.isEmpty ? "OCG #\(group.id)" : group.name,isOn: Binding(get: {
                            guard let index = selectedGroup,groups.indices.contains(index) else { return false }; return groups[index].contains(group.id)
                        },set: { value in
                            guard let index = selectedGroup,groups.indices.contains(index) else { return }; groups[index].removeAll { $0 == group.id }; if value { groups[index].append(group.id) }; error = nil
                        }))
                    }
                } }.frame(maxWidth: .infinity).frame(height: 310).disabled(!canEditMembers)
            }.disabled(configuration?.editable != true || inherited)
            Text(label("At most one layer in each group can be ON; all may be OFF. Groups may overlap. Create groups with at least two layers. Empty list explicitly disables radio groups in this configuration.","В каждой группе включён максимум один слой; все могут быть выключены. Группы могут пересекаться. Создавайте группы минимум из двух слоёв. Пустой список явно отключает радиогруппы этой конфигурации.")).font(.caption)
            Text(label("This edits relationships without changing visibility or activating a preset. First resolve conflicting ON states using the visibility editor. Default edits also check alternative configurations that inherit these groups.","Меняются связи без изменения видимости и активации конфигурации. Конфликтующие ON сначала исправьте в редакторе видимости. При изменении основной проверяются также наследующие её альтернативы.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let configuration else { return }
                guard inherited || groups.allSatisfy({ $0.count >= 2 }) else { error = label("Each group needs at least two layers.","В каждой группе должно быть минимум два слоя."); return }
                error = request.apply(configuration,inherited ? nil : groups); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction).disabled(configuration?.editable != true) }
        }.padding(24).frame(width: 760).onAppear { selectedConfiguration = request.report.configurations.first?.id ?? -1; load() }.onChange(of: selectedConfiguration) { _,_ in load() }
    }
    private func load() { guard let configuration else { return }; groups = configuration.radios; inherited = configuration.radiosInherited; selectedGroup = groups.isEmpty ? nil : 0; error = nil }
}
@MainActor struct PDFLayerStateRequest: Identifiable {
    let id = UUID(),russian: Bool,report: PDFLayerStateReport
    var applyWithLocks: ((PDFLayerStateConfiguration,String,[String],[Int],[Int],[Int]) -> String?)? = nil
    let apply: (PDFLayerStateConfiguration,String,[String],[Int],[Int]) -> String?
}
struct PDFLayerStateEditor: View {
    let request: PDFLayerStateRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selected = -1
    @State private var base = "ON"
    @State private var intents = "View"
    @State private var states: [Int:Int] = [:]
    @State private var locks = Set<Int>()
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var configuration: PDFLayerStateConfiguration? { request.report.configurations.first { $0.id == selected } }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("Configuration visibility and intent","Видимость и Intent конфигурации")).font(.title2)
            Picker(label("Configuration","Конфигурация"),selection: $selected) {
                ForEach(request.report.configurations) { entry in Text((entry.id == -1 ? label("Default: ","Основная: ") : "")+(entry.name.isEmpty ? "#\(entry.id)" : entry.name)).tag(entry.id) }
            }
            VStack(alignment: .leading,spacing: 10) {
                Picker("BaseState",selection: $base) { Text("ON").tag("ON"); if selected != -1 { Text("OFF").tag("OFF"); Text("Unchanged").tag("Unchanged") } }.disabled(selected == -1)
                Text(label("Intent names, one per line","Имена Intent, по одному на строке")).font(.caption)
                TextEditor(text: $intents).font(.system(.body,design: .monospaced)).frame(height: 60).disabled(selected == -1)
                ScrollView { VStack(spacing: 7) { ForEach(request.report.groups) { group in
                    HStack { Text("#\(group.id) · "+group.name).frame(maxWidth: .infinity,alignment: .leading)
                        Picker("",selection: Binding(get: { states[group.id] ?? -1 },set: { states[group.id] = $0 })) { Text(label("Base","Базовое")).tag(-1); Text("ON").tag(1); Text("OFF").tag(0) }.labelsHidden().frame(width: 170).disabled(configuration?.locked.contains(group.id) == true)
                        Toggle(label("Locked","Блокировка"),isOn: Binding(get: { locks.contains(group.id) },set: { if $0 { locks.insert(group.id) } else { locks.remove(group.id) } })).disabled(request.applyWithLocks == nil)
                    }
                } } }.frame(height: 230)
            }.disabled(configuration?.editable != true)
            Text(label("The default uses BaseState ON and Intent View. Alternative configurations can use OFF/Unchanged and other intents. ON/OFF lists override BaseState. Locked states and radio groups are checked; Usage, hierarchy and other keys are retained.","Основная использует BaseState ON и Intent View. Альтернативные конфигурации допускают OFF/Unchanged и другие Intent. Списки ON/OFF переопределяют BaseState. Проверяются Locked и радиогруппы; Usage, иерархия и прочие ключи сохраняются.")).font(.caption)
            Text(label("Locks belong to the selected configuration. To change a locked state, apply its unlock first, then reopen this editor. This is an interface rule, not access control.","Блокировки относятся к выбранной конфигурации. Чтобы изменить заблокированное состояние, сначала примените разблокировку и откройте редактор снова. Это правило интерфейса, а не защита доступа.")).font(.caption)
            if configuration?.editable == false { Text(label("Unsupported or noncanonical configuration; read-only.","Неподдерживаемая или неканоническая конфигурация; только просмотр.")).foregroundStyle(.orange) }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Close","Закрыть")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let configuration else { return }
                let names = intents.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                let on = states.filter { $0.value == 1 }.map(\.key).sorted(),off = states.filter { $0.value == 0 }.map(\.key).sorted()
                if let apply = request.applyWithLocks { error = apply(configuration,base,names,on,off,locks.sorted()) }
                else { error = request.apply(configuration,base,names,on,off) }; if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction).disabled(configuration?.editable != true) }
        }.padding(24).frame(width: 720).onAppear { selected = request.report.configurations.first?.id ?? -1; load() }.onChange(of: selected) { _,_ in load() }
    }
    private func load() {
        guard let configuration else { return }; base = configuration.base; intents = configuration.intents.joined(separator: "\n")
        states = Dictionary(uniqueKeysWithValues: request.report.groups.map { ($0.id,configuration.on.contains($0.id) ? 1 : configuration.off.contains($0.id) ? 0 : -1) }); locks = Set(configuration.locked); error = nil
    }
}

struct PDFLayerExtendedUsage: Equatable, Sendable {
    var exportState: Bool?
    var zoomEnabled = false
    var minZoom: Double?,maxZoom: Double?
    var language = ""
    var preferred: Bool?
    // nil keeps descriptive categories untouched for older callers.
    var metadata: PDFLayerUsageMetadata? = nil
    var valid: Bool {
        guard language.count <= 80,language.isEmpty || language.range(of: #"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"#,options: .regularExpression) != nil else { return false }
        if zoomEnabled {
            guard [minZoom,maxZoom].compactMap({ $0 }).allSatisfy({ $0.isFinite && (0...10000).contains($0) && ($0 == 0 || $0 >= 1e-8) }) else { return false }
            if let maximum = maxZoom,maximum < (minZoom ?? 0) { return false }
        }
        return metadata?.valid ?? true
    }
}

struct PDFLayerUsageMetadata: Equatable, Sendable {
    var creatorEnabled = false
    var creator = ""
    var creatorSubtype = "Technical"
    var userType = ""
    var userNames: [String] = []
    var pageElement = ""
    var printSubtype = ""
    static func validName(_ value: String) -> Bool { !value.isEmpty && value.utf8.count <= 256 && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }
    static func encodedName(_ value: String) -> Data {
        Data(("/"+value.utf8.map { (33...126).contains($0) && !Array("()<>[]{}/%#".utf8).contains($0) ? String(UnicodeScalar($0)) : String(format: "#%02X",$0) }.joined()).utf8)
    }
    var valid: Bool {
        if creatorEnabled && (creator.isEmpty || creator.utf16.count > 4096 || !Self.validName(creatorSubtype)) { return false }
        guard ["","Ind","Ttl","Org"].contains(userType),["","HF","FG","BG","L"].contains(pageElement),printSubtype.isEmpty || Self.validName(printSubtype) else { return false }
        return userType.isEmpty || (!userNames.isEmpty && userNames.count <= 256 && userNames.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 4096 })
    }
}


struct PDFFormResourceTransformOptions {
    var x = 0.0
    var y = 0.0
    var scaleX = 1.0
    var scaleY = 1.0
    var degrees = 0.0
    var centered = true
    var linear: CGAffineTransform? {
        guard [x,y].allSatisfy({ $0.isFinite && abs($0) <= 10000 }),[scaleX,scaleY].allSatisfy({ $0.isFinite && (0.1...10).contains($0) }),degrees.isFinite,(-360...360).contains(degrees) else { return nil }
        let radians = degrees*Double.pi/180,quarter = degrees/90,orthogonal = abs(quarter-quarter.rounded()) < 1e-10
        let cosine = orthogonal ? cos(radians).rounded() : cos(radians),sine = orthogonal ? sin(radians).rounded() : sin(radians)
        return CGAffineTransform(a: scaleX*cosine,b: scaleX*sine,c: -scaleY*sine,d: scaleY*cosine,tx: 0,ty: 0)
    }
    var isIdentity: Bool { linear == .identity && x == 0 && y == 0 }
}
@MainActor struct PDFFormResourceTransformRequest: Identifiable {
    let id = UUID(),russian: Bool,pageIndex: Int,targets: [PDFXObjectConditionTarget]
    let apply: (PDFXObjectConditionTarget,PDFFormResourceTransformOptions) -> String?
}
struct PDFFormResourceTransformEditor: View {
    let request: PDFFormResourceTransformRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?
    @State private var options = PDFFormResourceTransformOptions()
    @State private var error: String?
    private var target: PDFXObjectConditionTarget? { request.targets.first { $0.id == selection } }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("Independent Form resource transform","Независимое преобразование Form")).font(.title2)
            Text(label("Page ","Страница ")+String(request.pageIndex+1)).font(.caption)
            List(selection: $selection) { ForEach(request.targets) { value in Text("/"+value.path.joined(separator: " → /")+(value.editable && !value.owned ? "" : " ⚠︎")).tag(value.id) } }.frame(height: 180)
            HStack { TextField("X, pt",value: $options.x,format: .number); TextField("Y, pt",value: $options.y,format: .number) }
            HStack { TextField(label("Scale X","Масштаб X"),value: $options.scaleX,format: .number); TextField(label("Scale Y","Масштаб Y"),value: $options.scaleY,format: .number) }
            TextField(label("Angle, degrees","Угол, градусы"),value: $options.degrees,format: .number)
            Toggle(label("Rotate/scale around transformed BBox center","Поворот/масштаб относительно центра BBox"),isOn: $options.centered)
            Text(label("Coordinates are in the containing resource space. Every use of this path on this page changes; copies of the Form chain isolate other names and pages. Source streams, clipping and transparency groups are retained. Tagged PDF and existing OC assignments remain read-only.","Координаты заданы в пространстве родительского ресурса. Меняются все использования выбранного пути на странице; копии цепочки Form изолируют другие имена и страницы. Потоки, обрезка и группы прозрачности сохраняются. Tagged PDF и существующие OC доступны только для просмотра.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) {
                guard let target else { return }; error = request.apply(target,options); if error == nil { dismiss() }
            }.disabled(target?.editable != true || target?.owned != false).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 720).onAppear { selection = request.targets.first { $0.editable && !$0.owned }?.id }.onChange(of: selection) { _,_ in options = PDFFormResourceTransformOptions(); error = nil }
    }
}
