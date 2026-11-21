import SwiftUI

enum FindingKind: String, CaseIterable, Identifiable, Sendable, Hashable {
    case leftovers, caches, developer, installers, duplicates, oldFiles, trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leftovers: "App Leftovers"
        case .caches: "Caches & Logs"
        case .developer: "Developer Junk"
        case .installers: "Installers"
        case .duplicates: "Duplicates"
        case .oldFiles: "Large & Forgotten"
        case .trash: "Trash"
        }
    }

    var symbol: String {
        switch self {
        case .leftovers: "shippingbox.and.arrow.backward"
        case .caches: "internaldrive"
        case .developer: "hammer"
        case .installers: "opticaldisc"
        case .duplicates: "square.on.square"
        case .oldFiles: "clock.badge.questionmark"
        case .trash: "trash"
        }
    }

    var tint: Color {
        switch self {
        case .leftovers: .purple
        case .caches: .blue
        case .developer: .mint
        case .installers: .orange
        case .duplicates: .pink
        case .oldFiles: .yellow
        case .trash: .gray
        }
    }

    var blurb: String {
        switch self {
        case .leftovers: "Support files, preferences and containers left behind by apps that are no longer installed."
        case .caches: "Data apps rebuild on their own. Clearing it frees space; apps may be a little slower on first launch."
        case .developer: "Build products, simulator caches, package-manager caches and dependency folders in stale projects."
        case .installers: "Disk images and packages in Downloads and Desktop. The app they installed keeps working."
        case .duplicates: "Byte-for-byte identical copies, verified by SHA-256. The oldest copy is kept."
        case .oldFiles: "Files over 100 MB that haven't been modified in more than a year."
        case .trash: "Items already in the Trash. Emptying it is permanent."
        }
    }
}

enum Confidence: Int, Comparable, Sendable, Hashable {
    case safe, review, caution

    static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .safe: "Safe"
        case .review: "Review"
        case .caution: "Caution"
        }
    }

    var color: Color {
        switch self {
        case .safe: .green
        case .review: .orange
        case .caution: .red
        }
    }
}

struct Finding: Identifiable, Sendable, Hashable {
    let id = UUID()
    let kind: FindingKind
    let title: String
    let subtitle: String
    let reason: String
    var paths: [String]
    var size: Int64
    let confidence: Confidence
    var iconPath: String?
    var date: Date?
    /// Emptying the Trash cannot go through the Trash.
    var permanent = false
}
