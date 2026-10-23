import AppKit

/// Tuỳ chọn giải nén do người dùng chọn.
struct ExtractConfig {
    var baseFolder: URL
    var folderMode: ExtractFolderMode
    var overwrite: OverwriteMode
    var password: String = ""
    var openFolderAfter: Bool
    var trashArchiveAfter: Bool
    /// Chỉ giải nén các mục đang chọn (khi mở từ cửa sổ duyệt).
    var selectionOnly = false

    static func defaults(for archive: URL) -> ExtractConfig {
        ExtractConfig(
            baseFolder: Prefs.defaultExtractBase(for: archive),
            folderMode: Prefs.folderMode,
            overwrite: Prefs.overwrite,
            openFolderAfter: Prefs.bool(Prefs.openFolderAfterExtract),
            trashArchiveAfter: Prefs.bool(Prefs.trashArchiveAfterExtract)
        )
    }
}

/// Phạm vi giải nén một phần (từ cửa sổ duyệt).
struct ExtractScope {
    /// Đường dẫn đầy đủ các mục được chọn.
    var items: [String]
    /// Thư mục đang xem (bỏ tiền tố này khi đặt tệp ra ngoài).
    var stripPrefix: String
    /// Tên các mục cấp trên cùng sau khi bỏ tiền tố.
    var topNames: [String]
}

/// Tuỳ chọn sau khi nén.
struct CompressExtras {
    var separateArchives = false
    var testAfter = false
    var trashSources = false
}

/// Các luồng công việc dùng chung: cửa sổ duyệt, màn hình chào và menu Dịch vụ của Finder.
@MainActor
enum Workflows {
    // MARK: - Giải nén

    /// Giải nén một tệp nén (toàn bộ hoặc một phần) thành một tác vụ nền.
    @discardableResult
    static func extract(
        archive: URL,
        format: ArchiveFormat,
        config: ExtractConfig,
        scope: ExtractScope? = nil,
        knownPassword: String? = nil,
        window: NSWindow?,
        onPasswordAccepted: ((String) -> Void)? = nil,
        onFinish: ((URL?) -> Void)? = nil
    ) -> Job {
        JobCenter.shared.start(
            title: "Giải nén",
            detail: archive.lastPathComponent,
            symbol: "arrow.down.doc",
            operation: { job in
                var password = knownPassword ?? ""
                if !config.password.isEmpty { password = config.password }
                let skipJunk = Prefs.bool(Prefs.excludeJunk)

                // 1. Tìm các mục cấp trên cùng (để quyết định có tạo thư mục riêng không / kiểm tra trùng tên).
                var topNames = scope?.topNames
                let mayBeEncrypted = password.isEmpty && format.supportsPassword
                if topNames == nil && (config.folderMode == .smart || config.overwrite == .ask || mayBeEncrypted) {
                    job.detail = "Đang đọc \(archive.lastPathComponent)…"
                    let listing = try await listWithPassword(archive: archive, format: format, password: &password, window: window)
                    var names: [String] = []
                    var seen = Set<String>()
                    for entry in listing.entries {
                        guard let first = entry.path.split(separator: "/").first.map(String.init), !first.isEmpty else { continue }
                        if skipJunk && first == "__MACOSX" { continue }
                        if seen.insert(first).inserted { names.append(first) }
                    }
                    topNames = names
                    // Hỏi mật khẩu trước khi giải nén để không tạo ra tệp hỏng.
                    if password.isEmpty && listing.entries.contains(where: { $0.encrypted }) {
                        guard let entered = await Prompts.password(for: archive.lastPathComponent, wrongBefore: false, window: window) else {
                            throw ArchiveError.cancelled
                        }
                        password = entered
                    }
                }

                // 2. Thư mục đích.
                let destination = destinationFolder(base: config.baseFolder, archive: archive,
                                                    mode: config.folderMode, topNames: topNames)

                // 3. Xử lý trùng tên.
                var overwrite = config.overwrite
                if overwrite == .ask {
                    let conflicts = (topNames ?? []).filter {
                        FileOps.existsNoFollow(destination.appendingPathComponent($0))
                    }
                    if conflicts.isEmpty {
                        overwrite = .renameNew
                    } else {
                        guard let choice = await Prompts.conflict(names: conflicts, destination: destination, window: window) else {
                            throw ArchiveError.cancelled
                        }
                        overwrite = choice
                    }
                }

                // 4. Giải nén (hỏi lại mật khẩu nếu cần).
                job.detail = "\(archive.lastPathComponent) → \(destination.lastPathComponent)"
                var wrongBefore = false
                var outcome: ExtractOutcome?
                while outcome == nil {
                    let request = ExtractRequest(
                        archive: archive, format: format,
                        password: password.isEmpty ? nil : password,
                        items: scope?.items, stripPrefix: scope?.stripPrefix ?? "",
                        destination: destination, overwrite: overwrite,
                        skipMacJunk: skipJunk
                    )
                    do {
                        outcome = try await ArchiveEngine.extract(request, progress: job.progressHandler())
                    } catch let error as ArchiveError where error.isPasswordProblem {
                        guard let entered = await Prompts.password(for: archive.lastPathComponent,
                                                                   wrongBefore: wrongBefore || error == .wrongPassword,
                                                                   window: window) else {
                            throw ArchiveError.cancelled
                        }
                        password = entered
                        wrongBefore = true
                        // Lần trước có thể để lại tệp dở dang trong thư mục RarX vừa tạo — ghi đè chúng.
                        if destination != config.baseFolder { overwrite = .overwrite }
                    }
                }
                if !password.isEmpty { onPasswordAccepted?(password) }

                // 5. Sau khi giải nén.
                if config.trashArchiveAfter && scope == nil {
                    try? FileOps.trash(ArchiveFormat.volumeSiblings(of: archive))
                }
                job.resultURL = destination
                if config.openFolderAfter {
                    reveal(destination: destination, topNames: topNames, base: config.baseFolder)
                }
                onFinish?(destination)
                var message = "Đã giải nén vào “\(destination.lastPathComponent)”."
                if let warnings = outcome?.warnings, !warnings.isEmpty {
                    message += " Có cảnh báo: " + warnings.joined(separator: " ")
                }
                return message
            },
            completion: { _, error in
                if let error, !error.isCancellation {
                    Prompts.showError(error, title: "Giải nén “\(archive.lastPathComponent)” không thành công", window: window)
                    onFinish?(nil)
                }
            }
        )
    }

    /// Giải nén nhanh tại chỗ (Finder ▸ Dịch vụ, hoặc nút "Giải nén tại đây").
    static func extractHere(_ archives: [URL], window: NSWindow? = nil) {
        for archive in archives {
            guard let detection = ArchiveFormat.detect(archive) ?? ArchiveFormat.sniff(archive).map({
                ArchiveFormat.Detection(format: $0, isMultiVolume: false, primaryURL: archive)
            }) else { continue }
            var config = ExtractConfig.defaults(for: detection.primaryURL)
            config.baseFolder = detection.primaryURL.deletingLastPathComponent()
            extract(archive: detection.primaryURL, format: detection.format, config: config, window: window)
        }
    }

    /// Giải nén vào thư mục riêng mang tên tệp nén.
    static func extractToOwnFolder(_ archives: [URL], window: NSWindow? = nil) {
        for archive in archives {
            guard let detection = ArchiveFormat.detect(archive) else { continue }
            var config = ExtractConfig.defaults(for: detection.primaryURL)
            config.baseFolder = detection.primaryURL.deletingLastPathComponent()
            config.folderMode = .alwaysFolder
            extract(archive: detection.primaryURL, format: detection.format, config: config, window: window)
        }
    }

    static func destinationFolder(base: URL, archive: URL, mode: ExtractFolderMode, topNames: [String]?) -> URL {
        let named = base.appendingPathComponent(ArchiveFormat.baseName(of: archive), isDirectory: true)
        switch mode {
        case .direct:
            return base
        case .alwaysFolder:
            return FileOps.uniqueURL(for: named)
        case .smart:
            if let topNames, topNames.count == 1 { return base }
            return FileOps.uniqueURL(for: named)
        }
    }

    private static func reveal(destination: URL, topNames: [String]?, base: URL) {
        if destination == base, let names = topNames, !names.isEmpty {
            let urls = names.map { base.appendingPathComponent($0) }.filter { FileOps.existsNoFollow($0) }
            if !urls.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(urls)
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Liệt kê, hỏi mật khẩu khi tệp mã hoá cả tên tệp.
    static func listWithPassword(archive: URL, format: ArchiveFormat, password: inout String,
                                 window: NSWindow?) async throws -> ArchiveListing {
        var wrongBefore = false
        while true {
            do {
                return try await ArchiveEngine.list(archive, format: format, password: password.isEmpty ? nil : password)
            } catch let error as ArchiveError where error.isPasswordProblem {
                guard let entered = await Prompts.password(for: archive.lastPathComponent,
                                                           wrongBefore: wrongBefore || error == .wrongPassword,
                                                           window: window) else {
                    throw ArchiveError.cancelled
                }
                password = entered
                wrongBefore = true
            }
        }
    }

    // MARK: - Nén

    /// Tạo tệp nén thành tác vụ nền.
    @discardableResult
    static func compress(_ request: CreateRequest, extras: CompressExtras, window: NSWindow?,
                         onFinish: ((URL?) -> Void)? = nil) -> Job {
        let title = request.sources.count == 1
            ? request.sources[0].lastPathComponent
            : "\(request.sources.count) mục"
        return JobCenter.shared.start(
            title: "Nén \(request.format.displayName)",
            detail: "\(title) → \(request.output.lastPathComponent)",
            symbol: "archivebox",
            operation: { job in
                var requests: [CreateRequest] = []
                if extras.separateArchives && request.sources.count > 1 {
                    let folder = request.output.deletingLastPathComponent()
                    for source in request.sources {
                        var single = request
                        single.sources = [source]
                        let stem = FileOps.isDirectory(source)
                            ? source.lastPathComponent
                            : (source.lastPathComponent as NSString).deletingPathExtension
                        single.output = FileOps.uniqueURL(for: folder.appendingPathComponent(stem + "." + request.format.fileExtension))
                        requests.append(single)
                    }
                } else {
                    requests = [request]
                }

                var results: [URL] = []
                let share = 1.0 / Double(requests.count)
                for (index, item) in requests.enumerated() {
                    job.detail = "\(item.sources.count == 1 ? item.sources[0].lastPathComponent : title) → \(item.output.lastPathComponent)"
                    let testShare = extras.testAfter ? 0.25 : 0
                    let result = try await ArchiveEngine.create(
                        item,
                        progress: job.progressHandler(scale: share * (1 - testShare), offset: share * Double(index))
                    )
                    if extras.testAfter {
                        job.detail = "Đang kiểm tra \(result.lastPathComponent)…"
                        let outcome = try await ArchiveEngine.test(
                            result, format: item.format, password: item.password.isEmpty ? nil : item.password,
                            progress: job.progressHandler(scale: share * testShare, offset: share * (Double(index) + 1 - testShare))
                        )
                        if !outcome.passed {
                            throw ArchiveError.corrupted("Kiểm tra sau khi nén phát hiện lỗi trong \(result.lastPathComponent).\n" + outcome.report)
                        }
                    }
                    results.append(result)
                }
                if extras.trashSources {
                    try FileOps.trash(request.sources)
                }
                job.resultURL = results.first
                onFinish?(results.first)
                let size = results.reduce(Int64(0)) { $0 + ListParser.fileSize($1) }
                if results.count == 1, let first = results.first {
                    return "Đã tạo “\(first.lastPathComponent)” (\(Format.bytes(size)))."
                }
                return "Đã tạo \(results.count) tệp nén (\(Format.bytes(size)))."
            },
            completion: { _, error in
                if let error, !error.isCancellation {
                    Prompts.showError(error, title: "Không tạo được tệp nén", window: window)
                    onFinish?(nil)
                }
            }
        )
    }

    /// Nén nhanh thành .zip cạnh tệp gốc (Finder ▸ Dịch vụ).
    static func quickZip(_ sources: [URL]) {
        guard !sources.isEmpty else { return }
        let folder = sources[0].deletingLastPathComponent()
        let stem: String
        if sources.count == 1 {
            stem = FileOps.isDirectory(sources[0])
                ? sources[0].lastPathComponent
                : (sources[0].lastPathComponent as NSString).deletingPathExtension
        } else {
            stem = FileOps.commonParent(sources)?.lastPathComponent ?? "Tệp nén"
        }
        let output = FileOps.uniqueURL(for: folder.appendingPathComponent(stem + ".zip"))
        var request = CreateRequest(sources: sources, output: output, format: .zip)
        request.level = Prefs.preferredLevel
        request.excludeJunk = Prefs.bool(Prefs.excludeJunk)
        compress(request, extras: CompressExtras(), window: nil)
    }

    /// Tên mặc định cho tệp nén mới.
    static func suggestedName(for sources: [URL]) -> String {
        guard let first = sources.first else { return "Tệp nén" }
        if sources.count == 1 {
            return FileOps.isDirectory(first)
                ? first.lastPathComponent
                : (first.lastPathComponent as NSString).deletingPathExtension
        }
        let parent = FileOps.commonParent(sources)?.lastPathComponent ?? ""
        return parent.isEmpty || parent == "/" ? "Tệp nén" : parent
    }
}
