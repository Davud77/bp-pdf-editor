// SPDX-License-Identifier: AGPL-3.0-only
import SwiftUI
import AppKit
import PDFKit

enum PDFPathNodeKind: String, Codable { case move, line, curve, close }
struct PDFPathNode: Identifiable, Codable {
    var id = UUID()
    var kind: PDFPathNodeKind
    var point = CGPoint.zero, control1 = CGPoint.zero, control2 = CGPoint.zero
}
@MainActor struct PDFPathRequest: Identifiable {
    let id = UUID(); let nodes: [PDFPathNode], russian: Bool
    var ink = false
    let apply: ([PDFPathNode]) -> String?
}
struct PDFPathEditor: View {
    let request: PDFPathRequest
    @Environment(\.dismiss) private var dismiss
    @State private var nodes: [PDFPathNode] = []
    @State private var selected: UUID?
    @State private var error: String?
    private func label(_ en: String,_ ru: String) -> String { request.russian ? ru : en }
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(request.ink ? label("Edit Ink curves","Редактирование кривых Ink") : label("Edit vector path nodes","Редактирование узлов контура")).font(.title2)
            Text(request.ink ? label("Page coordinates in points. Control points remain editable in BotPlus metadata; the standard Ink paths use a fine polygonal approximation.","Координаты страницы в пунктах. Управляющие точки сохраняются в метаданных BotPlus; стандартные Ink-штрихи используют подробную ломаную.") : label("Coordinates are PDF points. Supports simple solid paths; tagged paths, clipping, patterns and transparency groups are refused to preserve their semantics.","Координаты в пунктах PDF. Поддерживаются простые контуры с обычной заливкой. Пути с тегами, обрезкой, узорами и сложной прозрачностью не изменяются.")).font(.caption).foregroundStyle(.secondary)
            HStack {
                List(nodes,selection: $selected) { node in Text(node.kind.rawValue+" · "+String(format: "%.1f, %.1f",node.point.x,node.point.y)).tag(node.id) }.frame(width: 210)
                VStack {
                    PathNodePreview(nodes: $nodes,selected: $selected).frame(width: 390,height: 330)
                    if let index = nodes.firstIndex(where: { $0.id == selected }),nodes[index].kind != .close {
                        HStack { number("X",$nodes[index].point.x); number("Y",$nodes[index].point.y) }
                        if nodes[index].kind == .curve {
                            HStack { number("C1 X",$nodes[index].control1.x); number("C1 Y",$nodes[index].control1.y) }
                            HStack { number("C2 X",$nodes[index].control2.x); number("C2 Y",$nodes[index].control2.y) }
                        }
                    }
                }
            }.frame(height: 450)
            HStack {
                Button(label("Add line","Добавить отрезок")) { nodes.append(PDFPathNode(kind: .line,point: nodes.last?.point ?? .zero)) }.disabled(request.ink && nodes.last?.kind == .close)
                if request.ink {
                    Button(label("Add curve","Добавить кривую")) {
                        let start = nodes.last(where: { $0.kind != .close })?.point ?? .zero
                        nodes.append(PDFPathNode(kind: .curve,point: CGPoint(x: start.x+30,y: start.y),control1: CGPoint(x: start.x+10,y: start.y+20),control2: CGPoint(x: start.x+20,y: start.y+20)))
                    }.disabled(nodes.last?.kind == .close)
                    Button(label("New stroke","Новый штрих")) { nodes.append(PDFPathNode(kind: .move,point: CGPoint(x: 50,y: 50))) }.disabled(nodes.last?.kind == .move)
                }
                Button(label("Close path","Замкнуть")) { nodes.append(PDFPathNode(kind: .close)) }.disabled(request.ink && (nodes.last?.kind == .close || nodes.last?.kind == .move))
                Button(label("Remove node","Удалить узел")) { if let index = nodes.firstIndex(where: { $0.id == selected }),index > 0 { nodes.remove(at: index); selected = nil } }.disabled(selected == nil || selected == nodes.first?.id)
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack { Button(label("Reset","Сбросить")) { nodes = request.nodes }; Spacer(); Button(label("Cancel","Отмена")) { dismiss() }; Button(label("Apply","Применить")) { error = request.apply(nodes); if error == nil { dismiss() } }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 700).onAppear { nodes = request.nodes }
    }
    private func number(_ title: String,_ value: Binding<CGFloat>) -> some View { TextField(title,value: Binding(get: { Double(value.wrappedValue) },set: { value.wrappedValue = CGFloat($0) }),format: .number.precision(.fractionLength(0...3))) }
}
struct PathNodePreview: NSViewRepresentable {
    @Binding var nodes: [PDFPathNode]
    @Binding var selected: UUID?
    func makeNSView(context: Context) -> NodeView { let view = NodeView(); configure(view); return view }
    func updateNSView(_ view: NodeView,context: Context) { configure(view) }
    private func configure(_ view: NodeView) { view.nodes = nodes; view.selected = selected; view.changed = { nodes = $0 }; view.chose = { selected = $0 }; view.needsDisplay = true }
    @MainActor final class NodeView: NSView {
        var nodes: [PDFPathNode] = [],selected: UUID?,changed: (([PDFPathNode]) -> Void)?,chose: ((UUID) -> Void)?
        private var drag: (Int,Int)?,dragTransform: CGAffineTransform?
        private var transform: CGAffineTransform {
            var box = CGRect.null
            for node in nodes where node.kind != .close { for p in node.kind == .curve ? [node.point,node.control1,node.control2] : [node.point] { box = box.union(CGRect(x: p.x,y: p.y,width: 0.1,height: 0.1)) } }
            guard !box.isNull else { return .identity }
            let scale = min(max(1,bounds.width-40)/max(1,box.width),max(1,bounds.height-40)/max(1,box.height))
            return CGAffineTransform(a: scale,b: 0,c: 0,d: scale,tx: bounds.midX-box.midX*scale,ty: bounds.midY-box.midY*scale)
        }
        override func resetCursorRects() { addCursorRect(bounds,cursor: .crosshair) }
        override func draw(_ rect: NSRect) {
            NSColor(calibratedWhite: 0.14,alpha: 1).setFill(); bounds.fill()
            let t = dragTransform ?? transform,path = NSBezierPath()
            for node in nodes {
                let p = node.point.applying(t)
                switch node.kind { case .move: path.move(to: p); case .line: path.line(to: p); case .curve: path.curve(to: p,controlPoint1: node.control1.applying(t),controlPoint2: node.control2.applying(t)); case .close: path.close() }
            }
            NSColor.white.setStroke(); path.lineWidth = 1.5; path.stroke()
            for node in nodes where node.kind != .close {
                let points = node.kind == .curve ? [node.point,node.control1,node.control2] : [node.point]
                for (i,p) in points.enumerated() {
                    let p = p.applying(t),handle = CGRect(x: p.x-4,y: p.y-4,width: 8,height: 8)
                    (node.id == selected ? NSColor.systemYellow : i == 0 ? .systemBlue : .systemOrange).setFill(); NSBezierPath(ovalIn: handle).fill()
                }
            }
        }
        override func mouseDown(with event: NSEvent) {
            let location = convert(event.locationInWindow,from: nil),t = transform
            for (index,node) in nodes.enumerated().reversed() where node.kind != .close {
                for (part,point) in (node.kind == .curve ? [node.point,node.control1,node.control2] : [node.point]).enumerated() {
                    let p = point.applying(t)
                    if hypot(p.x-location.x,p.y-location.y) < 10 { drag = (index,part); dragTransform = t; chose?(node.id); return }
                }
            }
        }
        override func mouseDragged(with event: NSEvent) {
            guard let (index,part) = drag,let t = dragTransform,nodes.indices.contains(index) else { return }
            let point = convert(event.locationInWindow,from: nil).applying(t.inverted())
            if part == 0 { nodes[index].point = point } else if part == 1 { nodes[index].control1 = point } else { nodes[index].control2 = point }
            changed?(nodes); needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) { drag = nil; dragTransform = nil; needsDisplay = true }
    }
}

/// Cubic geometry in page coordinates. Subdivision uses control-hull bounds;
/// a nearest point is returned only after its distance is bounded to precision.
struct PDFBezierSegment {
    let p0: CGPoint,p1: CGPoint,p2: CGPoint,p3: CGPoint
    var valid: Bool { [p0,p1,p2,p3].allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e9 && abs($0.y) <= 1e9 } }
    var bounds: CGRect {
        let points = [p0,p1,p2,p3],xs = points.map(\.x),ys = points.map(\.y)
        return CGRect(x: xs.min()!,y: ys.min()!,width: xs.max()!-xs.min()!,height: ys.max()!-ys.min()!)
    }
    func point(_ t: CGFloat) -> CGPoint {
        let s = 1-t
        return CGPoint(x: s*s*s*p0.x+3*s*s*t*p1.x+3*s*t*t*p2.x+t*t*t*p3.x,y: s*s*s*p0.y+3*s*s*t*p1.y+3*s*t*t*p2.y+t*t*t*p3.y)
    }
    func split() -> (Self,Self) {
        func mid(_ a: CGPoint,_ b: CGPoint) -> CGPoint { CGPoint(x: (a.x+b.x)/2,y: (a.y+b.y)/2) }
        let a = mid(p0,p1),b = mid(p1,p2),c = mid(p2,p3),d = mid(a,b),e = mid(b,c),m = mid(d,e)
        return (Self(p0: p0,p1: a,p2: d,p3: m),Self(p0: m,p1: e,p2: c,p3: p3))
    }
    var extrema: [CGPoint] {
        func roots(_ a: CGFloat,_ b: CGFloat,_ c: CGFloat,_ d: CGFloat) -> [CGFloat] {
            let aa = -a+3*b-3*c+d,bb = 2*(a-2*b+c),cc = b-a
            let epsilon = max(1,abs(aa),abs(bb),abs(cc))*1e-12
            if abs(aa) <= epsilon { return abs(bb) <= epsilon ? [] : [-cc/bb] }
            let discriminant = bb*bb-4*aa*cc
            guard discriminant >= 0 else { return [] }
            let q = -0.5*(bb+(bb >= 0 ? 1 : -1)*sqrt(discriminant))
            if abs(q) <= epsilon { return [-bb/(2*aa)] }
            return [q/aa,cc/q]
        }
        let values = roots(p0.x,p1.x,p2.x,p3.x)+roots(p0.y,p1.y,p2.y,p3.y)
        return values.filter { $0.isFinite && $0 > 1e-9 && $0 < 1-1e-9 }.reduce(into: [CGPoint]()) { result,t in
            let p = point(t); if !result.contains(where: { hypot($0.x-p.x,$0.y-p.y) < 1e-7 }) { result.append(p) }
        }
    }
    func arcMidpoint(accuracy: CGFloat = 0.0001) -> CGPoint? {
        guard valid,accuracy.isFinite,accuracy > 0 else { return nil }
        var leaves: [(Self,CGFloat)] = [],visits = 0
        func visit(_ curve: Self,budget: CGFloat,depth: Int) -> Bool {
            visits += 1; guard visits <= 32768,depth < 24 else { return false }
            let chord = hypot(curve.p3.x-curve.p0.x,curve.p3.y-curve.p0.y)
            let polygon = hypot(curve.p1.x-curve.p0.x,curve.p1.y-curve.p0.y)+hypot(curve.p2.x-curve.p1.x,curve.p2.y-curve.p1.y)+hypot(curve.p3.x-curve.p2.x,curve.p3.y-curve.p2.y)
            let dx = curve.p3.x-curve.p0.x,dy = curve.p3.y-curve.p0.y
            func distance(_ p: CGPoint) -> CGFloat { chord < 1e-12 ? hypot(p.x-curve.p0.x,p.y-curve.p0.y) : abs((p.x-curve.p0.x)*dy-(p.y-curve.p0.y)*dx)/chord }
            if polygon-chord <= budget,max(distance(curve.p1),distance(curve.p2)) <= 0.001 { leaves.append((curve,(polygon+chord)/2)); return true }
            let halves = curve.split()
            return visit(halves.0,budget: budget/2,depth: depth+1) && visit(halves.1,budget: budget/2,depth: depth+1)
        }
        guard visit(self,budget: accuracy,depth: 0) else { return nil }
        let total = leaves.reduce(CGFloat(0)) { $0+$1.1 }
        guard total > 1e-9 else { return nil }
        var remaining = total/2
        for (curve,length) in leaves where length > 0 {
            if remaining <= length {
                let fraction = min(1,max(0,remaining/length))
                let chordPoint = CGPoint(x: curve.p0.x+(curve.p3.x-curve.p0.x)*fraction,y: curve.p0.y+(curve.p3.y-curve.p0.y)*fraction)
                return curve.nearest(to: chordPoint,tolerance: 0.01,precision: 0.000001)
            }
            remaining -= length
        }
        return nil
    }
    func intersections(from start: CGPoint,to end: CGPoint) -> [CGPoint] {
        guard valid,[start,end].allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return [] }
        let dx = end.x-start.x,dy = end.y-start.y,length2 = dx*dx+dy*dy
        guard length2 > 1e-18 else { return [] }
        func cross(_ p: CGPoint) -> CGFloat { (p.x-start.x)*dy-(p.y-start.y)*dx }
        let f0 = cross(p0),f1 = cross(p1),f2 = cross(p2),f3 = cross(p3)
        let a = -f0+3*f1-3*f2+f3,b = 3*(f0-2*f1+f2),c = 3*(f1-f0),d = f0
        let epsilon = max(1,abs(a),abs(b),abs(c),abs(d))*1e-11
        if [a,b,c,d].allSatisfy({ abs($0) <= epsilon }) { return [] } // Collinear: no unique intersection.
        func value(_ t: CGFloat) -> CGFloat { ((a*t+b)*t+c)*t+d }
        var critical: [CGFloat] = []
        if abs(a) <= epsilon {
            if abs(b) > epsilon { critical = [-c/(2*b)] }
        } else {
            let discriminant = 4*b*b-12*a*c
            if discriminant >= 0 { critical = [(-2*b-sqrt(discriminant))/(6*a),(-2*b+sqrt(discriminant))/(6*a)] }
        }
        let stops = [CGFloat(0)]+critical.filter { $0 > 0 && $0 < 1 }.sorted()+[CGFloat(1)]
        var roots = stops.filter { abs(value($0)) <= epsilon }
        for (lo,hi) in zip(stops,stops.dropFirst()) {
            var lower = lo,upper = hi,left = value(lower)
            guard (left < 0 && value(upper) > 0) || (left > 0 && value(upper) < 0) else { continue }
            for _ in 0..<60 {
                let middle = (lower+upper)/2,at = value(middle)
                if (at < 0) == (left < 0) { lower = middle; left = at } else { upper = middle }
            }
            roots.append((lower+upper)/2)
        }
        return roots.sorted().reduce(into: [CGPoint]()) { result,t in
            let p = point(t),u = ((p.x-start.x)*dx+(p.y-start.y)*dy)/length2
            if u >= -1e-9 && u <= 1+1e-9,!result.contains(where: { hypot($0.x-p.x,$0.y-p.y) < 1e-6 }) { result.append(p) }
        }
    }
    /// Intersect control hulls until both candidates fit inside the requested
    /// geometric precision. Coincident curves have no unique snap location.
    func intersections(with other: Self,in region: CGRect? = nil,precision: CGFloat = 0.0001) -> [CGPoint] {
        guard valid,other.valid,precision.isFinite,precision > 0 else { return [] }
        func same(_ a: CGPoint,_ b: CGPoint) -> Bool { hypot(a.x-b.x,a.y-b.y) <= 1e-10 }
        if zip([p0,p1,p2,p3],[other.p0,other.p1,other.p2,other.p3]).allSatisfy(same) || zip([p0,p1,p2,p3],[other.p3,other.p2,other.p1,other.p0]).allSatisfy(same) { return [] }
        let points = [p0,p1,p2,p3,other.p0,other.p1,other.p2,other.p3]
        if let end = points.first(where: { !same(p0,$0) }) {
            let dx = end.x-p0.x,dy = end.y-p0.y,length = hypot(dx,dy)
            if points.allSatisfy({ abs(($0.x-p0.x)*dy-($0.y-p0.y)*dx)/length <= 1e-10 }) { return [] }
        } else { return [] }
        func overlaps(_ a: CGRect,_ b: CGRect) -> Bool { a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY }
        var pending: [(Self,Self,Int)] = [(self,other,0)],result: [CGPoint] = [],visits = 0
        while let (a,b,depth) = pending.popLast() {
            visits += 1
            // Partial overlaps and unresolved degeneracies do not produce snaps.
            guard visits <= 16384,depth <= 64 else { return [] }
            let ab = a.bounds,bb = b.bounds
            guard overlaps(ab,bb) else { continue }
            if let region,(!overlaps(ab,region) || !overlaps(bb,region)) { continue }
            let aSize = hypot(ab.width,ab.height),bSize = hypot(bb.width,bb.height)
            if max(aSize,bSize) <= precision {
                let x = (max(ab.minX,bb.minX)+min(ab.maxX,bb.maxX))/2
                let y = (max(ab.minY,bb.minY)+min(ab.maxY,bb.maxY))/2
                let point = CGPoint(x: x,y: y)
                if !result.contains(where: { hypot($0.x-x,$0.y-y) <= precision*4 }) { result.append(point) }
            } else if aSize >= bSize {
                let halves = a.split(); pending.append((halves.1,b,depth+1)); pending.append((halves.0,b,depth+1))
            } else {
                let halves = b.split(); pending.append((a,halves.1,depth+1)); pending.append((a,halves.0,depth+1))
            }
        }
        return result
    }
    func nearest(to query: CGPoint,tolerance: CGFloat,precision: CGFloat = 0.0001) -> CGPoint? {
        guard valid,query.x.isFinite,query.y.isFinite,tolerance.isFinite,tolerance > 0,precision.isFinite,precision > 0 else { return nil }
        func distance(_ p: CGPoint) -> CGFloat { hypot(query.x-p.x,query.y-p.y) }
        func lower(_ segment: Self) -> CGFloat {
            let b = segment.bounds,dx = max(b.minX-query.x,0,query.x-b.maxX),dy = max(b.minY-query.y,0,query.y-b.maxY)
            return hypot(dx,dy)
        }
        var best = p0,bestDistance = distance(p0)
        for p in [p3,point(0.5)] where distance(p) < bestDistance { best = p; bestDistance = distance(p) }
        var pending: [(Self,Int)] = [(self,0)],visits = 0
        while let (segment,depth) = pending.popLast() {
            visits += 1; guard visits <= 32768 else { return nil }
            let bound = lower(segment)
            if bound > tolerance || bestDistance <= bound+precision { continue }
            let halves = segment.split(),middle = halves.0.p3,delta = distance(middle)
            if delta < bestDistance { best = middle; bestDistance = delta }
            if bestDistance <= bound+precision { continue }
            guard depth < 40 else { return nil }
            if lower(halves.0) < lower(halves.1) { pending.append((halves.1,depth+1)); pending.append((halves.0,depth+1)) }
            else { pending.append((halves.0,depth+1)); pending.append((halves.1,depth+1)) }
        }
        return bestDistance <= tolerance ? best : nil
    }
}

struct PDFInkCurveRecord: Codable {
    var nodes: [PDFPathNode] // normalized to annotation bounds
    var strokes: [[CGPoint]] // normalized native geometry used to detect later edits
}
@MainActor enum PDFInkCurveGeometry {
    static func mapped(_ nodes: [PDFPathNode],_ transform: (CGPoint) -> CGPoint) -> [PDFPathNode] {
        nodes.map { source in
            var node = source
            if node.kind != .close { node.point = transform(node.point) }
            if node.kind == .curve { node.control1 = transform(node.control1); node.control2 = transform(node.control2) }
            return node
        }
    }
    static func nativeStrokes(_ annotation: PDFAnnotation) -> [[CGPoint]]? {
        let box = annotation.bounds
        guard box.width > 0,box.height > 0 else { return nil }
        var result: [[CGPoint]] = [],elements = 0
        for path in annotation.paths ?? [] {
            elements += path.elementCount; guard elements <= 100000 else { return nil }
            var stroke: [CGPoint] = [],start: CGPoint?
            func flush() { if stroke.count >= 2 { result.append(stroke) }; stroke = [] }
            for index in 0..<path.elementCount {
                var p = [NSPoint](repeating: .zero,count: 3)
                let kind = p.withUnsafeMutableBufferPointer { path.element(at: index,associatedPoints: $0.baseAddress!) }
                func normalized(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x/box.width,y: point.y/box.height) }
                switch kind {
                case .moveTo: flush(); start = normalized(p[0]); stroke = [start!]
                case .lineTo:
                    let point = normalized(p[0]); if stroke.last != point { stroke.append(point) }
                case .closePath: if let start,stroke.last != start { stroke.append(start) }; flush()
                default: return nil
                }
            }
            flush()
        }
        return result.isEmpty ? nil : result
    }
    static func read(_ annotation: PDFAnnotation,record: PDFInkCurveRecord?) throws -> [PDFPathNode] {
        guard annotation.type == "Ink" else { throw PDFSourceError.content }
        let box = annotation.bounds
        if let record,record.nodes.count <= 20000,let current = nativeStrokes(annotation),current.count == record.strokes.count,
           zip(current,record.strokes).allSatisfy({ a,b in a.count == b.count && zip(a,b).allSatisfy { abs($0.x-$1.x) <= 0.00002 && abs($0.y-$1.y) <= 0.00002 } }) {
            let nodes = mapped(record.nodes) { CGPoint(x: box.minX+$0.x*box.width,y: box.minY+$0.y*box.height) }
            if valid(nodes) { return nodes }
        }
        var result: [PDFPathNode] = []
        for path in annotation.paths ?? [] {
            guard path.elementCount+result.count <= 20000 else { throw PDFSourceError.content }
            var drawing = false,closed = false
            for index in 0..<path.elementCount {
                var p = [NSPoint](repeating: .zero,count: 3)
                let kind = p.withUnsafeMutableBufferPointer { path.element(at: index,associatedPoints: $0.baseAddress!) }
                func absolute(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x+box.minX,y: p.y+box.minY) }
                switch kind {
                case .moveTo:
                    if result.last?.kind == .move { result.removeLast() }
                    result.append(PDFPathNode(kind: .move,point: absolute(p[0]))); drawing = false
                case .lineTo: result.append(PDFPathNode(kind: .line,point: absolute(p[0]))); drawing = true; closed = false
                case .curveTo: result.append(PDFPathNode(kind: .curve,point: absolute(p[2]),control1: absolute(p[0]),control2: absolute(p[1]))); drawing = true; closed = false
                case .closePath: if drawing { result.append(PDFPathNode(kind: .close)); closed = true }
                default: throw PDFSourceError.content
                }
                if closed && index+1 == path.elementCount { drawing = false }
            }
            if result.last?.kind == .move { result.removeLast() } // PDFKit appends a move after closing.
        }
        guard valid(result) else { throw PDFSourceError.content }; return result
    }
    static func valid(_ nodes: [PDFPathNode]) -> Bool {
        guard !nodes.isEmpty,nodes.count <= 20000,nodes.first?.kind == .move else { return false }
        var active = false,segments = 0
        for node in nodes {
            let points = node.kind == .curve ? [node.point,node.control1,node.control2] : node.kind == .close ? [] : [node.point]
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1e6 && abs($0.y) <= 1e6 }) else { return false }
            switch node.kind {
            case .move: if active && segments == 0 { return false }; active = true; segments = 0
            case .line,.curve: guard active else { return false }; segments += 1
            case .close: guard active,segments > 0 else { return false }; active = false
            }
        }
        return !active || segments > 0
    }
    static func apply(_ nodes: [PDFPathNode],to annotation: PDFAnnotation) -> PDFInkCurveRecord? {
        guard annotation.type == "Ink",valid(nodes) else { return nil }
        var strokes: [[CGPoint]] = [],stroke: [CGPoint] = [],first = CGPoint.zero,previous = CGPoint.zero,total = 0
        func append(_ p: CGPoint) { if stroke.last != p { stroke.append(p); total += 1 } }
        func flush() { if stroke.count >= 2 { strokes.append(stroke) }; stroke = [] }
        func flatten(_ curve: PDFBezierSegment,depth: Int) -> Bool {
            guard total < 100000,depth < 24 else { return false }
            let dx = curve.p3.x-curve.p0.x,dy = curve.p3.y-curve.p0.y,chord = hypot(dx,dy)
            let polygon = hypot(curve.p1.x-curve.p0.x,curve.p1.y-curve.p0.y)+hypot(curve.p2.x-curve.p1.x,curve.p2.y-curve.p1.y)+hypot(curve.p3.x-curve.p2.x,curve.p3.y-curve.p2.y)
            func distance(_ p: CGPoint) -> CGFloat { chord < 1e-12 ? hypot(p.x-curve.p0.x,p.y-curve.p0.y) : abs((p.x-curve.p0.x)*dy-(p.y-curve.p0.y)*dx)/chord }
            if max(distance(curve.p1),distance(curve.p2)) <= 0.03 && polygon-chord <= 0.03 { append(curve.p3); return true }
            let halves = curve.split(); return flatten(halves.0,depth: depth+1) && flatten(halves.1,depth: depth+1)
        }
        for node in nodes {
            switch node.kind {
            case .move: flush(); first = node.point; previous = first; append(first)
            case .line: append(node.point); previous = node.point
            case .curve:
                guard flatten(PDFBezierSegment(p0: previous,p1: node.control1,p2: node.control2,p3: node.point),depth: 0) else { return nil }; previous = node.point
            case .close: append(first); flush(); previous = first
            }
        }
        flush(); guard !strokes.isEmpty,total <= 100000 else { return nil }
        let all = strokes.flatMap { $0 },padding = max(2,annotation.border?.lineWidth ?? 1)
        let x0 = all.map(\.x).min()!,x1 = all.map(\.x).max()!,y0 = all.map(\.y).min()!,y1 = all.map(\.y).max()!
        let box = CGRect(x: x0-padding,y: y0-padding,width: max(1,x1-x0)+2*padding,height: max(1,y1-y0)+2*padding)
        var paths: [NSBezierPath] = []
        for points in strokes {
            let path = NSBezierPath()
            for (i,p) in points.enumerated() { let local = CGPoint(x: p.x-box.minX,y: p.y-box.minY); if i == 0 { path.move(to: local) } else { path.line(to: local) } }
            paths.append(path)
        }
        for old in annotation.paths ?? [] { annotation.remove(old) }
        annotation.bounds = box; for path in paths { annotation.add(path) }
        annotation.removeValue(forAnnotationKey: .appearanceDictionary)
        guard let native = nativeStrokes(annotation) else { return nil }
        let normalized = mapped(nodes) { CGPoint(x: ($0.x-box.minX)/box.width,y: ($0.y-box.minY)/box.height) }
        return PDFInkCurveRecord(nodes: normalized,strokes: native)
    }
}
