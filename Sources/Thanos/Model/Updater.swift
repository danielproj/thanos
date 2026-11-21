import Combine
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater. Checks once a day by default (Info.plist `SUScheduledCheckInterval`)
/// against the appcast attached to the latest GitHub release, verifies every update with the EdDSA public key
/// in Info.plist, and shows Sparkle's standard update window. No system profile is sent.
@MainActor
final class AppUpdater: ObservableObject {
    private let controller: SPUStandardUpdaterController
    @Published private(set) var canCheckForUpdates = false
    @Published var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    @Published var automaticallyDownloads: Bool {
        didSet { controller.updater.automaticallyDownloadsUpdates = automaticallyDownloads }
    }
    private var cancellables: Set<AnyCancellable> = []

    /// Development builds (`swift run`, unsigned bundles) have no feed; Sparkle is left idle there.
    let isEnabled: Bool

    init() {
        let hasFeed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        isEnabled = hasFeed
        controller = SPUStandardUpdaterController(startingUpdater: hasFeed, updaterDelegate: nil, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.canCheckForUpdates = $0 && hasFeed }
            .store(in: &cancellables)
    }

    var lastCheck: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!updater.canCheckForUpdates)
    }
}

struct SettingsView: View {
    @ObservedObject var updater: AppUpdater

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section("Updates") {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecks)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloads)
                    .disabled(!updater.automaticallyChecks)
                LabeledContent("Version", value: version)
                if let last = updater.lastCheck {
                    LabeledContent("Last checked") { Text(last, format: .relative(presentation: .named)) }
                }
                HStack {
                    Spacer()
                    Button("Check Now", action: updater.checkForUpdates)
                        .buttonStyle(.glass)
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            .disabled(!updater.isEnabled)
            if !updater.isEnabled {
                Text("Updates are available in release builds downloaded from GitHub.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }
}
