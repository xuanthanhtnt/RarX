import Foundation

/// Lõi xử lý: gọi 7-Zip (7zz) cho hầu hết thao tác, và RAR chính chủ khi tạo/sửa tệp .rar.
enum ArchiveEngine {
    typealias Progress = @Sendable (Double) -> Void

    /// Tệp "rác" do macOS tạo ra, bỏ qua khi nén nếu người dùng chọn.
    static let junkPatterns7z = ["-xr!.DS_Store", "-xr!__MACOSX", "-xr!._*", "-xr!.Spotlight-V100", "-xr!.fseventsd", "-xr!.Trashes"]
    static let junkPatternsRar = ["-x.DS_Store", "-x._*", "-x__MACOSX", "-x*/__MACOSX", "-x.Spotlight-V100", "-x.fseventsd", "-x.Trashes"]

    // MARK: - Liệt kê

    static func list(_ url: URL, format: ArchiveFormat, password: String?) async throws -> ArchiveListing {
        let tool = try ToolLocator.shared.requireSevenZip()
        let pw = "-p" + (password ?? "")
        let hadPassword = !(password ?? "").isEmpty

        if format.isCompressedTar {
            let first = Command(tool.url, ["x", "-so", "-bsp0", pw] + tool.commonSwitches + [url.path])
            let second = Command(tool.url, ["l", "-slt", "-si", "-ttar"] + tool.commonSwitches)
            let (outer, inner) = try await ProcessRunner.runPipeline(first, second)
            if outer.wasCancelled || inner.wasCancelled { throw ArchiveError.cancelled }
            if outer.exitCode > 1 {
                throw classify(exitCode: outer.exitCode, text: outer.stderrText, hadPassword: hadPassword)
            }
            var listing = ListParser.parse(inner.stdoutText, archiveURL: url)
            if inner.exitCode > 1 && listing.entries.isEmpty {
                throw classify(exitCode: inner.exitCode, text: inner.stderrText, hadPassword: hadPassword)
            }
            listing.info.typeName = format.displayName
            listing.info.physicalSize = ListParser.fileSize(url)
            // Kích thước "sau nén" của từng tệp trong tar không phản ánh lớp nén gz/xz bên ngoài.
            for index in listing.entries.indices { listing.entries[index].packedSize = nil }
            listing.info.method = format.outerStreamType
            listing.info.rawProperties = [(key: "Type", value: format.displayName)]
            return listing
        }

        let result = try await ProcessRunner.run(Command(tool.url, ["l", "-slt", pw] + tool.commonSwitches + [url.path]))
        if result.wasCancelled { throw ArchiveError.cancelled }
        var listing = ListParser.parse(result.stdoutText, archiveURL: url)
        if result.exitCode > 1 {
            let error = classify(exitCode: result.exitCode, text: result.stderrText, hadPassword: hadPassword)
            // Tệp hỏng một phần vẫn có thể xem được danh sách — chỉ báo cảnh báo.
            if error.isPasswordProblem || listing.entries.isEmpty { throw error }
            listing.info.warnings.append(ConsoleText.errorSummary(result.stderrText))
        }
        // Trong tệp 7z/RAR nén solid, 7-Zip gán kích thước cả khối cho tệp đầu tiên — không có ý nghĩa theo từng tệp.
        if listing.info.solid == true {
            for index in listing.entries.indices { listing.entries[index].packedSize = nil }
        }
        return listing
    }

    // MARK: - Giải nén

    static func extract(_ request: ExtractRequest, progress: @escaping Progress) async throws -> ExtractOutcome {
        let tool = try ToolLocator.shared.requireSevenZip()
        let fm = FileManager.default
        try fm.createDirectory(at: request.destination, withIntermediateDirectories: true)

        let useStaging = !request.stripPrefix.isEmpty
        let target = useStaging
            ? request.destination.appendingPathComponent(".rarx-\(UUID().uuidString.prefix(8))", isDirectory: true)
            : request.destination
        if useStaging { try fm.createDirectory(at: target, withIntermediateDirectories: true) }
        defer { if useStaging { try? fm.removeItem(at: target) } }

        var listFile: URL?
        defer { if let listFile { try? fm.removeItem(at: listFile) } }
        var itemArgs: [String] = []
        if let items = request.items, !items.isEmpty {
            if items.count > 300 {
                let file = try writeListFile(items)
                listFile = file
                itemArgs = ["-spd", "-scsUTF-8", "@" + file.path]
            } else {
                itemArgs = ["-spd", "--"] + items
            }
        } else if request.skipMacJunk {
            itemArgs = ["-xr!__MACOSX"]
        }

        let pw = "-p" + (request.password ?? "")
        let hadPassword = !(request.password ?? "").isEmpty
        let overwrite = useStaging ? "-aoa" : request.overwrite.sevenZipSwitch
        let parser = PercentParser(onProgress: progress)
        var warnings: [String] = []

        if request.format.isCompressedTar {
            let first = Command(tool.url, ["x", "-so", "-bsp2", pw] + tool.commonSwitches + [request.archive.path])
            let second = Command(tool.url, ["x", "-si", "-ttar", "-o" + target.path, "-y", overwrite, "-bsp0", "-bso2", "-bse2"]
                                 + tool.commonSwitches + itemArgs)
            let (outer, inner) = try await ProcessRunner.runPipeline(first, second, onFirstStderr: { parser.feed($0) })
            if outer.wasCancelled || inner.wasCancelled { throw ArchiveError.cancelled }
            if outer.exitCode > 1 {
                throw classify(exitCode: outer.exitCode, text: ConsoleText.clean(outer.stderrText), hadPassword: hadPassword)
            }
            warnings += try check(inner, hadPassword: hadPassword)
        } else {
            let args = ["x", "-o" + target.path, "-y", overwrite, pw, "-bsp1", "-bso2", "-bse2"]
                + tool.commonSwitches + [request.archive.path] + itemArgs
            let result = try await ProcessRunner.run(Command(tool.url, args), onStdout: { parser.feed($0) })
            warnings += try check(result, hadPassword: hadPassword)
        }

        if useStaging {
            var base = target
            for component in request.stripPrefix.split(separator: "/") {
                base.appendPathComponent(String(component))
            }
            var topNames: [String] = []
            if let items = request.items {
                for item in items where item.hasPrefix(request.stripPrefix + "/") {
                    let rest = item.dropFirst(request.stripPrefix.count + 1)
                    if let first = rest.split(separator: "/").first.map(String.init), !topNames.contains(first) {
                        topNames.append(first)
                    }
                }
            } else {
                topNames = (try? fm.contentsOfDirectory(atPath: base.path)) ?? []
            }
            for name in topNames {
                let source = base.appendingPathComponent(name)
                guard FileOps.existsNoFollow(source) else { continue }
                try FileOps.mergeMove(from: source,
                                      to: request.destination.appendingPathComponent(name),
                                      mode: request.overwrite)
            }
        }
        progress(1)
        return ExtractOutcome(destination: request.destination, warnings: warnings)
    }

    // MARK: - Kiểm tra

    static func test(_ url: URL, format: ArchiveFormat, password: String?, progress: @escaping Progress) async throws -> TestOutcome {
        let tool = try ToolLocator.shared.requireSevenZip()
        let parser = PercentParser(onProgress: progress)
        let args = ["t", "-p" + (password ?? ""), "-bsp1", "-bso2", "-bse2"] + tool.commonSwitches + [url.path]
        let result = try await ProcessRunner.run(Command(tool.url, args), onStdout: { parser.feed($0) })
        if result.wasCancelled { throw ArchiveError.cancelled }
        let report = ConsoleText.clean(result.stderrText)
        if result.exitCode == 0 {
            return TestOutcome(passed: true, report: report)
        }
        let error = classify(exitCode: result.exitCode, text: result.stderrText, hadPassword: !(password ?? "").isEmpty)
        if error.isPasswordProblem || error == .cancelled { throw error }
        return TestOutcome(passed: false, report: report)
    }

    // MARK: - Tạo mới

    @discardableResult
    static func create(_ request: CreateRequest, progress: @escaping Progress) async throws -> URL {
        guard !request.sources.isEmpty else { throw ArchiveError.failed("Chưa chọn tệp nào để nén.") }
        let fm = FileManager.default
        try fm.createDirectory(at: request.output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let parent = FileOps.commonParent(request.sources)
        let names = request.sources.map { parent != nil ? $0.lastPathComponent : $0.path }
        let parser = PercentParser(onProgress: progress)

        do {
            switch request.format {
            case .rar:
                try await createRar(request, parent: parent, names: names, parser: parser)
            case .tarGz, .tarBz2, .tarXz:
                try await createCompressedTar(request, parent: parent, names: names, parser: parser)
            case .sevenZip, .zip, .tar:
                try await createWithSevenZip(request, parent: parent, names: names, parser: parser)
            default:
                throw ArchiveError.unsupported("RarX chưa hỗ trợ tạo tệp \(request.format.displayName).")
            }
        } catch {
            // Không để lại tệp dở dang.
            try? fm.removeItem(at: request.output)
            if request.resultURL != request.output { try? fm.removeItem(at: request.resultURL) }
            throw error
        }
        progress(1)
        return request.resultURL
    }

    private static func safeName(_ name: String) -> String {
        name.hasPrefix("@") ? "./" + name : name
    }

    private static func createWithSevenZip(_ request: CreateRequest, parent: URL?, names: [String], parser: PercentParser) async throws {
        let tool = try ToolLocator.shared.requireSevenZip()
        guard let type = request.format.sevenZipType else { throw ArchiveError.unsupported("Định dạng không hỗ trợ.") }
        var args = ["a", "-t" + type, "-bsp1", "-bso2", "-bse2", "-y"] + tool.commonSwitches
        if request.format.supportsCompressionLevel {
            args.append("-mx=\(request.level.sevenZipValue)")
        }
        if request.format == .sevenZip {
            args.append("-ms=" + (request.solid ? "on" : "off"))
        }
        if !request.password.isEmpty, request.format.supportsPassword {
            args.append("-p" + request.password)
            if request.format == .sevenZip && request.encryptFileNames { args.append("-mhe=on") }
            if request.format == .zip { args.append(request.zipLegacyEncryption ? "-mem=ZipCrypto" : "-mem=AES256") }
        }
        if let volume = request.volumeSize, request.format.supportsVolumes {
            args.append("-v\(volume)b")
        }
        if request.excludeJunk { args += junkPatterns7z }
        args += [request.output.path, "--"] + names.map(safeName)
        let result = try await ProcessRunner.run(Command(tool.url, args, in: parent), onStdout: { parser.feed($0) })
        _ = try check(result, hadPassword: true)
    }

    private static func createCompressedTar(_ request: CreateRequest, parent: URL?, names: [String], parser: PercentParser) async throws {
        let tool = try ToolLocator.shared.requireSevenZip()
        guard let outer = request.format.outerStreamType else { throw ArchiveError.unsupported("Định dạng không hỗ trợ.") }
        var firstArgs = ["a", "-ttar", "-so", "-an", "-bsp2", "-bso0"] + tool.commonSwitches
        if request.excludeJunk { firstArgs += junkPatterns7z }
        firstArgs += ["--"] + names.map(safeName)
        let innerName = ArchiveFormat.baseName(of: request.output) + ".tar"
        let secondArgs = ["a", "-si" + innerName, "-t" + outer, "-mx=\(request.level.streamValue)", "-bsp0", "-bso0", "-bse2", "-y"]
            + tool.commonSwitches + [request.output.path]
        let (producer, consumer) = try await ProcessRunner.runPipeline(
            Command(tool.url, firstArgs, in: parent),
            Command(tool.url, secondArgs, in: parent),
            onFirstStderr: { parser.feed($0) }
        )
        if producer.wasCancelled || consumer.wasCancelled { throw ArchiveError.cancelled }
        if producer.exitCode > 1 {
            throw classify(exitCode: producer.exitCode, text: ConsoleText.clean(producer.stderrText), hadPassword: false)
        }
        _ = try check(consumer, hadPassword: false)
    }

    private static func createRar(_ request: CreateRequest, parent: URL?, names: [String], parser: PercentParser) async throws {
        let rar = try ToolLocator.shared.requireRar()
        var args = ["a", "-ma5", "-m\(request.level.rarValue)", "-idc", "-y"]
        if parent == nil { args.append("-ep1") }
        if request.solid { args.append("-s") }
        if !request.password.isEmpty {
            args.append((request.encryptFileNames ? "-hp" : "-p") + request.password)
        }
        if let volume = request.volumeSize { args.append("-v\(volume)b") }
        if request.recoveryRecord { args.append("-rr5%") }
        if request.lockArchive { args.append("-k") }
        var commentFile: URL?
        defer { if let commentFile { try? FileManager.default.removeItem(at: commentFile) } }
        let comment = request.comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            let file = try TempSpace.makeDirectory("comment").appendingPathComponent("comment.txt")
            try comment.write(to: file, atomically: true, encoding: .utf8)
            commentFile = file
            args += ["-scfc", "-z" + file.path]
        }
        if request.excludeJunk { args += junkPatternsRar }
        args += ["--", request.output.path] + names
        let result = try await ProcessRunner.run(Command(rar, args, in: parent), onStdout: { parser.feed($0) })
        _ = try check(result, hadPassword: true, includeStdout: true)
    }

    // MARK: - Sửa tệp nén có sẵn

    /// Thêm tệp vào tệp nén, đặt trong thư mục `folder` ("" = gốc).
    static func add(files: [URL], to archive: URL, format: ArchiveFormat, folder: String,
                    password: String?, encryptNames: Bool, level: CompressionLevel,
                    excludeJunk: Bool, progress: @escaping Progress) async throws -> [String] {
        let parser = PercentParser(onProgress: progress)
        let pw = password ?? ""

        if format == .rar {
            let rar = try ToolLocator.shared.requireRar()
            let parent = FileOps.commonParent(files)
            var args = ["a", "-idc", "-y", "-m\(level.rarValue)"]
            if parent == nil { args.append("-ep1") }
            if !folder.isEmpty { args.append("-ap" + folder) }
            if !pw.isEmpty { args.append((encryptNames ? "-hp" : "-p") + pw) }
            if excludeJunk { args += junkPatternsRar }
            args += ["--", archive.path] + files.map { parent != nil ? $0.lastPathComponent : $0.path }
            let result = try await ProcessRunner.run(Command(rar, args, in: parent), onStdout: { parser.feed($0) })
            return try check(result, hadPassword: !pw.isEmpty, includeStdout: true)
        }

        guard format.modifiableBySevenZip, let type = format.sevenZipType else {
            throw ArchiveError.unsupported("Không thể thêm tệp vào tệp \(format.displayName). Hãy chuyển đổi sang 7Z hoặc ZIP trước.")
        }
        let tool = try ToolLocator.shared.requireSevenZip()
        var workingDirectory: URL?
        var names: [String]
        var staging: URL?
        defer { if let staging { try? FileManager.default.removeItem(at: staging) } }

        if folder.isEmpty {
            let parent = FileOps.commonParent(files)
            workingDirectory = parent
            names = files.map { parent != nil ? $0.lastPathComponent : $0.path }
        } else {
            // Dựng cấu trúc thư mục tạm bằng liên kết tượng trưng để tệp vào đúng thư mục trong tệp nén.
            let root = try TempSpace.makeDirectory("add")
            staging = root
            var inner = root
            for component in folder.split(separator: "/") { inner.appendPathComponent(String(component)) }
            try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
            for file in files {
                let link = inner.appendingPathComponent(file.lastPathComponent)
                try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
            }
            workingDirectory = root
            names = [String(folder.split(separator: "/").first ?? "")]
        }

        var args = ["a", "-t" + type, "-bsp1", "-bso2", "-bse2", "-y"] + tool.commonSwitches
        if format.supportsCompressionLevel { args.append("-mx=\(level.sevenZipValue)") }
        if !pw.isEmpty, format.supportsPassword {
            args.append("-p" + pw)
            if format == .sevenZip && encryptNames { args.append("-mhe=on") }
            if format == .zip { args.append("-mem=AES256") }
        }
        if excludeJunk { args += junkPatterns7z }
        args += [archive.path, "--"] + names.map(safeName)
        let result = try await ProcessRunner.run(Command(tool.url, args, in: workingDirectory), onStdout: { parser.feed($0) })
        return try check(result, hadPassword: !pw.isEmpty)
    }

    /// Xoá các mục (đường dẫn đầy đủ trong tệp nén). Với RAR cần truyền cả các mục con.
    static func delete(paths: [String], from archive: URL, format: ArchiveFormat,
                       password: String?, headersEncrypted: Bool) async throws {
        guard !paths.isEmpty else { return }
        let listFile = try writeListFile(paths)
        defer { try? FileManager.default.removeItem(at: listFile) }
        let pw = password ?? ""

        if format == .rar {
            let rar = try ToolLocator.shared.requireRar()
            var args = ["d", "-idc", "-y", "-scfl"]
            if !pw.isEmpty { args.append((headersEncrypted ? "-hp" : "-p") + pw) }
            args += [archive.path, "@" + listFile.path]
            let result = try await ProcessRunner.run(Command(rar, args))
            _ = try check(result, hadPassword: !pw.isEmpty, includeStdout: true)
            return
        }
        guard format.modifiableBySevenZip else {
            throw ArchiveError.unsupported("Không thể xoá mục khỏi tệp \(format.displayName).")
        }
        let tool = try ToolLocator.shared.requireSevenZip()
        var args = ["d", "-spd", "-scsUTF-8", "-bsp1", "-bso2", "-bse2", "-y"] + tool.commonSwitches
        if !pw.isEmpty { args.append("-p" + pw) }
        args += [archive.path, "@" + listFile.path]
        let result = try await ProcessRunner.run(Command(tool.url, args))
        _ = try check(result, hadPassword: !pw.isEmpty)
    }

    /// Đổi tên mục (kèm các mục con nếu là thư mục).
    static func rename(pairs: [(old: String, new: String)], in archive: URL, format: ArchiveFormat, password: String?) async throws {
        guard !pairs.isEmpty else { return }
        guard format.renamable else {
            throw ArchiveError.unsupported("Không thể đổi tên mục trong tệp \(format.displayName).")
        }
        let tool = try ToolLocator.shared.requireSevenZip()
        let pw = password ?? ""
        var args = ["rn", "-spd", "-bso2", "-bse2", "-y"] + tool.commonSwitches
        if !pw.isEmpty { args.append("-p" + pw) }
        args += [archive.path, "--"]
        for pair in pairs { args += [pair.old, pair.new] }
        let result = try await ProcessRunner.run(Command(tool.url, args))
        _ = try check(result, hadPassword: !pw.isEmpty)
    }

    /// Tạo thư mục rỗng mới bên trong tệp nén.
    static func makeFolder(named name: String, in folder: String, archive: URL, format: ArchiveFormat,
                           password: String?, encryptNames: Bool) async throws {
        let root = try TempSpace.makeDirectory("folder")
        defer { try? FileManager.default.removeItem(at: root) }
        let pw = password ?? ""

        if format == .rar {
            let rar = try ToolLocator.shared.requireRar()
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            var args = ["a", "-idc", "-y"]
            if !folder.isEmpty { args.append("-ap" + folder) }
            if !pw.isEmpty { args.append((encryptNames ? "-hp" : "-p") + pw) }
            args += ["--", archive.path, name]
            let result = try await ProcessRunner.run(Command(rar, args, in: root))
            _ = try check(result, hadPassword: !pw.isEmpty, includeStdout: true)
            return
        }

        guard format.modifiableBySevenZip, let type = format.sevenZipType else {
            throw ArchiveError.unsupported("Không thể tạo thư mục trong tệp \(format.displayName).")
        }
        let tool = try ToolLocator.shared.requireSevenZip()
        var inner = root
        for component in folder.split(separator: "/") { inner.appendPathComponent(String(component)) }
        inner.appendPathComponent(name)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let top = folder.isEmpty ? name : String(folder.split(separator: "/").first ?? "")
        var args = ["a", "-t" + type, "-bso2", "-bse2", "-y"] + tool.commonSwitches
        if !pw.isEmpty, format.supportsPassword {
            args.append("-p" + pw)
            if format == .sevenZip && encryptNames { args.append("-mhe=on") }
        }
        args += [archive.path, "--", safeName(top)]
        let result = try await ProcessRunner.run(Command(tool.url, args, in: root))
        _ = try check(result, hadPassword: !pw.isEmpty)
    }

    // MARK: - Sửa chữa, khoá, ghi chú (RAR / ZIP)

    static func canRepair(_ format: ArchiveFormat) -> Bool {
        switch format {
        case .rar: return ToolLocator.shared.rar != nil
        case .zip: return ToolLocator.shared.systemZip != nil
        default: return false
        }
    }

    /// Sửa tệp nén hỏng; trả về tệp đã sửa (tệp gốc giữ nguyên).
    static func repair(_ url: URL, format: ArchiveFormat) async throws -> URL {
        let folder = url.deletingLastPathComponent()
        switch format {
        case .rar:
            let rar = try ToolLocator.shared.requireRar()
            let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            let result = try await ProcessRunner.run(Command(rar, ["r", "-idc", "-y", "--", url.path], in: folder))
            _ = try check(result, hadPassword: false, includeStdout: true)
            let after = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            if let created = after.first(where: { !before.contains($0) && ($0.hasPrefix("fixed.") || $0.hasPrefix("rebuilt.")) }) {
                return folder.appendingPathComponent(created)
            }
            throw ArchiveError.failed("RAR đã chạy nhưng không tạo ra tệp sửa chữa — có thể tệp không cần sửa hoặc không có bản ghi khôi phục.")
        case .zip:
            guard let zip = ToolLocator.shared.systemZip else { throw ArchiveError.toolMissing("zip của hệ thống") }
            let output = FileOps.uniqueURL(for: folder.appendingPathComponent(ArchiveFormat.baseName(of: url) + " (đã sửa).zip"))
            let result = try await ProcessRunner.run(Command(zip, ["-FF", url.path, "--out", output.path], in: folder),
                                                     stdin: Data("y\n".utf8))
            if result.wasCancelled { throw ArchiveError.cancelled }
            guard FileOps.exists(output) else {
                throw ArchiveError.failed(ConsoleText.errorSummary(result.stdoutText + "\n" + result.stderrText))
            }
            return output
        default:
            throw ArchiveError.unsupported("Chỉ sửa được tệp .rar (cần công cụ RAR) và .zip.")
        }
    }

    static func lockRar(_ url: URL) async throws {
        let rar = try ToolLocator.shared.requireRar()
        let result = try await ProcessRunner.run(Command(rar, ["k", "-idc", "-y", "--", url.path]))
        _ = try check(result, hadPassword: false, includeStdout: true)
    }

    static func setRarComment(_ comment: String, on url: URL) async throws {
        let rar = try ToolLocator.shared.requireRar()
        let folder = try TempSpace.makeDirectory("comment")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("comment.txt")
        try comment.write(to: file, atomically: true, encoding: .utf8)
        let result = try await ProcessRunner.run(Command(rar, ["c", "-idc", "-y", "-scfc", "-z" + file.path, "--", url.path]))
        _ = try check(result, hadPassword: false, includeStdout: true)
    }

    // MARK: - Chuyển đổi định dạng

    static func convert(_ url: URL, format: ArchiveFormat, password: String?, into template: CreateRequest,
                        progress: @escaping Progress) async throws -> URL {
        let workFolder = template.output.deletingLastPathComponent()
            .appendingPathComponent(".rarx-convert-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let extractRequest = ExtractRequest(archive: url, format: format, password: password, items: nil,
                                            destination: workFolder, overwrite: .overwrite)
        _ = try await extract(extractRequest, progress: { progress($0 * 0.5) })
        let contents = try FileManager.default.contentsOfDirectory(at: workFolder, includingPropertiesForKeys: nil)
        guard !contents.isEmpty else { throw ArchiveError.failed("Tệp nén rỗng — không có gì để chuyển đổi.") }
        var request = template
        request.sources = contents
        return try await create(request, progress: { progress(0.5 + $0 * 0.5) })
    }

    // MARK: - Công cụ

    static func benchmark(onOutput: @escaping @Sendable (String) -> Void) async throws -> String {
        let tool = try ToolLocator.shared.requireSevenZip()
        let result = try await ProcessRunner.run(Command(tool.url, ["b"] + tool.commonSwitches), onStdout: { data in
            onOutput(String(decoding: data, as: UTF8.self))
        })
        if result.wasCancelled { throw ArchiveError.cancelled }
        return ConsoleText.clean(result.stdoutText)
    }

    static func checksum(files: [URL], algorithm: String) async throws -> String {
        let tool = try ToolLocator.shared.requireSevenZip()
        let parent = FileOps.commonParent(files)
        let names = files.map { parent != nil ? safeName($0.lastPathComponent) : $0.path }
        let args = ["h", "-scrc" + algorithm, "-bsp0"] + tool.commonSwitches + ["--"] + names
        let result = try await ProcessRunner.run(Command(tool.url, args, in: parent))
        if result.wasCancelled { throw ArchiveError.cancelled }
        if result.exitCode > 1 {
            throw ArchiveError.failed(ConsoleText.errorSummary(result.stderrText + "\n" + result.stdoutText))
        }
        return ConsoleText.clean(result.stdoutText)
    }

    // MARK: - Tiện ích

    private static func writeListFile(_ items: [String]) throws -> URL {
        let folder = try TempSpace.makeDirectory("list")
        let file = folder.appendingPathComponent("items.txt")
        try items.joined(separator: "\n").appending("\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    /// Kiểm tra mã thoát; trả về cảnh báo (nếu có), ném lỗi nếu thất bại.
    @discardableResult
    static func check(_ result: ProcessResult, hadPassword: Bool, includeStdout: Bool = false) throws -> [String] {
        if result.wasCancelled { throw ArchiveError.cancelled }
        var text = result.stderrText
        if includeStdout { text = result.stdoutText + "\n" + text }
        switch result.exitCode {
        case 0:
            return []
        case 1:
            let summary = ConsoleText.errorSummary(text)
            return summary.isEmpty ? [] : [summary]
        default:
            throw classify(exitCode: result.exitCode, text: text, hadPassword: hadPassword)
        }
    }

    static func classify(exitCode: Int32, text: String, hadPassword: Bool) -> ArchiveError {
        let lower = text.lowercased()
        let passwordHints = ["wrong password", "cannot open encrypted archive", "can not open encrypted archive",
                             "enter password", "password is incorrect", "incorrect password", "bad password"]
        if exitCode == 11 || passwordHints.contains(where: { lower.contains($0) }) {
            return hadPassword ? .wrongPassword : .passwordRequired
        }
        if lower.contains("can not open the file as archive") || lower.contains("cannot open the file as archive")
            || lower.contains("is not archive") || lower.contains("is not rar archive") || lower.contains("unsupported archive") {
            return .notAnArchive
        }
        if lower.contains("not enough space") || lower.contains("no space left") || lower.contains("disk full") {
            return .diskFull
        }
        let summary = ConsoleText.errorSummary(text)
        let corruptHints = ["data error", "crc failed", "unexpected end", "headers error", "is corrupt", "checksum error", "broken"]
        if corruptHints.contains(where: { lower.contains($0) }) {
            return .corrupted(summary)
        }
        if lower.contains("locked archive") || lower.contains("archive is locked") {
            return .failed("Tệp nén đã bị khoá — không thể sửa đổi.")
        }
        if exitCode == 255 { return .cancelled }
        return .failed(summary.isEmpty ? "Công cụ nén báo lỗi (mã \(exitCode))." : summary)
    }
}
