import SwiftUI
import AppKit

/// Tuỳ chọn giải nén — dùng cho cả bảng trong cửa sổ duyệt và cửa sổ giải nén độc lập.
@MainActor
struct ExtractOptionsView: View {
    @Binding var config: ExtractConfig
    let archiveNames: [String]
    let selectionCount: Int
    let showPasswordField: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    private var subtitle: String {
        if archiveNames.count == 1 { return archiveNames[0] }
        return "\(archiveNames.count) tệp nén"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Brand.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Giải nén")
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            Form {
                Section("Đích đến") {
                    LabeledContent("Thư mục") {
                        HStack(spacing: 6) {
                            Image(nsImage: FileIcons.folder)
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(config.baseFolder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(config.baseFolder.path)
                            Menu("Đổi") {
                                ForEach(quickFolders, id: \.url) { item in
                                    Button(item.title) { config.baseFolder = item.url }
                                }
                                Divider()
                                Button("Chọn thư mục khác…") { chooseFolder() }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    Picker("Cách đặt", selection: $config.folderMode) {
                        ForEach(ExtractFolderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(destinationHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if selectionCount > 0 {
                    Section("Phạm vi") {
                        Picker("Giải nén", selection: $config.selectionOnly) {
                            Text("Chỉ \(selectionCount) mục đang chọn").tag(true)
                            Text("Toàn bộ tệp nén").tag(false)
                        }
                        .pickerStyle(.radioGroup)
                    }
                }

                Section("Khi trùng tên") {
                    Picker("Tệp đã tồn tại", selection: $config.overwrite) {
                        ForEach(OverwriteMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                }

                if showPasswordField {
                    Section("Mật khẩu") {
                        SecureField("Mật khẩu", text: $config.password, prompt: Text("Để trống nếu chưa biết — RarX sẽ hỏi khi cần"))
                    }
                }

                Section("Sau khi xong") {
                    Toggle("Mở thư mục trong Finder", isOn: $config.openFolderAfter)
                    Toggle("Chuyển tệp nén vào Thùng rác", isOn: $config.trashArchiveAfter)
                        .disabled(config.selectionOnly && selectionCount > 0)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Huỷ", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Giải nén", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: showPasswordField ? 600 : 540)
    }

    private struct QuickFolder {
        let title: String
        let url: URL
    }

    private var quickFolders: [QuickFolder] {
        var items: [QuickFolder] = []
        let fm = FileManager.default
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            items.append(QuickFolder(title: "Màn hình nền", url: desktop))
        }
        if let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            items.append(QuickFolder(title: "Tải về", url: downloads))
        }
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            items.append(QuickFolder(title: "Tài liệu", url: documents))
        }
        return items
    }

    private var destinationHint: String {
        let name = archiveNames.count == 1 ? "“\(ArchiveFormat.baseName(of: URL(fileURLWithPath: archiveNames[0])))”" : "mang tên từng tệp nén"
        switch config.folderMode {
        case .smart:
            return "Nếu tệp nén chỉ có một mục, mục đó được đặt thẳng vào thư mục đích; nếu nhiều mục, RarX tạo thư mục \(name)."
        case .alwaysFolder:
            return "Luôn tạo thư mục \(name) bên trong thư mục đích."
        case .direct:
            return "Mọi tệp được đặt thẳng vào thư mục đích."
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = config.baseFolder
        panel.prompt = "Chọn"
        panel.message = "Chọn thư mục để giải nén vào"
        if panel.runModal() == .OK, let url = panel.url {
            config.baseFolder = url
        }
    }
}
