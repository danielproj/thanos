import SwiftUI

struct ExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var mode: Mode = .sunburst
    @State private var hovered: FileNode?
    @State private var selected: FileNode?
    @State private var pendingTrash: FileNode?
    @Namespace private var crumbs

    enum Mode: String, CaseIterable { case sunburst = "Sunburst", treemap = "Treemap" }

    var body: some View {
        let _ = model.treeVersion
        if let root = model.root {
            let focus = model.explorerFocus ?? root
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    HStack {
                        breadcrumb(focus)
                        Spacer()
                        Picker("View", selection: $mode) {
                            ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 200)
                    }
                    ZStack(alignment: .bottom) {
                        Group {
                            switch mode {
                            case .sunburst:
                                SunburstView(focus: focus, hovered: $hovered, version: model.treeVersion,
                                             onSelect: open, onUp: { goUp(focus) })
                            case .treemap:
                                TreemapView(focus: focus, hovered: $hovered, version: model.treeVersion, onSelect: open)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if let h = hovered {
                            HStack(spacing: 10) {
                                FileIcon(path: h.isAggregate ? nil : h.path, fallback: "doc.on.doc", size: 22)
                                Text(h.name).fontWeight(.semibold).lineLimit(1)
                                Text(h.size.bytes).monospacedDigit().foregroundStyle(.secondary)
                                Text(percent(h, of: focus)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .animation(.smooth(duration: 0.2), value: hovered?.id)
                }
                .padding(20)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))

                childList(focus)
                    .frame(width: 360)
            }
            .padding(24)
            .confirmationDialog("Move “\(pendingTrash?.name ?? "")” to the Trash?", isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
                Button("Move \(pendingTrash?.size.bytes ?? "") to Trash", role: .destructive) {
                    if let n = pendingTrash { model.trash(paths: [n.path]) }
                    pendingTrash = nil
                }
            } message: {
                Text("You can restore it from the Trash later.")
            }
        }
    }

    private func open(_ node: FileNode) {
        if node.isDirectory && !node.children.isEmpty {
            withAnimation(.smooth) { model.explorerFocus = node }
            hovered = nil
        } else {
            selected = node
        }
    }

    private func goUp(_ focus: FileNode) {
        if let p = focus.parent { withAnimation(.smooth) { model.explorerFocus = p } }
    }

    private func percent(_ n: FileNode, of focus: FileNode) -> String {
        guard focus.size > 0 else { return "" }
        return (Double(n.size) / Double(focus.size)).formatted(.percent.precision(.fractionLength(1)))
    }

    private func breadcrumb(_ focus: FileNode) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(focus.ancestors) { node in
                        Button {
                            withAnimation(.smooth) { model.explorerFocus = node }
                        } label: {
                            HStack(spacing: 5) {
                                if node.parent == nil { Image(systemName: model.target.symbol) }
                                Text(node.displayName).lineLimit(1)
                            }
                            .font(.callout.weight(node === focus ? .semibold : .regular))
                            .padding(.horizontal, 12).padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(node === focus ? .regular.tint(.purple.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
                        .glassEffectID(ObjectIdentifier(node).hashValue, in: crumbs)
                    }
                }
            }
        }
    }

    private func childList(_ focus: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(focus.displayName).font(.title3.weight(.semibold)).lineLimit(1)
                Text("\(focus.size.bytes) · \(focus.itemCount.grouped) files")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(18)
            Divider().opacity(0.4)
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(focus.children.prefix(300).enumerated()), id: \.element.id) { i, node in
                        ChildRow(node: node, parentSize: focus.size, color: folderPalette[i % folderPalette.count],
                                 isHovered: hovered === node, isSelected: selected === node)
                            .onHover { hovered = $0 ? node : (hovered === node ? nil : hovered) }
                            .onTapGesture(count: 2) { open(node) }
                            .onTapGesture { selected = node }
                            .contextMenu {
                                if !node.isAggregate {
                                    if node.isDirectory && !node.children.isEmpty { Button("Open", systemImage: "arrow.down.right.circle") { open(node) } }
                                    Button("Reveal in Finder", systemImage: "folder") { model.reveal([node.path]) }
                                    Button("Open with Default App", systemImage: "arrow.up.forward.app") { NSWorkspace.shared.open(node.url) }
                                    Divider()
                                    Button("Move to Trash…", systemImage: "trash", role: .destructive) { pendingTrash = node }
                                }
                            }
                    }
                }
                .padding(8)
            }
        }
        .frame(maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
    }
}

private struct ChildRow: View {
    let node: FileNode
    let parentSize: Int64
    let color: Color
    let isHovered: Bool
    let isSelected: Bool

    var body: some View {
        let fraction = parentSize > 0 ? Double(node.size) / Double(parentSize) : 0
        HStack(spacing: 10) {
            FileIcon(path: node.isAggregate ? nil : node.path, fallback: "doc.on.doc", size: 26)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 6)
                    Text(node.size.bytes).monospacedDigit().foregroundStyle(.secondary)
                }
                .font(.callout)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(color.gradient).frame(width: max(3, geo.size.width * fraction))
                    }
                }
                .frame(height: 4)
            }
            if node.isDirectory && !node.children.isEmpty {
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(isHovered ? Color.primary.opacity(0.07) : .clear))
        }
        .contentShape(.rect)
    }
}

// MARK: - Sunburst

struct SunArc {
    let node: FileNode
    let depth: Int
    let start: Double
    let end: Double
    let color: Color
}

struct SunburstView: View {
    let focus: FileNode
    @Binding var hovered: FileNode?
    let version: Int
    let onSelect: (FileNode) -> Void
    let onUp: () -> Void

    @State private var progress: Double = 0
    @State private var arcs: [SunArc] = []
    static let maxDepth = 4

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let outer = side / 2 - 8
            let inner = outer * 0.26
            ZStack {
                SunburstCanvas(arcs: arcs, progress: progress, center: center, inner: inner, outer: outer,
                               hovered: hovered.map(ObjectIdentifier.init))
                    .contentShape(.rect)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p): hovered = hit(p, center: center, inner: inner, outer: outer)
                        case .ended: hovered = nil
                        }
                    }
                    .onTapGesture { p in
                        let r = hypot(p.x - center.x, p.y - center.y)
                        if r < inner { onUp() }
                        else if let n = hit(p, center: center, inner: inner, outer: outer) { onSelect(n) }
                    }

                Button(action: onUp) {
                    VStack(spacing: 3) {
                        if focus.parent != nil {
                            Image(systemName: "arrow.up").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }
                        Text(focus.displayName).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                        Text(focus.size.bytes).font(.system(.title3, design: .rounded).weight(.bold))
                    }
                    .padding(10)
                    .frame(width: inner * 2 - 14, height: inner * 2 - 14)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .position(center)
                .disabled(focus.parent == nil)
            }
        }
        .task(id: TaskKey(focus: ObjectIdentifier(focus), version: version)) {
            arcs = Self.build(focus)
            progress = 0
            withAnimation(.spring(duration: 0.7, bounce: 0.15)) { progress = 1 }
        }
    }

    struct TaskKey: Hashable { let focus: ObjectIdentifier; let version: Int }

    private func hit(_ p: CGPoint, center: CGPoint, inner: Double, outer: Double) -> FileNode? {
        let dx = p.x - center.x, dy = p.y - center.y
        let r = hypot(dx, dy)
        guard r >= inner, r <= outer else { return nil }
        let ring = (outer - inner) / Double(Self.maxDepth)
        let depth = Int((r - inner) / ring) + 1
        var a = atan2(dy, dx) + .pi / 2
        if a < 0 { a += 2 * .pi }
        return arcs.first { $0.depth == depth && a >= $0.start && a < $0.end }?.node
    }

    static func build(_ focus: FileNode) -> [SunArc] {
        var arcs: [SunArc] = []
        func walk(_ n: FileNode, depth: Int, start: Double, end: Double, color: Color?) {
            guard depth <= maxDepth, n.size > 0 else { return }
            var a = start
            let span = end - start
            for (i, c) in n.children.enumerated() {
                let s = span * Double(c.size) / Double(n.size)
                if s < 0.004 { break }       // children are sorted; the rest are too thin to see
                let col = color ?? folderPalette[i % folderPalette.count]
                arcs.append(SunArc(node: c, depth: depth, start: a, end: a + s, color: c.isAggregate ? .gray : col))
                if c.isDirectory { walk(c, depth: depth + 1, start: a, end: a + s, color: col) }
                a += s
            }
        }
        walk(focus, depth: 1, start: 0, end: 2 * .pi, color: nil)
        return arcs
    }
}

private struct SunburstCanvas: View, Animatable {
    let arcs: [SunArc]
    var progress: Double
    let center: CGPoint
    let inner: Double
    let outer: Double
    let hovered: ObjectIdentifier?

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { ctx, _ in
            let ring = (outer - inner) / Double(SunburstView.maxDepth)
            for arc in arcs {
                let r0 = inner + ring * Double(arc.depth - 1) + 1.5
                let r1 = (inner + ring * Double(arc.depth)) * (0.85 + 0.15 * progress) - 1.5
                let gap = min(0.006, (arc.end - arc.start) * 0.15)
                let s = arc.start * progress + gap - .pi / 2
                let e = arc.end * progress - gap - .pi / 2
                guard e > s, r1 > r0 else { continue }
                var path = Path()
                path.addArc(center: center, radius: r1, startAngle: .radians(s), endAngle: .radians(e), clockwise: false)
                path.addArc(center: center, radius: r0, startAngle: .radians(e), endAngle: .radians(s), clockwise: true)
                path.closeSubpath()
                let isHover = hovered == ObjectIdentifier(arc.node)
                let opacity = [1.0, 0.78, 0.6, 0.46][min(arc.depth - 1, 3)]
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [arc.color.opacity(opacity), arc.color.opacity(opacity * 0.72)]),
                    startPoint: CGPoint(x: center.x - r1, y: center.y - r1),
                    endPoint: CGPoint(x: center.x + r1, y: center.y + r1)))
                if isHover {
                    ctx.fill(path, with: .color(.white.opacity(0.28)))
                    ctx.stroke(path, with: .color(.white.opacity(0.9)), lineWidth: 2)
                }
            }
        }
    }
}

// MARK: - Treemap

struct TreemapView: View {
    let focus: FileNode
    @Binding var hovered: FileNode?
    let version: Int
    let onSelect: (FileNode) -> Void

    struct Tile { let node: FileNode; let rect: CGRect; let color: Color; let isGroup: Bool }

    var body: some View {
        GeometryReader { geo in
            let tiles = Self.layoutTiles(focus, in: CGRect(origin: .zero, size: geo.size))
            Canvas { ctx, _ in
                for t in tiles {
                    let r = t.rect.insetBy(dx: 1.5, dy: 1.5)
                    guard r.width > 1, r.height > 1 else { continue }
                    let path = Path(roundedRect: r, cornerRadius: min(10, min(r.width, r.height) / 4))
                    if t.isGroup {
                        ctx.fill(path, with: .color(t.color.opacity(0.16)))
                        ctx.stroke(path, with: .color(t.color.opacity(0.5)), lineWidth: 1)
                        if r.width > 60 {
                            ctx.draw(Text(t.node.name).font(.caption.weight(.semibold)).foregroundStyle(.primary),
                                     at: CGPoint(x: r.minX + 8, y: r.minY + 9), anchor: .leading)
                        }
                    } else {
                        let hover = hovered === t.node
                        ctx.fill(path, with: .linearGradient(Gradient(colors: [t.color.opacity(0.85), t.color.opacity(0.55)]),
                                                             startPoint: r.origin, endPoint: CGPoint(x: r.maxX, y: r.maxY)))
                        if hover { ctx.stroke(path, with: .color(.white), lineWidth: 2) }
                        if r.width > 70 && r.height > 34 {
                            ctx.draw(Text(t.node.name).font(.caption).foregroundStyle(.white),
                                     in: r.insetBy(dx: 6, dy: 5))
                        }
                    }
                }
            }
            .contentShape(.rect)
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = tiles.last { !$0.isGroup && $0.rect.contains(p) }?.node
                                        ?? tiles.last { $0.rect.contains(p) }?.node
                case .ended: hovered = nil
                }
            }
            .onTapGesture { p in
                if let group = tiles.last(where: { $0.isGroup && $0.rect.contains(p) }) { onSelect(group.node) }
                else if let n = tiles.last(where: { $0.rect.contains(p) })?.node { onSelect(n) }
            }
        }
    }

    static func layoutTiles(_ focus: FileNode, in rect: CGRect) -> [Tile] {
        var tiles: [Tile] = []
        let top = Array(focus.children.prefix(60))
        for (i, (node, r)) in squarify(top, in: rect).enumerated() {
            let color = node.isAggregate ? Color.gray : folderPalette[i % folderPalette.count]
            if node.isDirectory && !node.children.isEmpty && r.width > 40 && r.height > 40 {
                tiles.append(Tile(node: node, rect: r, color: color, isGroup: true))
                let innerRect = CGRect(x: r.minX + 4, y: r.minY + 20, width: r.width - 8, height: r.height - 24)
                for (child, cr) in squarify(Array(node.children.prefix(80)), in: innerRect) {
                    tiles.append(Tile(node: child, rect: cr, color: child.isAggregate ? .gray : color, isGroup: false))
                }
            } else {
                tiles.append(Tile(node: node, rect: r, color: color, isGroup: false))
            }
        }
        return tiles
    }

    /// Squarified treemap (Bruls, Huizing & van Wijk) — keeps tiles close to square so sizes read honestly.
    static func squarify(_ nodes: [FileNode], in rect: CGRect) -> [(FileNode, CGRect)] {
        let items = nodes.filter { $0.size > 0 }
        let total = items.reduce(0.0) { $0 + Double($1.size) }
        guard total > 0, rect.width > 2, rect.height > 2 else { return [] }
        let scale = Double(rect.width * rect.height) / total
        var result: [(FileNode, CGRect)] = []
        var remaining = rect
        var row: [(FileNode, Double)] = []

        func worst(_ row: [(FileNode, Double)], _ side: Double) -> Double {
            let s = row.reduce(0) { $0 + $1.1 }
            guard let mx = row.map(\.1).max(), let mn = row.map(\.1).min(), s > 0, mn > 0 else { return .infinity }
            return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
        }
        func flush() {
            let s = row.reduce(0) { $0 + $1.1 }
            guard s > 0 else { row.removeAll(); return }
            if remaining.width >= remaining.height {
                let w = s / Double(remaining.height)
                var y = Double(remaining.minY)
                for (n, a) in row {
                    let h = a / w
                    result.append((n, CGRect(x: remaining.minX, y: y, width: w, height: h)))
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: max(0, remaining.width - w), height: remaining.height)
            } else {
                let h = s / Double(remaining.width)
                var x = Double(remaining.minX)
                for (n, a) in row {
                    let w = a / h
                    result.append((n, CGRect(x: x, y: remaining.minY, width: w, height: h)))
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: max(0, remaining.height - h))
            }
            row.removeAll()
        }
        for n in items {
            let item = (n, Double(n.size) * scale)
            let side = Double(min(remaining.width, remaining.height))
            if row.isEmpty || worst(row + [item], side) <= worst(row, side) { row.append(item) }
            else { flush(); row.append(item) }
        }
        flush()
        return result
    }
}
