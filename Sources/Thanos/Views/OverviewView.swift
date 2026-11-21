import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmSnap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                storageCard
                stats
                HStack(alignment: .top, spacing: 22) {
                    CategoryDonut()
                    TopFoldersCard()
                }
                suggestions
            }
            .padding(28)
            .frame(maxWidth: 1280)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .confirmationDialog("Snap away \(model.safeFindings.count) safe items?", isPresented: $confirmSnap) {
            Button("Move \(model.safeReclaimable.bytes) to Trash", role: .destructive) { model.snap(model.safeFindings) }
        } message: {
            Text("Only items marked Safe are included. Everything goes to the Trash, so you can put it back.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.root?.displayName ?? "Overview")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                if let r = model.result {
                    Text("\(r.stats.files.grouped) files in \(r.stats.directories.grouped) folders · scanned in \(r.duration.formatted(.number.precision(.fractionLength(1))))s")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                if let v = model.volume {
                    HStack(alignment: .firstTextBaseline) {
                        Label(v.name, systemImage: "internaldrive.fill").font(.headline)
                        Spacer()
                        Text("\(v.used.bytes) of \(v.total.bytes) used")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    let scanned = model.categoryTotals.reduce(Int64(0)) { $0 + $1.1 }
                    let rest = max(0, v.used - scanned)
                    SegmentBar(segments:
                        model.categoryTotals.map { .init(value: Double($0.1), color: $0.0.color, label: $0.0.title) }
                        + [.init(value: Double(rest), color: .gray.opacity(0.45), label: model.target == .disk ? "System data & snapshots" : "Outside this scan"),
                           .init(value: Double(v.available), color: .white.opacity(0.18), label: "Available")]
                    )
                    FlowLegend(items: model.categoryTotals.map { ($0.0.color, $0.0.title, $0.1.bytes) }
                               + [(.gray.opacity(0.45), model.target == .disk ? "System data" : "Elsewhere", rest.bytes),
                                  (.white.opacity(0.4), "Available", v.available.bytes)])
                }
            }
        }
    }

    // MARK: Stats

    private var stats: some View {
        GlassEffectContainer(spacing: 16) {
            HStack(spacing: 16) {
                StatTile(title: "Scanned", value: (model.root?.size ?? 0).bytes, symbol: "magnifyingglass", tint: .blue,
                         footnote: model.target.title)
                StatTile(title: "Reclaimable", value: model.reclaimable.bytes, symbol: "sparkles", tint: .purple,
                         footnote: "\(model.findings.count) findings")
                StatTile(title: "Safe to snap", value: model.safeReclaimable.bytes, symbol: "checkmark.shield", tint: .green,
                         footnote: "No review needed")
                StatTile(title: "App leftovers", value: model.total(.leftovers).bytes, symbol: FindingKind.leftovers.symbol, tint: .pink,
                         footnote: "\(model.findings(.leftovers).count) uninstalled apps")
            }
        }
    }

    // MARK: Suggestions

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                SectionTitle(title: "Smart suggestions", subtitle: model.analyzing ? "Looking for leftovers and junk…" : "Grouped by how sure we are it's junk.")
                Spacer()
                if model.safeReclaimable > 0 {
                    Button {
                        confirmSnap = true
                    } label: {
                        Label("Snap \(model.safeReclaimable.bytes) safely", systemImage: "hand.raised.fingers.spread.fill")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.purple)
                    .controlSize(.large)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 16)], spacing: 16) {
                ForEach(FindingKind.allCases) { kind in
                    SuggestionCard(kind: kind)
                }
            }
        }
    }
}

struct SuggestionCard: View {
    @Environment(AppModel.self) private var model
    let kind: FindingKind
    @State private var hover = false

    var body: some View {
        let items = model.findings(kind)
        let busy = kind == .duplicates ? model.findingDuplicates : model.analyzing
        Button {
            model.sidebar = .cleanup(kind)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    GlassIcon(symbol: kind.symbol, tint: kind.tint, size: 38)
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
                Text(kind.title).font(.headline)
                Text(busy && items.isEmpty ? "Analysing…" : model.total(kind).bytes)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(items.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(kind.tint.gradient))
                    .contentTransition(.numericText())
                Text(items.isEmpty ? (busy ? " " : "Nothing found") : "\(items.count) item\(items.count == 1 ? "" : "s") · \(items.filter { $0.confidence == .safe }.count) safe")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(kind.tint.opacity(hover ? 0.16 : 0.06)).interactive(), in: .rect(cornerRadius: 22))
        .scaleEffect(hover ? 1.015 : 1)
        .animation(.spring(duration: 0.25), value: hover)
        .onHover { hover = $0 }
    }
}

struct FlowLegend: View {
    let items: [(Color, String, String)]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                LegendDot(color: item.0, label: item.1, value: item.2)
            }
        }
    }
}

// MARK: - Category donut

struct CategoryDonut: View {
    @Environment(AppModel.self) private var model
    @State private var angle: Double?
    @State private var selected: FileCategory?

    var body: some View {
        let data = model.categoryTotals
        let total = data.reduce(Int64(0)) { $0 + $1.1 }
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "What's taking space", subtitle: "By kind of file")
                HStack(spacing: 24) {
                    Chart(data, id: \.0) { item in
                        SectorMark(angle: .value("Size", Double(item.1)),
                                   innerRadius: .ratio(0.64),
                                   outerRadius: .ratio(selected == item.0 ? 1.0 : 0.93),
                                   angularInset: 1.8)
                            .cornerRadius(5)
                            .foregroundStyle(item.0.color.gradient)
                            .opacity(selected == nil || selected == item.0 ? 1 : 0.35)
                    }
                    .chartAngleSelection(value: $angle)
                    .chartLegend(.hidden)
                    .chartBackground { proxy in
                        GeometryReader { geo in
                            if let frame = proxy.plotFrame.map({ geo[$0] }) {
                                let item = selected.flatMap { s in data.first { $0.0 == s } }
                                VStack(spacing: 2) {
                                    if let item {
                                        Image(systemName: item.0.symbol).foregroundStyle(item.0.color)
                                        Text(item.1.bytes).font(.system(.title3, design: .rounded).weight(.bold))
                                        Text(item.0.title).font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Text(total.bytes).font(.system(.title3, design: .rounded).weight(.bold))
                                        Text("in files").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(width: 220, height: 220)
                    .animation(.spring(duration: 0.35), value: selected)
                    .onChange(of: angle) { _, new in selected = category(at: new, in: data) }

                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(data, id: \.0) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.0.symbol)
                                    .foregroundStyle(item.0.color)
                                    .frame(width: 20)
                                Text(item.0.title).lineLimit(1)
                                Spacer()
                                Text(item.1.bytes).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .font(.callout)
                            .opacity(selected == nil || selected == item.0 ? 1 : 0.45)
                            .contentShape(.rect)
                            .onHover { selected = $0 ? item.0 : nil }
                        }
                    }
                }
            }
        }
    }

    private func category(at angle: Double?, in data: [(FileCategory, Int64)]) -> FileCategory? {
        guard let angle else { return nil }
        var acc = 0.0
        for item in data {
            acc += Double(item.1)
            if angle <= acc { return item.0 }
        }
        return nil
    }
}

// MARK: - Top folders

struct TopFoldersCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = model.treeVersion
        let root = model.root
        let kids = Array((root?.children ?? []).filter { !$0.isAggregate }.prefix(8))
        let maxSize = Double(kids.first?.size ?? 1)
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(title: "Biggest folders", subtitle: "Click to explore")
                VStack(spacing: 10) {
                    ForEach(Array(kids.enumerated()), id: \.element.id) { i, node in
                        Button {
                            model.explorerFocus = node.isDirectory ? node : root
                            model.sidebar = .explorer
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    FileIcon(path: node.path, fallback: "folder", size: 18)
                                    Text(node.name).lineLimit(1)
                                    Spacer()
                                    Text(node.size.bytes).monospacedDigit().foregroundStyle(.secondary)
                                }
                                .font(.callout)
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(folderPalette[i % folderPalette.count].gradient)
                                        .frame(width: max(6, geo.size.width * Double(node.size) / maxSize))
                                }
                                .frame(height: 6)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
