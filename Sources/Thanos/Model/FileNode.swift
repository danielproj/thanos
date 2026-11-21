import Foundation

/// One node of the scanned tree. Directories keep their children; files smaller than the scanner's
/// keep threshold are folded into a single "smaller files" aggregate per directory, which keeps a
/// multi-million-file scan in a few hundred MB of memory while every byte is still accounted for.
final class FileNode: Identifiable, @unchecked Sendable {
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isAggregate: Bool
    var size: Int64
    var itemCount: Int
    let modified: Date?
    let category: FileCategory
    var children: [FileNode] = []
    weak var parent: FileNode?

    init(name: String, isDirectory: Bool, isPackage: Bool = false, isAggregate: Bool = false,
         size: Int64 = 0, itemCount: Int = 0, modified: Date? = nil, category: FileCategory = .other) {
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isAggregate = isAggregate
        self.size = size
        self.itemCount = itemCount
        self.modified = modified
        self.category = category
    }

    /// Full filesystem path. The root stores its full path as `name`.
    var path: String {
        guard let parent else { return name }
        let p = parent.path
        return p == "/" ? "/" + name : p + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path) }

    var displayName: String {
        if parent == nil { return name == "/" ? "Macintosh HD" : (name as NSString).lastPathComponent }
        return name
    }

    var ancestors: [FileNode] {
        var out: [FileNode] = []
        var n: FileNode? = self
        while let cur = n { out.append(cur); n = cur.parent }
        return out.reversed()
    }

    var root: FileNode { var n = self; while let p = n.parent { n = p }; return n }

    /// Finds a node by absolute path, walking down from this node.
    func descendant(atPath target: String) -> FileNode? {
        let base = path
        if target == base { return self }
        let prefix = base == "/" ? "/" : base + "/"
        guard target.hasPrefix(prefix) else { return nil }
        var node: FileNode = self
        for comp in target.dropFirst(prefix.count).split(separator: "/") {
            guard let next = node.children.first(where: { !$0.isAggregate && $0.name == comp }) else { return nil }
            node = next
        }
        return node
    }

    /// Removes this node from the tree and subtracts its size from every ancestor.
    func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var p: FileNode? = parent
        while let n = p {
            n.size -= size
            n.itemCount -= itemCount
            p = n.parent
        }
        self.parent = nil
    }

    func isAttached(to root: FileNode) -> Bool { self.root === root }
}
