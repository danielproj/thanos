import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 250, max: 300)
        } detail: {
            ZStack {
                Backdrop()
                    .ignoresSafeArea()
                    .backgroundExtensionEffect()
                detail
            }
            .toolbar { ScanToolbar() }
        }
        .overlay {
            if let report = model.snapReport {
                SnapOverlay(report: report) { model.snapReport = nil }
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: model.snapReport?.id)
    }

    @ViewBuilder private var detail: some View {
        switch model.phase {
        case .idle: WelcomeView()
        case .scanning: ScanningView()
        case .ready:
            switch model.sidebar ?? .overview {
            case .overview: OverviewView()
            case .explorer: ExplorerView()
            case .largeFiles: LargeFilesView()
            case .cleanup(let kind): CleanupView(kind: kind)
            }
        }
    }
}

struct ScanToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Menu {
                Button("Home Folder", systemImage: "house") { model.startScan(.home) }
                Button("Macintosh HD", systemImage: "internaldrive") { model.startScan(.disk) }
                Divider()
                Button("Choose Folder…", systemImage: "folder") { model.chooseFolder() }
            } label: {
                Label(model.target.title, systemImage: model.target.symbol)
                    .labelStyle(.titleAndIcon)
            }
            .help("Choose what to scan")
        }

        ToolbarSpacer(.flexible)

        if model.phase == .ready && (model.analyzing || model.findingDuplicates) {
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .controlSize(.small)
                    .help(model.analyzing ? "Looking for leftovers…" : "Comparing duplicates…")
            }
            .sharedBackgroundVisibility(.hidden)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if model.phase == .scanning {
                Button("Stop", systemImage: "stop.fill") { model.cancelScan() }
            } else {
                Button {
                    model.startScan()
                } label: {
                    Label(model.phase == .ready ? "Rescan" : "Scan", systemImage: "sparkle.magnifyingglass")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.glassProminent)
                .tint(.purple)
            }
        }
    }
}
