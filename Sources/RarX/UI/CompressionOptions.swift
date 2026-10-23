import SwiftUI
import AppKit

/// Kích thước chia phần có sẵn.
enum SplitPreset: String, CaseIterable, Identifiable {
    case mb100, mb500, cd700, gb1, gb2, fat32, dvd, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mb100: return "100 MB"
        case .mb500: return "500 MB"
        case .cd700: return "700 MB (CD)"
        case .gb1: return "1 GB"
        case .gb2: return "2 GB"
        case .fat32: return "4 GB (giới hạn USB FAT32)"
        case .dvd: return "4,7 GB (DVD)"
        case .custom: return "Tuỳ chỉnh…"
        }
    }

    var bytes: Int64? {
        let mb: Int64 = 1_000_000
        switch self {
        case .mb100: return 100 * mb
        case .mb500: return 500 * mb
        case .cd700: return 700 * mb
        case .gb1: return 1_000 * mb
        case .gb2: return 2_000 * mb
        case .fat32: return 4_294_967_295 - 1_048_576   // dưới 4 GiB một chút
        case .dvd: return 4_700 * mb
        case .custom: return nil
        }
    }
}

/// Toàn bộ lựa chọn khi tạo một tệp nén.
struct CompressionSettings {
    var name: String
    var folder: URL
    var format: ArchiveFormat
    var level: CompressionLevel
    var password = ""
    var confirmPassword = ""
    var revealPassword = false
    var encryptNames = true
    var zipLegacy: Bool
    var splitEnabled = false
    var splitPreset: SplitPreset = .cd700
    var customSplitMB = "100"
    var solid = true
    var recovery = false
    var lock = false
    var comment = ""
    var excludeJunk: Bool
    var testAfter: Bool
    var trashSources: Bool
    var separate = false

    init(name: String, folder: URL, format: ArchiveFormat? = nil) {
        self.name = name
        self.folder = folder
        self.format = format ?? Prefs.preferredFormat
        self.level = Prefs.preferredLevel
        self.zipLegacy = Prefs.bool(Prefs.zipLegacyEncryption)
        self.excludeJunk = Prefs.bool(Prefs.excludeJunk)
        self.testAfter = Prefs.bool(Prefs.testAfterCompress)
        self.trashSources = Prefs.bool(Prefs.trashSourcesAfterCompress)
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var outputURL: URL {
        folder.appendingPathComponent(trimmedName + "." + format.fileExtension)
    }

    var volumeBytes: Int64? {
        guard splitEnabled, format.supportsVolumes else { return nil }
        if let bytes = splitPreset.bytes { return bytes }
        let text = customSplitMB.replacingOccurrences(of: ",", with: ".")
        guard let mb = Double(text), mb >= 1 else { return nil }
        return Int64(mb * 1_000_000)
    }

    var usesPassword: Bool { format.supportsPassword && !password.isEmpty }

    /// Lỗi chặn việc tạo (nil = hợp lệ).
    var validationError: String? {
        if trimmedName.isEmpty { return "Hãy đặt tên cho tệp nén." }
        if trimmedName.contains("/") || trimmedName.contains(":") { return "Tên tệp không được chứa “/” hoặc “:”." }
        if format == .rar && ToolLocator.shared.rar == nil {
            return "Tạo tệp .rar cần công cụ RAR — RarX tự cài khi có mạng, hoặc bấm “Cài công cụ RAR” trong Cài đặt ▸ Công cụ."
        }
        if format.supportsPassword && !password.isEmpty && !revealPassword && password != confirmPassword {
            return "Hai lần nhập mật khẩu chưa khớp."
        }
        if splitEnabled && format.supportsVolumes && volumeBytes == nil {
            return "Kích thước mỗi phần không hợp lệ."
        }
        return nil
    }

    func makeRequest(sources: [URL]) -> CreateRequest {
        var request = CreateRequest(sources: sources, output: outputURL, format: format)
        request.level = level
        if usesPassword {
            request.password = password
            request.encryptFileNames = format.supportsEncryptedNames && encryptNames
            request.zipLegacyEncryption = format == .zip && zipLegacy
        }
        request.volumeSize = volumeBytes
        request.solid = format.supportsSolid && solid
        request.excludeJunk = excludeJunk
        request.recoveryRecord = format == .rar && recovery
        request.lockArchive = format == .rar && lock
        request.comment = format == .rar ? comment : ""
        return request
    }

    var extras: CompressExtras {
        CompressExtras(separateArchives: separate, testAfter: testAfter, trashSources: trashSources)
    }
}

/// Các phần (Section) chọn định dạng, mức nén, mật khẩu, chia phần… dùng chung.
@MainActor
struct CompressionOptionsSections: View {
    @Binding var settings: CompressionSettings
    var showSourceOptions = true
    var sourceCount = 1

    var body: some View {
        Section("Tệp nén") {
            LabeledContent("Tên") {
                HStack(spacing: 4) {
                    TextField("Tên", text: $settings.name)
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                    Text("." + settings.format.fileExtension)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Lưu vào") {
                HStack(spacing: 6) {
                    Text(settings.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(settings.folder.path)
                    Button("Đổi…") { chooseFolder() }
                }
            }
            Picker("Định dạng", selection: $settings.format) {
                ForEach(ArchiveFormat.creatable) { format in
                    Text(formatLabel(format)).tag(format)
                }
            }
            Text(settings.format.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Mức nén", selection: $settings.level) {
                ForEach(CompressionLevel.allCases) { level in
                    Text(level.title).tag(level)
                }
            }
            .disabled(!settings.format.supportsCompressionLevel)
        }

        Section("Mật khẩu") {
            if settings.format.supportsPassword {
                Group {
                    if settings.revealPassword {
                        TextField("Mật khẩu", text: $settings.password, prompt: Text("Để trống nếu không cần"))
                    } else {
                        SecureField("Mật khẩu", text: $settings.password, prompt: Text("Để trống nếu không cần"))
                        SecureField("Nhập lại", text: $settings.confirmPassword)
                    }
                }
                Toggle("Hiện mật khẩu", isOn: $settings.revealPassword)
                if settings.format.supportsEncryptedNames {
                    Toggle("Mã hoá cả tên tệp (người khác không xem được danh sách)", isOn: $settings.encryptNames)
                        .disabled(settings.password.isEmpty)
                }
                if settings.format == .zip {
                    Picker("Kiểu mã hoá ZIP", selection: $settings.zipLegacy) {
                        Text("AES-256 (an toàn)").tag(false)
                        Text("ZipCrypto (tương thích Finder, kém an toàn)").tag(true)
                    }
                    .disabled(settings.password.isEmpty)
                }
            } else {
                Text("Định dạng \(settings.format.displayName) không hỗ trợ mật khẩu. Chọn 7Z, ZIP hoặc RAR nếu cần bảo vệ.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Tuỳ chọn") {
            if settings.format.supportsVolumes {
                Toggle("Chia thành nhiều phần", isOn: $settings.splitEnabled)
                if settings.splitEnabled {
                    Picker("Mỗi phần", selection: $settings.splitPreset) {
                        ForEach(SplitPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    if settings.splitPreset == .custom {
                        LabeledContent("Kích thước (MB)") {
                            TextField("MB", text: $settings.customSplitMB)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)
                                .labelsHidden()
                        }
                    }
                }
            }
            if settings.format.supportsSolid {
                Toggle("Nén dạng solid (tỉ lệ cao hơn, sửa đổi chậm hơn)", isOn: $settings.solid)
            }
            if settings.format == .rar {
                Toggle("Thêm bản ghi khôi phục (giúp sửa khi tệp bị hỏng)", isOn: $settings.recovery)
                Toggle("Khoá tệp nén (không cho sửa đổi sau này)", isOn: $settings.lock)
                LabeledContent("Ghi chú") {
                    TextField("Ghi chú", text: $settings.comment, prompt: Text("Không bắt buộc"))
                        .labelsHidden()
                }
            }
            Toggle("Bỏ qua tệp rác của macOS (.DS_Store, __MACOSX…)", isOn: $settings.excludeJunk)
            if showSourceOptions {
                Toggle("Kiểm tra tệp nén sau khi tạo", isOn: $settings.testAfter)
                Toggle("Chuyển tệp gốc vào Thùng rác sau khi nén", isOn: $settings.trashSources)
                if sourceCount > 1 {
                    Toggle("Nén mỗi mục thành một tệp riêng", isOn: $settings.separate)
                }
            }
        }
    }

    private func formatLabel(_ format: ArchiveFormat) -> String {
        if format == .rar && ToolLocator.shared.rar == nil { return "RAR (cần công cụ RAR)" }
        return format.displayName
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.directoryURL = settings.folder
        panel.prompt = "Chọn"
        panel.message = "Chọn nơi lưu tệp nén"
        if panel.runModal() == .OK, let url = panel.url {
            settings.folder = url
        }
    }
}

/// Màn hình "Tạo tệp nén".
@MainActor
struct CreateArchiveView: View {
    let sources: [URL]
    let onCancel: () -> Void
    let onCreate: (CreateRequest, CompressExtras) -> Void

    @State private var settings: CompressionSettings
    @State private var totals: (bytes: Int64, files: Int)? = nil

    init(sources: [URL], onCancel: @escaping () -> Void, onCreate: @escaping (CreateRequest, CompressExtras) -> Void) {
        self.sources = sources
        self.onCancel = onCancel
        self.onCreate = onCreate
        let folder = sources.first?.deletingLastPathComponent()
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        var initial = CompressionSettings(name: Workflows.suggestedName(for: sources), folder: folder)
        if !ArchiveFormat.creatable.contains(initial.format) || (initial.format == .rar && ToolLocator.shared.rar == nil) {
            initial.format = .zip
        }
        _settings = State(initialValue: initial)
    }

    private var outputExists: Bool {
        !settings.separate && FileOps.exists(settings.outputURL)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Form {
                CompressionOptionsSections(settings: $settings, showSourceOptions: true, sourceCount: sources.count)
            }
            .formStyle(.grouped)
            Divider()
            footer
        }
        .frame(width: 580, height: 680)
        .task {
            let urls = sources
            let result = await Task.detached { FileOps.totalSize(of: urls) }.value
            totals = result
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Brand.gradient)
                    .frame(width: 44, height: 44)
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Brand.glow)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Tạo tệp nén")
                    .font(.title3.weight(.semibold))
                Text(sourceSummary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private var sourceSummary: String {
        let what = sources.count == 1 ? "“\(sources[0].lastPathComponent)”" : "\(sources.count) mục"
        guard let totals else { return what + " · đang tính dung lượng…" }
        return "\(what) · \(totals.files) tệp · \(Format.bytes(totals.bytes))"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let error = settings.validationError {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .lineLimit(2)
            } else if outputExists {
                Label("“\(settings.outputURL.lastPathComponent)” đã có — tệp cũ sẽ được chuyển vào Thùng rác.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Brand.amber)
                    .font(.callout)
                    .lineLimit(2)
            }
            Spacer()
            Button("Huỷ", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("Nén") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.validationError != nil)
        }
        .padding(16)
    }

    private func create() {
        guard settings.validationError == nil else { return }
        if outputExists {
            try? FileOps.trash([settings.outputURL])
        }
        UserDefaults.standard.set(settings.format.rawValue, forKey: Prefs.defaultFormat)
        UserDefaults.standard.set(settings.level.rawValue, forKey: Prefs.defaultLevel)
        onCreate(settings.makeRequest(sources: sources), settings.extras)
    }
}

/// Bảng "Chuyển đổi định dạng" trong cửa sổ duyệt.
@MainActor
struct ConvertSheet: View {
    @ObservedObject var doc: ArchiveDocument
    @State private var settings: CompressionSettings

    init(doc: ArchiveDocument) {
        self.doc = doc
        var initial = CompressionSettings(name: ArchiveFormat.baseName(of: doc.url),
                                          folder: doc.url.deletingLastPathComponent(),
                                          format: doc.format == .sevenZip ? .zip : .sevenZip)
        initial.password = doc.password ?? ""
        initial.confirmPassword = doc.password ?? ""
        _settings = State(initialValue: initial)
    }

    private var outputExists: Bool { FileOps.exists(settings.outputURL) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 24))
                    .foregroundStyle(Brand.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chuyển đổi định dạng")
                        .font(.title3.weight(.semibold))
                    Text("“\(doc.displayName)” sẽ được giải nén tạm rồi nén lại; tệp gốc giữ nguyên.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            Form {
                CompressionOptionsSections(settings: $settings, showSourceOptions: false)
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let error = settings.validationError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(.red)
                        .font(.callout)
                } else if outputExists {
                    Label("Đã có tệp cùng tên — tệp cũ sẽ được chuyển vào Thùng rác.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Brand.amber)
                        .font(.callout)
                }
                Spacer()
                Button("Huỷ", role: .cancel) { doc.sheet = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Chuyển đổi") {
                    if outputExists { try? FileOps.trash([settings.outputURL]) }
                    let template = settings.makeRequest(sources: [])
                    doc.sheet = nil
                    doc.convert(to: template)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.validationError != nil || settings.outputURL.standardizedFileURL == doc.url.standardizedFileURL)
            }
            .padding(16)
        }
        .frame(width: 580, height: 640)
    }
}
