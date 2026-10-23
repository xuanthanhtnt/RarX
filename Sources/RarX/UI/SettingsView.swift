import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Cửa sổ Cài đặt (⌘,).
@MainActor
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Chung", systemImage: "gearshape") }
            CompressSettings()
                .tabItem { Label("Nén", systemImage: "archivebox") }
            ExtractSettings()
                .tabItem { Label("Giải nén", systemImage: "arrow.down.doc") }
            ToolsSettings()
                .tabItem { Label("Công cụ", systemImage: "wrench.and.screwdriver") }
        }
        .padding(12)
        .frame(width: 600, height: 600)
    }
}

@MainActor
private struct GeneralSettings: View {
    @AppStorage(Prefs.hideJunkInBrowser) private var hideJunk = true
    @AppStorage(Prefs.confirmDelete) private var confirmDelete = true
    @State private var defaultMessage: String? = nil

    var body: some View {
        Form {
            Section("Cửa sổ duyệt tệp nén") {
                Toggle("Ẩn tệp rác của macOS/Windows (.DS_Store, __MACOSX, Thumbs.db)", isOn: $hideJunk)
                Toggle("Hỏi lại trước khi xoá mục khỏi tệp nén", isOn: $confirmDelete)
            }
            Section("Ứng dụng mặc định") {
                Text("Mở tệp nén bằng RarX khi nhấp đúp trong Finder.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("RAR, 7Z và các định dạng khác") { setDefault(includeZip: false) }
                    Button("Cả tệp ZIP") { setDefault(includeZip: true) }
                }
                if let defaultMessage {
                    Text(defaultMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Tích hợp Finder") {
                Text("Nhấp chuột phải vào tệp trong Finder ▸ Thao tác nhanh / Dịch vụ để thấy “RarX: Nén…”, “RarX: Giải nén tại đây”… Nếu chưa thấy, bật chúng trong Cài đặt hệ thống ▸ Bàn phím ▸ Phím tắt ▸ Dịch vụ.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Mở cài đặt Phím tắt bàn phím") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func setDefault(includeZip: Bool) {
        var identifiers = ["com.rarlab.rar-archive", "org.7-zip.7-zip-archive", "public.tar-archive",
                           "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive", "org.tukaani.xz-archive",
                           "public.bzip2-archive", "com.microsoft.cab"]
        if includeZip { identifiers.append("public.zip-archive") }
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            defaultMessage = "Chỉ đặt được khi chạy bản RarX.app (tạo bằng build.sh)."
            return
        }
        let types = identifiers.compactMap { UTType($0) }
        Task { @MainActor in
            var done = 0
            for type in types {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                    done += 1
                } catch {
                    continue
                }
            }
            defaultMessage = done > 0
                ? "Đã đặt RarX làm ứng dụng mặc định cho \(done) loại tệp."
                : "macOS không cho phép thay đổi lúc này — hãy dùng Finder ▸ Lấy thông tin ▸ Mở bằng."
        }
    }
}

@MainActor
private struct CompressSettings: View {
    @AppStorage(Prefs.defaultFormat) private var format = ArchiveFormat.zip
    @AppStorage(Prefs.defaultLevel) private var level = CompressionLevel.normal
    @AppStorage(Prefs.excludeJunk) private var excludeJunk = true
    @AppStorage(Prefs.testAfterCompress) private var testAfter = false
    @AppStorage(Prefs.zipLegacyEncryption) private var zipLegacy = false
    @AppStorage(Prefs.trashSourcesAfterCompress) private var trashSources = false

    var body: some View {
        Form {
            Section("Mặc định khi tạo tệp nén") {
                Picker("Định dạng", selection: $format) {
                    ForEach(ArchiveFormat.creatable) { item in
                        Text(item.displayName).tag(item)
                    }
                }
                Picker("Mức nén", selection: $level) {
                    ForEach(CompressionLevel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("Mã hoá ZIP", selection: $zipLegacy) {
                    Text("AES-256 (an toàn)").tag(false)
                    Text("ZipCrypto (mở được bằng Finder)").tag(true)
                }
            }
            Section("Tuỳ chọn") {
                Toggle("Bỏ qua tệp rác của macOS khi nén và giải nén", isOn: $excludeJunk)
                Toggle("Kiểm tra tệp nén ngay sau khi tạo", isOn: $testAfter)
                Toggle("Chuyển tệp gốc vào Thùng rác sau khi nén", isOn: $trashSources)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
private struct ExtractSettings: View {
    @AppStorage(Prefs.extractFolderMode) private var folderMode = ExtractFolderMode.smart
    @AppStorage(Prefs.overwriteMode) private var overwrite = OverwriteMode.ask
    @AppStorage(Prefs.openFolderAfterExtract) private var openFolder = true
    @AppStorage(Prefs.trashArchiveAfterExtract) private var trashArchive = false
    @AppStorage(Prefs.extractLocation) private var location = "same"
    @AppStorage(Prefs.extractFixedFolder) private var fixedFolder = ""

    var body: some View {
        Form {
            Section("Vị trí") {
                Picker("Giải nén vào", selection: $location) {
                    Text("Cùng thư mục với tệp nén").tag("same")
                    Text("Một thư mục cố định").tag("fixed")
                }
                if location == "fixed" {
                    LabeledContent("Thư mục") {
                        HStack {
                            Text(fixedFolder.isEmpty ? "Chưa chọn" : fixedFolder.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Button("Chọn…") { chooseFolder() }
                        }
                    }
                }
                Picker("Cách đặt", selection: $folderMode) {
                    ForEach(ExtractFolderMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Picker("Khi trùng tên", selection: $overwrite) {
                    ForEach(OverwriteMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            }
            Section("Sau khi giải nén") {
                Toggle("Mở thư mục kết quả trong Finder", isOn: $openFolder)
                Toggle("Chuyển tệp nén vào Thùng rác", isOn: $trashArchive)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Chọn"
        if panel.runModal() == .OK, let url = panel.url {
            fixedFolder = url.path
        }
    }
}

@MainActor
private struct ToolsSettings: View {
    @AppStorage(ToolLocator.sevenZipPathKey) private var sevenZipPath = ""
    @AppStorage(ToolLocator.rarPathKey) private var rarPath = ""
    @AppStorage(Prefs.autoInstallRar) private var autoInstallRar = true
    @AppStorage(Prefs.autoCheckUpdates) private var autoCheckUpdates = true
    @ObservedObject private var rarManager = RarToolManager.shared
    @State private var sevenZip = ToolLocator.shared.sevenZip
    @State private var rar = ToolLocator.shared.rar
    @State private var showAdvanced = false

    var body: some View {
        Form {
            Section("7-Zip (lõi chính)") {
                statusRow(ok: sevenZip != nil,
                          text: sevenZip.map { "\($0.sourceDescription): \($0.url.path)" } ?? "Chưa tìm thấy 7zz")
                Text("RarX dùng 7-Zip (giấy phép GNU LGPL) để đọc và giải nén 7Z, ZIP, RAR, TAR, GZ, XZ, ISO, DMG, CAB… và tạo 7Z, ZIP, TAR. 7-Zip được đóng gói sẵn trong ứng dụng và cập nhật cùng RarX.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("RAR (tạo và sửa tệp .rar)") {
                statusRow(ok: rar != nil, text: rarStatusText)
                rarActionRow
                if let message = rarMessage {
                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(message.isError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Toggle("Tự cài công cụ RAR khi chưa có", isOn: $autoInstallRar)
                Toggle("Tự kiểm tra cập nhật (RAR và RarX) khi mở ứng dụng", isOn: $autoCheckUpdates)
                HStack {
                    Button("Nhập khoá bản quyền…") { importLicense() }
                    Spacer()
                    Link("Trang RARLAB", destination: URL(string: "https://www.rarlab.com/download.htm")!)
                }
                Text("RarX tải gói “RAR for macOS” chính thức của RARLAB từ rarlab.com về máy bạn (không đóng gói sẵn trong ứng dụng) và để trong thư mục riêng của RarX. Đây là bản dùng thử của RARLAB; nếu dùng lâu dài, hãy mua giấy phép tại rarlab.com rồi bấm “Nhập khoá bản quyền…” để chọn tệp rarreg.key. Giải nén .rar không cần công cụ này — 7-Zip đã đọc được.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Nâng cao: dùng công cụ ở vị trí khác", isExpanded: $showAdvanced) {
                    HStack {
                        Button("Chọn tệp rar…") { pick(\.rarPath, title: "Chọn chương trình rar") }
                        Button("Chọn tệp 7zz…") { pick(\.sevenZipPath, title: "Chọn chương trình 7zz") }
                        Button("Tự động tìm") {
                            rarPath = ""
                            sevenZipPath = ""
                            refresh()
                        }
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: .toolsChanged)) { _ in
            sevenZip = ToolLocator.shared.sevenZip
            rar = ToolLocator.shared.rar
        }
        .task {
            await rarManager.refreshInstalledVersion()
            if rarManager.remote == nil { await rarManager.checkForUpdate(silent: true) }
        }
    }

    // MARK: RAR

    private var rarStatusText: String {
        guard let rar else {
            switch rarManager.phase {
            case .checking, .downloading, .installing: return "Đang cài công cụ RAR…"
            default: return "Chưa cài — RarX vẫn xem và giải nén .rar bình thường"
            }
        }
        let version = rarManager.installedText ?? "RAR"
        let isManaged = rar.standardizedFileURL == RarPaths.managedExecutable.standardizedFileURL
        return "\(version) — \(isManaged ? "bản do RarX cài" : "đường dẫn riêng"): \(rar.path)"
    }

    private var rarMessage: (text: String, isError: Bool)? {
        if case .failed(let message) = rarManager.phase { return (message, true) }
        if let notice = rarManager.notice { return (notice, false) }
        guard let remote = rarManager.remote else { return nil }
        if rar == nil { return ("Bản mới nhất trên rarlab.com: RAR \(remote.versionText).", false) }
        if rarManager.updateAvailable { return ("Có bản mới trên rarlab.com: RAR \(remote.versionText).", false) }
        return ("Bạn đang dùng bản mới nhất trên rarlab.com (RAR \(remote.versionText)).", false)
    }

    @ViewBuilder
    private var rarActionRow: some View {
        switch rarManager.phase {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang hỏi rarlab.com…").foregroundStyle(.secondary)
            }
        case .downloading(let fraction):
            HStack(spacing: 8) {
                if fraction >= 0 { ProgressView(value: fraction).frame(maxWidth: 220) } else { ProgressView().controlSize(.small) }
                Text(fraction >= 0 ? "Đang tải… \(Int(fraction * 100))%" : "Đang tải…").foregroundStyle(.secondary)
            }
        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang cài đặt…").foregroundStyle(.secondary)
            }
        case .idle, .failed:
            HStack {
                if rar == nil {
                    Button("Cài công cụ RAR") { Task { await rarManager.installOrUpdate() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.teal)
                } else if rarManager.updateAvailable, let remote = rarManager.remote {
                    Button("Cập nhật lên RAR \(remote.versionText)") { Task { await rarManager.installOrUpdate() } }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.teal)
                } else {
                    Button("Kiểm tra cập nhật") { Task { await rarManager.checkForUpdate() } }
                    if rar != nil {
                        Button("Cài lại") { Task { await rarManager.installOrUpdate() } }
                            .help("Tải lại gói RAR mới nhất từ rarlab.com và cài đè")
                    }
                }
                Spacer()
            }
        }
    }

    private func importLicense() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Chọn tệp rarreg.key bạn nhận được từ RARLAB"
        panel.prompt = "Nhập"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try rarManager.importLicenseKey(from: url)
        } catch {
            Prompts.showMessage("Không nhập được khoá", error.localizedDescription, window: NSApp.keyWindow)
        }
    }

    private func statusRow(ok: Bool, text: String) -> some View {
        Label {
            Text(text)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
        }
    }

    private func pick(_ keyPath: ReferenceWritableKeyPath<ToolsSettingsStore, String>, title: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = title
        panel.prompt = "Chọn"
        panel.showsHiddenFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            Prompts.showMessage("Không dùng được tệp này", "“\(url.lastPathComponent)” không phải chương trình chạy được.", window: NSApp.keyWindow)
            return
        }
        ToolsSettingsStore.shared[keyPath: keyPath] = url.path
        refresh()
    }

    private func refresh() {
        ToolLocator.shared.refresh()
        sevenZip = ToolLocator.shared.sevenZip
        rar = ToolLocator.shared.rar
        NotificationCenter.default.post(name: .toolsChanged, object: nil)
        Task { await rarManager.refreshInstalledVersion() }
    }
}

/// Ghi đường dẫn công cụ vào UserDefaults (dùng chung với @AppStorage ở trên).
final class ToolsSettingsStore {
    static let shared = ToolsSettingsStore()

    var sevenZipPath: String {
        get { UserDefaults.standard.string(forKey: ToolLocator.sevenZipPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: ToolLocator.sevenZipPathKey) }
    }

    var rarPath: String {
        get { UserDefaults.standard.string(forKey: ToolLocator.rarPathKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: ToolLocator.rarPathKey) }
    }
}
