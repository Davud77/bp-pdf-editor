// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import PDFKit
import Vision
import CoreText
import SwiftUI
import AppKit

struct PDFOCRLine: Identifiable, Sendable {
    let id = UUID()
    var text: String, bounds: CGRect
    var confidence: Float = 1, selected = true
}
struct PDFOCREditPage: Identifiable, Sendable {
    var id: Int { index }
    let index: Int, mediaBox: CGRect, rasterToPage: CGAffineTransform
    var lines: [PDFOCRLine]
}
struct PDFOCRResult: Sendable { let layer: Data, pages: [Int], lines: Int, review: [PDFOCREditPage] }
enum PDFOCREngine {
    static func valid(pages: [PDFOCREditPage]) -> Bool {
        let active = pages.filter { $0.lines.contains { $0.selected && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return !active.isEmpty && active.count <= 1000 && Set(active.map(\.index)).count == active.count && active.allSatisfy { page in
            page.index >= 0 && page.lines.count <= 5000 && page.mediaBox.width > 0 && page.mediaBox.height > 0 &&
            [page.mediaBox.minX,page.mediaBox.minY,page.mediaBox.width,page.mediaBox.height,page.rasterToPage.a,page.rasterToPage.b,page.rasterToPage.c,page.rasterToPage.d,page.rasterToPage.tx,page.rasterToPage.ty].allSatisfy(\.isFinite) &&
            page.lines.filter { $0.selected && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.allSatisfy { line in
                line.text.utf16.count <= 20000 && line.bounds.width > 0 && line.bounds.height > 0 && [line.bounds.minX,line.bounds.minY,line.bounds.width,line.bounds.height].allSatisfy { $0.isFinite && abs($0) <= 1e8 }
            }
        }
    }
    static func recognize(data: Data,indices: [Int],languages: [String],dpi: Int,progress: @Sendable (Double) -> Void) throws -> PDFOCRResult {
        guard let document = PDFDocument(data: data),(72...300).contains(dpi),!indices.isEmpty else { throw PDFSourceError.document }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
        let supported = try request.supportedRecognitionLanguages()
        guard !languages.isEmpty,languages.allSatisfy(supported.contains) else { throw PDFSourceError.content }; request.recognitionLanguages = languages
        var pages: [PDFOCREditPage] = []
        for (offset,index) in indices.enumerated() {
            try Task.checkCancellation()
            let recognized: PDFOCREditPage = try autoreleasepool {
                guard let page = document.page(at: index),let reference = page.pageRef else { throw PDFSourceError.page }
                let box = page.bounds(for: .cropBox),factor = CGFloat(dpi)/72,rotated = page.rotation%180 != 0
                let width = Int(ceil((rotated ? box.height : box.width)*factor)),height = Int(ceil((rotated ? box.width : box.height)*factor))
                guard width > 0,height > 0,width <= 20000,height <= 20000,Double(width)*Double(height) <= 40_000_000,
                      let raster = CGContext(data: nil,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width*4,space: CGColorSpaceCreateDeviceRGB(),bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PDFSourceError.content }
                let canvas = CGRect(x: 0,y: 0,width: width,height: height)
                raster.setFillColor(CGColor(gray: 1,alpha: 1)); raster.fill(canvas)
                let transform = PDFFormattingGeometry.transform(page,box: .cropBox,target: canvas)
                raster.concatenate(transform); raster.drawPDFPage(reference)
                guard let image = raster.makeImage() else { throw PDFSourceError.content }
                try VNImageRequestHandler(cgImage: image,options: [:]).perform([request]); try Task.checkCancellation()
                let lines = (request.results ?? []).prefix(5000).compactMap { observation -> PDFOCRLine? in
                    guard let candidate = observation.topCandidates(1).first,!candidate.string.isEmpty else { return nil }
                    let n = observation.boundingBox,rect = CGRect(x: n.minX*CGFloat(width),y: n.minY*CGFloat(height),width: n.width*CGFloat(width),height: n.height*CGFloat(height))
                    guard rect.width > 0,rect.height > 0 else { return nil }
                    return PDFOCRLine(text: candidate.string,bounds: rect,confidence: candidate.confidence)
                }
                return PDFOCREditPage(index: index,mediaBox: page.bounds(for: .mediaBox),rasterToPage: transform.inverted(),lines: lines)
            }
            pages.append(recognized); progress(Double(offset+1)/Double(indices.count))
        }
        if !pages.contains(where: { !$0.lines.isEmpty }) { return PDFOCRResult(layer: Data(),pages: indices,lines: 0,review: pages) }
        return try render(pages: pages)
    }
    static func render(pages: [PDFOCREditPage]) throws -> PDFOCRResult {
        guard valid(pages: pages) else { throw PDFSourceError.content }
        let active = pages.filter { $0.lines.contains { $0.selected && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        guard !active.isEmpty,active.count <= 1000 else { throw PDFSourceError.content }
        let storage = NSMutableData()
        guard let consumer = CGDataConsumer(data: storage) else { throw PDFSourceError.save }
        var initial = CGRect(x: 0,y: 0,width: 612,height: 792)
        guard let output = CGContext(consumer: consumer,mediaBox: &initial,nil) else { throw PDFSourceError.save }
        var count = 0
        for page in active {
            try Task.checkCancellation()
            guard page.lines.count <= 5000,page.mediaBox.width > 0,page.mediaBox.height > 0,
                  [page.mediaBox.minX,page.mediaBox.minY,page.mediaBox.width,page.mediaBox.height,page.rasterToPage.a,page.rasterToPage.b,page.rasterToPage.c,page.rasterToPage.d,page.rasterToPage.tx,page.rasterToPage.ty].allSatisfy(\.isFinite) else { throw PDFSourceError.content }
            var media = page.mediaBox
            let mediaData = NSData(bytes: &media,length: MemoryLayout<CGRect>.size)
            output.beginPDFPage([kCGPDFContextMediaBox as String:mediaData] as CFDictionary)
            output.saveGState(); output.concatenate(page.rasterToPage); output.textMatrix = .identity
            for entry in page.lines where entry.selected && !entry.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let rect = entry.bounds
                guard entry.text.utf16.count <= 20000,rect.width > 0,rect.height > 0,
                      [rect.minX,rect.minY,rect.width,rect.height].allSatisfy({ $0.isFinite && abs($0) <= 1e8 }) else { throw PDFSourceError.content }
                let font = CTFontCreateWithName("Helvetica" as CFString,max(2,rect.height*0.8),nil)
                let text = NSAttributedString(string: entry.text,attributes: [NSAttributedString.Key(kCTFontAttributeName as String):font])
                let line = CTLineCreateWithAttributedString(text)
                var ascent: CGFloat = 0,descent: CGFloat = 0
                let advance = CTLineGetTypographicBounds(line,&ascent,&descent,nil)
                guard advance > 0 else { continue }
                output.saveGState(); output.translateBy(x: rect.minX,y: rect.minY+descent); output.scaleBy(x: rect.width/advance,y: 1)
                output.textPosition = .zero; output.setTextDrawingMode(.invisible); CTLineDraw(line,output); output.restoreGState(); count += 1
            }
            output.restoreGState(); output.endPDFPage()
        }
        output.closePDF(); guard count > 0 else { throw PDFSourceError.content }
        return PDFOCRResult(layer: storage as Data,pages: active.map(\.index),lines: count,review: pages)
    }
}
@MainActor struct PDFOCRReviewRequest: Identifiable {
    let id = UUID(), russian: Bool, dpi: Int
    let source: Data, pages: [PDFOCREditPage]
    let apply: ([PDFOCREditPage]) -> String?
}
struct PDFOCRReviewPanel: View {
    let request: PDFOCRReviewRequest
    @Environment(\.dismiss) private var dismiss
    @State private var pages: [PDFOCREditPage]
    @State private var index = 0
    @State private var focused: UUID?
    @State private var source: PDFDocument?
    @State private var error: String?
    init(request: PDFOCRReviewRequest) { self.request = request; _pages = State(initialValue: request.pages) }
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(label("Review recognized text","Проверка распознанного текста")).font(.title2)
            Picker(label("Page","Страница"),selection: $index) { ForEach(pages.indices,id: \.self) { Text(String(pages[$0].index+1)).tag($0) } }
            HStack(alignment: .top) {
                OCRPagePreview(page: source?.page(at: pages[index].index),highlight: pages[index].lines.first(where: { $0.id == focused }).map { $0.bounds.applying(pages[index].rasterToPage) }).frame(width: 320,height: 430)
                VStack(alignment: .leading) {
                    List(pages[index].lines.indices,id: \.self,selection: $focused) { row in
                        HStack {
                            Toggle("",isOn: $pages[index].lines[row].selected).labelsHidden()
                            TextField(label("Text","Текст"),text: $pages[index].lines[row].text)
                            Text("\(Int(pages[index].lines[row].confidence*100))%").font(.caption)
                        }.tag(pages[index].lines[row].id)
                    }.frame(width: 510,height: 340)
                    if let row = pages[index].lines.firstIndex(where: { $0.id == focused }) {
                        Text(label("Recognition box, pixels at ","Рамка распознавания, пиксели при ")+String(request.dpi)+" DPI").font(.caption)
                        HStack { metric("X",$pages[index].lines[row].bounds.origin.x); metric("Y",$pages[index].lines[row].bounds.origin.y) }
                        HStack { metric("W",$pages[index].lines[row].bounds.size.width); metric("H",$pages[index].lines[row].bounds.size.height) }
                    }
                }
            }
            Text(label("Selected lines become an invisible searchable layer. The scanned image remains unchanged.","Выбранные строки станут невидимым поисковым слоем. Изображение скана сохраняется.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                Button(label("Select all","Выбрать всё")) { for i in pages[index].lines.indices { pages[index].lines[i].selected = true } }
                Button(label("Clear","Снять")) { for i in pages[index].lines.indices { pages[index].lines[i].selected = false } }
                Button(label("Add line","Добавить строку")) { let line = PDFOCRLine(text: "",bounds: CGRect(x: 10,y: 10,width: 150,height: 20)); pages[index].lines.append(line); focused = line.id }
                Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply OCR layer","Записать слой OCR")) { error = request.apply(pages); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 900).onAppear { source = PDFDocument(data: request.source) }.onChange(of: index) { _,_ in focused = nil }
    }
    private func metric(_ title: String,_ value: Binding<CGFloat>) -> some View {
        TextField(title,value: Binding<Double>(get: { Double(value.wrappedValue) },set: { value.wrappedValue = CGFloat($0) }),format: .number)
    }
}
struct OCRPagePreview: NSViewRepresentable {
    let page: PDFPage?, highlight: CGRect?
    func makeNSView(context: Context) -> Preview { Preview() }
    func updateNSView(_ view: Preview,context: Context) { view.page = page; view.highlight = highlight; view.needsDisplay = true }
    @MainActor final class Preview: NSView {
        var page: PDFPage?, highlight: CGRect?
        override func draw(_ dirtyRect: NSRect) {
            NSColor(calibratedWhite: 0.18,alpha: 1).setFill(); bounds.fill()
            guard let page,let context = NSGraphicsContext.current?.cgContext else { return }
            let box = page.bounds(for: .cropBox),transform = PDFFormattingGeometry.transform(page,box: .cropBox,target: bounds.insetBy(dx: 10,dy: 10))
            context.saveGState(); context.concatenate(transform); context.clip(to: box)
            context.setFillColor(NSColor.white.cgColor); context.fill(box)
            if let reference = page.pageRef { context.drawPDFPage(reference) }
            if let highlight {
                context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.18).cgColor); context.fill(highlight)
                context.setStrokeColor(NSColor.systemBlue.cgColor); context.setLineWidth(1.5/max(0.001,hypot(transform.a,transform.b))); context.stroke(highlight)
            }
            context.restoreGState()
        }
    }
}
