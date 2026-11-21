import SwiftUI

struct CleanupView: View {
    @Environment(AppModel.self) private var model
    let kind: FindingKind
    @State private var confirm = false
    @State private var sort: Sort = .size
    @State private var expanded: Set<UUID> = []

    enum Sort: String, CaseIterable { case size = "Size", confidence = "Confidence", name = "Name" }

    var body: some View {
        let items = sorted(model.findings(kind))
        let selected = items.filter { model.selection.contains($0.id) }
        let selectedSize = selected.reduce(Int64(0)) { $0 + $1.size }
        let busy = kind == .duplicates ? model.findingDuplicates : model.analyzing

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(items: items, busy: busy)
                if items.isEmpty {
                    ContentUnavailableView {
                        Label(busy ? "Analysing…" : "Nothing to clean here", systemImage: busy ? "hourglass" : "checkmark.seal")
                    } description: {
                        Text(busy ? "Thanos is still inspecting your files." : "Your Mac is tidy in this area.")
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            FindingRow(finding: item,
                                       isSelected: model.selection.contains(item.id),
                                       isExpanded: expanded.contains(item.id),
                                       toggle: { toggle(item) },
                                       expand: { withAnimation(.smooth) { expanded.formSymmetricDifference([item.id]) } })
                        }
                    }
                }
            }
            .padding(28)
            .padding(.bottom, 90)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .safeAreaInset(edge: .bottom) {
            if !selected.isEmpty { snapBar(selected: selected, size: selectedSize) }
        }
        .animation(.spring(duration: 0.35), value: selected.isEmpty)
        .confirmationDialog(selected.contains(where: \.permanent) ? "Permanently delete \(selectedSize.bytes)?" : "Move \(selectedSize.bytes) to the Trash?",
                            isPresented: $confirm) {
            Button(selected.contains(where: \.permanent) ? "Delete Permanently" : "Move to Trash", role: .destructive) {
                model.snap(selected)
            }
        } message: {
            if selected.contains(where: \.permanent) {
                Text("Emptying the Trash cannot be undone.")
            } else {
                Text("\(selected.reduce(0) { $0 + $1.paths.count }) items go to the Trash. You can put them back from there.")
            }
        }
    }

    private func header(items: [Finding], busy: Bool) -> some View {
        GlassCard(tint: kind.tint) {
            HStack(alignment: .top, spacing: 18) {
                GlassIcon(symbol: kind.symbol, tint: kind.tint, size: 58)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(kind.title).font(.system(size: 28, weight: .bold, design: .rounded))
                        if busy { ProgressView().controlSize(.small) }
                    }
                    Text(kind.blurb).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 10) {
                        let safe = items.filter { $0.confidence == .safe }
                        Button("Select Safe (\(safe.count))") {
                            model.selection.formUnion(safe.map(\.id))
                        }
                        .disabled(safe.isEmpty)
                        Button("Select All") { model.selection.formUnion(items.map(\.id)) }
                            .disabled(items.isEmpty)
                        Button("Deselect") { model.selection.subtract(items.map(\.id)) }
                            .disabled(!items.contains { model.selection.contains($0.id) })
                        Spacer()
                        Picker("Sort", selection: $sort) {
                            ForEach(Sort.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .padding(.top, 6)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(items.reduce(Int64(0)) { $0 + $1.size }.bytes)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(kind.tint.gradient)
                        .contentTransition(.numericText())
                    Text("\(items.count) items").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func snapBar(selected: [Finding], size: Int64) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(selected.count) selected").font(.headline)
                Text(size.bytes).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { model.selection.subtract(selected.map(\.id)) }
                .buttonStyle(.glass)
            Button {
                confirm = true
            } label: {
                Label(selected.contains(where: \.permanent) ? "Empty" : "Snap", systemImage: "hand.raised.fingers.spread.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(selected.contains(where: \.permanent) ? .red : .purple)
            .controlSize(.large)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
        .frame(maxWidth: 640)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 20)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func toggle(_ f: Finding) {
        if model.selection.contains(f.id) { model.selection.remove(f.id) } else { model.selection.insert(f.id) }
    }

    private func sorted(_ items: [Finding]) -> [Finding] {
        switch sort {
        case .size: items.sorted { $0.size > $1.size }
        case .confidence: items.sorted { ($0.confidence, -$0.size) < ($1.confidence, -$1.size) }
        case .name: items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }
}

struct FindingRow: View {
    @Environment(AppModel.self) private var model
    let finding: Finding
    let isSelected: Bool
    let isExpanded: Bool
    let toggle: () -> Void
    let expand: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Toggle("", isOn: Binding(get: { isSelected }, set: { _ in toggle() }))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                FileIcon(path: finding.iconPath ?? finding.paths.first, fallback: finding.kind.symbol, size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(finding.title).font(.headline).lineLimit(1)
                        ConfidenceBadge(confidence: finding.confidence)
                    }
                    Text(finding.subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(finding.size.bytes).font(.system(.headline, design: .rounded)).monospacedDigit()
                    if let d = finding.date {
                        Text(d, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(action: expand) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(width: 26, height: 26)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .contentShape(.rect)
            .onTapGesture(perform: toggle)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Label(finding.reason, systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(finding.paths.prefix(40), id: \.self) { p in
                            HStack {
                                Text(abbreviated(p)).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button { model.reveal([p]) } label: { Image(systemName: "magnifyingglass.circle") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                                    .help("Reveal in Finder")
                            }
                        }
                        if finding.paths.count > 40 {
                            Text("and \(finding.paths.count - 40) more…").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                }
                .padding([.horizontal, .bottom], 14)
                .padding(.leading, 40)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isSelected ? finding.kind.tint.opacity(0.7) : .white.opacity(hover ? 0.18 : 0.08), lineWidth: isSelected ? 1.5 : 1)
                }
        }
        .onHover { hover = $0 }
        .contextMenu {
            Button("Reveal in Finder", systemImage: "folder") { model.reveal(finding.paths) }
        }
    }

    private func abbreviated(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
