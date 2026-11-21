import Foundation
import Testing
@testable import Thanos

@Suite struct FileCategoryTests {
    @Test(arguments: [
        ("photo.HEIC", FileCategory.images), ("movie.mov", .video), ("song.flac", .audio),
        ("Report.pdf", .documents), ("installer.dmg", .archives), ("main.swift", .developer),
        ("prefs.plist", .system), ("README", .other), (".zshrc", .other),
    ])
    func classifiesByExtension(name: String, expected: FileCategory) {
        #expect(FileCategory.classify(fileName: name) == expected)
    }
}

@Suite struct FileNodeTests {
    private func tree() -> (FileNode, FileNode, FileNode) {
        let root = FileNode(name: "/tmp/root", isDirectory: true, size: 300, itemCount: 3)
        let dir = FileNode(name: "a", isDirectory: true, size: 200, itemCount: 2)
        let file = FileNode(name: "b.bin", isDirectory: false, size: 150, itemCount: 1)
        dir.parent = root; root.children = [dir]
        file.parent = dir; dir.children = [file]
        return (root, dir, file)
    }

    @Test func buildsPathsAndFindsDescendants() {
        let (root, _, file) = tree()
        #expect(file.path == "/tmp/root/a/b.bin")
        #expect(root.descendant(atPath: "/tmp/root/a/b.bin") === file)
        #expect(root.descendant(atPath: "/tmp/root/missing") == nil)
        #expect(root.descendant(atPath: "/tmp/rootX/a") == nil)
    }

    @Test func detachSubtractsSizeFromEveryAncestor() {
        let (root, dir, file) = tree()
        file.detach()
        #expect(dir.children.isEmpty)
        #expect(dir.size == 50)
        #expect(root.size == 150)
        #expect(root.itemCount == 2)
        #expect(!file.isAttached(to: root))
    }
}

@Suite struct CleanupEngineTests {
    private func finding(_ paths: [String], size: Int64 = 100) -> Finding {
        Finding(kind: .caches, title: "t", subtitle: "s", reason: "r", paths: paths, size: size, confidence: .safe)
    }

    @Test func laterFindingsLosePathsAlreadyClaimed() {
        let parent = finding(["/x/cache"], size: 1_000)
        let child = finding(["/x/cache/inner"])                 // inside a claimed path
        let wrapper = finding(["/x"])                           // contains a claimed path
        let mixed = finding(["/x/cache", "/y/other"], size: 500)
        let out = CleanupEngine.removingOverlaps([parent, child, wrapper, mixed], claimed: []) { _ in 7 }
        #expect(out.count == 2)
        #expect(out[0].size == 1_000)
        #expect(out[1].paths == ["/y/other"])
        #expect(out[1].size == 7, "a trimmed finding is re-measured")
    }

    @Test func respectsPreviouslyClaimedPaths() {
        let out = CleanupEngine.removingOverlaps([finding(["/a/b"])], claimed: ["/a"]) { _ in 0 }
        #expect(out.isEmpty)
    }
}

@Suite struct TreemapTests {
    @Test func tilesCoverTheRectProportionally() {
        let nodes = [600, 300, 100].map { FileNode(name: "\($0)", isDirectory: false, size: Int64($0)) }
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let tiles = TreemapView.squarify(nodes, in: rect)
        #expect(tiles.count == 3)
        let total = tiles.reduce(0.0) { $0 + $1.1.width * $1.1.height }
        #expect(abs(total - 20_000) < 0.5)
        for (node, r) in tiles {
            #expect(abs(r.width * r.height - 20_000 * Double(node.size) / 1_000) < 0.5)
            #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(r))
        }
    }
}

@Suite struct DiskScannerTests {
    @Test func scansSizesAggregatesSmallFilesAndFindsArtifacts() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("thanos-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let project = root.appendingPathComponent("app")
        let modules = project.appendingPathComponent("node_modules/pkg")
        try fm.createDirectory(at: modules, withIntermediateDirectories: true)
        try Data(count: 2 << 20).write(to: root.appendingPathComponent("big.mov"))
        for i in 0..<3 { try Data(count: 1_000).write(to: root.appendingPathComponent("small\(i).txt")) }
        try Data(count: 1 << 20).write(to: modules.appendingPathComponent("index.js"))
        try Data("{}".utf8).write(to: project.appendingPathComponent("package.json"))

        let result = DiskScanner().scan(rootPath: root.path)
        let tree = result.root

        #expect(result.stats.files == 6)
        #expect(tree.children.contains { $0.name == "big.mov" && $0.category == .video })
        let aggregate = try #require(tree.children.first { $0.isAggregate })
        #expect(aggregate.itemCount == 3)
        #expect(tree.size == tree.children.reduce(0) { $0 + $1.size })
        #expect(result.stats.devArtifacts.map(\.kind) == [.nodeModules])
        #expect(result.stats.categoryTotals[.developer, default: 0] > 0, "files inside node_modules count as developer")
    }

    @Test func filesInsideGitWorkingTreesAreNotDuplicateCandidates() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("thanos-dup-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo/tests/fixtures")
        let worktree = root.appendingPathComponent("worktree/tests/fixtures")
        let loose = root.appendingPathComponent("Downloads")
        for dir in [repo, worktree, loose] { try fm.createDirectory(at: dir, withIntermediateDirectories: true) }
        try fm.createDirectory(at: root.appendingPathComponent("repo/.git"), withIntermediateDirectories: true)
        try Data("gitdir: ../repo/.git/worktrees/w".utf8).write(to: root.appendingPathComponent("worktree/.git"))  // worktrees use a .git FILE
        let blob = Data(repeating: 7, count: 5 << 20)
        try blob.write(to: repo.appendingPathComponent("big.json"))
        try blob.write(to: worktree.appendingPathComponent("big.json"))
        try blob.write(to: loose.appendingPathComponent("big copy.json"))
        try blob.write(to: loose.appendingPathComponent("big.json"))

        let candidates = DiskScanner().scan(rootPath: root.path).stats.duplicateCandidates.map(\.path)
        #expect(candidates.count == 2, "only the two loose copies outside any repo are candidates")
        #expect(candidates.allSatisfy { $0.contains("/Downloads/") })
    }
}

