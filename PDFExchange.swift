// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import AppKit
import PDFKit

// Standard XFDF data exchange, without executing scripts or external entities.
enum PDFXFDF {
    // Parse PDF dates as data, never as executable annotation actions.
    static func modificationDate(_ text: String) -> Date? {
        guard text.utf8.count <= 64 else { return nil }
        let raw = text.hasPrefix("D:") ? String(text.dropFirst(2)) : text
        let pattern = #"^(\d{4})(\d{2})?(\d{2})?(\d{2})?(\d{2})?(\d{2})?(?:(Z)|([+-])(\d{2})(?:'?(\d{2})'?)?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),let match = regex.firstMatch(in: raw,range: NSRange(raw.startIndex...,in: raw)) else { return nil }
        func part(_ index: Int) -> String? { Range(match.range(at: index),in: raw).map { String(raw[$0]) } }
        let year = Int(part(1) ?? "") ?? 0,month = Int(part(2) ?? "1") ?? 0,day = Int(part(3) ?? "1") ?? 0,hour = Int(part(4) ?? "0") ?? -1,minute = Int(part(5) ?? "0") ?? -1,second = Int(part(6) ?? "0") ?? -1
        guard (1...9999).contains(year),(1...12).contains(month),(1...31).contains(day),(0...23).contains(hour),(0...59).contains(minute),(0...59).contains(second) else { return nil }
        var zone = TimeZone.current
        if part(7) != nil { zone = TimeZone(secondsFromGMT: 0)! }
        else if let sign = part(8) {
            guard let hours = part(9).flatMap(Int.init),let minutes = Int(part(10) ?? "0"),(0...23).contains(hours),(0...59).contains(minutes),let parsed = TimeZone(secondsFromGMT: (sign == "-" ? -1 : 1)*(hours*3600+minutes*60)) else { return nil }; zone = parsed
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let components = DateComponents(timeZone: zone,year: year,month: month,day: day,hour: hour,minute: minute,second: second)
        guard let date = calendar.date(from: components) else { return nil }
        let check = calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from: date)
        guard check.year == year,check.month == month,check.day == day,check.hour == hour,check.minute == minute,check.second == second else { return nil }
        return date
    }
    static func modificationDateText(_ date: Date) -> String? {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "'D:'yyyyMMddHHmmss'Z'"
        let text = formatter.string(from: date); return modificationDate(text) != nil ? text : nil
    }
    static let noteIcons = ["Comment","Key","Note","Help","NewParagraph","Paragraph","Insert"]
    static func noteIcon(_ name: String) -> PDFTextAnnotationIconType? {
        guard let index = noteIcons.firstIndex(of: name) else { return nil }
        return [PDFTextAnnotationIconType.comment,.key,.note,.help,.newParagraph,.paragraph,.insert][index]
    }
    static func noteIconName(_ icon: PDFTextAnnotationIconType) -> String { noteIcons.indices.contains(icon.rawValue) ? noteIcons[icon.rawValue] : "Note" }
    static let borderNames = ["solid","dash","bevelled","inset","underline"]
    static func borderName(_ style: PDFBorderStyle) -> String { borderNames.indices.contains(style.rawValue) ? borderNames[style.rawValue] : "solid" }
    static func borderStyle(_ name: String) -> PDFBorderStyle? {
        guard let index = borderNames.firstIndex(of: name.lowercased()) else { return nil }
        return [PDFBorderStyle.solid,.dashed,.beveled,.inset,.underline][index]
    }
    static func dashValues(_ text: String) -> [Double]? {
        let tokens = text.split { $0 == "," || $0.isWhitespace },values = tokens.compactMap { Double($0) }
        guard tokens.count == values.count,values.count <= 64,values.allSatisfy({ $0.isFinite && (0...14400).contains($0) }),values.isEmpty || values.contains(where: { $0 > 0 }) else { return nil }; return values
    }
    static func lineStyleName(_ style: PDFLineStyle) -> String {
        switch style { case .square: "Square"; case .circle: "Circle"; case .diamond: "Diamond"; case .openArrow: "OpenArrow"; case .closedArrow: "ClosedArrow"; default: "None" }
    }
    static func lineStyle(_ name: String) -> PDFLineStyle? {
        switch name { case "None": PDFLineStyle.none; case "Square": .square; case "Circle": .circle; case "Diamond": .diamond; case "OpenArrow": .openArrow; case "ClosedArrow": .closedArrow; default: nil }
    }
    private static let annotationFlags: [(String,Int)] = [("invisible",1),("hidden",2),("print",4),("nozoom",8),("norotate",16),("noview",32),("readonly",64),("locked",128),("togglenoview",256),("lockedcontents",512)]
    static func flagsText(_ bits: Int) -> String { annotationFlags.filter { bits & $0.1 != 0 }.map(\.0).joined(separator: ",") }
    static func flagsValue(_ text: String) -> Int {
        let flags = Set(text.lowercased().split { $0 == "," || $0.isWhitespace }.map(String.init))
        return annotationFlags.filter { flags.contains($0.0) }.reduce(0) { $0 | $1.1 }
    }
    static func escape(_ text: String) -> String { String(String.UnicodeScalarView(text.unicodeScalars.filter { value in
        value.value == 9 || value.value == 10 || value.value == 13 || (0x20...0xD7FF).contains(value.value) || (0xE000...0xFFFD).contains(value.value) || (0x10000...0x10FFFF).contains(value.value)
    })).replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: ">",with: "&gt;").replacingOccurrences(of: "\"",with: "&quot;").replacingOccurrences(of: "'",with: "&apos;") }
    static func forms(_ values: [String:String]) -> Data {
        let fields = values.keys.sorted().map { "<field name=\""+escape($0)+"\"><value>"+escape(values[$0] ?? "")+"</value></field>" }.joined()
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><xfdf xmlns=\"http://ns.adobe.com/xfdf/\" xml:space=\"preserve\"><fields>"+fields+"</fields></xfdf>").utf8)
    }
    static func forms(_ values: [String:PDFFDF.FieldValue]) -> Data {
        let fields = values.keys.sorted().map { name in
            "<field name=\""+escape(name)+"\">"+(values[name]?.strings ?? []).map { "<value>"+escape($0)+"</value>" }.joined()+"</field>"
        }.joined()
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><xfdf xmlns=\"http://ns.adobe.com/xfdf/\" xml:space=\"preserve\"><fields>"+fields+"</fields></xfdf>").utf8)
    }
    struct Comment { var kind: String, attributes: [String:String], contents: String, gestures: [[CGPoint]], quads: [CGPoint] }
    final class Reader: NSObject, XMLParserDelegate {
        var values: [String:String] = [:], comments: [Comment] = []
        var multipleValues: [String:[String]] = [:]
        private var fields: [String] = [], value: String?, comment: Comment?, text = "", element = ""
        private var depth = 0
        private(set) var hasRoot = false
        func parser(_ parser: XMLParser,foundInternalEntityDeclarationWithName name: String,value: String?) { parser.abortParsing() }
        func parser(_ parser: XMLParser,foundExternalEntityDeclarationWithName name: String,publicID: String?,systemID: String?) { parser.abortParsing() }
        func parser(_ parser: XMLParser,didStartElement elementName: String,namespaceURI: String?,qualifiedName qName: String?,attributes: [String:String]) {
            if depth == 0 {
                guard elementName == "xfdf",namespaceURI == nil || namespaceURI == "" || namespaceURI == "http://ns.adobe.com/xfdf/" else { parser.abortParsing(); return }
                hasRoot = true
            }
            depth += 1
            guard depth <= 128,fields.count <= 64 else { parser.abortParsing(); return }
            element = elementName; text = ""
            if elementName == "field" { fields.append(attributes["name"] ?? "") }
            if elementName == "value" { value = "" }
            if ["text","freetext","highlight","underline","strikeout","square","circle","line","ink","link"].contains(elementName),attributes["page"] != nil { comment = Comment(kind: elementName,attributes: attributes,contents: "",gestures: [],quads: attributes["coords"].map(Self.points) ?? []) }
        }
        func parser(_ parser: XMLParser,foundCDATA data: Data) { if let string = String(data: data,encoding: .utf8) { self.parser(parser,foundCharacters: string) } }
        func parser(_ parser: XMLParser,foundCharacters string: String) {
            text += string; if value != nil { value! += string }
            if text.utf16.count > 1_000_000 || (value?.utf16.count ?? 0) > 1_000_000 { parser.abortParsing() }
        }
        func parser(_ parser: XMLParser,didEndElement elementName: String,namespaceURI: String?,qualifiedName qName: String?) {
            depth = max(0,depth-1)
            if elementName == "value",let value { let name = fields.joined(separator: "."); values[name] = value; multipleValues[name,default: []].append(value); self.value = nil }
            if elementName == "field",!fields.isEmpty { let name = fields.joined(separator: "."); if multipleValues[name] == nil { multipleValues[name] = []; values[name] = "" }; fields.removeLast() }
            if elementName == "contents" { comment?.contents = text }
            if elementName == "gesture" { comment?.gestures.append(Self.points(text)) }
            if elementName == "quadpoints" || elementName == "coords" { comment?.quads = Self.points(text) }
            if comment?.kind == elementName,let entry = comment { comments.append(entry); comment = nil }
            text = ""
            if comments.count > 50000 || values.count > 50000 { parser.abortParsing() }
        }
        static func points(_ value: String) -> [CGPoint] { let tokens = value.split { $0 == "," || $0 == ";" || $0.isWhitespace }; guard tokens.count <= 1_000_000 else { return [] }; let numbers = tokens.compactMap { Double($0) }; guard numbers.count == tokens.count,numbers.count%2 == 0,numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }) else { return [] }; return stride(from: 0,to: numbers.count,by: 2).map { CGPoint(x: numbers[$0],y: numbers[$0+1]) } }
    }
    static func read(_ data: Data) throws -> Reader {
        guard data.count <= 32*1024*1024,data.range(of: Data("<!DOCTYPE".utf8)) == nil else { throw PDFSourceError.content }
        let parser = XMLParser(data: data), reader = Reader(); parser.delegate = reader; parser.shouldResolveExternalEntities = false; parser.externalEntityResolvingPolicy = .never; parser.shouldProcessNamespaces = true
        guard parser.parse(),reader.hasRoot else { throw PDFSourceError.content }; return reader
    }
    @MainActor static func comments(_ document: PDFDocument,include: (PDFAnnotation) -> Bool,opacity: ((PDFAnnotation) -> Double)? = nil) -> Data {
        var values: [String] = []
        for index in 0..<document.pageCount { for annotation in document.page(at: index)?.annotations ?? [] where include(annotation) {
            let kind: String
            switch annotation.type { case "Text": kind = "text"; case "FreeText": kind = "freetext"; case "Highlight": kind = "highlight"; case "Underline": kind = "underline"; case "StrikeOut": kind = "strikeout"; case "Square": kind = "square"; case "Circle": kind = "circle"; case "Line": kind = "line"; case "Ink": kind = "ink"; default: continue }
            let rect = annotation.bounds,color = (annotation.type == "FreeText" ? annotation.fontColor ?? .black : annotation.color).usingColorSpace(.sRGB) ?? .red
            let hex = String(format: "#%02X%02X%02X",Int32(color.redComponent*255),Int32(color.greenComponent*255),Int32(color.blueComponent*255))
            let requestedAlpha = opacity?(annotation) ?? Double(color.alphaComponent),alpha = requestedAlpha.isFinite ? min(1,max(0,requestedAlpha)) : 1
            let flagBits = (annotation.value(forAnnotationKey: .flags) as? NSNumber)?.intValue ?? 0
            let flags = flagsText(flagBits)
            var attrs = " page=\"\(index)\" rect=\"\(rect.minX),\(rect.minY),\(rect.maxX),\(rect.maxY)\" color=\"\(hex)\" opacity=\"\(alpha)\" width=\"\(annotation.border?.lineWidth ?? 1)\" flags=\"\(flags)\""
            if let date = annotation.modificationDate,let text = modificationDateText(date) { attrs += " date=\""+escape(text)+"\"" }
            if let author = annotation.userName { attrs += " title=\""+escape(author)+"\"" }
            if kind == "text" { attrs += " icon=\"\(noteIconName(annotation.iconType))\"" }
            if kind == "freetext" { attrs += " justification=\"\(annotation.alignment == .right ? "right" : annotation.alignment == .center ? "centered" : "left")\"" }
            if let border = annotation.border {
                attrs += " style=\"\(borderName(border.style))\""
                if let pattern = border.dashPattern {
                    let text = pattern.compactMap { ($0 as? NSNumber)?.doubleValue }.map { String($0) }.joined(separator: ",")
                    if dashValues(text) != nil { attrs += " dashes=\"\(text)\"" }
                }
            }
            if ["Square","Circle","Line"].contains(annotation.type ?? ""),let fill = annotation.interiorColor?.usingColorSpace(.sRGB),fill.alphaComponent > 0 {
                attrs += String(format: " interior-color=\"#%02X%02X%02X\"",Int(fill.redComponent*255),Int(fill.greenComponent*255),Int(fill.blueComponent*255))
            }
            if kind == "line" { attrs += " start=\"\(annotation.startPoint.x+rect.minX),\(annotation.startPoint.y+rect.minY)\" end=\"\(annotation.endPoint.x+rect.minX),\(annotation.endPoint.y+rect.minY)\" head=\"\(lineStyleName(annotation.startLineStyle))\" tail=\"\(lineStyleName(annotation.endLineStyle))\"" }
            var body = "<contents>"+escape(annotation.contents ?? "")+"</contents>"
            if let quads = annotation.quadrilateralPoints,!quads.isEmpty { attrs += " coords=\""+quads.map { "\($0.pointValue.x+rect.minX),\($0.pointValue.y+rect.minY)" }.joined(separator: ",")+"\"" }
            if kind == "ink" { guard let gestures = inkGestures(annotation) else { continue }; body += "<inklist>"; for points in gestures {
                body += "<gesture>"+points.map { "\($0.x),\($0.y)" }.joined(separator: ";")+"</gesture>"
            }; body += "</inklist>" }
            values.append("<"+kind+attrs+">"+body+"</"+kind+">")
        } }
        return Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?><xfdf xmlns=\"http://ns.adobe.com/xfdf/\"><annots>"+values.joined()+"</annots></xfdf>").utf8)
    }
    @MainActor private static func inkGestures(_ annotation: PDFAnnotation) -> [[CGPoint]]? {
        func absolute(_ strokes: [[CGPoint]],box: CGRect) -> [[CGPoint]] {
            strokes.map { $0.map { CGPoint(x: box.minX+$0.x*box.width,y: box.minY+$0.y*box.height) } }
        }
        if let strokes = PDFInkCurveGeometry.nativeStrokes(annotation) { return absolute(strokes,box: annotation.bounds) }
        // XFDF gestures are polylines. Preserve native cubic shape through the
        // same bounded adaptive subdivision used by the editable Ink engine.
        guard let nodes = try? PDFInkCurveGeometry.read(annotation,record: nil) else { return nil }
        let probe = PDFAnnotation(bounds: annotation.bounds,forType: .ink,withProperties: nil); probe.border = annotation.border
        guard let record = PDFInkCurveGeometry.apply(nodes,to: probe) else { return nil }
        return absolute(record.strokes,box: probe.bounds)
    }
    @MainActor static func annotation(_ entry: Comment) -> (Int,PDFAnnotation)? {
        guard let page = entry.attributes["page"].flatMap(Int.init),page >= 0,let raw = entry.attributes["rect"] else { return nil }
        let corners = Reader.points(raw); guard corners.count == 2 else { return nil }
        let rect = CGRect(x: corners[0].x,y: corners[0].y,width: corners[1].x-corners[0].x,height: corners[1].y-corners[0].y)
        guard rect.width > 0,rect.height > 0,[rect.minX,rect.minY,rect.width,rect.height].allSatisfy({ $0.isFinite && abs($0) < 1000000 }) else { return nil }
        let subtype: PDFAnnotationSubtype
        switch entry.kind { case "text": subtype = .text; case "freetext": subtype = .freeText; case "highlight": subtype = .highlight; case "underline": subtype = .underline; case "strikeout": subtype = .strikeOut; case "square": subtype = .square; case "circle": subtype = .circle; case "line": subtype = .line; case "ink": subtype = .ink; case "link": subtype = .link; default: return nil }
        let allPoints = entry.gestures.flatMap { $0 }+entry.quads
        guard allPoints.count <= 100000,allPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),entry.quads.count%4 == 0 else { return nil }
        if subtype == .ink { guard !entry.gestures.isEmpty,entry.gestures.allSatisfy({ $0.count >= 2 }) else { return nil } }
        if [.highlight,.underline,.strikeOut].contains(subtype) { guard !entry.quads.isEmpty else { return nil } }
        if subtype == .line { guard Reader.points(entry.attributes["start"] ?? "").count == 1,Reader.points(entry.attributes["end"] ?? "").count == 1 else { return nil } }
        let annotation = PDFAnnotation(bounds: rect,forType: subtype,withProperties: nil)
        let hex = (entry.attributes["color"] ?? "#FF0000").replacingOccurrences(of: "#",with: "")
        let opacity = Double(entry.attributes["opacity"] ?? "1") ?? 1,width = Double(entry.attributes["width"] ?? "1") ?? 1
        guard opacity.isFinite,width.isFinite else { return nil }
        let rgb = UInt32(hex,radix: 16) ?? 0xff0000,alpha = min(1,max(0,opacity))
        annotation.color = NSColor(srgbRed: CGFloat((rgb>>16)&255)/255,green: CGFloat((rgb>>8)&255)/255,blue: CGFloat(rgb&255)/255,alpha: alpha)
        let border = PDFBorder(); border.lineWidth = min(100,max(0,width))
        guard let style = borderStyle(entry.attributes["style"] ?? "solid") else { return nil }; border.style = style
        if let raw = entry.attributes["dashes"] { guard let values = dashValues(raw) else { return nil }; border.dashPattern = values.map { NSNumber(value: $0) } }
        annotation.border = border; annotation.contents = entry.contents
        annotation.userName = entry.attributes["title"]
        if let text = entry.attributes["date"] { guard let date = modificationDate(text) else { return nil }; annotation.modificationDate = date }
        if let raw = entry.attributes["flags"] {
            annotation.setValue(NSNumber(value: flagsValue(raw)),forAnnotationKey: .flags)
        }
        if [.square,.circle,.line].contains(subtype),let raw = entry.attributes["interior-color"],raw.hasPrefix("#"),raw.count == 7,let fill = UInt32(raw.dropFirst(),radix: 16) {
            annotation.interiorColor = NSColor(srgbRed: CGFloat((fill>>16)&255)/255,green: CGFloat((fill>>8)&255)/255,blue: CGFloat(fill&255)/255,alpha: 1)
        }
        if subtype == .text {
            guard let icon = noteIcon(entry.attributes["icon"] ?? "Note") else { return nil }; annotation.iconType = icon
        }
        if subtype == .freeText {
            annotation.font = .systemFont(ofSize: 12); annotation.fontColor = annotation.color; annotation.color = .clear
            let justification = entry.attributes["justification"]?.lowercased() ?? "left"
            guard ["left","centered","right"].contains(justification) else { return nil }
            annotation.alignment = justification == "right" ? .right : justification == "centered" ? .center : .left
        }
        if subtype == .line,let start = entry.attributes["start"],let end = entry.attributes["end"],let a = Reader.points(start).first,let b = Reader.points(end).first { annotation.startPoint = CGPoint(x: a.x-rect.minX,y: a.y-rect.minY); annotation.endPoint = CGPoint(x: b.x-rect.minX,y: b.y-rect.minY) }
        if subtype == .line {
            guard let start = lineStyle(entry.attributes["head"] ?? "None"),let end = lineStyle(entry.attributes["tail"] ?? "None") else { return nil }
            annotation.startLineStyle = start; annotation.endLineStyle = end
        }
        if !entry.quads.isEmpty,entry.quads.count%4 == 0 { annotation.quadrilateralPoints = entry.quads.map { NSValue(point: CGPoint(x: $0.x-rect.minX,y: $0.y-rect.minY)) } }
        for gesture in entry.gestures where !gesture.isEmpty { let path = NSBezierPath(); for (i,p) in gesture.enumerated() { let point = CGPoint(x: p.x-rect.minX,y: p.y-rect.minY); if i == 0 { path.move(to: point) } else { path.line(to: point) } }; annotation.add(path) }
        return (page,annotation)
    }
}

// FDF form data. The parser reads data objects only; actions and scripts are never executed.
enum PDFFDF {
    enum FieldValue: Equatable { case text(String), name(String), array([String])
        var strings: [String] { switch self { case .text(let s),.name(let s): [s]; case .array(let s): s } }
    }
    // PDFDocEncoding differs from Latin-1/Windows-1252 in these ranges.
    static func decodeText(_ bytes: [UInt8],encoding: String.Encoding? = nil) throws -> String {
        let explicit: (ArraySlice<UInt8>,String.Encoding)?
        if bytes.starts(with: [254,255]) { explicit = (bytes.dropFirst(2),.utf16BigEndian) }
        else if bytes.starts(with: [255,254]) { explicit = (bytes.dropFirst(2),.utf16LittleEndian) }
        else if bytes.starts(with: [239,187,191]) { explicit = (bytes.dropFirst(3),.utf8) }
        else if let encoding { explicit = (bytes[...],encoding) }
        else { explicit = nil }
        if let (data,encoding) = explicit { guard let text = String(data: Data(data),encoding: encoding) else { throw PDFSourceError.content }; return text }
        let accents: [UInt32] = [0x02D8,0x02C7,0x02C6,0x02D9,0x02DD,0x02DB,0x02DA,0x02DC]
        let punctuation: [UInt32] = [0x2022,0x2020,0x2021,0x2026,0x2014,0x2013,0x0192,0x2044,0x2039,0x203A,0x2212,0x2030,0x201E,0x201C,0x201D,0x2018,0x2019,0x201A,0x2122,0xFB01,0xFB02,0x0141,0x0152,0x0160,0x0178,0x017D,0x0131,0x0142,0x0153,0x0161,0x017E]
        return String(String.UnicodeScalarView(bytes.map { byte in
            let scalar: UInt32
            switch byte { case 0x18...0x1F: scalar = accents[Int(byte-0x18)]; case 0x80...0x9E: scalar = punctuation[Int(byte-0x80)]; case 0xA0: scalar = 0x20AC; case 0x16,0x7F,0x9F,0xAD: scalar = 0xFFFD; default: scalar = UInt32(byte) }
            return UnicodeScalar(scalar)!
        }))
    }
    private indirect enum Value { case string([UInt8]), name(String), array([Value]), dictionary([String:Value]), number(Int), real(Double), reference(Int,Int), keyword(String) }
    private struct Parser {
        let bytes: [UInt8]
        var at = 0, tokens = 0
        mutating func skip() {
            while at < bytes.count {
                if bytes[at] == 37 { while at < bytes.count && bytes[at] != 10 && bytes[at] != 13 { at += 1 } }
                else if [0,9,10,12,13,32].contains(bytes[at]) { at += 1 }
                else { break }
            }
        }
        func decode(_ data: [UInt8]) -> String {
            String(bytes: data,encoding: .utf8) ?? (try? PDFFDF.decodeText(data)) ?? ""
        }
        mutating func word() -> String {
            skip(); let start = at
            while at < bytes.count && ![0,9,10,12,13,32,40,41,60,62,91,93,47,37].contains(bytes[at]) { at += 1 }
            return String(decoding: bytes[start..<at],as: UTF8.self)
        }
        mutating func value(_ depth: Int = 0) throws -> Value {
            skip(); tokens += 1
            guard depth < 64,tokens < 500000,at < bytes.count else { throw PDFSourceError.content }
            let c = bytes[at]; at += 1
            if c == 40 {
                var result: [UInt8] = [],nesting = 1
                while at < bytes.count && nesting > 0 {
                    let c = bytes[at]; at += 1
                    if c == 92 {
                        guard at < bytes.count else { throw PDFSourceError.content }; let escaped = bytes[at]; at += 1
                        if escaped == 13 { if at < bytes.count && bytes[at] == 10 { at += 1 }; continue }
                        if escaped == 10 { continue }
                        if (48...55).contains(escaped) {
                            var number = Int(escaped-48),digits = 1
                            while digits < 3 && at < bytes.count && (48...55).contains(bytes[at]) { number = number*8+Int(bytes[at]-48); at += 1; digits += 1 }
                            result.append(UInt8(number & 255))
                        } else { result.append([110:10,114:13,116:9,98:8,102:12][escaped] ?? escaped) }
                    } else if c == 40 { nesting += 1; result.append(c) }
                    else if c == 41 { nesting -= 1; if nesting > 0 { result.append(c) } }
                    else { result.append(c) }
                    guard result.count <= 1_000_000 else { throw PDFSourceError.content }
                }
                guard nesting == 0 else { throw PDFSourceError.content }; return .string(result)
            }
            if c == 60 {
                if at < bytes.count && bytes[at] == 60 {
                    at += 1; var dictionary: [String:Value] = [:]
                    while true {
                        skip(); guard at+1 < bytes.count else { throw PDFSourceError.content }
                        if bytes[at] == 62 && bytes[at+1] == 62 { at += 2; return .dictionary(dictionary) }
                        guard case .name(let key) = try value(depth+1) else { throw PDFSourceError.content }
                        dictionary[key] = try value(depth+1)
                    }
                }
                var hex: [UInt8] = []
                while at < bytes.count && bytes[at] != 62 { if ![9,10,12,13,32].contains(bytes[at]) { hex.append(bytes[at]) }; at += 1 }
                guard at < bytes.count else { throw PDFSourceError.content }; at += 1
                if hex.count%2 == 1 { hex.append(48) }
                var result: [UInt8] = []
                for i in stride(from: 0,to: hex.count,by: 2) { guard let byte = UInt8(String(decoding: hex[i..<(i+2)],as: UTF8.self),radix: 16) else { throw PDFSourceError.content }; result.append(byte) }
                return .string(result)
            }
            if c == 91 {
                var list: [Value] = []
                while true { skip(); guard at < bytes.count else { throw PDFSourceError.content }; if bytes[at] == 93 { at += 1; return .array(list) }; list.append(try value(depth+1)) }
            }
            if c == 47 {
                let start = at
                while at < bytes.count && ![0,9,10,12,13,32,40,41,60,62,91,93,47,37].contains(bytes[at]) { at += 1 }
                var raw: [UInt8] = [],i = start
                while i < at {
                    if bytes[i] == 35,i+2 < at,let byte = UInt8(String(decoding: bytes[(i+1)...(i+2)],as: UTF8.self),radix: 16) { raw.append(byte); i += 3 }
                    else { raw.append(bytes[i]); i += 1 }
                }
                return .name(decode(raw))
            }
            at -= 1; let token = word()
            guard !token.isEmpty else { throw PDFSourceError.content }
            if let number = Int(token) {
                let saved = at,second = word(),third = word()
                if let generation = Int(second),third == "R" { return .reference(number,generation) }
                at = saved; return .number(number)
            }
            if let real = Double(token),real.isFinite { return .real(real) }
            guard token != "stream" else { throw PDFSourceError.content }
            return .keyword(token)
        }
    }
    private static func contents(_ data: Data) throws -> ([String:Value],[String:Value]) {
        guard data.count <= 32*1024*1024,data.starts(with: Data("%FDF-".utf8)) else { throw PDFSourceError.content }
        var parser = Parser(bytes: Array(data)),objects: [String:Value] = [:],root: Value?
        while true {
            parser.skip(); if parser.at == parser.bytes.count { break }
            let start = parser.at,first = parser.word()
            if first == "trailer" { root = try parser.value(); continue }
            let second = parser.word(),third = parser.word()
            if let id = Int(first),let generation = Int(second),third == "obj" {
                objects["\(id):\(generation)"] = try parser.value()
                guard parser.word() == "endobj" else { throw PDFSourceError.content }
            } else {
                parser.at = start; guard parser.word() != "stream",parser.at > start else { throw PDFSourceError.content }
            }
        }
        func resolve(_ value: Value?,depth: Int = 0) throws -> Value {
            guard let value,depth < 64 else { throw PDFSourceError.content }
            if case .reference(let id,let generation) = value { return try resolve(objects["\(id):\(generation)"],depth: depth+1) }
            return value
        }
        guard case .dictionary(let trailer) = try resolve(root),case .dictionary(let document) = try resolve(trailer["Root"]),
              case .dictionary(let fdf) = try resolve(document["FDF"]) else { throw PDFSourceError.content }
        return (objects,fdf)
    }
    static func read(_ data: Data) throws -> [String:FieldValue] {
        let (objects,fdf) = try contents(data)
        func resolve(_ value: Value?,depth: Int = 0) throws -> Value {
            guard let value,depth < 64 else { throw PDFSourceError.content }
            if case .reference(let id,let generation) = value { return try resolve(objects["\(id):\(generation)"],depth: depth+1) }
            return value
        }
        guard case .array(let fields) = try resolve(fdf["Fields"]) else { throw PDFSourceError.content }
        let encoding: String.Encoding?
        if let raw = fdf["Encoding"] {
            guard case .name(let name) = try resolve(raw) else { throw PDFSourceError.content }
            switch name { case "PDFDocEncoding": encoding = nil; case "utf_8": encoding = .utf8; case "utf_16": encoding = .utf16BigEndian; default: throw PDFSourceError.content }
        } else { encoding = nil }
        var result: [String:FieldValue] = [:]
        func collect(_ values: [Value],prefix: String,depth: Int) throws {
            guard depth < 64,result.count <= 50000 else { throw PDFSourceError.content }
            for value in values {
                guard case .dictionary(let field) = try resolve(value) else { throw PDFSourceError.content }
                let name: String
                if let title = field["T"],case .string(let raw) = try resolve(title) { let text = try decodeText(raw,encoding: encoding); name = prefix.isEmpty ? text : prefix+"."+text } else { name = prefix }
                if let raw = field["V"] {
                    switch try resolve(raw) {
                    case .string(let value): result[name] = .text(try decodeText(value,encoding: encoding))
                    case .name(let value): result[name] = .name(value)
                    case .array(let values): result[name] = .array(try values.map { value in switch try resolve(value) { case .string(let s): return try decodeText(s,encoding: encoding); case .name(let s): return s; default: throw PDFSourceError.content } })
                    case .keyword("null"): result[name] = .text("")
                    default: throw PDFSourceError.content
                    }
                }
                if let kids = field["Kids"],case .array(let children) = try resolve(kids) { try collect(children,prefix: name,depth: depth+1) }
            }
        }
        try collect(fields,prefix: "",depth: 0); return result
    }
    static func write(_ values: [String:FieldValue]) -> Data {
        func string(_ text: String) -> String { "<FEFF"+text.utf16.map { String(format: "%04X",$0) }.joined()+">" }
        func name(_ text: String) -> String { "/"+text.utf8.map { (33...126).contains($0) && !Array("()<>[]{}/%#".utf8).contains($0) ? String(UnicodeScalar($0)) : String(format: "#%02X",$0) }.joined() }
        let fields = values.keys.sorted().map { key -> String in
            let value: String
            switch values[key]! { case .text(let s): value = string(s); case .name(let s): value = name(s); case .array(let s): value = "["+s.map(string).joined(separator: " ")+"]" }
            return "<< /T \(string(key)) /V \(value) >>"
        }.joined(separator: "\n")
        return Data(("%FDF-1.2\n1 0 obj\n<< /FDF << /Fields [\n"+fields+"\n] >> >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n").utf8)
    }
}

extension PDFFDF {
    struct Comments { let entries: [PDFXFDF.Comment],unsupported: Int }
    private struct CommentFile {
        let objects: [String:Value],dictionary: [String:Value]
        init(_ data: Data) throws { (objects,dictionary) = try PDFFDF.contents(data) }
        func resolve(_ value: Value?,depth: Int = 0) throws -> Value {
            guard let value,depth < 64 else { throw PDFSourceError.content }
            if case .reference(let id,let generation) = value { return try resolve(objects["\(id):\(generation)"],depth: depth+1) }; return value
        }
        func array(_ value: Value?) throws -> [Value] { guard case .array(let items) = try resolve(value) else { throw PDFSourceError.content }; return items }
        func numbers(_ value: Value?) throws -> [Double] {
            try array(value).map { item in
                let number: Double
                switch try resolve(item) { case .number(let n): number = Double(n); case .real(let n): number = n; default: throw PDFSourceError.content }
                guard number.isFinite,abs(number) <= 1_000_000 else { throw PDFSourceError.content }; return number
            }
        }
        func text(_ value: Value?) throws -> String {
            guard let value else { return "" }; guard case .string(let text) = try resolve(value) else { throw PDFSourceError.content }; return try PDFFDF.decodeText(text)
        }
        func color(_ value: Value?) throws -> String? {
            guard let value else { return nil }; let channels = try numbers(value)
            guard channels.allSatisfy({ (0...1).contains($0) }) else { throw PDFSourceError.content }
            let rgb: [Double]
            switch channels.count { case 1: rgb = Array(repeating: channels[0],count: 3); case 3: rgb = channels; case 4: rgb = channels.prefix(3).map { 1-min(1,$0+channels[3]) }; default: throw PDFSourceError.content }
            return String(format: "#%02X%02X%02X",Int((rgb[0]*255).rounded()),Int((rgb[1]*255).rounded()),Int((rgb[2]*255).rounded()))
        }
    }
    static func readComments(_ data: Data) throws -> Comments {
        let file = try CommentFile(data),annotations = try file.array(file.dictionary["Annots"])
        guard annotations.count <= 50000 else { throw PDFSourceError.content }
        let kinds = ["Text":"text","FreeText":"freetext","Highlight":"highlight","Underline":"underline","StrikeOut":"strikeout","Square":"square","Circle":"circle","Line":"line","Ink":"ink"]
        var result: [PDFXFDF.Comment] = [],unsupported = 0
        for value in annotations {
            guard case .dictionary(let values) = try file.resolve(value),case .name(let subtype) = try file.resolve(values["Subtype"]) else { throw PDFSourceError.content }
            guard let kind = kinds[subtype] else { unsupported += 1; continue }
            guard case .number(let page) = try file.resolve(values["Page"]),page >= 0 else { throw PDFSourceError.content }
            let rect = try file.numbers(values["Rect"]); guard rect.count == 4,rect[2] > rect[0],rect[3] > rect[1] else { throw PDFSourceError.content }
            var attrs = ["page":String(page),"rect":rect.map { String($0) }.joined(separator: ","),"color":try file.color(values["C"]) ?? "#000000"]
            if let fill = try file.color(values["IC"]) { attrs["interior-color"] = fill }
            if let flags = values["F"] { guard case .number(let bits) = try file.resolve(flags),bits >= 0 else { throw PDFSourceError.content }; attrs["flags"] = PDFXFDF.flagsText(bits) }
            if values["T"] != nil { attrs["title"] = try file.text(values["T"]) }
            if values["M"] != nil { let text = try file.text(values["M"]); guard PDFXFDF.modificationDate(text) != nil else { throw PDFSourceError.content }; attrs["date"] = text }
            if kind == "text",let raw = values["Name"] { guard case .name(let icon) = try file.resolve(raw),PDFXFDF.noteIcon(icon) != nil else { throw PDFSourceError.content }; attrs["icon"] = icon }
            if kind == "freetext",let raw = values["Q"] { guard case .number(let value) = try file.resolve(raw),(0...2).contains(value) else { throw PDFSourceError.content }; attrs["justification"] = ["left","centered","right"][value] }
            if let raw = values["CA"] { let alpha: Double; switch try file.resolve(raw) { case .number(let n): alpha = Double(n); case .real(let n): alpha = n; default: throw PDFSourceError.content }; guard alpha.isFinite,(0...1).contains(alpha) else { throw PDFSourceError.content }; attrs["opacity"] = String(alpha) }
            if let raw = values["BS"] {
                guard case .dictionary(let border) = try file.resolve(raw) else { throw PDFSourceError.content }
                if let width = border["W"] { switch try file.resolve(width) { case .number(let n): attrs["width"] = String(n); case .real(let n): attrs["width"] = String(n); default: throw PDFSourceError.content } }
                if let raw = border["S"] { guard case .name(let name) = try file.resolve(raw),let index = ["S","D","B","I","U"].firstIndex(of: name) else { throw PDFSourceError.content }; attrs["style"] = PDFXFDF.borderNames[index] }
                if let raw = border["D"] { let text = try file.numbers(raw).map { String($0) }.joined(separator: ","); guard PDFXFDF.dashValues(text) != nil else { throw PDFSourceError.content }; attrs["dashes"] = text }
            }
            if kind == "line" {
                let line = try file.numbers(values["L"]); guard line.count == 4 else { throw PDFSourceError.content }
                attrs["start"] = "\(line[0]),\(line[1])"; attrs["end"] = "\(line[2]),\(line[3])"
                if let raw = values["LE"] {
                    let endings = try file.array(raw); guard endings.count == 2 else { throw PDFSourceError.content }
                    for (index,key) in ["head","tail"].enumerated() { guard case .name(let name) = try file.resolve(endings[index]),PDFXFDF.lineStyle(name) != nil else { throw PDFSourceError.content }; attrs[key] = name }
                }
            }
            func points(_ numbers: [Double]) throws -> [CGPoint] {
                guard numbers.count%2 == 0 else { throw PDFSourceError.content }
                return stride(from: 0,to: numbers.count,by: 2).map { CGPoint(x: numbers[$0],y: numbers[$0+1]) }
            }
            var gestures: [[CGPoint]] = [],quads: [CGPoint] = []
            if kind == "ink" { for stroke in try file.array(values["InkList"]) { let strokePoints = try points(file.numbers(stroke)); guard strokePoints.count >= 2 else { throw PDFSourceError.content }; gestures.append(strokePoints) }; guard !gestures.isEmpty else { throw PDFSourceError.content } }
            if let raw = values["QuadPoints"] { quads = try points(file.numbers(raw)); guard !quads.isEmpty,quads.count%4 == 0 else { throw PDFSourceError.content } }
            result.append(PDFXFDF.Comment(kind: kind,attributes: attrs,contents: try file.text(values["Contents"]),gestures: gestures,quads: quads))
        }
        return Comments(entries: result,unsupported: unsupported)
    }
    static func writeComments(_ entries: [PDFXFDF.Comment]) throws -> Data {
        guard entries.count <= 50000 else { throw PDFSourceError.content }
        func string(_ text: String) -> String { "<FEFF"+text.utf16.map { String(format: "%04X",$0) }.joined()+">" }
        func numbers(_ value: String) throws -> String {
            let points = PDFXFDF.Reader.points(value); guard !points.isEmpty else { throw PDFSourceError.content }
            return "["+points.map { "\($0.x) \($0.y)" }.joined(separator: " ")+"]"
        }
        func color(_ text: String) throws -> String {
            guard text.hasPrefix("#"),text.count == 7,let rgb = UInt32(text.dropFirst(),radix: 16) else { throw PDFSourceError.content }
            return "[\(Double((rgb>>16)&255)/255) \(Double((rgb>>8)&255)/255) \(Double(rgb&255)/255)]"
        }
        let kinds = ["text":"Text","freetext":"FreeText","highlight":"Highlight","underline":"Underline","strikeout":"StrikeOut","square":"Square","circle":"Circle","line":"Line","ink":"Ink"]
        var annotations: [String] = []
        for entry in entries {
            guard let subtype = kinds[entry.kind],let page = entry.attributes["page"].flatMap(Int.init),page >= 0,let rect = entry.attributes["rect"] else { throw PDFSourceError.content }
            let corners = PDFXFDF.Reader.points(rect),points = entry.gestures.flatMap { $0 }+entry.quads
            guard corners.count == 2,corners[1].x > corners[0].x,corners[1].y > corners[0].y,points.count <= 100000,points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1_000_000 && abs($0.y) <= 1_000_000 }),entry.quads.count%4 == 0 else { throw PDFSourceError.content }
            if entry.kind == "ink" { guard !entry.gestures.isEmpty,entry.gestures.allSatisfy({ $0.count >= 2 }) else { throw PDFSourceError.content } }
            if entry.kind == "line" { guard PDFXFDF.Reader.points(entry.attributes["start"] ?? "").count == 1,PDFXFDF.Reader.points(entry.attributes["end"] ?? "").count == 1 else { throw PDFSourceError.content } }
            let alpha = Double(entry.attributes["opacity"] ?? "1") ?? .nan,width = Double(entry.attributes["width"] ?? "1") ?? .nan
            guard alpha.isFinite,(0...1).contains(alpha),width.isFinite,(0...100).contains(width) else { throw PDFSourceError.content }
            guard let style = PDFXFDF.borderStyle(entry.attributes["style"] ?? "solid") else { throw PDFSourceError.content }
            var bs = "<< /W \(width) /S /"+["S","D","B","I","U"][style.rawValue]
            if let raw = entry.attributes["dashes"] { guard let values = PDFXFDF.dashValues(raw) else { throw PDFSourceError.content }; bs += " /D ["+values.map { String($0) }.joined(separator: " ")+"]" }; bs += " >>"
            var body = "<< /Type /Annot /Subtype /\(subtype) /Page \(page) /Rect "+(try numbers(rect))+" /Contents "+string(entry.contents)+" /CA \(alpha) /BS "+bs+" /F \(PDFXFDF.flagsValue(entry.attributes["flags"] ?? ""))"
            body += " /C "+(try color(entry.attributes["color"] ?? "#000000"))
            if let fill = entry.attributes["interior-color"] { body += " /IC "+(try color(fill)) }
            if let author = entry.attributes["title"] { body += " /T "+string(author) }
            if let text = entry.attributes["date"] { guard PDFXFDF.modificationDate(text) != nil else { throw PDFSourceError.content }; body += " /M "+string(text) }
            if entry.kind == "text" { let name = entry.attributes["icon"] ?? "Note"; guard PDFXFDF.noteIcon(name) != nil else { throw PDFSourceError.content }; body += " /Name /"+name }
            if entry.kind == "freetext" { let name = entry.attributes["justification"] ?? "left"; guard let value = ["left","centered","right"].firstIndex(of: name) else { throw PDFSourceError.content }; body += " /Q \(value)" }
            if entry.kind == "line" {
                guard let start = entry.attributes["start"],let end = entry.attributes["end"] else { throw PDFSourceError.content }; body += " /L "+(try numbers(start+","+end))
                let head = entry.attributes["head"] ?? "None",tail = entry.attributes["tail"] ?? "None"
                guard PDFXFDF.lineStyle(head) != nil,PDFXFDF.lineStyle(tail) != nil else { throw PDFSourceError.content }
                body += " /LE [/\(head) /\(tail)]"
            }
            if entry.kind == "ink" { body += " /InkList ["+entry.gestures.map { "["+$0.map { "\($0.x) \($0.y)" }.joined(separator: " ")+"]" }.joined(separator: " ")+"]" }
            if !entry.quads.isEmpty { body += " /QuadPoints ["+entry.quads.map { "\($0.x) \($0.y)" }.joined(separator: " ")+"]" }
            annotations.append(body+" >>")
        }
        let bytes = Data(("%FDF-1.3\n1 0 obj\n<< /FDF << /Annots [\n"+annotations.joined(separator: "\n")+"\n] >> >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n").utf8)
        guard bytes.count <= 32*1024*1024 else { throw PDFSourceError.content }; return bytes
    }
}
