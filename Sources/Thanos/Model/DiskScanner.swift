import Foundation
import Synchronization

struct FileRecord: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let size: Int64
    let modified: Date
    let category: FileCategory

    var name: String { (path as NSString).lastPathComponent }
    var folder: String { (path as NSString).deletingLastPathComponent }
    var url: URL { URL(fileURLWithPath: path) }
}

enum DevArtifactKind: String, Sendable {
    case nodeModules = "node_modules"
    case pythonVenv = "Python virtualenv"
    case swiftBuild = "SwiftPM build"
    case rustTarget = "Rust target"
    case gradle = "Gradle cache"
    case pods = "CocoaPods"
    case nextBuild = "Next.js build"
}

struct DevArtifact: @unchecked Sendable {
    let node: FileNode
    let kind: DevArtifactKind
    let projectPath: String
    let projectModified: Date?
}

struct ScanStats: Sendable {
    var categoryTotals: [FileCategory: Int64] = [:]
    var categoryCounts: [FileCategory: Int] = [:]
    var largeFiles: [FileRecord] = []
    var duplicateCandidates: [FileRecord] = []
    var devArtifacts: [DevArtifact] = []
    var files = 0
    var directories = 0
    var unreadable = 0

    mutating func merge(_ o: ScanStats) {
        for (k, v) in o.categoryTotals { categoryTotals[k, default: 0] += v }
        for (k, v) in o.categoryCounts { categoryCounts[k, default: 0] += v }
        largeFiles += o.largeFiles
        duplicateCandidates += o.duplicateCandidates
        devArtifacts += o.devArtifacts
        files += o.files
        directories += o.directories
        unreadable += o.unreadable
    }
}

final class ScanProgress: Sendable {
    let files = Atomic<Int>(0)
    let skippedProtected = Atomic<Int>(0)
    let bytes = Atomic<Int64>(0)
    let cancelled = Atomic<Bool>(false)
    let current = Mutex<String>("")
}

struct ScanResult: @unchecked Sendable {
    let root: FileNode
    var stats: ScanStats
    let duration: TimeInterval
    let finishedAt: Date
}

/// Parallel filesystem walker. The top few levels fan out across cores with `concurrentPerform`;
/// below that each subtree is walked serially, so threads never fight over tiny directories.
final class DiskScanner: @unchecked Sendable {
    let progress = ScanProgress()

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        .contentModificationDateKey,
    ]
    private static let keySet = Set(keys)

    private let keepThreshold: Int64 = 1 << 20          // files >= 1 MB stay individual nodes
    private let largeThreshold: Int64 = 100 << 20       // >= 100 MB listed as large
    private let duplicateThreshold: Int64 = 4 << 20     // >= 4 MB considered for duplicates
    private let parallelDepth = 3

    private let home = NSHomeDirectory()
    private lazy var homeLibrary = home + "/Library"
    private let skipPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/cores",
        "/private/var/vm", "/.Spotlight-V100", "/.fseventsd", "/.DocumentRevisions-V100",
    ]
    private let systemRoots: Set<String> = ["/System", "/Library", "/private", "/usr", "/bin", "/sbin", "/opt"]

    private struct Context {
        var categoryOverride: FileCategory?
        var insideArtifact = false
        var insidePackage = false
    }

    /// Other apps' sandbox containers. Without Full Disk Access, opening one makes macOS show a
    /// "would like to access data from other apps" prompt and blocks the read until it's answered.
    private lazy var protectedParents: Set<String> = [home + "/Library/Containers", home + "/Library/Group Containers"]
    var hasFullDiskAccess = true

    func cancel() { progress.cancelled.store(true, ordering: .relaxed) }

    func scan(rootPath: String) -> ScanResult {
        let start = Date()
        _ = homeLibrary
        _ = protectedParents
        let root = FileNode(name: rootPath, isDirectory: true)
        var stats = ScanStats()
        var ctx = Context()
        if rootPath.hasPrefix(homeLibrary) { ctx.categoryOverride = .system }
        scanDirectory(root, url: URL(fileURLWithPath: rootPath, isDirectory: true), depth: 0, ctx: ctx, stats: &stats)
        stats.largeFiles.sort { $0.size > $1.size }
        return ScanResult(root: root, stats: stats, duration: Date().timeIntervalSince(start), finishedAt: Date())
    }

    private func scanDirectory(_ node: FileNode, url: URL, depth: Int, ctx: Context, stats: inout ScanStats) {
        if progress.cancelled.load(ordering: .relaxed) { return }
        if depth <= 4 { let p = url.path; progress.current.withLock { $0 = p } }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: Self.keys, options: [])
        } catch {
            stats.unreadable += 1
            return
        }

        var subdirs: [(url: URL, node: FileNode, ctx: Context, artifact: DevArtifactKind?)] = []
        var kids: [FileNode] = []
        var fileBytes: Int64 = 0
        var fileCount = 0
        var smallBytes: Int64 = 0
        var smallCount = 0
        var progressBatch = 0
        var progressBytes: Int64 = 0
        let parentPath = url.path
        let skipChildren = !hasFullDiskAccess && protectedParents.contains(parentPath)

        for entry in entries {
            let path = entry.path
            if skipPaths.contains(path) { continue }
            guard let v = try? entry.resourceValues(forKeys: Self.keySet) else { stats.unreadable += 1; continue }
            if v.isSymbolicLink == true { continue }
            // Never cross into another filesystem (VM mounts like ~/OrbStack, network shares, disk images).
            if v.isVolume == true { continue }
            let name = entry.lastPathComponent

            if v.isDirectory == true {
                let isPackage = v.isPackage == true
                var child = ctx
                var artifact: DevArtifactKind?
                if isPackage { child.insidePackage = true }
                if ctx.categoryOverride == nil {
                    if isPackage && name.hasSuffix(".app") { child.categoryOverride = .apps }
                    else if path == homeLibrary || systemRoots.contains(path) { child.categoryOverride = .system }
                    else if name == ".git" || name == "DerivedData" { child.categoryOverride = .developer }
                }
                if !ctx.insideArtifact && !ctx.insidePackage, let kind = artifactKind(name: name, path: path, parent: parentPath) {
                    artifact = kind
                    child.insideArtifact = true
                    child.categoryOverride = .developer
                }
                let dirNode = FileNode(name: name, isDirectory: true, isPackage: isPackage,
                                       modified: v.contentModificationDate,
                                       category: child.categoryOverride ?? (isPackage ? .apps : .other))
                dirNode.parent = node
                kids.append(dirNode)
                if skipChildren {
                    progress.skippedProtected.add(1, ordering: .relaxed)
                } else {
                    subdirs.append((entry, dirNode, child, artifact))
                }
                stats.directories += 1
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? v.fileSize ?? 0)
                let category = ctx.categoryOverride ?? FileCategory.classify(fileName: name)
                stats.files += 1
                stats.categoryTotals[category, default: 0] += size
                stats.categoryCounts[category, default: 0] += 1
                fileBytes += size
                fileCount += 1

                if size >= keepThreshold {
                    let f = FileNode(name: name, isDirectory: false, size: size, itemCount: 1,
                                     modified: v.contentModificationDate, category: category)
                    f.parent = node
                    kids.append(f)
                    let mod = v.contentModificationDate ?? .distantPast
                    if size >= largeThreshold && !ctx.insidePackage {
                        stats.largeFiles.append(FileRecord(path: path, size: size, modified: mod, category: category))
                    }
                    if size >= duplicateThreshold && !ctx.insidePackage && !ctx.insideArtifact
                        && ctx.categoryOverride != .system && ctx.categoryOverride != .apps {
                        stats.duplicateCandidates.append(FileRecord(path: path, size: size, modified: mod, category: category))
                    }
                } else {
                    smallBytes += size
                    smallCount += 1
                }

                progressBatch += 1
                progressBytes += size
                if progressBatch >= 128 {
                    progress.files.add(progressBatch, ordering: .relaxed)
                    progress.bytes.add(progressBytes, ordering: .relaxed)
                    progressBatch = 0; progressBytes = 0
                }
            }
        }
        progress.files.add(progressBatch, ordering: .relaxed)
        progress.bytes.add(progressBytes, ordering: .relaxed)

        if smallCount > 0 {
            let agg = FileNode(name: smallCount == 1 ? "1 small file" : "\(smallCount) small files",
                               isDirectory: false, isAggregate: true, size: smallBytes, itemCount: smallCount,
                               category: ctx.categoryOverride ?? .other)
            agg.parent = node
            kids.append(agg)
        }

        if depth < parallelDepth && subdirs.count > 1 {
            let lock = NSLock()
            var merged = ScanStats()
            let work = subdirs
            DispatchQueue.concurrentPerform(iterations: work.count) { i in
                var local = ScanStats()
                let item = work[i]
                self.scanDirectory(item.node, url: item.url, depth: depth + 1, ctx: item.ctx, stats: &local)
                lock.lock(); merged.merge(local); lock.unlock()
            }
            stats.merge(merged)
        } else {
            for item in subdirs {
                scanDirectory(item.node, url: item.url, depth: depth + 1, ctx: item.ctx, stats: &stats)
            }
        }

        var total = fileBytes
        var count = fileCount
        for item in subdirs {
            total += item.node.size
            count += item.node.itemCount
            if let kind = item.artifact {
                stats.devArtifacts.append(DevArtifact(node: item.node, kind: kind, projectPath: parentPath,
                                                      projectModified: node.modified))
            }
        }
        node.size = total
        node.itemCount = count
        kids.sort { $0.size > $1.size }
        node.children = kids
    }

    private func artifactKind(name: String, path: String, parent: String) -> DevArtifactKind? {
        let fm = FileManager.default
        switch name {
        case "node_modules": return .nodeModules
        case ".venv", "venv": return fm.fileExists(atPath: path + "/pyvenv.cfg") ? .pythonVenv : nil
        case ".build": return fm.fileExists(atPath: parent + "/Package.swift") ? .swiftBuild : nil
        case "target": return fm.fileExists(atPath: parent + "/Cargo.toml") ? .rustTarget : nil
        case "Pods": return fm.fileExists(atPath: parent + "/Podfile") ? .pods : nil
        case ".next": return fm.fileExists(atPath: parent + "/package.json") ? .nextBuild : nil
        case ".gradle":
            return parent != home && (fm.fileExists(atPath: parent + "/settings.gradle")
                || fm.fileExists(atPath: parent + "/settings.gradle.kts")
                || fm.fileExists(atPath: parent + "/build.gradle")) ? .gradle : nil
        default: return nil
        }
    }
}

enum DiskSize {
    /// Allocated size of a file or directory tree, for paths outside the scanned root.
    static func of(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let v = try? url.resourceValues(forKeys: keys) else { return 0 }
        if v.isDirectory != true { return Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0) }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            if let r = try? f.resourceValues(forKeys: keys), r.isDirectory != true {
                total += Int64(r.totalFileAllocatedSize ?? r.fileAllocatedSize ?? 0)
            }
        }
        return total
    }
}
