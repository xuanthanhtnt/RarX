import Foundation

/// Công cụ 7-Zip đã tìm được.
struct SevenZipTool: Sendable, Equatable {
    let url: URL
    /// 7zz (7-Zip chính chủ ≥ 21) hỗ trợ -scc; bản p7zip cũ ("7z", "7za") thì không.
    let isModern: Bool

    /// Tham số chung luôn thêm vào.
    var commonSwitches: [String] { isModern ? ["-sccUTF-8"] : [] }

    var sourceDescription: String {
        let path = url.path
        if path.contains(".app/Contents/") { return "Đóng gói sẵn trong RarX" }
        if path.hasPrefix("/opt/homebrew") || path.hasPrefix("/usr/local") { return "Homebrew / hệ thống" }
        return "Tuỳ chỉnh"
    }
}

/// Tìm các công cụ dòng lệnh mà RarX dùng làm lõi.
final class ToolLocator: @unchecked Sendable {
    static let shared = ToolLocator()

    private let lock = NSLock()
    private var cachedSevenZip: SevenZipTool?
    private var cachedRar: URL?
    private var didScan = false

    static let sevenZipPathKey = "tools.sevenZipPath"
    static let rarPathKey = "tools.rarPath"

    var sevenZip: SevenZipTool? {
        scanIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return cachedSevenZip
    }

    var rar: URL? {
        scanIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return cachedRar
    }

    /// Công cụ zip của hệ thống (dùng để sửa tệp .zip hỏng).
    var systemZip: URL? {
        let url = URL(fileURLWithPath: "/usr/bin/zip")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func requireSevenZip() throws -> SevenZipTool {
        guard let tool = sevenZip else { throw ArchiveError.toolMissing("7-Zip (7zz)") }
        return tool
    }

    func requireRar() throws -> URL {
        guard let tool = rar else { throw ArchiveError.toolMissing("công cụ RAR (rar)") }
        return tool
    }

    func refresh() {
        let seven = Self.findSevenZip()
        let rar = Self.findRar()
        lock.lock()
        cachedSevenZip = seven
        cachedRar = rar
        didScan = true
        lock.unlock()
    }

    private func scanIfNeeded() {
        lock.lock()
        let scanned = didScan
        lock.unlock()
        if !scanned { refresh() }
    }

    // MARK: - Tìm kiếm

    private static func isExecutable(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
            && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: path)
    }

    /// Thư mục gốc của mã nguồn (khi chạy thử từ Xcode hay `swift run`).
    static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Engine
            .deletingLastPathComponent() // RarX
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // gốc dự án
    }

    private static var sourceVendorDirectory: URL {
        sourceRoot.appendingPathComponent("Vendor")
    }

    private static func findSevenZip() -> SevenZipTool? {
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: sevenZipPathKey), !custom.isEmpty {
            candidates.append((custom as NSString).expandingTildeInPath)
        }
        if let env = ProcessInfo.processInfo.environment["RARX_7ZZ"] { candidates.append(env) }
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "7zz") { candidates.append(bundled.path) }
        candidates.append(sourceVendorDirectory.appendingPathComponent("7zz").path)
        candidates += [
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
            "/opt/local/bin/7zz",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7z",
            "/opt/local/bin/7z",
            "/opt/homebrew/bin/7za",
            "/usr/local/bin/7za",
        ]
        for path in candidates where isExecutable(path) {
            let name = (path as NSString).lastPathComponent
            return SevenZipTool(url: URL(fileURLWithPath: path), isModern: name.hasPrefix("7zz"))
        }
        return nil
    }

    private static func findRar() -> URL? {
        var candidates: [String] = []
        if let custom = UserDefaults.standard.string(forKey: rarPathKey), !custom.isEmpty {
            candidates.append((custom as NSString).expandingTildeInPath)
        }
        // Bản RarX tự tải từ rarlab.com (cập nhật được bằng nút Cập nhật trong Cài đặt ▸ Công cụ).
        candidates.append(RarPaths.managedExecutable.path)
        if let bundled = Bundle.main.url(forAuxiliaryExecutable: "rar") { candidates.append(bundled.path) }
        candidates.append(sourceVendorDirectory.appendingPathComponent("rar").path)
        let home = NSHomeDirectory()
        candidates += [
            "/opt/homebrew/bin/rar",
            "/usr/local/bin/rar",
            "/opt/local/bin/rar",
            "\(home)/bin/rar",
            "\(home)/Applications/rar/rar",
            "/Applications/rar/rar",
            "/usr/local/rar/rar",
        ]
        for path in candidates where isExecutable(path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
