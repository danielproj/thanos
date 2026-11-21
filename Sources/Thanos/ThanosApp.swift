import SwiftUI

@main
struct ThanosApp: App {
    @State private var model = AppModel()
    @StateObject private var updater = AppUpdater()

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("Thanos") {
            RootView()
                .environment(model)
                .frame(minWidth: 1080, minHeight: 700)
                .onAppear { NSApp.activate() }
        }
        .defaultSize(width: 1360, height: 880)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updater: updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Scan Home Folder") { model.startScan(.home) }.keyboardShortcut("r")
                Button("Scan Entire Disk") { model.startScan(.disk) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Scan Folder…") { model.chooseFolder() }.keyboardShortcut("o")
            }
        }

        Settings {
            SettingsView(updater: updater)
        }
    }
}
