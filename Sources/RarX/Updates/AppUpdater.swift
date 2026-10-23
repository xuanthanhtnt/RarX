import AppKit

/// Thông tin một bản phát hành trên GitHub.
struct ReleaseInfo: Equatable, Sendable {
    let version: SemanticVersion
    let tag: String
    let title: String
    let notes: String
    let pageURL: URL
    let publishedAt: Date?
    let assetName: String?
    let assetURL: URL?
    let assetSize: Int64
}

/// Phản hồi của GitHub cho `releases/latest` (chỉ các trường cần dùng).
private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browserDownloadUrl: URL
        let size: Int64
    }

    let tagName: String
    let name: String?
    let body: String?
    let htmlUrl: URL
    let publishedAt: Date?
    let assets: [Asset]
}

/// Kiểm tra và cài bản RarX mới từ GitHub Releases.
///
/// Luồng: hỏi `releases/latest` → so với phiên bản đang chạy → tải gói .zip (hoặc .dmg) đính kèm →
/// giải nén → xác nhận đúng RarX và mới hơn → một script nhỏ chờ RarX thoát, thay RarX.app rồi mở lại.
@MainActor
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double)   // 0…1; âm = chưa biết tổng dung lượng
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    /// Bản phát hành mới hơn bản đang chạy (nil nếu đã mới nhất hoặc chưa kiểm tra).
    @Published private(set) var release: ReleaseInfo?
    @Published private(set) var lastChecked: Date?

    var isBusy: Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    var currentVersion: SemanticVersion? { SemanticVersion(AppInfo.version) }

    // MARK: - Kiểm tra

    /// Kiểm tra khi mở ứng dụng: tối đa mỗi 12 giờ, và chỉ báo khi có bản mới.
    func autoCheckOnLaunch() async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.autoCheckUpdates) else { return }
        if let last = defaults.object(forKey: Prefs.lastUpdateCheck) as? Date,
           Date().timeIntervalSince(last) < 12 * 3600 { return }
        await check(silent: true)
        guard case .available = phase, let release else { return }
        if defaults.string(forKey: Prefs.skippedVersion) == release.tag { return }
        await announce(release)
    }

    func check(silent: Bool = false) async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let info = try await Self.fetchLatest()
            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: Prefs.lastUpdateCheck)
            if let current = currentVersion, info.version > current {
                release = info
                phase = .available
            } else {
                release = nil
                phase = .upToDate
            }
        } catch {
            release = nil
            phase = silent ? .idle : .failed(error.localizedDescription)
        }
    }

    func skipCurrentRelease() {
        guard let release else { return }
        UserDefaults.standard.set(release.tag, forKey: Prefs.skippedVersion)
        self.release = nil
        phase = .idle
    }

    private func announce(_ release: ReleaseInfo) async {
        let alert = NSAlert()
        alert.messageText = "Có phiên bản RarX mới: \(release.version)"
        alert.informativeText = "Bạn đang dùng \(AppInfo.version). Mở cửa sổ Giới thiệu để xem thay đổi và cập nhật chỉ bằng một cú nhấp."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Xem và cập nhật")
        alert.addButton(withTitle: "Để sau")
        alert.addButton(withTitle: "Bỏ qua bản này")
        switch await Prompts.present(alert, on: nil) {
        case .alertFirstButtonReturn: WindowManager.shared.showAbout()
        case .alertThirdButtonReturn: skipCurrentRelease()
        default: break
        }
    }

    nonisolated private static func fetchLatest() async throws -> ReleaseInfo {
        var request = URLRequest(url: AppInfo.latestReleaseAPI, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            throw UpdateError.network(error.localizedDescription)
        }
        guard let http = result.1 as? HTTPURLResponse else { throw UpdateError.badResponse }
        switch http.statusCode {
        case 200: break
        case 404: throw UpdateError.noRelease
        case 403, 429: throw UpdateError.rateLimited
        default: throw UpdateError.http(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        guard let release = try? decoder.decode(GitHubRelease.self, from: result.0),
              let version = SemanticVersion(release.tagName) else { throw UpdateError.badResponse }

        // Ưu tiên .zip (nhanh, không cần gắn đĩa), sau đó .dmg.
        func asset(withSuffix suffix: String) -> GitHubRelease.Asset? {
            release.assets.first { $0.name.lowercased().hasSuffix(suffix) }
        }
        let package = asset(withSuffix: ".zip") ?? asset(withSuffix: ".dmg")
        return ReleaseInfo(
            version: version,
            tag: release.tagName,
            title: release.name ?? release.tagName,
            notes: (release.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            pageURL: release.htmlUrl,
            publishedAt: release.publishedAt,
            assetName: package?.name,
            assetURL: package?.browserDownloadUrl,
            assetSize: package?.size ?? 0
        )
    }

    // MARK: - Cập nhật

    fileprivate func setProgress(_ fraction: Double) {
        if case .downloading = phase { phase = .downloading(fraction) }
    }

    func installUpdate() async {
        guard case .available = phase, let release else { return }
        guard let assetURL = release.assetURL, let assetName = release.assetName else {
            phase = .failed(UpdateError.noPackage.localizedDescription)
            return
        }
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            // Đang chạy thử từ Xcode / swift run: không có gì để thay.
            NSWorkspace.shared.open(release.pageURL)
            return
        }

        if JobCenter.shared.hasRunningJobs {
            let alert = NSAlert()
            alert.messageText = "Đang có tác vụ chạy"
            alert.informativeText = "Cập nhật sẽ đóng RarX và huỷ các tác vụ nén/giải nén đang dở. Bạn vẫn muốn cập nhật?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Cập nhật")
            alert.addButton(withTitle: "Để sau")
            guard await Prompts.present(alert, on: NSApp.keyWindow) == .alertFirstButtonReturn else { return }
        }

        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appendingPathComponent("RarX-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
            phase = .downloading(0)
            let archive = work.appendingPathComponent(assetName)
            var request = URLRequest(url: assetURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
            request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
            let downloader = FileDownloader(destination: archive) { fraction in
                Task { @MainActor in AppUpdater.shared.setProgress(fraction) }
            }
            _ = try await downloader.download(request)

            phase = .installing
            let newApp = try await Self.extractApp(from: archive, into: work)
            try Self.validate(newApp)

            let parent = bundleURL.deletingLastPathComponent()
            guard fileManager.isWritableFile(atPath: parent.path) else {
                NSWorkspace.shared.activateFileViewerSelecting([newApp])
                phase = .failed("\(UpdateError.notWritable(parent.path).localizedDescription) Bản mới đã được mở trong Finder — hãy kéo RarX.app vào thư mục Ứng dụng.")
                return
            }
            try Self.launchReplacer(newApp: newApp, target: bundleURL, work: work)
            // Thoát ngay, không hỏi lại về tác vụ đang chạy (đã xác nhận ở trên).
            AppDelegate.isRelaunchingForUpdate = true
            JobCenter.shared.cancelAll()
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
            try? fileManager.removeItem(at: work)
        }
    }

    // MARK: - Giải nén & thay thế

    nonisolated private static func firstApp(in directory: URL, depth: Int = 2) -> URL? {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        if let direct = items.first(where: { $0.pathExtension == "app" && $0.lastPathComponent == "\(AppInfo.name).app" })
            ?? items.first(where: { $0.pathExtension == "app" }) {
            return direct
        }
        guard depth > 1 else { return nil }
        for item in items {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDirectory), isDirectory.boolValue,
               let found = firstApp(in: item, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    nonisolated private static func extractApp(from archive: URL, into work: URL) async throws -> URL {
        let fileManager = FileManager.default
        let output = work.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
        let hdiutil = URL(fileURLWithPath: "/usr/bin/hdiutil")

        if archive.pathExtension.lowercased() == "dmg" {
            let mount = work.appendingPathComponent("mount", isDirectory: true)
            try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
            let attach = try await ProcessRunner.run(Command(hdiutil, [
                "attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mount.path, archive.path,
            ]))
            guard attach.exitCode == 0 else { throw UpdateError.extractFailed(attach.stderrText) }

            let outcome: Result<URL, Error>
            if let source = firstApp(in: mount, depth: 1) {
                let destination = output.appendingPathComponent(source.lastPathComponent)
                let copy = try? await ProcessRunner.run(Command(ditto, [source.path, destination.path]))
                if copy?.exitCode == 0 {
                    outcome = .success(destination)
                } else {
                    outcome = .failure(UpdateError.extractFailed(copy?.stderrText ?? "ditto"))
                }
            } else {
                outcome = .failure(UpdateError.invalidPackage("không thấy \(AppInfo.name).app trong tệp .dmg"))
            }
            _ = try? await ProcessRunner.run(Command(hdiutil, ["detach", "-quiet", "-force", mount.path]))
            return try outcome.get()
        }

        let unzip = try await ProcessRunner.run(Command(ditto, ["-x", "-k", archive.path, output.path]))
        guard unzip.exitCode == 0 else { throw UpdateError.extractFailed(unzip.stderrText) }
        guard let app = firstApp(in: output) else {
            throw UpdateError.invalidPackage("không thấy \(AppInfo.name).app trong tệp .zip")
        }
        return app
    }

    nonisolated private static func validate(_ app: URL) throws {
        guard let bundle = Bundle(url: app), let identifier = bundle.bundleIdentifier else {
            throw UpdateError.invalidPackage("thiếu Info.plist")
        }
        guard identifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.invalidPackage("mã định danh “\(identifier)” khác với RarX")
        }
        let executable = app.appendingPathComponent("Contents/MacOS/\(AppInfo.name)")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateError.invalidPackage("thiếu tệp chạy")
        }
        let text = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? ""
        guard let newVersion = SemanticVersion(text), let current = SemanticVersion(AppInfo.version), newVersion > current else {
            throw UpdateError.invalidPackage("phiên bản \(text) không mới hơn bản đang chạy")
        }
    }

    /// Chạy một script độc lập: chờ RarX thoát, thay RarX.app bằng bản mới, rồi mở lại.
    nonisolated private static func launchReplacer(newApp: URL, target: URL, work: URL) throws {
        let lines = [
            "#!/bin/sh",
            "# RarX: thay ứng dụng cũ bằng bản mới sau khi RarX thoát, rồi mở lại.",
            "PID=\"$1\"; NEW=\"$2\"; TARGET=\"$3\"; WORK=\"$4\"",
            "i=0",
            "while kill -0 \"$PID\" 2>/dev/null; do",
            "    i=$((i + 1))",
            "    if [ \"$i\" -gt 120 ]; then rm -rf \"$WORK\"; exit 0; fi",
            "    sleep 0.5",
            "done",
            "BACKUP=\"$TARGET.rarx-old\"",
            "rm -rf \"$BACKUP\"",
            "if mv \"$TARGET\" \"$BACKUP\"; then",
            "    if /usr/bin/ditto \"$NEW\" \"$TARGET\"; then",
            "        /usr/bin/xattr -cr \"$TARGET\" 2>/dev/null",
            "        rm -rf \"$BACKUP\"",
            "    else",
            "        rm -rf \"$TARGET\"",
            "        mv \"$BACKUP\" \"$TARGET\"",
            "    fi",
            "fi",
            "LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
            "[ -x \"$LSREGISTER\" ] && \"$LSREGISTER\" -f \"$TARGET\" >/dev/null 2>&1",
            "/usr/bin/open \"$TARGET\"",
            "rm -rf \"$WORK\"",
            "",
        ]
        let script = work.appendingPathComponent("apply-update.sh")
        try lines.joined(separator: "\n").write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            newApp.path,
            target.path,
            work.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }
}
