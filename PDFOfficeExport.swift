// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import PDFKit
import Foundation

struct PDFOfficeText: Sendable { var text: String, bounds: CGRect, font: String, size: Double }
struct PDFOfficePage: Sendable { var width: Double, height: Double, blocks: [PDFOfficeText] }
@MainActor struct PDFOfficeRequest: Identifiable {
    let id = UUID(); let format: String, russian: Bool, count: Int
    let export: (String) -> String?
}
struct PDFOfficePanel: View {
    let request: PDFOfficeRequest
    @Environment(\.dismiss) private var dismiss
    @State private var range = "all"
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading,spacing: 16) {
            Text(request.russian ? "Базовый экспорт в Office" : "Basic Office export").font(.title2)
            Text(request.format == "word" ? "Word · DOCX" : request.format == "excel" ? "Excel · XLSX" : "PowerPoint · PPTX")
            Text(request.russian ? "Экспортируется существующий текстовый слой. DOCX содержит абзацы с разрывами страниц; XLSX — строки текста по листам; PPTX — редактируемые текстовые поля с геометрией PDF. Иллюстрации, чертежи, таблицы, колонки и исходная вёрстка полностью не восстанавливаются. Для сканов сначала выполните OCR." : "Exports existing text. DOCX contains paragraphs and page breaks; XLSX contains text rows on separate sheets; PPTX contains editable text boxes using PDF geometry. Graphics, drawings, tables, columns and original layout are not fully reconstructed. Run OCR first for scans.").font(.callout)
            TextField(request.russian ? "Страницы: all или 1-3,5" : "Pages: all or 1-3,5",text: $range)
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Spacer(); Button(request.russian ? "Отмена" : "Cancel") { dismiss() }; Button(request.russian ? "Экспорт…" : "Export…") { error = request.export(range); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 580)
    }
}
enum PDFOfficeExporter {
    static let relationship = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
    static func xml(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.filter { $0.value == 9 || $0.value == 10 || $0.value == 13 || ($0.value >= 32 && $0.value <= 0xD7FF) || ($0.value >= 0xE000 && $0.value <= 0xFFFD) || ($0.value >= 0x10000 && $0.value <= 0x10FFFF) }))
            .replacingOccurrences(of: "&",with: "&amp;").replacingOccurrences(of: "<",with: "&lt;").replacingOccurrences(of: ">",with: "&gt;").replacingOccurrences(of: "\"",with: "&quot;")
    }
    static func rels(_ rows: [(String,String,String)]) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"+rows.map { "<Relationship Id=\"\(xml($0.0))\" Type=\"\(relationship+xml($0.1))\" Target=\"\(xml($0.2))\"/>" }.joined()+"</Relationships>"
    }
    static func create(pages: [PDFOfficePage],format: String) throws -> Data {
        guard !pages.isEmpty,pages.count <= 10000,pages.contains(where: { $0.blocks.contains { !$0.text.isEmpty } }) else { throw PDFSourceError.textNotFound }
        var files: [(String,Data)] = [],overrides: [(String,String)] = []
        func add(_ name: String,_ text: String,_ type: String? = nil) { files.append((name,Data(text.utf8))); if let type { overrides.append(("/"+name,type)) } }
        let prefix = "application/vnd.openxmlformats-officedocument."
        let root: String
        if format == "word" {
            root = "word/document.xml"
            var body = ""
            for (index,page) in pages.enumerated() {
                try Task.checkCancellation()
                for block in page.blocks {
                    for line in block.text.components(separatedBy: .newlines) {
                        body += "<w:p><w:r><w:rPr><w:rFonts w:ascii=\"\(xml(block.font))\" w:hAnsi=\"\(xml(block.font))\"/><w:sz w:val=\"\(Int(min(400,max(6,block.size))*2))\"/></w:rPr><w:t xml:space=\"preserve\">\(xml(line))</w:t></w:r></w:p>"
                    }
                }
                if index+1 < pages.count { body += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>" }
            }
            add(root,"<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:document xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:body>"+body+"<w:sectPr><w:pgSz w:w=\"11906\" w:h=\"16838\"/><w:pgMar w:top=\"720\" w:right=\"720\" w:bottom=\"720\" w:left=\"720\"/></w:sectPr></w:body></w:document>",prefix+"wordprocessingml.document.main+xml")
        } else if format == "excel" {
            root = "xl/workbook.xml"
            var sheets = "",links: [(String,String,String)] = []
            for (index,page) in pages.enumerated() {
                try Task.checkCancellation()
                let id = index+1
                sheets += "<sheet name=\"Page \(id)\" sheetId=\"\(id)\" r:id=\"rId\(id)\"/>"; links.append(("rId\(id)","worksheet","worksheets/sheet\(id).xml"))
                let lines = page.blocks.flatMap { $0.text.components(separatedBy: .newlines) }
                guard lines.count <= 1_048_576 else { throw PDFSourceError.content }
                var rows = ""
                for (row,line) in lines.enumerated() {
                    let values = line.components(separatedBy: "\t"); guard values.count <= 16384 else { throw PDFSourceError.content }
                    rows += "<row r=\"\(row+1)\">"
                    for (column,value) in values.enumerated() {
                        var number = column+1,name = ""
                        while number > 0 { number -= 1; name = String(UnicodeScalar(65+number%26)!)+name; number /= 26 }
                        rows += "<c r=\"\(name)\(row+1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(xml(String(value.prefix(32767))))</t></is></c>"
                    }; rows += "</row>"
                }
                add("xl/worksheets/sheet\(id).xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData>"+rows+"</sheetData></worksheet>",prefix+"spreadsheetml.worksheet+xml")
            }
            add(root,"<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"\(String(relationship.dropLast()))\"><sheets>"+sheets+"</sheets></workbook>",prefix+"spreadsheetml.sheet.main+xml")
            add("xl/_rels/workbook.xml.rels",rels(links))
        } else if format == "powerpoint" {
            root = "ppt/presentation.xml"
            let size = pages[0],cx = Int64(min(14400,max(1,size.width))*12700),cy = Int64(min(14400,max(1,size.height))*12700)
            let ns = "xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"\(String(relationship.dropLast()))\" xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\""
            let group = "<p:nvGrpSpPr><p:cNvPr id=\"1\" name=\"\"/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"0\" cy=\"0\"/><a:chOff x=\"0\" y=\"0\"/><a:chExt cx=\"0\" cy=\"0\"/></a:xfrm></p:grpSpPr>"
            var links = [("master","slideMaster","slideMasters/slideMaster1.xml")],slides = ""
            for (index,page) in pages.enumerated() {
                try Task.checkCancellation()
                let id = index+1; links.append(("rId\(id)","slide","slides/slide\(id).xml")); slides += "<p:sldId id=\"\(255+id)\" r:id=\"rId\(id)\"/>"
                let factor = min(Double(cx)/max(1,page.width),Double(cy)/max(1,page.height))
                var shapes = ""
                for (i,block) in page.blocks.enumerated() {
                    let x = Int64(max(0,block.bounds.minX)*factor),y = Int64(max(0,page.height-block.bounds.maxY)*factor)
                    let width = Int64(max(1,block.bounds.width)*factor),height = Int64(max(1,block.bounds.height)*factor)
                    let paragraphs = block.text.components(separatedBy: .newlines).map { "<a:p><a:r><a:rPr lang=\"ru-RU\" sz=\"\(Int(min(400,max(1,block.size*factor/12700))*100))\"><a:solidFill><a:srgbClr val=\"000000\"/></a:solidFill><a:latin typeface=\"\(xml(block.font))\"/></a:rPr><a:t>\(xml($0))</a:t></a:r><a:endParaRPr/></a:p>" }.joined()
                    shapes += "<p:sp><p:nvSpPr><p:cNvPr id=\"\(i+2)\" name=\"Text \(i+1)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x=\"\(x)\" y=\"\(y)\"/><a:ext cx=\"\(width)\" cy=\"\(height)\"/></a:xfrm><a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap=\"square\" lIns=\"0\" tIns=\"0\" rIns=\"0\" bIns=\"0\"><a:noAutofit/></a:bodyPr><a:lstStyle/>"+paragraphs+"</p:txBody></p:sp>"
                }
                add("ppt/slides/slide\(id).xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sld \(ns)><p:cSld><p:spTree>"+group+shapes+"</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>",prefix+"presentationml.slide+xml")
                add("ppt/slides/_rels/slide\(id).xml.rels",rels([("layout","slideLayout","../slideLayouts/slideLayout1.xml")]))
            }
            add(root,"<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:presentation \(ns)><p:sldMasterIdLst><p:sldMasterId id=\"2147483648\" r:id=\"master\"/></p:sldMasterIdLst><p:sldIdLst>"+slides+"</p:sldIdLst><p:sldSz cx=\"\(cx)\" cy=\"\(cy)\"/><p:notesSz cx=\"6858000\" cy=\"9144000\"/></p:presentation>",prefix+"presentationml.presentation.main+xml")
            add("ppt/_rels/presentation.xml.rels",rels(links))
            let colorMap = "<p:clrMap accent1=\"accent1\" accent2=\"accent2\" accent3=\"accent3\" accent4=\"accent4\" accent5=\"accent5\" accent6=\"accent6\" bg1=\"lt1\" bg2=\"lt2\" folHlink=\"folHlink\" hlink=\"hlink\" tx1=\"dk1\" tx2=\"dk2\"/>"
            add("ppt/slideMasters/slideMaster1.xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sldMaster \(ns)><p:cSld><p:spTree>"+group+"</p:spTree></p:cSld>"+colorMap+"<p:sldLayoutIdLst><p:sldLayoutId id=\"2147483649\" r:id=\"layout\"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>",prefix+"presentationml.slideMaster+xml")
            add("ppt/slideMasters/_rels/slideMaster1.xml.rels",rels([("layout","slideLayout","../slideLayouts/slideLayout1.xml"),("theme","theme","../theme/theme1.xml")]))
            add("ppt/slideLayouts/slideLayout1.xml","<?xml version=\"1.0\" encoding=\"UTF-8\"?><p:sldLayout \(ns) type=\"blank\" preserve=\"1\"><p:cSld name=\"Blank\"><p:spTree>"+group+"</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>",prefix+"presentationml.slideLayout+xml")
            add("ppt/slideLayouts/_rels/slideLayout1.xml.rels",rels([("master","slideMaster","../slideMasters/slideMaster1.xml")]))
            let colors = [("dk1","000000"),("lt1","FFFFFF"),("dk2","202020"),("lt2","EEEEEE"),("accent1","B12C40"),("accent2","2784C5"),("accent3","47A06A"),("accent4","D69B32"),("accent5","8055AA"),("accent6","477B8A"),("hlink","0563C1"),("folHlink","954F72")].map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
            let fill = "<a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill>"
            let line = "<a:ln w=\"9525\">"+fill+"<a:prstDash val=\"solid\"/></a:ln>"
            let theme = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"BotPlus\"><a:themeElements><a:clrScheme name=\"BotPlus\">"+colors+"</a:clrScheme><a:fontScheme name=\"BotPlus\"><a:majorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"Arial\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"BotPlus\"><a:fillStyleLst>"+String(repeating: fill,count: 3)+"</a:fillStyleLst><a:lnStyleLst>"+String(repeating: line,count: 3)+"</a:lnStyleLst><a:effectStyleLst>"+String(repeating: "<a:effectStyle><a:effectLst/></a:effectStyle>",count: 3)+"</a:effectStyleLst><a:bgFillStyleLst>"+String(repeating: fill,count: 3)+"</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>"
            add("ppt/theme/theme1.xml",theme,prefix+"theme+xml")
        } else { throw PDFSourceError.content }
        add("_rels/.rels",rels([("document","officeDocument",root)]))
        let types = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"+overrides.map { "<Override PartName=\"\(xml($0.0))\" ContentType=\"\(xml($0.1))\"/>" }.joined()+"</Types>"
        add("[Content_Types].xml",types)
        return try PDFStoredZip.make(files)
    }
}
// OOXML is a ZIP container. Stored entries avoid any third-party compressor.
enum PDFStoredZip {
    static func make(_ files: [(String,Data)]) throws -> Data {
        guard files.count < 65535,Set(files.map(\.0)).count == files.count else { throw PDFSourceError.content }
        var output = Data(),central = Data()
        func word(_ value: UInt16,_ buffer: inout Data) { buffer.append(UInt8(value & 255)); buffer.append(UInt8(value >> 8)) }
        func dword(_ value: UInt32,_ buffer: inout Data) { word(UInt16(value & 65535),&buffer); word(UInt16(value >> 16),&buffer) }
        func crc(_ bytes: Data) -> UInt32 { var value: UInt32 = 0xFFFFFFFF; for byte in bytes { value ^= UInt32(byte); for _ in 0..<8 { value = (value >> 1) ^ (value & 1 != 0 ? 0xEDB88320 : 0) } }; return value ^ 0xFFFFFFFF }
        for (name,bytes) in files {
            try Task.checkCancellation()
            let path = Data(name.utf8)
            guard path.count <= 65535,bytes.count <= 256*1024*1024,output.count <= 512*1024*1024 else { throw PDFSourceError.content }
            let checksum = crc(bytes),offset = UInt32(output.count),size = UInt32(bytes.count),length = UInt16(path.count)
            dword(0x04034B50,&output); word(20,&output); word(0x0800,&output); word(0,&output); word(0,&output); word(33,&output); dword(checksum,&output); dword(size,&output); dword(size,&output); word(length,&output); word(0,&output); output.append(path); output.append(bytes)
            dword(0x02014B50,&central); word(20,&central); word(20,&central); word(0x0800,&central); word(0,&central); word(0,&central); word(33,&central); dword(checksum,&central); dword(size,&central); dword(size,&central); word(length,&central); word(0,&central); word(0,&central); word(0,&central); word(0,&central); dword(0,&central); dword(offset,&central); central.append(path)
        }
        let offset = UInt32(output.count); output.append(central)
        dword(0x06054B50,&output); word(0,&output); word(0,&output); word(UInt16(files.count),&output); word(UInt16(files.count),&output); dword(UInt32(central.count),&output); dword(offset,&output); word(0,&output)
        return output
    }
}
