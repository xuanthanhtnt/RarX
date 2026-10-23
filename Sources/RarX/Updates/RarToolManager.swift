import AppKit

/// Nơi RarX cất công cụ RAR do chính nó tải về (không cần quyền quản trị, giữ nguyên khi cập nhật RarX).
enum RarPaths {
    static var toolsDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("RarX", isDirectory: true).appendingPathComponent("Tools", isDirectory: true)
    }

    /// Thư mục chứa gói “RAR for macOS” đã giải nén (rar, default.sfx, rarfiles.lst…).
    static var managedDirectory: URL { toolsDirectory.appendingPathComponent("rar", isDirectory: true) }
    static var managedExecutable: URL { managedDirectory.appendingPathComponent("rar") }
    /// Bản sao khoá bản quyền người dùng đã nhập, để không mất khi cập nhật công cụ.
    static var licenseBackup: URL { toolsDirectory.appendingPathComponent("rarreg.key") }
}

enum RarToolError: LocalizedError {
    case network(String)
    case http(Int)
    case notListed
    case extractFailed(String)
    case invalidPackage
    case notRunnable

    var errorDescription: String? {
        switch self {
        case .network(let detail): return "Không kết nối được rarlab.com: \(detail)"
        case .http(let code): return "rarlab.com trả về lỗi \(code)."
        case .notListed: return "Không tìm thấy bản RAR dành cho máy Mac này trên trang tải của RARLAB."
        case .extractFailed(let detail): return "Không giải nén được gói RAR: \(detail)"
        case .invalidPackage: return "Gói RAR tải về không có tệp “rar”."
        case .notRunnable: return "Công cụ RAR tải về không chạy được trên máy này."
        }
    }
}

/// Tự cài và cập nhật công cụ dòng lệnh `rar` của RARLAB.
///
/// RarX không đóng gói sẵn `rar` (bản quyền thuộc RARLAB). Thay vào đó, lần mở đầu tiên RarX tải gói
/// “RAR for macOS” chính thức từ rarlab.com về `~/Library/Application Support/RarX/Tools/rar`.
/// Khi RARLAB phát hành bản mới, Cài đặt ▸ Công cụ hiện nút **Cập nhật**.
@MainActor
final class RarToolManager: ObservableObject {
    static let shared = RarToolManager()

    /// Gói tải về trên rarlab.com. `code` = số phiên bản nhân 100 (723 ⇒ 7.23).
    struct Remote: Equatable, Sendable {
        let code: Int
        let fileName: String
        let url: URL
        var versionText: String { RarToolManager.text(for: code) }
    }

    enum Phase: Equatable {
        case idle
        case checking
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Phiên bản của công cụ `rar` đang được dùng (nil nếu chưa có).
    @Published private(set) var installedCode: Int?
    /// Bản mới nhất RARLAB đang phát hành cho máy này.
    @Published private(set) var remote: Remote?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var notice: String?

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var updateAvailable: Bool {
        guard let remote, let installedCode else { return false }
        return remote.code > installedCode
    }

    var installedText: String? { installedCode.map { "RAR " + Self.text(for: $0) } }

    /// 723 → "7.23"
    nonisolated static func text(for code: Int) -> String {
        String(format: "%d.%02d", code / 100, code % 100)
    }

    // MARK: - Khi mở ứng dụng

    func runLaunchTasks() async {
        await refreshInstalledVersion()
        let defaults = UserDefaults.standard
        if ToolLocator.shared.rar == nil {
            if defaults.bool(forKey: Prefs.autoInstallRar) { await installOrUpdate() }
            return
        }
        guard defaults.bool(forKey: Prefs.autoCheckUpdates) else { return }
        if let last = defaults.object(forKey: Prefs.lastRarCheck) as? Date, Date().timeIntervalSince(last) < 12 * 3600 {
            return
        }
        await checkForUpdate(silent: true)
    }

    // MARK: - Phiên bản

    func refreshInstalledVersion() async {
        guard let url = ToolLocator.shared.rar else {
            installedCode = nil
            return
        }
        installedCode = await Self.queryVersion(of: url)
    }

    /// Chạy `rar` không tham số và đọc dòng “RAR 7.23 …” ở đầu.
    nonisolated static func queryVersion(of executable: URL) async -> Int? {
        guard let result = try? await ProcessRunner.run(Command(executable, [])) else { return nil }
        let text = result.stdoutText + "\n" + result.stderrText
        guard let regex = try? NSRegularExpression(pattern: #"RAR\s+(\d+)\.(\d+)"#) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              let major = Int(nsText.substring(with: match.range(at: 1))),
              let minor = Int(nsText.substring(with: match.range(at: 2))) else { return nil }
        return major * 100 + minor
    }

    // MARK: - Kiểm tra bản mới

    func checkForUpdate(silent: Bool = false) async {
        guard !isBusy else { return }
        phase = .checking
        notice = nil
        do {
            remote = try await Self.fetchRemote()
            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: Prefs.lastRarCheck)
            phase = .idle
        } catch {
            phase = silent ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Đọc trang tải của RARLAB, lấy bản phát hành (không phải beta) mới nhất cho kiến trúc của máy.
    nonisolated private static func fetchRemote() async throws -> Remote {
        var request = URLRequest(url: URL(string: "https://www.rarlab.com/download.htm")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw RarToolError.network(error.localizedDescription)
        }
        if let http = result.1 as? HTTPURLResponse, http.statusCode != 200 { throw RarToolError.http(http.statusCode) }
        guard let html = String(data: result.0, encoding: .utf8) ?? String(data: result.0, encoding: .isoLatin1) else {
            throw RarToolError.notListed
        }

        #if arch(arm64)
        let wanted: Set<String> = ["arm", "arm64"]
        #else
        let wanted: Set<String> = ["x64"]
        #endif

        // rarmacos-arm-723.tar.gz · rarmacos-x64-723.tar.gz · (beta) rarmacos-arm64-730b1.tar.gz
        let pattern = #"rarmacos-(arm64|arm|x64)-(\d+)(b\d+)?\.tar\.gz"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { throw RarToolError.notListed }
        let nsHTML = html as NSString
        var best: Remote?
        for match in regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length)) {
            guard wanted.contains(nsHTML.substring(with: match.range(at: 1))) else { continue }
            if match.range(at: 3).location != NSNotFound { continue } // bỏ bản beta
            guard let code = Int(nsHTML.substring(with: match.range(at: 2))) else { continue }
            let fileName = nsHTML.substring(with: match.range(at: 0))
            guard let url = URL(string: "https://www.rarlab.com/rar/\(fileName)") else { continue }
            if best == nil || code > (best?.code ?? 0) {
                best = Remote(code: code, fileName: fileName, url: url)
            }
        }
        guard let best else { throw RarToolError.notListed }
        return best
    }

    // MARK: - Cài / cập nhật

    fileprivate func setProgress(_ fraction: Double) {
        if case .downloading = phase { phase = .downloading(fraction) }
    }

    /// Tải gói RAR mới nhất từ rarlab.com và cài vào thư mục riêng của RarX (thay bản cũ nếu có).
    func installOrUpdate() async {
        guard !isBusy else { return }
        phase = .checking
        notice = nil
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("RarX-rar-\(UUID().uuidString)", isDirectory: true)
        do {
            let latest = try await Self.fetchRemote()
            remote = latest
            lastChecked = Date()
            UserDefaults.standard.set(Date(), forKey: Prefs.lastRarCheck)

            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            phase = .downloading(0)
            let archive = work.appendingPathComponent(latest.fileName)
            var request = URLRequest(url: latest.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            let downloader = FileDownloader(destination: archive) { fraction in
                Task { @MainActor in RarToolManager.shared.setProgress(fraction) }
            }
            _ = try await downloader.download(request)

            phase = .installing
            try await Self.installFiles(from: archive, work: work)
            try? fileManager.removeItem(at: work)

            // Người dùng đã chủ động cài bản của RarX: bỏ đường dẫn tuỳ chọn cũ để bản mới được dùng.
            UserDefaults.standard.removeObject(forKey: ToolLocator.rarPathKey)
            ToolLocator.shared.refresh()
            await refreshInstalledVersion()
            NotificationCenter.default.post(name: .toolsChanged, object: nil)
            notice = "Đã cài RAR \(latest.versionText)."
            phase = .idle
        } catch {
            try? fileManager.removeItem(at: work)
            phase = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    nonisolated private static func locateExecutable(in directory: URL, depth: Int = 3) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        if let direct = items.first(where: { $0.lastPathComponent == "rar" && !isDirectory($0) }) { return direct }
        guard depth > 1 else { return nil }
        for item in items where isDirectory(item) {
            if let found = locateExecutable(in: item, depth: depth - 1) { return found }
        }
        return nil
    }

    nonisolated private static func installFiles(from archive: URL, work: URL) async throws {
        let fileManager = FileManager.default
        let extract = work.appendingPathComponent("extract", isDirectory: true)
        try fileManager.createDirectory(at: extract, withIntermediateDirectories: true)

        let tar = try await ProcessRunner.run(Command(URL(fileURLWithPath: "/usr/bin/tar"),
                                                      ["-xzf", archive.path, "-C", extract.path]))
        guard tar.exitCode == 0 else { throw RarToolError.extractFailed(tar.stderrText) }

        // Gói của RARLAB giải nén ra thư mục “rar/” chứa tệp chạy “rar”; tìm linh hoạt phòng khi cấu trúc đổi.
        guard let newExecutable = locateExecutable(in: extract) else { throw RarToolError.invalidPackage }
        let newDirectory = newExecutable.deletingLastPathComponent()
        try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: newExecutable.path)
        _ = try? await ProcessRunner.run(Command(URL(fileURLWithPath: "/usr/bin/xattr"), ["-cr", newDirectory.path]))

        // Thử chạy; nếu macOS từ chối (thiếu chữ ký) thì ký ad-hoc rồi thử lại.
        var version = await queryVersion(of: newExecutable)
        if version == nil {
            _ = try? await ProcessRunner.run(Command(URL(fileURLWithPath: "/usr/bin/codesign"),
                                                     ["--force", "--sign", "-", newExecutable.path]))
            version = await queryVersion(of: newExecutable)
        }
        guard version != nil else { throw RarToolError.notRunnable }

        // Giữ khoá bản quyền người dùng đã nhập trước đó.
        if fileManager.fileExists(atPath: RarPaths.licenseBackup.path) {
            let target = newDirectory.appendingPathComponent("rarreg.key")
            try? fileManager.removeItem(at: target)
            try? fileManager.copyItem(at: RarPaths.licenseBackup, to: target)
        }

        try fileManager.createDirectory(at: RarPaths.toolsDirectory, withIntermediateDirectories: true)
        let old = RarPaths.toolsDirectory.appendingPathComponent("rar.old-\(UUID().uuidString)", isDirectory: true)
        let hadOld = fileManager.fileExists(atPath: RarPaths.managedDirectory.path)
        if hadOld { try fileManager.moveItem(at: RarPaths.managedDirectory, to: old) }
        do {
            try fileManager.moveItem(at: newDirectory, to: RarPaths.managedDirectory)
        } catch {
            if hadOld { try? fileManager.moveItem(at: old, to: RarPaths.managedDirectory) }
            throw error
        }
        if hadOld { try? fileManager.removeItem(at: old) }
    }

    // MARK: - Khoá bản quyền

    /// Chép tệp `rarreg.key` (mua từ RARLAB) vào cạnh công cụ `rar` của RarX.
    func importLicenseKey(from url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: RarPaths.toolsDirectory, withIntermediateDirectories: true)
        try? fileManager.removeItem(at: RarPaths.licenseBackup)
        try fileManager.copyItem(at: url, to: RarPaths.licenseBackup)
        if fileManager.fileExists(atPath: RarPaths.managedDirectory.path) {
            let target = RarPaths.managedDirectory.appendingPathComponent("rarreg.key")
            try? fileManager.removeItem(at: target)
            try fileManager.copyItem(at: url, to: target)
        }
        notice = "Đã nhập khoá bản quyền RAR."
    }

    var hasLicenseKey: Bool { FileManager.default.fileExists(atPath: RarPaths.licenseBackup.path) }
}
