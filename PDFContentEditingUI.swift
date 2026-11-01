// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (c) 2026 BotPlus
import SwiftUI
import AppKit

@MainActor
final class PDFContentPropertiesModel: ObservableObject {
    @Published var active = false
    @Published var kind = "path"
    @Published var x: CGFloat = 0
    @Published var y: CGFloat = 0
    @Published var width: CGFloat = 1
    @Published var height: CGFloat = 1
    @Published var rotation: CGFloat = 0
    @Published var stroke = Color.black
    @Published var fill = Color.black
    @Published var strokeEnabled = true
    @Published var fillEnabled = false
    @Published var lineWidth: CGFloat = 1
    @Published var opacity: CGFloat = 1
    var styleChanged = false
    var strokeChanged = false,fillChanged = false,opacityChanged = false
    @Published var opacitySupported = true
    var apply: (() -> Void)?
    var delete: (() -> Void)?
    var replace: (() -> Void)?
    var editNodes: (() -> Void)?
    var arrange: ((Int) -> Void)?
    func load(_ object: PDFSourceSession.ContentObject) {
        active = true; kind = object.kind; geometry(object.bounds)
        rotation = 0; stroke = Color(nsColor: object.stroke ?? .black); fill = Color(nsColor: object.fill ?? .black)
        strokeEnabled = object.strokeEnabled; fillEnabled = object.fillEnabled
        lineWidth = object.lineWidth; opacity = object.opacity; styleChanged = false
        strokeChanged = false; fillChanged = false; opacityChanged = false
        opacitySupported = !(object.kind == "path" && ((object.fillEnabled && object.fill == nil) || (object.strokeEnabled && object.stroke == nil)))
    }
    func geometry(_ rect: CGRect) { x = rect.minX; y = rect.minY; width = rect.width; height = rect.height }
    var bounds: CGRect { CGRect(x: x,y: y,width: width,height: height) }
    var style: PDFContentSession.Style? {
        guard styleChanged else { return nil }
        return .init(stroke: NSColor(stroke),fill: NSColor(fill),width: lineWidth,opacity: opacity,strokeEnabled: strokeEnabled,fillEnabled: fillEnabled,editStroke: strokeChanged,editFill: fillChanged,editOpacity: opacityChanged)
    }
    func reset() { active = false; apply = nil; delete = nil; replace = nil; editNodes = nil; arrange = nil }
}

struct PDFContentPropertiesView: View {
    @ObservedObject var model: PDFContentPropertiesModel
    let russian: Bool
    private func text(_ en: String,_ ru: String) -> String { russian ? ru : en }
    private func style<Value>(_ key: ReferenceWritableKeyPath<PDFContentPropertiesModel,Value>) -> Binding<Value> {
        Binding(get: { model[keyPath: key] },set: { model[keyPath: key] = $0; model.styleChanged = true })
    }
    private func metric(_ label: String,_ binding: Binding<CGFloat>) -> some View {
        HStack {
            Text(label).font(.system(size: 10)); Spacer()
            TextField("",value: Binding(get: { Double(binding.wrappedValue) },set: { binding.wrappedValue = CGFloat($0) }),format: .number.precision(.fractionLength(0...2))).textFieldStyle(.roundedBorder).frame(width: 82)
        }
    }
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            Text(text("Content object","Объект содержимого")).font(.headline)
            Text(model.kind == "image" ? text("Image","Изображение") : model.kind == "path" ? text("Vector path","Векторный контур") : model.kind == "group" ? text("PDF group (entire instance)","Группа PDF (целиком)") : model.kind == "text" ? text("Text object","Текстовый объект") : text("Shading","Градиент"))
            metric("X, pt",$model.x); metric("Y, pt",$model.y)
            metric(text("Width, pt","Ширина, pt"),$model.width)
            metric(text("Height, pt","Высота, pt"),$model.height)
            metric(text("Rotate by, °","Повернуть на, °"),$model.rotation)
            if model.kind == "path" {
                Divider()
                Toggle(text("Stroke","Линия"),isOn: style(\.strokeEnabled))
                ColorPicker(text("Stroke color","Цвет линии"),selection: Binding(get: { model.stroke },set: { model.stroke = $0; model.styleChanged = true; model.strokeChanged = true }),supportsOpacity: false)
                metric(text("Thickness, pt","Толщина, pt"),style(\.lineWidth))
                Toggle(text("Fill","Заливка"),isOn: style(\.fillEnabled))
                ColorPicker(text("Fill color","Цвет заливки"),selection: Binding(get: { model.fill },set: { model.fill = $0; model.styleChanged = true; model.fillChanged = true }),supportsOpacity: false)
            } else if model.kind == "text" {
                ColorPicker(text("Color","Цвет"),selection: Binding(get: { model.fill },set: { model.fill = $0; model.styleChanged = true; model.fillChanged = true }),supportsOpacity: false)
                Text(text("For typing, use Edit PDF Text.","Для ввода текста используйте «Редактировать текст».")).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if ["path","text","image"].contains(model.kind) && model.opacitySupported {
                Slider(value: Binding(get: { model.opacity },set: { model.opacity = $0; model.styleChanged = true; model.opacityChanged = true }),in: 0...1) { Text(text("Opacity","Непрозрачность")) }
                Text(text("Opacity: ","Непрозрачность: ")+String(Int((model.opacity*100).rounded()))+"%").font(.system(size: 10))
            }
            HStack {
                Button(text("Apply","Применить")) { model.apply?() }
                Button(text("Delete","Удалить")) { model.delete?() }
            }
            Menu(text("Arrange", "Порядок наложения")) {
                Button(text("Bring to front", "На передний план")) { model.arrange?(2) }
                Button(text("Bring forward", "Вперёд")) { model.arrange?(1) }
                Button(text("Send backward", "Назад")) { model.arrange?(-1) }
                Button(text("Send to back", "На задний план")) { model.arrange?(-2) }
            }
            if model.kind == "path" { Button(text("Edit nodes…", "Редактировать узлы…")) { model.editNodes?() } }
            if model.kind == "image" { Button(text("Replace image…","Заменить изображение…")) { model.replace?() } }
            if model.kind == "group" { Text(text("Children of shared XObjects remain intact. The group is transformed as one object.","Дочерние элементы общего XObject сохраняются. Группа преобразуется как один объект.")).font(.system(size: 10)).foregroundStyle(.secondary) }
            Text(text("Drag inside to move, corners to resize, circle above to rotate.","Внутри рамки — перемещение, углы — размер, круг сверху — поворот.")).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
