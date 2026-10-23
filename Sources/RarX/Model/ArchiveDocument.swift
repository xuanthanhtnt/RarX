import AppKit
import Combine
import UniformTypeIdentifiers

/// Các bảng (sheet) có thể hiện trên cửa sổ duyệt tệp nén.
enum ArchiveSheet: Identifiable {
    case extract(selectionCount: Int)
    case info
    case convert
    case testResult(TestOutcome)

    var id: String {
        switch self {
        case .extract: return "extract"
        case .info: return "info"
        case .convert: return "convert"
        case .testResult: return "test"
        }
    }
}

/// Trạng thái và thao tác của một tệp nén đang mở trong cửa sổ.
@MainActor
final class ArchiveDocument: ObservableObject {
    enum LoadState: Equatable {
        case loading
        case loaded
        case locked
        case failed(String)
    }

    let url: URL
    let format: ArchiveFormat
    let isMultiVolume: Bool
    weak var window: NSWindow?

    @Published private(set) var state: LoadState = .loading
    @Published private(set) var info = ArchiveInfo()
    @Published private(set) var root = ArchiveNode(id: "", name: "", isDirectory: true, isImplicit: true)
    @Published private(set) var visibleNodes: [ArchiveNode] = []
    @Published var selection = Set<String>()
    @Published var currentPath = "" {
        didSet {
            guard oldValue != currentPath else { return }
            selection = []
            refreshVisible()
        }
    }
    @Published var sortOrder: [KeyPathComparator<ArchiveNode>] = [
        KeyPathComparator(\ArchiveNode.name, comparator: String.StandardComparator.localizedStandard)
    ] {
        didSet { refreshVisible() }
    }
    @Published var searchText = "" {
        didSet { if oldValue != searchText { refreshVisible() } }
    }
    @Published var hideJunk: Bool {
        didSet { refreshVisible() }
    }
    @Published var showSidebar: Bool {
        didSet { UserDefaults.standard.set(showSidebar, forKey: Prefs.showSidebar) }
    }
    @Published var sheet: ArchiveSheet? = nil
    @Published var quickLookURL: URL? = nil
    @Published private(set) var activeJob: Job? = nil
    @Published var banner: String? = nil

    private(set) var index: [String: ArchiveNode] = [:]
    private var allNodes: [ArchiveNode] = []
    var password: String?
    private var loadTask: Task<Void, Never>?
    private var jobObservation: AnyCancellable?

    init(url: URL, format: ArchiveFormat, isMultiVolume: Bool) {
        self.url = url
        self.format = format
        self.isMultiVolume = isMultiVolume
        self.hideJunk = Prefs.bool(Prefs.hideJunkInBrowser)
        self.showSidebar = Prefs.bool(Prefs.showSidebar)
    }

    // MARK: - Thông tin chung

    var displayName: String { url.lastPathComponent }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var isBusy: Bool { activeJob?.isRunning == true }

    var currentFolder: ArchiveNode { index[currentPath] ?? root }

    var selectedNodes: [ArchiveNode] {
        selection.compactMap { index[$0] }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var hasEncryptedEntries: Bool { root.encrypted }

    var isWritable: Bool { FileManager.default.isWritableFile(atPath: url.path) }

    /// Có thể thêm/xoá/sửa không.
    var canModify: Bool {
        guard state == .loaded, !isMultiVolume, isWritable, !isBusy else { return false }
        if format.modifiableBySevenZip { return true }
        if format == .rar { return ToolLocator.shared.rar != nil && !(info.characteristics ?? "").contains("Locked") }
        return false
    }

    var canRename: Bool { canModify && format.renamable && selection.count == 1 }
    var canRepair: Bool { !isBusy && ArchiveEngine.canRepair(format) }
    var canLock: Bool { canModify && format == .rar }
    var isLoaded: Bool { state == .loaded }

    /// Lý do chỉ đọc (hiện trên thanh trạng thái).
    var readOnlyReason: String? {
        guard state == .loaded else { return nil }
        if isMultiVolume { return "Tệp nén nhiều phần chỉ có thể xem và giải nén." }
        if !isWritable { return "Bạn không có quyền ghi vào tệp này." }
        if format == .rar && ToolLocator.shared.rar == nil {
            return "Cần công cụ RAR (rarlab.com) để sửa tệp .rar. Xem và giải nén vẫn dùng được."
        }
        if format == .rar && (info.characteristics ?? "").contains("Locked") { return "Tệp RAR đã bị khoá." }
        if !format.modifiableBySevenZip && format != .rar {
            return "Định dạng \(format.displayName) chỉ có thể xem và giải nén."
        }
        return nil
    }

    var formatSummary: String {
        var parts: [String] = [info.typeName.isEmpty ? format.displayName : info.typeName.uppercased()]
        if let method = info.method, !method.isEmpty { parts.append(method) }
        if info.solid == true { parts.append("Solid") }
        if info.headersEncrypted || hasEncryptedEntries { parts.append("Có mật khẩu") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Đọc tệp nén

    func load(keepPath: Bool = false) {
        loadTask?.cancel()
        if !keepPath || state != .loaded { state = .loading }
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let listing = try await ArchiveEngine.list(self.url, format: self.format, password: self.password)
                self.apply(listing, keepPath: keepPath)
            } catch let error as ArchiveError where error.isPasswordProblem {
                self.info.headersEncrypted = true
                self.state = .locked
                await self.unlock(wrongBefore: error == .wrongPassword)
            } catch {
                if error.isCancellation { return }
                self.state = .failed(error.userMessage)
            }
        }
    }

    func unlock(wrongBefore: Bool = false) async {
        guard let entered = await Prompts.password(for: displayName, wrongBefore: wrongBefore, window: window) else { return }
        password = entered
        load()
    }

    private func apply(_ listing: ArchiveListing, keepPath: Bool) {
        let headersWereEncrypted = info.headersEncrypted
        info = listing.info
        info.headersEncrypted = info.headersEncrypted || headersWereEncrypted
        let tree = ArchiveNode.buildTree(from: listing.entries)
        root = tree.root
        index = tree.index
        allNodes = tree.all
        if !keepPath || index[currentPath] == nil {
            currentPath = ""
        }
        selection = selection.filter { index[$0] != nil }
        refreshVisible()
        state = .loaded
        if !info.warnings.isEmpty {
            banner = "Tệp nén có thể bị lỗi: " + info.warnings.joined(separator: " ")
        }
    }

    func refreshVisible() {
        var nodes: [ArchiveNode]
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            nodes = allNodes.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        } else {
            nodes = currentFolder.children
        }
        if hideJunk {
            nodes = nodes.filter { !$0.isJunk && !$0.id.hasPrefix("__MACOSX/") }
        }
        nodes.sort(using: sortOrder)
        visibleNodes = nodes.filter(\.isDirectory) + nodes.filter { !$0.isDirectory }
    }

    // MARK: - Điều hướng

    func navigate(to path: String) {
        searchText = ""
        currentPath = index[path] == nil ? "" : path
    }

    func goUp() {
        guard !currentPath.isEmpty else { return }
        navigate(to: currentFolder.parentPath)
    }

    var canGoUp: Bool { !currentPath.isEmpty && !isSearching }

    /// Các đoạn đường dẫn hiện tại (cho thanh đường dẫn).
    var pathComponents: [(name: String, path: String)] {
        var result: [(name: String, path: String)] = []
        var node: ArchiveNode? = currentFolder
        while let current = node, !current.id.isEmpty {
            result.insert((name: current.name, path: current.id), at: 0)
            node = current.parent
        }
        return result
    }

    /// Mở (nhấp đúp): thư mục thì vào trong, tệp thì mở bằng ứng dụng mặc định.
    func open(_ ids: Set<String>) {
        let nodes = ids.compactMap { index[$0] }
        if nodes.count == 1, let node = nodes.first, node.isDirectory {
            navigate(to: node.id)
            return
        }
        let files = nodes.filter { !$0.isDirectory }
        guard !files.isEmpty else { return }
        Task {
            do {
                let urls = try await extractToTemporary(files)
                for url in urls {
                    if ArchiveFormat.isArchive(url) {
                        WindowManager.shared.openArchive(url)
                    } else {
                        NSWorkspace.shared.open(url)
                    }
                }
            } catch {
                Prompts.showError(error, title: "Không mở được tệp", window: window)
            }
        }
    }

    func openSelection() { open(selection) }

    func quickLook() {
        guard let node = selectedNodes.first(where: { !$0.isDirectory }) else { return }
        Task {
            do {
                quickLookURL = try await extractToTemporary([node]).first
            } catch {
                Prompts.showError(error, title: "Không xem nhanh được", window: window)
            }
        }
    }

    /// Giải nén các tệp vào thư mục tạm (để mở, xem nhanh, kéo ra Finder).
    func extractToTemporary(_ nodes: [ArchiveNode]) async throws -> [URL] {
        let folder = try TempSpace.makeDirectory("open")
        var password = self.password ?? ""
        var wrongBefore = false
        let groups = Dictionary(grouping: nodes, by: \.parentPath)
        for (prefix, group) in groups {
            while true {
                let request = ExtractRequest(
                    archive: url, format: format, password: password.isEmpty ? nil : password,
                    items: group.map(\.id), stripPrefix: prefix, destination: folder, overwrite: .overwrite
                )
                do {
                    _ = try await ArchiveEngine.extract(request, progress: { _ in })
                    break
                } catch let error as ArchiveError where error.isPasswordProblem {
                    guard let entered = await Prompts.password(for: displayName,
                                                               wrongBefore: wrongBefore || error == .wrongPassword,
                                                               window: window) else {
                        throw ArchiveError.cancelled
                    }
                    password = entered
                    wrongBefore = true
                }
            }
        }
        if !password.isEmpty { self.password = password }
        return nodes.map { folder.appendingPathComponent($0.name) }
    }

    /// NSItemProvider để kéo tệp từ tệp nén ra Finder.
    func dragProvider(for node: ArchiveNode) -> NSItemProvider? {
        let provider = NSItemProvider()
        provider.suggestedName = node.name
        let type: UTType = node.isDirectory ? .folder : (UTType(filenameExtension: node.fileExtension) ?? .data)
        let nodeID = node.id
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { [weak self] completion in
            let progress = Progress(totalUnitCount: 1)
            Task { @MainActor [weak self] in
                guard let self, let target = self.index[nodeID] else {
                    completion(nil, false, ArchiveError.cancelled)
                    return
                }
                do {
                    let url = try await self.extractToTemporary([target]).first
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        }
        return provider
    }

    // MARK: - Tác vụ

    private func track(_ job: Job) {
        activeJob = job
        jobObservation = job.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        // Khi tác vụ xong, giữ thông báo kết quả trên thanh trạng thái vài giây rồi ẩn đi.
        let jobID = job.id
        Task { [weak self] in
            while let current = self?.activeJob, current.id == jobID, current.isRunning {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard let self, let current = self.activeJob, current.id == jobID, !current.isRunning else { return }
            self.activeJob = nil
            self.jobObservation = nil
        }
    }

    func presentExtract() {
        sheet = .extract(selectionCount: selection.count)
    }

    func performExtract(_ initialConfig: ExtractConfig) {
        let scope: ExtractScope? = (initialConfig.selectionOnly && !selection.isEmpty)
            ? makeScope(for: selectedNodes)
            : nil
        Task {
            var config = initialConfig
            // Hỏi mật khẩu trước để 7-Zip không tạo ra tệp hỏng khi đoán sai.
            if config.password.isEmpty && (password ?? "").isEmpty && hasEncryptedEntries {
                guard let entered = await Prompts.password(for: displayName, wrongBefore: false, window: window) else { return }
                config.password = entered
            }
            let job = Workflows.extract(archive: url, format: format, config: config, scope: scope,
                                        knownPassword: password, window: window,
                                        onPasswordAccepted: { self.password = $0 })
            track(job)
        }
    }

    /// Giải nén toàn bộ cạnh tệp nén theo cài đặt mặc định.
    func extractHere() {
        var config = ExtractConfig.defaults(for: url)
        config.baseFolder = url.deletingLastPathComponent()
        if !selection.isEmpty {
            config.selectionOnly = true
            config.folderMode = .direct
            config.openFolderAfter = Prefs.bool(Prefs.openFolderAfterExtract)
        }
        config.trashArchiveAfter = false
        performExtract(config)
    }

    private func makeScope(for nodes: [ArchiveNode]) -> ExtractScope {
        let prefix = isSearching ? "" : currentPath
        let tops: [String]
        if prefix.isEmpty {
            var seen = Set<String>()
            tops = nodes.compactMap { $0.id.split(separator: "/").first.map(String.init) }.filter { seen.insert($0).inserted }
        } else {
            tops = nodes.map(\.name)
        }
        return ExtractScope(items: nodes.map(\.id), stripPrefix: prefix, topNames: tops)
    }

    func test() {
        let job = JobCenter.shared.start(
            title: "Kiểm tra",
            detail: displayName,
            symbol: "checkmark.shield",
            operation: { [weak self] job in
                guard let self else { return nil }
                var password = self.password ?? ""
                var wrongBefore = false
                while true {
                    do {
                        let outcome = try await ArchiveEngine.test(self.url, format: self.format,
                                                                   password: password.isEmpty ? nil : password,
                                                                   progress: job.progressHandler())
                        if !password.isEmpty { self.password = password }
                        self.sheet = .testResult(outcome)
                        return outcome.passed ? "Không phát hiện lỗi." : "Phát hiện lỗi trong tệp nén."
                    } catch let error as ArchiveError where error.isPasswordProblem {
                        guard let entered = await Prompts.password(for: self.displayName,
                                                                   wrongBefore: wrongBefore || error == .wrongPassword,
                                                                   window: self.window) else {
                            throw ArchiveError.cancelled
                        }
                        password = entered
                        wrongBefore = true
                    }
                }
            },
            completion: { [weak self] _, error in
                if let error { Prompts.showError(error, title: "Không kiểm tra được", window: self?.window) }
            }
        )
        track(job)
    }

    /// Đảm bảo có mật khẩu khi sửa tệp nén đã mã hoá (để tệp mới cũng được mã hoá).
    private func passwordForModification() async -> String?? {
        guard info.headersEncrypted || hasEncryptedEntries else { return .some(password) }
        if let password { return .some(password) }
        guard let entered = await Prompts.password(for: displayName, wrongBefore: false, window: window) else { return nil }
        password = entered
        return .some(entered)
    }

    /// Chạy một thao tác sửa đổi rồi tải lại danh sách.
    private func modify(title: String, symbol: String, _ body: @escaping @MainActor (Job, String?) async throws -> String?) {
        guard canModify else { return }
        Task {
            guard let pw = await passwordForModification() else { return }
            let job = JobCenter.shared.start(
                title: title,
                detail: displayName,
                symbol: symbol,
                operation: { job in try await body(job, pw) },
                completion: { _, error in
                    if let archiveError = error as? ArchiveError, archiveError.isPasswordProblem {
                        self.password = nil
                    }
                    if let error { Prompts.showError(error, title: "\(title) không thành công", window: self.window) }
                    self.load(keepPath: true)
                }
            )
            track(job)
        }
    }

    func addFiles(_ urls: [URL]) {
        let files = urls.filter { $0.standardizedFileURL != url.standardizedFileURL }
        guard !files.isEmpty else { return }
        let folder = isSearching ? "" : currentPath
        let format = self.format
        let archive = url
        let encryptNames = info.headersEncrypted
        modify(title: "Thêm tệp", symbol: "doc.badge.plus") { job, pw in
            let warnings = try await ArchiveEngine.add(
                files: files, to: archive, format: format, folder: folder, password: pw,
                encryptNames: encryptNames, level: Prefs.preferredLevel,
                excludeJunk: Prefs.bool(Prefs.excludeJunk), progress: job.progressHandler()
            )
            return warnings.isEmpty ? "Đã thêm \(files.count) mục." : warnings.joined(separator: "\n")
        }
    }

    func chooseFilesToAdd() {
        guard canModify, let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Thêm"
        panel.message = "Chọn tệp hoặc thư mục để thêm vào “\(displayName)”"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in self?.addFiles(urls) }
        }
    }

    func deleteSelection() {
        let nodes = selectedNodes
        guard canModify, !nodes.isEmpty else { return }
        Task {
            if Prefs.bool(Prefs.confirmDelete) {
                let what = nodes.count == 1 ? "“\(nodes[0].name)”" : "\(nodes.count) mục"
                let ok = await Prompts.confirm(title: "Xoá \(what) khỏi tệp nén?",
                                               message: "Thao tác này sửa trực tiếp “\(displayName)” và không thể hoàn tác.",
                                               confirm: "Xoá", destructive: true, window: window)
                guard ok else { return }
            }
            let archiveFormat = self.format
            var collected = nodes.map(\.id)
            if archiveFormat == .rar {
                // RAR cần liệt kê rõ cả các mục con.
                var all = Set(collected)
                for node in nodes where node.isDirectory {
                    for child in node.descendants() { all.insert(child.id) }
                }
                collected = Array(all).sorted()
            }
            let paths = collected
            let archive = url
            let encrypted = info.headersEncrypted
            let count = nodes.count
            selection = []
            modify(title: "Xoá", symbol: "trash") { _, pw in
                try await ArchiveEngine.delete(paths: paths, from: archive, format: archiveFormat,
                                               password: pw, headersEncrypted: encrypted)
                return "Đã xoá \(count) mục."
            }
        }
    }

    func renameSelection() {
        guard canRename, let node = selectedNodes.first else { return }
        Task {
            guard let newName = await Prompts.text(title: "Đổi tên",
                                                   message: "Tên mới cho “\(node.name)”:",
                                                   initial: node.name, confirm: "Đổi tên", window: window),
                  newName != node.name else { return }
            guard !newName.contains("/") else {
                Prompts.showMessage("Tên không hợp lệ", "Tên không được chứa ký tự “/”.", window: window)
                return
            }
            let parent = node.parentPath
            let newPath = parent.isEmpty ? newName : parent + "/" + newName
            if index[newPath] != nil {
                Prompts.showMessage("Tên đã tồn tại", "Đã có mục “\(newName)” trong thư mục này.", window: window)
                return
            }
            let format = self.format
            let archive = url
            let oldPath = node.id
            modify(title: "Đổi tên", symbol: "pencil") { _, pw in
                try await ArchiveEngine.rename(pairs: [(old: oldPath, new: newPath)], in: archive, format: format, password: pw)
                return "Đã đổi tên thành “\(newName)”."
            }
        }
    }

    func createFolder() {
        guard canModify else { return }
        Task {
            guard let name = await Prompts.text(title: "Thư mục mới",
                                                message: "Tên thư mục mới trong “\(currentPath.isEmpty ? displayName : currentFolder.name)”:",
                                                initial: "Thư mục mới", confirm: "Tạo", window: window) else { return }
            guard !name.contains("/") else { return }
            let folder = isSearching ? "" : currentPath
            let format = self.format
            let archive = url
            let encryptNames = info.headersEncrypted
            modify(title: "Tạo thư mục", symbol: "folder.badge.plus") { _, pw in
                try await ArchiveEngine.makeFolder(named: name, in: folder, archive: archive, format: format,
                                                   password: pw, encryptNames: encryptNames)
                return "Đã tạo thư mục “\(name)”."
            }
        }
    }

    func lockArchive() {
        guard canLock else { return }
        Task {
            let ok = await Prompts.confirm(title: "Khoá tệp RAR?",
                                           message: "Sau khi khoá, không ai có thể thêm, xoá hay sửa nội dung của “\(displayName)” nữa (kể cả bạn).",
                                           confirm: "Khoá", destructive: true, window: window)
            guard ok else { return }
            let archive = url
            modify(title: "Khoá tệp nén", symbol: "lock") { _, _ in
                try await ArchiveEngine.lockRar(archive)
                return "Đã khoá tệp nén."
            }
        }
    }

    func saveComment(_ comment: String) {
        guard canModify, format == .rar else { return }
        let archive = url
        modify(title: "Lưu ghi chú", symbol: "text.bubble") { _, _ in
            try await ArchiveEngine.setRarComment(comment, on: archive)
            return "Đã lưu ghi chú."
        }
    }

    func repair() {
        guard canRepair else { return }
        let archive = url
        let format = self.format
        let job = JobCenter.shared.start(
            title: "Sửa tệp nén",
            detail: displayName,
            symbol: "wrench.and.screwdriver",
            operation: { job in
                let fixed = try await ArchiveEngine.repair(archive, format: format)
                job.resultURL = fixed
                return "Đã tạo “\(fixed.lastPathComponent)”."
            },
            completion: { [weak self] job, error in
                guard let self else { return }
                if let error {
                    Prompts.showError(error, title: "Không sửa được tệp nén", window: self.window)
                } else if let fixed = job.resultURL {
                    Task {
                        let open = await Prompts.confirm(title: "Đã sửa xong",
                                                         message: "Tệp đã sửa được lưu thành “\(fixed.lastPathComponent)” cạnh tệp gốc. Mở tệp này?",
                                                         confirm: "Mở", window: self.window)
                        if open { WindowManager.shared.openArchive(fixed) }
                    }
                }
            }
        )
        track(job)
    }

    func convert(to template: CreateRequest) {
        let archive = url
        let format = self.format
        let password = self.password
        let job = JobCenter.shared.start(
            title: "Chuyển đổi sang \(template.format.displayName)",
            detail: displayName,
            symbol: "arrow.triangle.2.circlepath",
            operation: { job in
                let result = try await ArchiveEngine.convert(archive, format: format, password: password,
                                                             into: template, progress: job.progressHandler())
                job.resultURL = result
                return "Đã tạo “\(result.lastPathComponent)”."
            },
            completion: { [weak self] job, error in
                if let error {
                    Prompts.showError(error, title: "Không chuyển đổi được", window: self?.window)
                } else if let result = job.resultURL {
                    NSWorkspace.shared.activateFileViewerSelecting([result])
                }
            }
        )
        track(job)
    }

    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Thống kê cho thanh trạng thái

    var statusText: String {
        if isSearching {
            return "Tìm thấy \(visibleNodes.count) mục"
        }
        let nodes = selection.isEmpty ? visibleNodes : selectedNodes
        let size = nodes.reduce(Int64(0)) { $0 + $1.size }
        if selection.isEmpty {
            return "\(nodes.count) mục · \(Format.bytes(size))"
        }
        return "Đã chọn \(nodes.count)/\(visibleNodes.count) mục · \(Format.bytes(size))"
    }

    var totalsText: String {
        let packed = info.physicalSize
        let unpacked = root.size
        var text = "\(root.fileCount) tệp, \(root.folderCount) thư mục · \(Format.bytes(unpacked))"
        if unpacked > 0 && packed > 0 {
            let ratio = Double(packed) / Double(unpacked) * 100
            text += " → \(Format.bytes(packed))"
            if ratio <= 150 { text += " (\(Format.percent(ratio)))" }
        }
        return text
    }
}
