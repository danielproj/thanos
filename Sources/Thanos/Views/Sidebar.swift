import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebar) {
            Section("Storage") {
                row(.overview, "Overview", "gauge.with.dots.needle.67percent", .purple)
                row(.explorer, "Explorer", "circle.circle", .blue)
                row(.largeFiles, "Large Files", "doc.on.doc", .orange,
                    badge: model.result.map { "\($0.stats.largeFiles.count)" })
            }
            Section("Clean Up") {
                ForEach(FindingKind.allCases) { kind in
                    let total = model.total(kind)
                    row(.cleanup(kind), kind.title, kind.symbol, kind.tint,
                        badge: total > 0 ? total.bytes : nil,
                        busy: kind == .duplicates ? model.findingDuplicates : model.analyzing)
                }
            }
        }
        .listStyle(.sidebar)
        .overlay(alignment: .bottom) { footer.padding(12) }
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, _ tint: Color,
                     badge: String? = nil, busy: Bool = false) -> some View {
        NavigationLink(value: item) {
            HStack {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: symbol).foregroundStyle(tint)
                }
                Spacer()
                if busy && model.phase == .ready {
                    ProgressView().controlSize(.mini)
                } else if let badge {
                    Text(badge).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .disabled(model.phase != .ready)
    }

    @ViewBuilder private var footer: some View {
        if !model.hasFullDiskAccess {
            VStack(alignment: .leading, spacing: 8) {
                Label("Limited access", systemImage: "lock.shield")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("Grant Full Disk Access so Thanos can see Mail, Messages, containers and the Trash.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Settings") { model.openFullDiskAccessSettings() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(.orange.opacity(0.12)), in: .rect(cornerRadius: 16))
        } else if model.phase == .ready, model.reclaimable > 0 {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reclaimable").font(.caption).foregroundStyle(.secondary)
                Text(model.reclaimable.bytes)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink], startPoint: .leading, endPoint: .trailing))
                    .contentTransition(.numericText())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        }
    }
}
