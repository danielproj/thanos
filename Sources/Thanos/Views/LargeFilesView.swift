import SwiftUI

struct LargeFilesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: Set<FileRecord.ID> = []
    @State private var order = [KeyPathComparator(\FileRecord.size, order: .reverse)]
    @State private var filter: FileCategory?
    @State private var search = ""
    @State private var confirm = false

    var body: some View {
        let all = model.result?.stats.largeFiles ?? []
        let rows = all
            .filter { filter == nil || $0.category == filter }
            .filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }
            .sorted(using: order)
        let selectedSize = rows.filter { selection.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Large Files").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("\(rows.count) files over 100 MB · \(rows.reduce(Int64(0)) { $0 + $1.size }.bytes)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                categoryChips(all)
            }

            Table(rows, selection: $selection, sortOrder: $order) {
                TableColumn("Name", value: \.name) { r in
                    HStack(spacing: 8) {
                        FileIcon(path: r.path, size: 20)
                        Text(r.name).lineLimit(1)
                    }
                }
                .width(min: 220, ideal: 320)
                TableColumn("Kind", value: \.category.title) { r in
                    Label(r.category.title, systemImage: r.category.symbol)
                        .foregroundStyle(r.category.color)
                        .labelStyle(.titleAndIcon)
                }
                .width(min: 110, ideal: 150)
                TableColumn("Size", value: \.size) { r in
                    Text(r.size.bytes).monospacedDigit()
                }
                .width(min: 80, ideal: 100)
                TableColumn("Modified", value: \.modified) { r in
                    Text(r.modified, format: .dateTime.year().month().day()).foregroundStyle(.secondary)
                }
                .width(min: 90, ideal: 110)
                TableColumn("Location", value: \.folder) { r in
                    Text(abbreviated(r.folder)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            .contextMenu(forSelectionType: FileRecord.ID.self) { ids in
                Button("Reveal in Finder", systemImage: "folder") { model.reveal(Array(ids)) }
                Button("Move to Trash…", systemImage: "trash", role: .destructive) { selection = ids; confirm = true }
            } primaryAction: { ids in
                model.reveal(Array(ids))
            }
            .scrollContentBackground(.hidden)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
            .clipShape(.rect(cornerRadius: 22))
        }
        .padding(24)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter large files")
        .safeAreaInset(edge: .bottom) {
            if !selection.isEmpty {
                HStack(spacing: 14) {
                    Text("\(selection.count) selected · \(selectedSize.bytes)").font(.headline)
                    Spacer()
                    Button("Reveal", systemImage: "folder") { model.reveal(Array(selection)) }
                        .buttonStyle(.glass)
                    Button("Move to Trash", systemImage: "trash") { confirm = true }
                        .buttonStyle(.glassProminent).tint(.purple)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .frame(maxWidth: 600)
                .glassEffect(.regular, in: .capsule)
                .padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: selection.isEmpty)
        .confirmationDialog("Move \(selection.count) files to the Trash?", isPresented: $confirm) {
            Button("Move \(selectedSize.bytes) to Trash", role: .destructive) {
                model.trash(paths: Array(selection))
                selection = []
            }
        }
    }

    private func categoryChips(_ all: [FileRecord]) -> some View {
        let present = FileCategory.allCases.filter { c in all.contains { $0.category == c } }
        return GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                chip(nil, "All", "square.grid.2x2", .purple)
                ForEach(present) { c in chip(c, c.title, c.symbol, c.color) }
            }
        }
    }

    private func chip(_ c: FileCategory?, _ title: String, _ symbol: String, _ tint: Color) -> some View {
        Button {
            withAnimation(.smooth) { filter = c }
        } label: {
            Image(systemName: symbol)
                .frame(width: 30, height: 22)
                .foregroundStyle(filter == c ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
        }
        .buttonStyle(.plain)
        .padding(4)
        .glassEffect(filter == c ? .regular.tint(tint.opacity(0.25)).interactive() : .regular.interactive(), in: .capsule)
        .help(title)
    }

    private func abbreviated(_ p: String) -> String {
        let home = NSHomeDirectory()
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }
}
