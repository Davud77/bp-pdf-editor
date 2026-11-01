// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import PDFKit

@MainActor struct PDFRegionRequest: Identifiable {
    let id = UUID()
    let page: PDFPage, region: CGRect, russian: Bool
    let apply: (CGRect) -> String?
}
struct PDFRegionEditor: View {
    let request: PDFRegionRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PageGeometryOptions()
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    private var region: CGRect {
        let box = request.page.bounds(for: .cropBox),factor = options.unit.factor
        return CGRect(x: box.minX+options.left*factor,y: box.minY+options.bottom*factor,width: box.width-(options.left+options.right)*factor,height: box.height-(options.top+options.bottom)*factor)
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 14) {
            Text(label("Snapshot region","Область снимка")).font(.title2)
            HStack(spacing: 20) {
                Form {
                    Picker(label("Units","Единицы"),selection: $options.unit) { ForEach(PageGeometryUnit.allCases) { Text($0.title).tag($0) } }
                    number(label("Left inset","Отступ слева"),$options.left)
                    number(label("Right inset","Отступ справа"),$options.right)
                    number(label("Top inset","Отступ сверху"),$options.top)
                    number(label("Bottom inset","Отступ снизу"),$options.bottom)
                    Text(String(format: "X %.2f · Y %.2f pt\n%.2f × %.2f pt",region.minX,region.minY,region.width,region.height)).font(.caption).monospacedDigit()
                    Button(label("Entire page","Вся страница")) { options.left = 0; options.right = 0; options.top = 0; options.bottom = 0 }
                    Button(label("Original selection","Исходное выделение")) { load(request.region) }
                }.frame(width: 250)
                InteractiveCropPreview(page: request.page,options: $options,displayBox: .cropBox).frame(width: 430,height: 440)
            }
            Text(label("Drag the frame or its handles. Only the snapshot region changes; page geometry stays intact.","Перемещайте рамку и её ручки. Меняется только область снимка, размеры страницы сохраняются.")).font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Capture","Сделать снимок")) {
                let margins = [options.left,options.right,options.top,options.bottom]
                guard margins.allSatisfy({ $0.isFinite && $0 >= 0 }),region.width >= 1,region.height >= 1 else { error = label("Choose a region of at least 1 × 1 pt.","Выберите область размером хотя бы 1 × 1 pt."); return }
                error = request.apply(region); if error == nil { dismiss() }
            }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 760).onAppear { load(request.region) }.onChange(of: options.unit) { old,new in
            let ratio = old.factor/new.factor
            options.left *= ratio; options.right *= ratio; options.top *= ratio; options.bottom *= ratio
        }
    }
    private func number(_ label: String,_ value: Binding<Double>) -> some View { TextField(label,value: value,format: .number.precision(.fractionLength(0...3))) }
    private func load(_ requested: CGRect) {
        let box = request.page.bounds(for: .cropBox),clipped = requested.intersection(box),factor = options.unit.factor
        let rect = clipped.isNull || clipped.isEmpty ? box : clipped
        options.left = (rect.minX-box.minX)/factor; options.right = (box.maxX-rect.maxX)/factor
        options.top = (box.maxY-rect.maxY)/factor; options.bottom = (rect.minY-box.minY)/factor
    }
}
