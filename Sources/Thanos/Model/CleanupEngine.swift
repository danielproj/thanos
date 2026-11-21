import AppKit
import CryptoKit

/// Everything installed on this Mac that could own files in ~/Library.
struct InstalledApps: Sendable {
    var bundleIDs: Set<String> = []          // lowercased
    var names: Set<String> = []              // normalised display/executable names
    var vendors: Set<String> = []            // second reverse-DNS component, e.g. "google"
    var displayNameByID: [String: String] = [:]
    var pathByID: [String: String] = [:]

    static func normalise(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    static func discover() -> InstalledApps {
        var apps = InstalledApps()
        var seen = Set<String>()
        var paths: [String] = spotlightApps()
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", NSHomeDirectory() + "/Applications",
                     "/System/Library/CoreServices", "/Library/Application Support"]
        for root in roots {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                        options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                if e.level > 4 { e.skipDescendants(); continue }
                if url.pathExtension == "app" { paths.append(url.path) }
            }
        }
        for path in paths where seen.insert(path).inserted {
            apps.register(appAt: path)
            // Login items and helpers carry their own identifiers.
            for sub in ["Contents/Library/LoginItems", "Contents/Helpers", "Contents/Frameworks"] {
                let dir = path + "/" + sub
                for item in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where item.hasSuffix(".app") {
                    apps.register(appAt: dir + "/" + item, primary: false)
                }
            }
        }
        return apps
    }

    private mutating func register(appAt path: String, primary: Bool = true) {
        guard let bundle = Bundle(path: path) else { return }
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if let id = bundle.bundleIdentifier?.lowercased() {
            bundleIDs.insert(id)
            let parts = id.split(separator: ".")
            if parts.count >= 2 { vendors.insert(String(parts[1])) }
            if primary {
                displayNameByID[id] = fileName
                pathByID[id] = path
            }
        }
        guard primary else { return }
        names.insert(Self.normalise(fileName))
        for key in ["CFBundleName", "CFBundleDisplayName", "CFBundleExecutable"] {
            if let v = bundle.object(forInfoDictionaryKey: key) as? String, !v.isEmpty { names.insert(Self.normalise(v)) }
        }
    }

    private static func spotlightApps() -> [String] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        p.arguments = ["kMDItemContentType == 'com.apple.application-bundle'"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
            .filter { !$0.hasPrefix("/Volumes/") && !$0.contains("/.Trash/") }
    }

    enum Match { case installed, sameVendor(String), none }

    func match(identifier raw: String) -> Match {
        let id = raw.lowercased()
        if bundleIDs.contains(id) { return .installed }
        for b in bundleIDs where id.hasPrefix(b + ".") || b.hasPrefix(id + ".") { return .installed }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: raw) != nil { return .installed }
        let parts = id.split(separator: ".")
        if parts.count >= 2, vendors.contains(String(parts[1])) { return .sameVendor(String(parts[1])) }
        return .none
    }

    func matches(name: String) -> Bool {
        let n = Self.normalise(name)
        guard n.count >= 3 else { return true }
        if names.contains(n) || vendors.contains(n) { return true }
        for installed in names where installed.count >= 4 && (installed.hasPrefix(n) || n.hasPrefix(installed)) { return true }
        return false
    }
}

/// Turns a finished scan into actionable findings. Pure read-only: nothing is removed here.
struct CleanupEngine: @unchecked Sendable {
    let result: ScanResult
    let home = NSHomeDirectory()
    let fm = FileManager.default
    let now = Date()

    func size(of path: String) -> Int64 {
        if let node = result.root.descendant(atPath: path) { return node.size }
        return DiskSize.of(path)
    }

    func modified(_ path: String) -> Date? {
        (try? fm.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    func list(_ dir: String) -> [String] {
        ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).filter { !$0.hasPrefix(".") }
    }

    func days(_ d: Date?) -> Int { d.map { Int(now.timeIntervalSince($0) / 86_400) } ?? 9_999 }

    // MARK: - Run

    func run() -> [Finding] {
        let apps = InstalledApps.discover()
        var findings: [Finding] = []
        let (leftovers, claimed) = leftoverFindings(apps)
        findings += leftovers
        findings += cacheFindings(apps, claimed: claimed)
        findings += developerFindings()
        findings += installerFindings()
        findings += oldFileFindings()
        findings += trashFindings()
        return Self.removingOverlaps(findings, claimed: []) { size(of: $0) }.filter { $0.size > 0 }
    }

    /// Each byte may be offered once. Findings claim their paths in priority order; a later finding
    /// loses any path equal to, inside, or containing one already claimed, and its size is recomputed.
    static func removingOverlaps(_ findings: [Finding], claimed initial: [String], size: (String) -> Int64) -> [Finding] {
        var claimed = initial
        func overlaps(_ p: String) -> Bool {
            claimed.contains { p == $0 || p.hasPrefix($0 + "/") || $0.hasPrefix(p + "/") }
        }
        var out: [Finding] = []
        for var f in findings {
            let kept = f.paths.filter { !overlaps($0) }
            guard !kept.isEmpty else { continue }
            if kept.count != f.paths.count {
                f.paths = kept
                f.size = kept.reduce(0) { $0 + size($1) }
            }
            claimed += kept
            out.append(f)
        }
        return out
    }

    // MARK: - Leftovers

    private static let ignoredNames: Set<String> = [
        "addressbook", "callhistorydb", "callhistorytransactions", "clouddocs", "cloudkit", "crashreporter",
        "dock", "icdd", "knowledge", "mobilesync", "fileprovider", "accounts", "animoji", "askpermission",
        "contacts", "facetime", "familycircle", "quicklook", "syncservices", "videoconference", "identityservices",
        "ubiquity", "sharedfilelist", "dmd", "siri", "translation", "default", "caches", "cache", "logs", "diagnosticreports",
        "spotlight", "homekit", "metadata", "stickers", "recentservers", "geoservices", "storeassets", "keychains",
        "networkserviceproxy", "app store", "appstore", "tmp", "temp", "backgroundassets", "mobiledevice", "itunes",
        "sessions", "familysettings", "photos", "music", "tv", "podcasts", "news", "maps", "weather", "fontregistry",
        "audio", "colorpickers", "colorsync", "compositions", "fonts", "input methods", "internet plug-ins", "screen savers",
        "services", "sounds", "spelling", "assistants", "autosave information", "calendars", "mail", "messages",
        "safari", "shortcuts", "reminders", "journal", "passwords", "sharing", "intelligenceplatform", "duetexpertcenter",
        "node", "npm", "pnpm", "yarn", "pip", "virtualenv", "pypoetry", "uv", "go", "rustup", "cargo", "deno", "bun",
        "jupyter", "matplotlib", "homebrew", "gem", "cocoapods", "carthage", "swiftpm", "org.swift.swiftpm",
        "claude", "anthropic", "electron", "chromium", "crashpad", "sentry",
    ]

    private func identifier(fromEntry name: String) -> String? {
        var n = name
        for ext in [".plist", ".savedState", ".binarycookies", ".lockfile"] where n.hasSuffix(ext) {
            n.removeLast(ext.count)
        }
        if n.hasPrefix("group.") { n.removeFirst("group.".count) }
        // Group containers are prefixed by a 10-character team ID: "ABCDE12345.com.vendor.app"
        let parts = n.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count >= 3, parts[0].count == 10, parts[0].allSatisfy({ $0.isUppercase || $0.isNumber }) {
            n = parts.dropFirst().joined(separator: ".")
        }
        let comps = n.split(separator: ".")
        guard comps.count >= 3, comps.allSatisfy({ !$0.isEmpty }),
              comps[0].count <= 6, comps[0].allSatisfy({ $0.isLetter }) else { return nil }
        let lower = n.lowercased()
        let reserved = ["com.apple.", "apple.", "systemgroup.", "homebrew.", "org.homebrew.", "com.apple",
                        "net.whatsapp.family", "org.cups", "com.vmware.fusion.keys"]
        if reserved.contains(where: { lower.hasPrefix($0) }) { return nil }
        return n
    }

    private func leftoverFindings(_ apps: InstalledApps) -> ([Finding], Set<String>) {
        let lib = home + "/Library"
        let bundleDirs: [(String, String)] = [
            ("Application Support", lib + "/Application Support"),
            ("Caches", lib + "/Caches"),
            ("Containers", lib + "/Containers"),
            ("Group Containers", lib + "/Group Containers"),
            ("Preferences", lib + "/Preferences"),
            ("Saved State", lib + "/Saved Application State"),
            ("HTTP Storage", lib + "/HTTPStorages"),
            ("WebKit", lib + "/WebKit"),
            ("Logs", lib + "/Logs"),
            ("Cookies", lib + "/Cookies"),
            ("Launch Agents", lib + "/LaunchAgents"),
            ("Application Scripts", lib + "/Application Scripts"),
        ]

        struct Group { var paths: [String] = []; var places: Set<String> = []; var vendor: String?; var agent = false; var newest: Date? }
        var groups: [String: Group] = [:]
        var claimed = Set<String>()

        for (place, dir) in bundleDirs {
            for entry in list(dir) {
                guard let id = identifier(fromEntry: entry) else { continue }
                let match = apps.match(identifier: id)
                if case .installed = match { continue }
                let key = id.lowercased()
                let path = dir + "/" + entry
                var g = groups[key] ?? Group()
                g.paths.append(path)
                g.places.insert(place)
                if case .sameVendor(let v) = match { g.vendor = v }
                if place == "Launch Agents" { g.agent = true }
                if let m = modified(path), m > (g.newest ?? .distantPast) { g.newest = m }
                groups[key] = g
                claimed.insert(path)
            }
        }

        var findings: [Finding] = []
        for (id, g) in groups {
            let total = g.paths.reduce(Int64(0)) { $0 + size(of: $1) }
            guard total >= 64 * 1024 else { continue }
            let recent = days(g.newest) < 14
            var reasons: [String] = ["No installed app uses the identifier \(id)."]
            var confidence: Confidence = .safe
            if let v = g.vendor { confidence = .review; reasons.append("Another app from “\(v)” is installed and may share this data.") }
            if g.agent { confidence = .review; reasons.append("Includes a launch agent — check it isn't a command-line tool's service.") }
            if recent { confidence = .review; reasons.append("Modified \(days(g.newest)) days ago, so something may still be writing to it.") }
            findings.append(Finding(kind: .leftovers, title: prettyName(fromIdentifier: id),
                                    subtitle: "\(g.paths.count) item\(g.paths.count == 1 ? "" : "s") in " + g.places.sorted().joined(separator: ", "),
                                    reason: reasons.joined(separator: " "), paths: g.paths.sorted(), size: total,
                                    confidence: confidence, iconPath: nil, date: g.newest))
        }

        // Named folders (no bundle identifier) — matched against installed app names, flagged for review only.
        for dir in [lib + "/Application Support", lib + "/Logs"] {
            for entry in list(dir) where identifier(fromEntry: entry) == nil && !entry.lowercased().hasPrefix("com.apple") {
                let path = dir + "/" + entry
                guard !claimed.contains(path),
                      !Self.ignoredNames.contains(entry.lowercased()),
                      !apps.matches(name: entry) else { continue }
                let mod = modified(path)
                guard days(mod) > 30 else { continue }     // something is clearly still using it
                let s = size(of: path)
                guard s >= 1 << 20 else { continue }
                claimed.insert(path)
                findings.append(Finding(kind: .leftovers, title: entry,
                                        subtitle: "Folder in " + (dir as NSString).lastPathComponent,
                                        reason: "No installed app is called “\(entry)”, and nothing has touched this folder in \(days(mod)) days. Command-line tools also keep data here, so check before removing.",
                                        paths: [path], size: s, confidence: .review, date: mod))
            }
        }
        return (findings, claimed)
    }

    private func prettyName(fromIdentifier id: String) -> String {
        let parts = id.split(separator: ".")
        guard let last = parts.last else { return id }
        var name = String(last)
        if ["helper", "agent", "daemon", "launcher", "app", "mac", "macos", "desktop", "shipit", "updater"].contains(name.lowercased()), parts.count >= 3 {
            name = String(parts[parts.count - 2])
        }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    // MARK: - Caches & logs

    private func cacheFindings(_ apps: InstalledApps, claimed: Set<String>) -> [Finding] {
        let dir = home + "/Library/Caches"
        let devCaches: Set<String> = ["com.apple.dt.Xcode", "Homebrew", "pip", "Yarn", "CocoaPods", "org.swift.swiftpm",
                                      "go-build", "ms-playwright", "pnpm", "node-gyp", "JetBrains"]
        var findings: [Finding] = []
        for entry in list(dir) {
            let path = dir + "/" + entry
            guard !claimed.contains(path), !devCaches.contains(entry) else { continue }
            let s = size(of: path)
            guard s >= 20 << 20 else { continue }
            let lower = entry.lowercased()
            let isApple = lower.hasPrefix("com.apple.")
            let appPath = apps.pathByID[lower]
            let title = apps.displayNameByID[lower] ?? (isApple ? entry.replacingOccurrences(of: "com.apple.", with: "Apple ") : entry)
            findings.append(Finding(kind: .caches, title: title, subtitle: "Cache · " + entry,
                                    reason: isApple ? "A macOS cache. It is rebuilt automatically, but some system features may re-download content."
                                                    : "Application cache. The app rebuilds it when needed.",
                                    paths: [path], size: s, confidence: isApple ? .review : .safe,
                                    iconPath: appPath, date: modified(path)))
        }
        let logs = home + "/Library/Logs"
        let logItems = list(logs).map { logs + "/" + $0 }.filter { !claimed.contains($0) }
        let logSize = logItems.reduce(Int64(0)) { $0 + size(of: $1) }
        if logSize >= 10 << 20 {
            findings.append(Finding(kind: .caches, title: "User Logs", subtitle: "\(logItems.count) items in ~/Library/Logs",
                                    reason: "Diagnostic logs written by apps. Only useful when you're actively troubleshooting.",
                                    paths: logItems, size: logSize, confidence: .safe))
        }
        return findings
    }

    // MARK: - Developer

    private func developerFindings() -> [Finding] {
        let lib = home + "/Library"
        let fixed: [(String, String, String, Confidence)] = [
            ("Xcode DerivedData", lib + "/Developer/Xcode/DerivedData", "Intermediate build products. Xcode rebuilds them on the next build.", .safe),
            ("iOS Device Support", lib + "/Developer/Xcode/iOS DeviceSupport", "Debug symbols copied from devices. Re-created when a device is connected.", .safe),
            ("watchOS Device Support", lib + "/Developer/Xcode/watchOS DeviceSupport", "Debug symbols copied from watches. Re-created on next connection.", .safe),
            ("Xcode Archives", lib + "/Developer/Xcode/Archives", "Archived app builds. You need these only to symbolicate crashes from shipped versions.", .review),
            ("Simulator Caches", lib + "/Developer/CoreSimulator/Caches", "Dyld and runtime caches for simulators. Rebuilt automatically.", .safe),
            ("Simulator Devices", lib + "/Developer/CoreSimulator/Devices", "Every simulator with its installed apps and data. Prefer `xcrun simctl delete unavailable`.", .caution),
            ("Xcode Cache", lib + "/Caches/com.apple.dt.Xcode", "Xcode's own download and index cache.", .safe),
            ("SwiftPM Cache", lib + "/Caches/org.swift.swiftpm", "Swift Package Manager download cache.", .safe),
            ("Homebrew Downloads", lib + "/Caches/Homebrew", "Bottles already installed. Same as `brew cleanup`.", .safe),
            ("pip Cache", lib + "/Caches/pip", "Python wheel cache.", .safe),
            ("Yarn Cache", lib + "/Caches/Yarn", "Yarn package cache.", .safe),
            ("CocoaPods Cache", lib + "/Caches/CocoaPods", "CocoaPods spec and download cache.", .safe),
            ("Go Build Cache", lib + "/Caches/go-build", "Go compiler cache. Same as `go clean -cache`.", .safe),
            ("Playwright Browsers", lib + "/Caches/ms-playwright", "Browser binaries downloaded by Playwright.", .review),
            ("JetBrains Caches", lib + "/Caches/JetBrains", "IDE index caches. Re-indexed on next open.", .safe),
            ("npm Cache", home + "/.npm/_cacache", "npm's content-addressed download cache.", .safe),
            ("pnpm Store", lib + "/pnpm/store", "pnpm's global store. Projects re-link on next install.", .review),
            ("Gradle Caches", home + "/.gradle/caches", "Downloaded Gradle dependencies and build caches.", .safe),
            ("Cargo Registry", home + "/.cargo/registry", "Downloaded crate sources.", .review),
            ("Bun Cache", home + "/.bun/install/cache", "Bun package cache.", .safe),
            ("General Cache (~/.cache)", home + "/.cache", "Tools following the XDG convention keep caches here.", .review),
        ]
        var findings: [Finding] = []
        for (title, path, reason, confidence) in fixed where fm.fileExists(atPath: path) {
            let s = size(of: path)
            guard s >= 50 << 20 else { continue }
            findings.append(Finding(kind: .developer, title: title, subtitle: abbreviate(path), reason: reason,
                                    paths: [path], size: s, confidence: confidence, date: modified(path)))
        }
        for artifact in result.stats.devArtifacts where artifact.node.size >= 20 << 20 {
            let age = days(artifact.projectModified)
            let project = (artifact.projectPath as NSString).lastPathComponent
            let stale = age > 30
            findings.append(Finding(kind: .developer, title: "\(project) — \(artifact.kind.rawValue)",
                                    subtitle: abbreviate(artifact.projectPath),
                                    reason: stale ? "Project untouched for \(age) days. Reinstall dependencies when you return to it."
                                                  : "Active project (changed \(age) days ago). Removing it means reinstalling dependencies.",
                                    paths: [artifact.node.path], size: artifact.node.size,
                                    confidence: stale ? .safe : .review, date: artifact.projectModified))
        }
        return findings
    }

    // MARK: - Installers

    private func installerFindings() -> [Finding] {
        let exts: Set<String> = ["dmg", "pkg", "mpkg", "xip", "iso", "ipsw"]
        var findings: [Finding] = []
        for dir in [home + "/Downloads", home + "/Desktop"] {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey],
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 3 { e.skipDescendants(); continue }
                guard exts.contains(url.pathExtension.lowercased()) else { continue }
                let v = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey])
                let s = Int64(v?.totalFileAllocatedSize ?? 0)
                guard s >= 5 << 20 else { continue }
                let age = days(v?.contentModificationDate)
                findings.append(Finding(kind: .installers, title: url.lastPathComponent, subtitle: abbreviate(url.deletingLastPathComponent().path),
                                        reason: age > 14 ? "Downloaded \(age) days ago. Installers can be downloaded again if needed."
                                                         : "Downloaded recently — make sure you've finished installing.",
                                        paths: [url.path], size: s, confidence: age > 14 ? .safe : .review,
                                        iconPath: url.path, date: v?.contentModificationDate))
            }
        }
        return findings
    }

    // MARK: - Old large files

    private func oldFileFindings() -> [Finding] {
        let lib = home + "/Library/"
        return result.stats.largeFiles
            .filter { days($0.modified) > 365 && !$0.path.hasPrefix(lib) && $0.category != .system && !$0.path.contains("/.Trash/") }
            .prefix(200)
            .map { r in
                Finding(kind: .oldFiles, title: r.name, subtitle: abbreviate(r.folder),
                        reason: "\(r.category.title) file, last modified \(days(r.modified) / 30) months ago.",
                        paths: [r.path], size: r.size, confidence: .review, iconPath: r.path, date: r.modified)
            }
    }

    // MARK: - Trash

    private func trashFindings() -> [Finding] {
        let trash = home + "/.Trash"
        guard let items = try? fm.contentsOfDirectory(atPath: trash), !items.isEmpty else { return [] }
        let paths = items.filter { $0 != ".DS_Store" }.map { trash + "/" + $0 }
        let s = paths.reduce(Int64(0)) { $0 + size(of: $1) }
        return [Finding(kind: .trash, title: "Trash", subtitle: "\(paths.count) items",
                        reason: "These are already in the Trash. Emptying is permanent and cannot be undone.",
                        paths: paths, size: s, confidence: .safe, permanent: true)]
    }

    func abbreviate(_ p: String) -> String { p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p }
}

// MARK: - Duplicates

enum DuplicateFinder {
    static func findings(from candidates: [FileRecord]) -> [Finding] {
        let home = NSHomeDirectory()
        let sizeGroups = Dictionary(grouping: candidates, by: \.size).values.filter { $0.count > 1 }.map { Array($0) }
        let lock = NSLock()
        var groups: [[FileRecord]] = []
        DispatchQueue.concurrentPerform(iterations: sizeGroups.count) { i in
            var local: [[FileRecord]] = []
            let unique = uniqueInodes(sizeGroups[i])
            guard unique.count > 1 else { return }
            for head in Dictionary(grouping: unique, by: { hash($0.path, limit: 64 * 1024) ?? UUID().uuidString }).values where head.count > 1 {
                for full in Dictionary(grouping: head, by: { hash($0.path, limit: nil) ?? UUID().uuidString }).values where full.count > 1 {
                    local.append(full)
                }
            }
            lock.lock(); groups += local; lock.unlock()
        }
        return groups.map { group in
            let sorted = group.sorted { ($0.modified, $0.path.count) < ($1.modified, $1.path.count) }
            let keep = sorted[0]
            let extra = Array(sorted.dropFirst())
            let short = keep.path.hasPrefix(home) ? "~" + keep.path.dropFirst(home.count) : keep.path
            return Finding(kind: .duplicates, title: keep.name,
                           subtitle: "\(group.count) identical copies · keeping \(short)",
                           reason: "Identical SHA-256. The oldest copy stays; \(extra.count) newer cop\(extra.count == 1 ? "y goes" : "ies go") to the Trash. If the copies are APFS clones, less space is freed.",
                           paths: extra.map(\.path), size: extra.reduce(0) { $0 + $1.size },
                           confidence: .review, iconPath: keep.path, date: keep.modified)
        }
    }

    /// Hard links are the same file; never offer to "dedupe" them.
    private static func uniqueInodes(_ files: [FileRecord]) -> [FileRecord] {
        var seen = Set<UInt64>()
        return files.filter { f in
            guard let ino = (try? FileManager.default.attributesOfItem(atPath: f.path)[.systemFileNumber]) as? UInt64 else { return true }
            return seen.insert(ino).inserted
        }
    }

    static func hash(_ path: String, limit: Int?) -> String? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        var read = 0
        while true {
            let chunk = limit.map { min(1 << 20, $0 - read) } ?? (1 << 20)
            guard chunk > 0, let data = try? h.read(upToCount: chunk), !data.isEmpty else { break }
            hasher.update(data: data)
            read += data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
