import Foundation

/// Thư mục tạm của RarX (xem nhanh, mở tệp trong tệp nén, chuyển đổi định dạng…).
enum TempSpace {
    static let root: URL = {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("RarX-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func makeDirectory(_ label: String = "work") throws -> URL {
        let url = root.appendingPathComponent("\(label)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func cleanAll() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Dọn thư mục tạm còn sót của các lần chạy trước.
    static func purgeStale() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        for item in items where item.lastPathComponent.hasPrefix("RarX-") && item != root {
            let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date < cutoff { try? FileManager.default.removeItem(at: item) }
        }
    }
}

enum FileOps {
    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Có tồn tại (kể cả liên kết tượng trưng bị hỏng) hay không.
    static func existsNoFollow(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// "Báo cáo.docx" → "Báo cáo 2.docx" (giống Finder) nếu tên đã có.
    static func uniqueURL(for url: URL) -> URL {
        guard exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        var stem = name
        var ext = ""
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst"] where lower.hasSuffix(compound) {
            stem = String(name.dropLast(compound.count))
            ext = String(name.suffix(compound.count))
        }
        if ext.isEmpty {
            let nsName = name as NSString
            if !nsName.pathExtension.isEmpty, !isDirectory(url) {
                stem = nsName.deletingPathExtension
                ext = "." + nsName.pathExtension
            }
        }
        var counter = 2
        while true {
            let candidate = folder.appendingPathComponent("\(stem) \(counter)\(ext)")
            if !exists(candidate) { return candidate }
            counter += 1
        }
    }

    /// Thư mục cha chung của nhiều tệp (nil nếu nằm ở nhiều nơi khác nhau).
    static func commonParent(_ urls: [URL]) -> URL? {
        guard let first = urls.first?.deletingLastPathComponent().standardizedFileURL else { return nil }
        for url in urls.dropFirst() where url.deletingLastPathComponent().standardizedFileURL.path != first.path {
            return nil
        }
        return first
    }

    /// Tổng dung lượng các tệp/thư mục.
    static func totalSize(of urls: [URL]) -> (bytes: Int64, files: Int) {
        var bytes: Int64 = 0
        var files = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        for url in urls {
            if isDirectory(url) {
                let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
                while let item = enumerator?.nextObject() as? URL {
                    let values = try? item.resourceValues(forKeys: Set(keys))
                    if values?.isDirectory == true { continue }
                    bytes += Int64(values?.fileSize ?? 0)
                    files += 1
                }
            } else {
                let values = try? url.resourceValues(forKeys: Set(keys))
                bytes += Int64(values?.fileSize ?? 0)
                files += 1
            }
        }
        return (bytes, files)
    }

    /// Chuyển vào Thùng rác (an toàn hơn xoá hẳn).
    static func trash(_ urls: [URL]) throws {
        for url in urls where exists(url) {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// Di chuyển `source` vào `destination`, gộp thư mục và xử lý trùng tên theo `mode`.
    static func mergeMove(from source: URL, to destination: URL, mode: OverwriteMode) throws {
        let fm = FileManager.default
        if !existsNoFollow(destination) {
            try fm.moveItem(at: source, to: destination)
            return
        }
        if isDirectory(source) && isDirectory(destination) {
            let children = try fm.contentsOfDirectory(atPath: source.path)
            for child in children {
                try mergeMove(from: source.appendingPathComponent(child),
                              to: destination.appendingPathComponent(child),
                              mode: mode)
            }
            try? fm.removeItem(at: source)
            return
        }
        switch mode {
        case .overwrite, .ask:
            try fm.removeItem(at: destination)
            try fm.moveItem(at: source, to: destination)
        case .skip:
            try? fm.removeItem(at: source)
        case .renameNew:
            try fm.moveItem(at: source, to: uniqueURL(for: destination))
        case .renameExisting:
            try fm.moveItem(at: destination, to: uniqueURL(for: destination))
            try fm.moveItem(at: source, to: destination)
        }
    }

    /// Thư mục Unicode chuẩn hoá để so sánh tên (macOS lưu tên dạng NFD).
    static func normalized(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping
    }
}
