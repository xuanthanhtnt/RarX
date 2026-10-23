import Foundation
import UniformTypeIdentifiers

/// Một nút trong cây thư mục của tệp nén.
final class ArchiveNode: Identifiable, Hashable {
    /// Đường dẫn đầy đủ trong tệp nén ("" là gốc).
    let id: String
    let name: String
    private(set) var isDirectory: Bool
    /// Thư mục không có mục riêng trong tệp nén (chỉ suy ra từ đường dẫn con).
    private(set) var isImplicit: Bool
    private(set) var size: Int64 = 0
    /// -1 nếu không rõ (ví dụ trong khối nén solid).
    private(set) var packedSize: Int64 = -1
    private(set) var modified: Date?
    private(set) var crc: String = ""
    private(set) var encrypted = false
    private(set) var method: String = ""
    private(set) var attributes: String = ""
    private(set) var isSymlink = false
    private(set) var fileCount = 0
    private(set) var folderCount = 0

    weak var parent: ArchiveNode?
    private(set) var children: [ArchiveNode] = []
    /// Thư mục con (cho thanh bên); nil nếu không có — để OutlineGroup biết đây là lá.
    private(set) var childFolders: [ArchiveNode]?

    init(id: String, name: String, isDirectory: Bool, isImplicit: Bool) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.isImplicit = isImplicit
    }

    static func == (lhs: ArchiveNode, rhs: ArchiveNode) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    // MARK: Thuộc tính hiển thị / sắp xếp

    var fileExtension: String { (name as NSString).pathExtension.lowercased() }

    var modifiedSortKey: Date { modified ?? .distantPast }

    /// Tỉ lệ nén (kích thước sau nén / gốc); 2 nếu không rõ để xếp cuối.
    var ratio: Double {
        guard packedSize >= 0, size > 0 else { return 2 }
        return Double(packedSize) / Double(size)
    }

    var kindDescription: String { FileKind.describe(self) }

    var parentPath: String { parent?.id ?? "" }

    var isJunk: Bool {
        name == ".DS_Store" || name == "__MACOSX" || name.hasPrefix("._") || name == "Thumbs.db" || name == "desktop.ini"
    }

    /// Mọi nút con cháu (không gồm chính nó).
    func descendants() -> [ArchiveNode] {
        var result: [ArchiveNode] = []
        var stack = children
        while let node = stack.popLast() {
            result.append(node)
            stack.append(contentsOf: node.children)
        }
        return result
    }

    // MARK: Dựng cây

    struct Tree {
        let root: ArchiveNode
        let index: [String: ArchiveNode]
        let all: [ArchiveNode]
    }

    static func buildTree(from entries: [ArchiveEntry]) -> Tree {
        let root = ArchiveNode(id: "", name: "", isDirectory: true, isImplicit: true)
        var index: [String: ArchiveNode] = ["": root]
        var childMap: [String: [ArchiveNode]] = [:]

        func folder(for path: String, name: String, parentPath: String) -> ArchiveNode {
            if let existing = index[path] {
                if !existing.isDirectory { existing.isDirectory = true }
                return existing
            }
            let node = ArchiveNode(id: path, name: name, isDirectory: true, isImplicit: true)
            node.parent = index[parentPath]
            index[path] = node
            childMap[parentPath, default: []].append(node)
            return node
        }

        for entry in entries {
            let components = entry.path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
            guard !components.isEmpty else { continue }
            var parentPath = ""
            for component in components.dropLast() {
                let path = parentPath.isEmpty ? component : parentPath + "/" + component
                _ = folder(for: path, name: component, parentPath: parentPath)
                parentPath = path
            }
            let name = components[components.count - 1]
            let path = parentPath.isEmpty ? name : parentPath + "/" + name
            let node: ArchiveNode
            if let existing = index[path] {
                node = existing
            } else {
                node = ArchiveNode(id: path, name: name, isDirectory: entry.isDirectory, isImplicit: false)
                node.parent = index[parentPath]
                index[path] = node
                childMap[parentPath, default: []].append(node)
            }
            node.isImplicit = false
            if entry.isDirectory { node.isDirectory = true }
            node.size = entry.size
            node.packedSize = entry.packedSize ?? -1
            node.modified = entry.modified
            node.crc = entry.crc ?? ""
            node.encrypted = entry.encrypted
            node.method = entry.method ?? ""
            node.attributes = entry.attributes ?? ""
            node.isSymlink = entry.isSymlink
        }

        for (path, kids) in childMap {
            index[path]?.children = kids
        }
        root.aggregate()
        return Tree(root: root, index: index, all: Array(index.values).filter { $0 !== root })
    }

    /// Tính tổng dung lượng/số tệp cho thư mục, sắp xếp danh sách thư mục con.
    private func aggregate() {
        guard isDirectory else {
            fileCount = 1
            return
        }
        var totalSize: Int64 = 0
        var totalPacked: Int64 = 0
        var packedKnown = false
        var files = 0
        var folders = 0
        var latest = modified
        for child in children {
            child.aggregate()
            totalSize += child.size
            if child.packedSize >= 0 {
                totalPacked += child.packedSize
                packedKnown = true
            }
            files += child.fileCount
            folders += child.folderCount + (child.isDirectory ? 1 : 0)
            if isImplicit, let date = child.modified {
                if let current = latest {
                    if date > current { latest = date }
                } else {
                    latest = date
                }
            }
            if child.encrypted { encrypted = true }
        }
        size = totalSize
        packedSize = packedKnown ? totalPacked : -1
        fileCount = files
        folderCount = folders
        if isImplicit { modified = latest }
        let folderKids = children
            .filter(\.isDirectory)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        childFolders = folderKids.isEmpty ? nil : folderKids
    }
}

/// Mô tả loại tệp và biểu tượng (có bộ nhớ đệm theo phần mở rộng).
enum FileKind {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func describe(_ node: ArchiveNode) -> String {
        if node.isDirectory { return "Thư mục" }
        if node.isSymlink { return "Liên kết" }
        let ext = node.fileExtension
        if ext.isEmpty { return "Tệp" }
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[ext] { return cached }
        let description = UTType(filenameExtension: ext)?.localizedDescription ?? "Tệp \(ext.uppercased())"
        cache[ext] = description
        return description
    }
}
