import SwiftUI
import AppKit

extension Int64 {
    var bytes: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

extension Int {
    var grouped: String { formatted(.number) }
}

/// The colour field behind everything. Liquid Glass needs something to refract,
/// so the backdrop is a slowly breathing mesh gradient rather than a flat fill.
struct Backdrop: View {
    @Environment(\.colorScheme) private var scheme
    @State private var t = false

    var body: some View {
        let dark = scheme == .dark
        MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [t ? 0.6 : 0.4, 0], [1, 0],
                [0, t ? 0.4 : 0.6], [t ? 0.45 : 0.6, t ? 0.55 : 0.4], [1, t ? 0.6 : 0.45],
                [0, 1], [t ? 0.4 : 0.6, 1], [1, 1],
            ],
            colors: dark ? [
                .init(red: 0.09, green: 0.06, blue: 0.20), .init(red: 0.20, green: 0.08, blue: 0.32), .init(red: 0.05, green: 0.10, blue: 0.24),
                .init(red: 0.12, green: 0.05, blue: 0.22), .init(red: 0.32, green: 0.14, blue: 0.42), .init(red: 0.06, green: 0.16, blue: 0.30),
                .init(red: 0.04, green: 0.05, blue: 0.12), .init(red: 0.24, green: 0.10, blue: 0.20), .init(red: 0.05, green: 0.06, blue: 0.14),
            ] : [
                .init(red: 0.93, green: 0.90, blue: 1.00), .init(red: 0.98, green: 0.88, blue: 0.96), .init(red: 0.86, green: 0.92, blue: 1.00),
                .init(red: 0.95, green: 0.92, blue: 1.00), .init(red: 0.88, green: 0.80, blue: 0.99), .init(red: 0.84, green: 0.93, blue: 0.99),
                .init(red: 0.97, green: 0.95, blue: 0.99), .init(red: 1.00, green: 0.90, blue: 0.90), .init(red: 0.91, green: 0.94, blue: 1.00),
            ]
        )
        .onAppear { withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { t.toggle() } }
    }
}

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 20
    var radius: CGFloat = 26
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular.tint(tint?.opacity(0.12)), in: .rect(cornerRadius: radius))
    }
}

struct SectionTitle: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

/// A tinted SF Symbol sitting on its own small glass disc.
struct GlassIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint.gradient)
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(tint.opacity(0.18)), in: .circle)
    }
}

struct ConfidenceBadge: View {
    let confidence: Confidence
    var body: some View {
        Text(confidence.title)
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .foregroundStyle(confidence.color)
            .background(confidence.color.opacity(0.15), in: .capsule)
    }
}

/// Finder's own icon for a path — real app icons, document thumbnails' type icons, folder tints.
struct FileIcon: View {
    let path: String?
    var fallback: String = "doc"
    var size: CGFloat = 28
    var body: some View {
        if let path, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: fallback)
                .font(.system(size: size * 0.6))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol).foregroundStyle(tint.gradient).font(.title3.weight(.semibold))
                Spacer()
            }
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .lineLimit(1).minimumScaleFactor(0.6)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                if let footnote { Text(footnote).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: .rect(cornerRadius: 22))
    }
}

/// A horizontal proportional bar like the one in System Settings › Storage.
struct SegmentBar: View {
    struct Segment: Identifiable { let id = UUID(); let value: Double; let color: Color; let label: String }
    let segments: [Segment]
    var height: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let total = max(segments.reduce(0) { $0 + $1.value }, 1)
            HStack(spacing: 2) {
                ForEach(segments) { s in
                    Rectangle()
                        .fill(s.color.gradient)
                        .frame(width: max(0, geo.size.width * s.value / total - 2))
                        .help("\(s.label) — \(Int64(s.value).bytes)")
                }
            }
        }
        .frame(height: height)
        .clipShape(.capsule)
    }
}

struct LegendDot: View {
    let color: Color
    let label: String
    let value: String
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color.gradient).frame(width: 9, height: 9)
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }
}

let folderPalette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .yellow, .cyan, .red, .mint, .brown]
