// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import PDFKit
import CoreImage
import AppKit
import ImageIO
import Vision

struct PDFPerspectiveQuad: Sendable, Equatable {
    // Normalized coordinates in the rendered page, origin at bottom left.
    var topLeft = CGPoint(x: 0,y: 1),topRight = CGPoint(x: 1,y: 1)
    var bottomRight = CGPoint(x: 1,y: 0),bottomLeft = CGPoint(x: 0,y: 0)
    var points: [CGPoint] { [topLeft,topRight,bottomRight,bottomLeft] }
    var valid: Bool {
        let p = points
        guard p.allSatisfy({ $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }) else { return false }
        var area = 0.0
        for i in 0..<4 {
            let a = p[i],b = p[(i+1)%4],c = p[(i+2)%4]
            guard hypot(b.x-a.x,b.y-a.y) >= 0.01,(b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x) < -0.00001 else { return false }
            area += a.x*b.y-b.x*a.y
        }
        return -area/2 >= 0.01 && topLeft.y > bottomLeft.y && topRight.y > bottomRight.y && topRight.x > topLeft.x && bottomRight.x > bottomLeft.x
    }
    mutating func set(_ point: CGPoint,at index: Int) {
        switch index { case 0: topLeft = point; case 1: topRight = point; case 2: bottomRight = point; case 3: bottomLeft = point; default: break }
    }
}
struct PDFRasterOptions: Sendable, Equatable {
    var range = "all", dpi = 150, mode = 0
    var contrast = 1.0, brightness = 0.0, angle = 0.0, noise = 0.0, threshold = 0.5
    var left = 0.0, right = 0.0, top = 0.0, bottom = 0.0
    var normalizePaper = false
    var correctLighting = false,lightingStrength = 0.8
    var perspectiveMode = 0 // Off, manual, per-page Vision detection
    var quad = PDFPerspectiveQuad()
}
@MainActor struct PDFRasterRequest: Identifiable {
    let id = UUID(); let russian: Bool, enhancement: Bool
    let pageCount: Int, initialPage: Int
    let preview: (PDFRasterOptions,Int) async throws -> (Data,Data)
    let deskew: (Int) async throws -> Double
    let detectBounds: (Int) async throws -> CGRect?
    let detectPerspective: (Int) async throws -> PDFPerspectiveQuad?
    let run: (PDFRasterOptions) -> String?
}
struct PDFRasterEditor: View {
    let request: PDFRasterRequest
    @Environment(\.dismiss) private var dismiss
    @State private var options = PDFRasterOptions()
    @State private var error: String?
    @State private var previewPage = 1
    @State private var before: NSImage?
    @State private var after: NSImage?
    @State private var previewTask: Task<Void,Never>?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        ScrollView {
        VStack(alignment: .leading,spacing: 14) {
            Text(request.enhancement ? label("Enhance scanned pages","Улучшить сканированные страницы") : label("Raster color conversion","Преобразование цветов в растровую копию")).font(.title2)
            TextField(label("Pages","Страницы"),text: $options.range)
            Picker("DPI",selection: $options.dpi) { ForEach([72,150,200,300],id: \.self) { Text(String($0)).tag($0) } }
            Picker(label("Output color","Цвет результата"),selection: $options.mode) { Text(label("Color","Цветной")).tag(0); Text(label("Grayscale","Серый")).tag(1); Text(label("Black / white","Чёрно-белый")).tag(2) }
            if options.mode == 2 { Slider(value: $options.threshold,in: 0...1) { Text(label("Threshold","Порог")) } }
            if request.enhancement {
                Slider(value: $options.contrast,in: 0.5...3) { Text(label("Contrast","Контраст")) }
                Slider(value: $options.brightness,in: -0.5...0.5) { Text(label("Brightness","Яркость")) }
                Slider(value: $options.noise,in: 0...0.1) { Text(label("Noise reduction","Подавление шума")) }
                TextField(label("Deskew angle, degrees","Угол исправления наклона, °"),value: $options.angle,format: .number)
                Picker(label("Perspective correction","Исправление перспективы"),selection: $options.perspectiveMode) {
                    Text(label("Off","Выключено")).tag(0); Text(label("Manual corners","Углы вручную")).tag(1); Text(label("Detect on every page","Определить на каждой странице")).tag(2)
                }
                if options.perspectiveMode == 1 {
                    ForEach(0..<4,id: \.self) { index in
                        HStack {
                            Text([label("Top left","Верхний левый"),label("Top right","Верхний правый"),label("Bottom right","Нижний правый"),label("Bottom left","Нижний левый")][index]).frame(width: 130,alignment: .leading)
                            TextField("X, %",value: coordinate(index,x: true),format: .number)
                            TextField("Y, %",value: coordinate(index,x: false),format: .number)
                        }
                    }
                    Text(label("Coordinates start at bottom left. The same relative corners apply to all selected pages.","Начало координат — снизу слева. Одинаковые относительные углы применяются ко всем выбранным страницам.")).font(.caption)
                }
                if options.perspectiveMode == 2 { Text(label("Each page must have a reliable quadrilateral. Detection failure stops creation of the copy.","Для каждой страницы нужна уверенная четырёхугольная рамка. Если она не найдена, создание копии прекращается.")).font(.caption) }
                Toggle(label("Normalize paper background","Осветлить фон бумаги"),isOn: $options.normalizePaper)
                Toggle(label("Reduce shadows and uneven lighting","Ослабить тени и неравномерный свет"),isOn: $options.correctLighting)
                if options.correctLighting { Slider(value: $options.lightingStrength,in: 0...1) { Text(label("Lighting correction strength","Сила коррекции света")) } }
                HStack { TextField(label("Left, %","Слева, %"),value: $options.left,format: .number); TextField(label("Right, %","Справа, %"),value: $options.right,format: .number) }
                HStack { TextField(label("Top, %","Сверху, %"),value: $options.top,format: .number); TextField(label("Bottom, %","Снизу, %"),value: $options.bottom,format: .number) }
            }
            HStack {
                TextField(label("Preview page","Страница предпросмотра"),value: $previewPage,format: .number).frame(width: 200)
                Button(label("Update preview","Обновить предпросмотр")) { updatePreview() }.disabled(previewTask != nil)
                if previewTask != nil { ProgressView().controlSize(.small); Button(label("Cancel preview","Отменить предпросмотр")) { previewTask?.cancel(); previewTask = nil } }
                if request.enhancement { Button(label("Detect skew","Определить наклон")) { detectSkew() }.disabled(previewTask != nil) }
                if request.enhancement { Button(label("Detect borders","Найти границы")) { detectBounds() }.disabled(previewTask != nil) }
            }
            if request.enhancement { Button(label("Detect perspective corners on preview page","Найти углы перспективы на странице предпросмотра")) { detectPerspective() }.disabled(previewTask != nil) }
            if let before,let after {
                HStack {
                    VStack { Text(label("Original","Исходник")); PDFPerspectivePreview(image: before,quad: options.perspectiveMode == 1 ? options.quad : nil).frame(width: 400,height: 320) }
                    VStack { Text(label("Result","Результат")); Image(nsImage: after).resizable().scaledToFit().frame(width: 400,height: 320) }
                }
            }
            Text(label("Creates a new raster PDF. Text, vector paths, forms and annotations become pixels. Keep the original for editing. This is not secure redaction.","Создаёт отдельный растровый PDF. Текст, векторы, формы и комментарии становятся изображением. Сохраните исходник для редактирования. Это не инструмент безопасного удаления данных.")).font(.caption)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Create copy","Создать копию")) { error = request.run(options); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24)
        }.frame(width: before == nil ? 570 : 870).frame(maxHeight: min(900,(NSScreen.main?.visibleFrame.height ?? 900)-100))
            .onAppear { previewPage = request.initialPage }
            .onChange(of: options) { _,_ in resetPreview() }
            .onChange(of: previewPage) { _,_ in resetPreview() }
            .onDisappear { previewTask?.cancel() }
    }
    private func coordinate(_ index: Int,x: Bool) -> Binding<Double> {
        Binding(get: { (x ? options.quad.points[index].x : options.quad.points[index].y)*100 },set: { value in
            var point = options.quad.points[index]; if x { point.x = value/100 } else { point.y = value/100 }; options.quad.set(point,at: index)
        })
    }
    private func detectPerspective() {
        guard (1...request.pageCount).contains(previewPage) else { return }
        let index = previewPage-1
        previewTask = Task { @MainActor in
            defer { if !Task.isCancelled { previewTask = nil } }
            do {
                guard let quad = try await request.detectPerspective(index) else { error = label("No reliable page quadrilateral found.","Уверенный четырёхугольник страницы не найден."); return }
                try Task.checkCancellation(); options.quad = quad; options.perspectiveMode = 1; before = nil; after = nil
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = label("Perspective detection failed.","Не удалось определить углы перспективы.") } }
        }
    }
    private func resetPreview() { previewTask?.cancel(); previewTask = nil; before = nil; after = nil; error = nil }
    private func updatePreview() {
        guard (1...request.pageCount).contains(previewPage) else { error = label("Invalid preview page","Некорректная страница предпросмотра"); return }
        let snapshot = options,index = previewPage-1
        previewTask = Task { @MainActor in
            defer { if !Task.isCancelled { previewTask = nil } }
            do {
                let (original,processed) = try await request.preview(snapshot,index)
                try Task.checkCancellation()
                before = NSImage(data: original)
                let document = PDFDocument(data: processed)
                after = document?.page(at: 0)?.thumbnail(of: CGSize(width: 1000,height: 1000),for: .mediaBox)
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = label("Preview failed. Check range, DPI and options.","Не удалось построить предпросмотр. Проверьте диапазон, DPI и параметры.") } }
        }
    }
    private func detectSkew() {
        guard (1...request.pageCount).contains(previewPage) else { return }
        let index = previewPage-1
        previewTask = Task { @MainActor in
            defer { if !Task.isCancelled { previewTask = nil } }
            do {
                let angle = try await request.deskew(index); try Task.checkCancellation()
                options.angle = angle; before = nil; after = nil
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = label("Cannot estimate skew for this page.","Не удалось оценить наклон страницы.") } }
        }
    }
    private func detectBounds() {
        guard (1...request.pageCount).contains(previewPage) else { return }
        let index = previewPage-1
        previewTask = Task { @MainActor in
            defer { if !Task.isCancelled { previewTask = nil } }
            do {
                guard let rect = try await request.detectBounds(index) else { error = label("No reliable page rectangle found.","Уверенная рамка страницы не найдена."); return }
                try Task.checkCancellation()
                options.left = rect.minX*100; options.right = (1-rect.maxX)*100; options.bottom = rect.minY*100; options.top = (1-rect.maxY)*100
                before = nil; after = nil
            } catch is CancellationError { }
            catch { if !Task.isCancelled { self.error = label("Border detection failed.","Не удалось определить границы.") } }
        }
    }
}
struct PDFPerspectivePreview: View {
    let image: NSImage,quad: PDFPerspectiveQuad?
    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width/max(1,image.size.width),proxy.size.height/max(1,image.size.height))
            let width = image.size.width*scale,height = image.size.height*scale,x = (proxy.size.width-width)/2,y = (proxy.size.height-height)/2
            ZStack(alignment: .topLeading) {
                Image(nsImage: image).resizable().frame(width: width,height: height).offset(x: x,y: y)
                if let quad {
                    Path { path in
                        let points = quad.points.map { CGPoint(x: x+$0.x*width,y: y+(1-$0.y)*height) }
                        path.addLines(points); path.closeSubpath()
                    }.stroke(quad.valid ? Color.blue : Color.red,lineWidth: 2)
                    ForEach(0..<4,id: \.self) { index in
                        Text(String(index+1)).font(.caption.bold()).padding(3).background(Color.blue).foregroundStyle(.white)
                            .position(x: x+quad.points[index].x*width,y: y+(1-quad.points[index].y)*height)
                    }
                }
            }
        }
    }
}
enum PDFRasterEngine {
    static func detectPerspective(image: CGImage) throws -> PDFPerspectiveQuad? {
        let request = VNDetectRectanglesRequest(); request.maximumObservations = 1; request.minimumConfidence = 0.6; request.minimumSize = 0.3; request.minimumAspectRatio = 0.2; request.quadratureTolerance = 35
        try VNImageRequestHandler(cgImage: image,options: [:]).perform([request]); try Task.checkCancellation()
        guard let rect = request.results?.first else { return nil }
        let quad = PDFPerspectiveQuad(topLeft: rect.topLeft,topRight: rect.topRight,bottomRight: rect.bottomRight,bottomLeft: rect.bottomLeft)
        return quad.valid ? quad : nil
    }
    static func detectPerspective(data: Data,index: Int) throws -> PDFPerspectiveQuad? {
        guard let document = PDFDocument(data: data),let page = document.page(at: index) else { throw PDFSourceError.page }
        defer { withExtendedLifetime(document) {} }
        let png = try PDFSnapshotRenderer.render(data: data,index: index,region: page.bounds(for: .cropBox),dpi: 72)
        guard let source = CGImageSourceCreateWithData(png as CFData,nil),let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw PDFSourceError.content }
        return try detectPerspective(image: image)
    }
    static func correctPerspective(_ image: CIImage,quad: PDFPerspectiveQuad) throws -> CIImage {
        guard quad.valid else { throw PDFSourceError.content }
        let extent = image.extent
        func vector(_ p: CGPoint) -> CIVector { CIVector(x: extent.minX+p.x*extent.width,y: extent.minY+p.y*extent.height) }
        let result = image.applyingFilter("CIPerspectiveCorrection",parameters: ["inputTopLeft":vector(quad.topLeft),"inputTopRight":vector(quad.topRight),"inputBottomRight":vector(quad.bottomRight),"inputBottomLeft":vector(quad.bottomLeft),"inputCrop":true])
        guard !result.extent.isEmpty,!result.extent.isInfinite,result.extent.width.isFinite,result.extent.height.isFinite,result.extent.width <= extent.width*4,result.extent.height <= extent.height*4 else { throw PDFSourceError.content }
        return result.transformed(by: CGAffineTransform(translationX: -result.extent.minX,y: -result.extent.minY))
    }
    static func detectBounds(data: Data,index: Int) throws -> CGRect? {
        guard let document = PDFDocument(data: data),let page = document.page(at: index) else { throw PDFSourceError.page }
        defer { withExtendedLifetime(document) {} }
        let png = try PDFSnapshotRenderer.render(data: data,index: index,region: page.bounds(for: .cropBox),dpi: 72)
        guard let source = CGImageSourceCreateWithData(png as CFData,nil),let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw PDFSourceError.content }
        let request = VNDetectRectanglesRequest(); request.maximumObservations = 1; request.minimumConfidence = 0.6; request.minimumSize = 0.35; request.minimumAspectRatio = 0.2; request.quadratureTolerance = 15
        try VNImageRequestHandler(cgImage: image,options: [:]).perform([request]); try Task.checkCancellation()
        guard let rect = request.results?.first?.boundingBox.intersection(CGRect(x: 0,y: 0,width: 1,height: 1)),!rect.isNull,!rect.isEmpty else { return nil }
        return rect
    }
    static func correctLighting(_ image: CIImage,strength: Double) throws -> CIImage {
        guard strength.isFinite,(0...1).contains(strength),!image.extent.isEmpty else { throw PDFSourceError.content }
        guard strength > 0 else { return image }
        let extent = image.extent,scale = min(1,800/max(extent.width,extent.height))
        let sample = image.transformed(by: CGAffineTransform(scaleX: scale,y: scale)).applyingFilter("CIColorControls",parameters: [kCIInputSaturationKey:0])
        let radius = max(2,min(sample.extent.width,sample.extent.height)*0.015)
        let illumination = sample.clampedToExtent().applyingFilter("CIMorphologyMaximum",parameters: [kCIInputRadiusKey:radius])
            .applyingFilter("CIGaussianBlur",parameters: [kCIInputRadiusKey:radius*2]).cropped(to: sample.extent)
            .transformed(by: CGAffineTransform(scaleX: 1/scale,y: 1/scale))
            .applyingFilter("CIColorClamp",parameters: ["inputMinComponents":CIVector(x: 0.25,y: 0.25,z: 0.25,w: 1),"inputMaxComponents":CIVector(x: 1,y: 1,z: 1,w: 1)])
        let corrected = illumination.applyingFilter("CIDivideBlendMode",parameters: [kCIInputBackgroundImageKey:image]).cropped(to: extent)
        return image.applyingFilter("CIDissolveTransition",parameters: [kCIInputTargetImageKey:corrected,kCIInputTimeKey:strength]).cropped(to: extent)
    }
    private static func paperGain(_ image: CIImage,context: CIContext) -> Double {
        let scale = min(1,256/max(image.extent.width,image.extent.height)),sample = image.transformed(by: CGAffineTransform(scaleX: scale,y: scale))
        guard let cg = context.createCGImage(sample,from: sample.extent),cg.width > 0,cg.height > 0 else { return 1 }
        var bytes = [UInt8](repeating: 255,count: cg.width*cg.height)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let gray = CGContext(data: storage.baseAddress,width: cg.width,height: cg.height,bitsPerComponent: 8,bytesPerRow: cg.width,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            gray.draw(cg,in: CGRect(x: 0,y: 0,width: cg.width,height: cg.height)); return true
        }
        guard drawn else { return 1 }
        var histogram = [Int](repeating: 0,count: 256); for value in bytes { histogram[Int(value)] += 1 }
        let target = Int(Double(bytes.count)*0.85); var count = 0
        for value in histogram.indices { count += histogram[value]; if count >= target { return 1/max(0.35,Double(value)/255) } }
        return 1
    }
    static func suggestDeskew(data: Data,index: Int) throws -> Double {
        guard let document = PDFDocument(data: data),let page = document.page(at: index) else { throw PDFSourceError.page }
        defer { withExtendedLifetime(document) {} }
        let png = try PDFSnapshotRenderer.render(data: data,index: index,region: page.bounds(for: .cropBox),dpi: 72)
        guard let source = CGImageSourceCreateWithData(png as CFData,nil),let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { throw PDFSourceError.content }
        return try suggestDeskew(image: image)
    }
    static func suggestDeskew(image: CGImage) throws -> Double {
        let ratio = min(1,900/Double(max(image.width,image.height))),width = max(1,Int(Double(image.width)*ratio)),height = max(1,Int(Double(image.height)*ratio))
        var bytes = [UInt8](repeating: 255,count: width*height)
        let drawn = bytes.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress,width: width,height: height,bitsPerComponent: 8,bytesPerRow: width,space: CGColorSpaceCreateDeviceGray(),bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(CGColor(gray: 1,alpha: 1)); context.fill(CGRect(x: 0,y: 0,width: width,height: height)); context.draw(image,in: CGRect(x: 0,y: 0,width: width,height: height)); return true
        }
        guard drawn,width > 12,height > 12 else { return 0 }
        var points: [(Double,Double)] = []
        let strideSize = max(1,Int(sqrt(Double(width*height)/180000)))
        for y in stride(from: 5,to: height-5,by: strideSize) {
            for x in stride(from: 5,to: width-5,by: strideSize) where bytes[y*width+x] < 135 { points.append((Double(x)-Double(width)/2,Double(y)-Double(height)/2)) }
        }
        guard points.count >= 200,points.count < width*height/2 else { return 0 }
        func score(_ angle: Double) -> Double {
            let radians = angle*Double.pi/180,s = sin(radians),c = cos(radians)
            var rows = [Int](repeating: 0,count: height+width+4)
            let center = Double(rows.count)/2
            for point in points { let row = Int((-s*point.0+c*point.1+center).rounded()); if rows.indices.contains(row) { rows[row] += 1 } }
            return rows.reduce(0) { $0+Double($1)*Double($1) }
        }
        let baseline = score(0)
        var best = 0.0,bestScore = baseline
        for step in -24...24 { try Task.checkCancellation(); let angle = Double(step)*0.25,value = score(angle); if value > bestScore { best = angle; bestScore = value } }
        let coarse = best
        for step in -5...5 { try Task.checkCancellation(); let angle = coarse+Double(step)*0.05,value = score(angle); if value > bestScore { best = angle; bestScore = value } }
        return bestScore > baseline*1.08 ? (best*100).rounded()/100 : 0
    }
    static func process(data: Data,indices: [Int],options: PDFRasterOptions,progress: @Sendable (Double) -> Void) throws -> Data {
        guard options.lightingStrength.isFinite,(0...1).contains(options.lightingStrength),(0...2).contains(options.perspectiveMode),(options.perspectiveMode != 1 || options.quad.valid),let document = PDFDocument(data: data),!indices.isEmpty,(72...300).contains(options.dpi),(0...2).contains(options.mode),
              [options.contrast,options.brightness,options.angle,options.noise,options.threshold].allSatisfy(\.isFinite),abs(options.angle) <= 20,
              (0.5...3).contains(options.contrast),(-0.5...0.5).contains(options.brightness),(0...0.1).contains(options.noise),(0...1).contains(options.threshold),
              [options.left,options.right,options.top,options.bottom].allSatisfy({ $0.isFinite && (0...95).contains($0) }),options.left+options.right < 95,options.top+options.bottom < 95 else { throw PDFSourceError.content }
        let buffer = NSMutableData(); var initial = CGRect(x: 0,y: 0,width: 612,height: 792)
        guard let consumer = CGDataConsumer(data: buffer),let pdf = CGContext(consumer: consumer,mediaBox: &initial,nil) else { throw PDFSourceError.save }
        let context = CIContext(options: [.cacheIntermediates:false])
        for (offset,index) in indices.enumerated() {
            try Task.checkCancellation()
            try autoreleasepool {
                guard let page = document.page(at: index) else { throw PDFSourceError.page }
                let box = page.bounds(for: .cropBox),rotated = page.rotation%180 != 0
                let png = try PDFSnapshotRenderer.render(data: data,index: index,region: box,dpi: options.dpi)
                guard var image = CIImage(data: png) else { throw PDFSourceError.content }
                let originalExtent = image.extent
                if options.perspectiveMode != 0 {
                    let quad: PDFPerspectiveQuad
                    if options.perspectiveMode == 1 { quad = options.quad }
                    else {
                        guard let cg = context.createCGImage(image,from: originalExtent),let detected = try detectPerspective(image: cg) else { throw PDFSourceError.content }; quad = detected
                    }
                    image = try correctPerspective(image,quad: quad)
                }
                let extent = image.extent
                if options.correctLighting { image = try correctLighting(image,strength: options.lightingStrength) }
                if options.normalizePaper {
                    let gain = paperGain(image,context: context)
                    image = image.applyingFilter("CIColorMatrix",parameters: ["inputRVector":CIVector(x: gain,y: 0,z: 0,w: 0),"inputGVector":CIVector(x: 0,y: gain,z: 0,w: 0),"inputBVector":CIVector(x: 0,y: 0,z: gain,w: 0)])
                }
                image = image.applyingFilter("CIColorControls",parameters: [kCIInputSaturationKey: options.mode == 0 ? 1 : 0,kCIInputContrastKey: options.contrast,kCIInputBrightnessKey: options.brightness])
                if options.noise > 0 { image = image.applyingFilter("CINoiseReduction",parameters: ["inputNoiseLevel":options.noise,"inputSharpness":0.4]) }
                if options.mode == 2 { image = image.applyingFilter("CIColorThreshold",parameters: ["inputThreshold":options.threshold]) }
                if options.angle != 0 {
                    let transform = CGAffineTransform(translationX: extent.midX,y: extent.midY).rotated(by: options.angle*Double.pi/180).translatedBy(x: -extent.midX,y: -extent.midY)
                    image = image.transformed(by: transform).cropped(to: extent)
                }
                let crop = CGRect(x: extent.minX+extent.width*options.left/100,y: extent.minY+extent.height*options.bottom/100,width: extent.width*(1-(options.left+options.right)/100),height: extent.height*(1-(options.top+options.bottom)/100))
                guard let result = context.createCGImage(image,from: crop) else { throw PDFSourceError.content }
                var media = CGRect(x: 0,y: 0,width: (rotated ? box.height : box.width)*crop.width/originalExtent.width,height: (rotated ? box.width : box.height)*crop.height/originalExtent.height)
                let encoded = NSData(bytes: &media,length: MemoryLayout<CGRect>.size)
                pdf.beginPDFPage([kCGPDFContextMediaBox as String:encoded] as CFDictionary)
                pdf.setFillColor(CGColor(gray: 1,alpha: 1)); pdf.fill(media); pdf.draw(result,in: media); pdf.endPDFPage()
            }
            progress(Double(offset+1)/Double(indices.count))
        }
        pdf.closePDF(); return buffer as Data
    }
}
