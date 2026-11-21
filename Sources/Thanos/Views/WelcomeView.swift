import SwiftUI

struct WelcomeView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var glass
    @State private var hovered: Int?

    var body: some View {
        VStack(spacing: 36) {
            VStack(spacing: 14) {
                Image(systemName: "sparkles")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 112, height: 112)
                    .glassEffect(.regular.tint(.purple.opacity(0.15)).interactive(), in: .circle)
                Text("See everything. Keep what matters.")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Thanos maps every byte on your Mac, finds what apps left behind,\nand lets you snap the rest away — safely, into the Trash.")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            GlassEffectContainer(spacing: 18) {
                HStack(spacing: 18) {
                    targetTile(0, .home, "Your files, apps' data and caches. Fast.")
                    targetTile(1, .disk, "Everything on the startup disk, including system.")
                    Button { model.chooseFolder() } label: {
                        tileBody(symbol: "folder.badge.plus", title: "Choose Folder…", detail: "Any folder or external drive.", tint: .teal, index: 2)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(.teal.opacity(hovered == 2 ? 0.2 : 0.08)).interactive(), in: .rect(cornerRadius: 26))
                    .glassEffectID(2, in: glass)
                    .onHover { hovered = $0 ? 2 : nil }
                }
            }
            .frame(maxWidth: 820)
            .fixedSize(horizontal: false, vertical: true)

            if !model.hasFullDiskAccess {
                Button {
                    model.openFullDiskAccessSettings()
                } label: {
                    Label("Grant Full Disk Access for a complete picture", systemImage: "lock.open")
                }
                .buttonStyle(.glass)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func targetTile(_ index: Int, _ target: ScanTarget, _ detail: String) -> some View {
        Button { model.startScan(target) } label: {
            tileBody(symbol: target.symbol, title: target.title, detail: detail,
                     tint: index == 0 ? .purple : .blue, index: index)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint((index == 0 ? Color.purple : .blue).opacity(hovered == index ? 0.2 : 0.08)).interactive(),
                     in: .rect(cornerRadius: 26))
        .glassEffectID(index, in: glass)
        .onHover { hovered = $0 ? index : nil }
    }

    private func tileBody(symbol: String, title: String, detail: String, tint: Color, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(tint.gradient)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Text(index == 2 ? "Browse" : "Scan").font(.callout.weight(.semibold))
                Image(systemName: "arrow.right")
            }
            .foregroundStyle(tint)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 190, maxHeight: 210, alignment: .topLeading)
        .contentShape(.rect)
        .scaleEffect(hovered == index ? 1.02 : 1)
        .animation(.spring(duration: 0.3), value: hovered)
    }
}

struct ScanningView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 30) {
            ZStack {
                TimelineView(.animation) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                    ZStack {
                        Circle()
                            .stroke(AngularGradient(colors: [.purple, .pink, .orange, .blue, .purple], center: .center),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.radians(t * 0.9))
                            .blur(radius: 18)
                            .opacity(0.8)
                        Circle()
                            .trim(from: 0, to: 0.72)
                            .stroke(AngularGradient(colors: [.purple.opacity(0), .purple, .pink], center: .center),
                                    style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.radians(t * 2.2))
                    }
                }
                .frame(width: 230, height: 230)

                VStack(spacing: 4) {
                    Text(model.progressFiles.grouped)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .padding(.horizontal, 14)
                        .contentTransition(.numericText())
                    Text("files").font(.callout).foregroundStyle(.secondary)
                    Text(model.progressBytes.bytes)
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(width: 190, height: 190)
                .glassEffect(.regular, in: .circle)
            }
            .animation(.snappy, value: model.progressFiles)

            VStack(spacing: 6) {
                Text("Scanning \(model.target.title)…").font(.title2.weight(.semibold))
                Text(model.currentPath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 560)
            }
            if model.scanStalled {
                Label("Waiting on macOS — if a permission dialog is open, answer it to continue.", systemImage: "hand.raised")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassEffect(.regular.tint(.orange.opacity(0.15)), in: .capsule)
                    .transition(.opacity)
            }
            Button("Stop Scan", systemImage: "stop.fill") { model.cancelScan() }
                .buttonStyle(.glass)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
