import AppKit
import Observation

enum ScanTarget: Hashable {
    case home, disk, folder(URL)

    var path: String {
        switch self {
        case .home: NSHomeDirectory()
        case .disk: "/"
        case .folder(let url): url.path
        }
    }

    var title: String {
        switch self {
        case .home: "Home Folder"
        case .disk: "Macintosh HD"
        case .folder(let url): url.lastPathComponent
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .disk: "internaldrive"
        case .folder: "folder"
        }
    }
}

struct VolumeInfo {
    let name: String
    let total: Int64
    let available: Int64
    var used: Int64 { total - available }

    static func current() -> VolumeInfo? {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = v.volumeTotalCapacity else { return nil }
        return VolumeInfo(name: v.volumeName ?? "Macintosh HD", total: Int64(total),
                          available: v.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

struct SnapReport: Identifiable {
    let id = UUID()
    let freed: Int64
    let items: Int
    let failures: [String]
}

enum SidebarItem: Hashable {
    case overview, explorer, largeFiles, cleanup(FindingKind)
}

@Observable @MainActor
final class AppModel {
    enum Phase { case idle, scanning, ready }

    var phase: Phase = .idle
    var target: ScanTarget = .home
    var result: ScanResult?
    var findings: [Finding] = []
    var selection: Set<UUID> = []
    var analyzing = false
    var findingDuplicates = false
    var progressFiles = 0
    var progressBytes: Int64 = 0
    var currentPath = ""
    /// True when the file count hasn't moved for a while — usually macOS waiting on a permission dialog.
    var scanStalled = false
    var skippedProtected = 0
    var volume = VolumeInfo.current()
    var hasFullDiskAccess = AppModel.checkFullDiskAccess()
    var snapReport: SnapReport?
    var sidebar: SidebarItem? = .overview
    var explorerFocus: FileNode?
    /// FileNode is a plain class; views read this to redraw after the tree is mutated.
    var treeVersion = 0

    private var scanner: DiskScanner?

    init() {
        let env = ProcessInfo.processInfo.environment
        switch env["THANOS_VIEW"] {
        case "explorer": sidebar = .explorer
        case "large": sidebar = .largeFiles
        case let k?: if let kind = FindingKind(rawValue: k) { sidebar = .cleanup(kind) }
        default: break
        }
        if let p = env["THANOS_SCAN"], !p.isEmpty {
            let target: ScanTarget = p == NSHomeDirectory() ? .home : (p == "/" ? .disk : .folder(URL(fileURLWithPath: p)))
            Task { @MainActor in self.startScan(target) }
        }
    }
    private var scanTask: Task<Void, Never>?

    var root: FileNode? { result?.root }

    // MARK: - Scanning

    func startScan(_ newTarget: ScanTarget? = nil) {
        if let newTarget { target = newTarget }
        cancelScan()
        let scanner = DiskScanner()
        scanner.hasFullDiskAccess = Self.checkFullDiskAccess()
        self.scanner = scanner
        scanStalled = false
        phase = .scanning
        findings = []
        selection = []
        progressFiles = 0
        progressBytes = 0
        explorerFocus = nil
        hasFullDiskAccess = Self.checkFullDiskAccess()
        let path = target.path

        scanTask = Task {
            let poll = Task { @MainActor in
                var lastCount = -1
                var lastChange = Date()
                while !Task.isCancelled {
                    let count = scanner.progress.files.load(ordering: .relaxed)
                    if count != lastCount { lastCount = count; lastChange = Date() }
                    self.scanStalled = Date().timeIntervalSince(lastChange) > 12
                    self.progressFiles = scanner.progress.files.load(ordering: .relaxed)
                    self.progressBytes = scanner.progress.bytes.load(ordering: .relaxed)
                    self.currentPath = scanner.progress.current.withLock { $0 }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let result = await Task.detached(priority: .userInitiated) { scanner.scan(rootPath: path) }.value
            poll.cancel()
            guard !scanner.progress.cancelled.load(ordering: .relaxed) else { return }
            self.result = result
            self.skippedProtected = scanner.progress.skippedProtected.load(ordering: .relaxed)
            self.scanStalled = false
            self.explorerFocus = result.root
            self.volume = VolumeInfo.current()
            self.phase = .ready
            self.treeVersion += 1
            await self.analyze(result)
        }
    }

    func cancelScan() {
        scanner?.cancel()
        scanTask?.cancel()
        if phase == .scanning { phase = result == nil ? .idle : .ready }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        if panel.runModal() == .OK, let url = panel.url { startScan(.folder(url)) }
    }

    private func analyze(_ result: ScanResult) async {
        analyzing = true
        let found = await Task.detached(priority: .utility) { CleanupEngine(result: result).run() }.value
        findings = found.sorted { $0.size > $1.size }
        analyzing = false

        findingDuplicates = true
        let candidates = result.stats.duplicateCandidates
        let dupes = await Task.detached(priority: .utility) { DuplicateFinder.findings(from: candidates) }.value
        let taken = findings.flatMap(\.paths)
        findings += CleanupEngine.removingOverlaps(dupes.sorted { $0.size > $1.size }, claimed: taken) { DiskSize.of($0) }
        findingDuplicates = false
    }

    // MARK: - Queries

    func findings(_ kind: FindingKind) -> [Finding] { findings.filter { $0.kind == kind } }
    func total(_ kind: FindingKind) -> Int64 { findings(kind).reduce(0) { $0 + $1.size } }
    var reclaimable: Int64 { findings.reduce(0) { $0 + $1.size } }
    var safeFindings: [Finding] { findings.filter { $0.confidence == .safe && !$0.permanent } }
    var safeReclaimable: Int64 { safeFindings.reduce(0) { $0 + $1.size } }
    var selectedFindings: [Finding] { findings.filter { selection.contains($0.id) } }

    var categoryTotals: [(FileCategory, Int64)] {
        guard let r = result else { return [] }
        return FileCategory.allCases.compactMap { c in
            let v = r.stats.categoryTotals[c] ?? 0
            return v > 0 ? (c, v) : nil
        }.sorted { $0.1 > $1.1 }
    }

    // MARK: - Removal

    /// Moves findings to the Trash (or empties the Trash for the Trash finding).
    func snap(_ items: [Finding]) {
        var freed: Int64 = 0
        var count = 0
        var failures: [String] = []
        var removedPaths: [String] = []
        let fm = FileManager.default

        for item in items {
            var okForItem = true
            for path in item.paths {
                do {
                    if item.permanent { try fm.removeItem(atPath: path) }
                    else { try fm.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) }
                    removedPaths.append(path)
                    count += 1
                } catch {
                    okForItem = false
                    failures.append((path as NSString).lastPathComponent + ": " + error.localizedDescription)
                }
            }
            if okForItem { freed += item.size }
        }
        prune(removedPaths)
        let removedIDs = Set(items.map(\.id))
        findings.removeAll { f in removedIDs.contains(f.id) && f.paths.allSatisfy { removedPaths.contains($0) } }
        selection.subtract(removedIDs)
        volume = VolumeInfo.current()
        snapReport = SnapReport(freed: freed, items: count, failures: failures)
    }

    func trash(paths: [String]) {
        var freed: Int64 = 0
        var removed: [String] = []
        var failures: [String] = []
        for p in paths {
            let size = root?.descendant(atPath: p)?.size ?? DiskSize.of(p)
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil)
                freed += size
                removed.append(p)
            } catch {
                failures.append((p as NSString).lastPathComponent + ": " + error.localizedDescription)
            }
        }
        prune(removed)
        findings.removeAll { f in f.paths.allSatisfy { removed.contains($0) } }
        volume = VolumeInfo.current()
        snapReport = SnapReport(freed: freed, items: removed.count, failures: failures)
    }

    private func prune(_ paths: [String]) {
        guard var r = result else { return }
        let removed = Set(paths)
        for p in paths { r.root.descendant(atPath: p)?.detach() }
        r.stats.largeFiles.removeAll { removed.contains($0.path) }
        result = r
        if let focus = explorerFocus, !focus.isAttached(to: r.root) { explorerFocus = r.root }
        treeVersion += 1
    }

    // MARK: - System

    /// Full Disk Access can't be queried directly, so probe locations only it unlocks.
    /// Each fails cleanly (no prompt) without access; any one succeeding means access is on.
    static func checkFullDiskAccess() -> Bool {
        let home = NSHomeDirectory()
        let files = [home + "/Library/Application Support/com.apple.TCC/TCC.db",
                     "/Library/Application Support/com.apple.TCC/TCC.db"]
        for f in files {
            if let h = FileHandle(forReadingAtPath: f) { try? h.close(); return true }
        }
        let dirs = [home + "/Library/Mail", home + "/Library/Messages", home + "/Library/Safari",
                    home + "/Library/Cookies", "/Library/Application Support/com.apple.TCC"]
        for d in dirs where FileManager.default.fileExists(atPath: d) {
            if (try? FileManager.default.contentsOfDirectory(atPath: d)) != nil { return true }
        }
        return false
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func reveal(_ paths: [String]) {
        NSWorkspace.shared.activateFileViewerSelecting(paths.map { URL(fileURLWithPath: $0) })
    }
}
