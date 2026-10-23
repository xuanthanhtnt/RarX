import SwiftUI
import AppKit

/// Thông tin chi tiết về tệp nén.
@MainActor
struct InfoView: View {
    @ObservedObject var doc: ArchiveDocument
    @State private var comment: String
    @State private var tab = 0

    init(doc: ArchiveDocument) {
        self.doc = doc
        _comment = State(initialValue: doc.info.comment ?? "")
    }

    private var canEditComment: Bool { doc.format == .rar && doc.canModify }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: FileIcons.icon(forFile: doc.url))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.displayName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(doc.formatSummary)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(20)

            Picker("", selection: $tab) {
                Text("Tổng quan").tag(0)
                Text("Ghi chú").tag(1)
                Text("Chi tiết kỹ thuật").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)

            Group {
                switch tab {
                case 0: overview
                case 1: commentTab
                default: technical
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            HStack {
                Button("Hiện trong Finder") { doc.revealInFinder() }
                Spacer()
                Button("Đóng") { doc.sheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 540, height: 520)
    }

    private var overview: some View {
        Form {
            Section {
                row("Vị trí", doc.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                row("Định dạng", doc.info.typeName.isEmpty ? doc.format.displayName : doc.info.typeName.uppercased())
                if let method = doc.info.method { row("Phương thức nén", method) }
                row("Nén solid", doc.info.solid == true ? "Có" : "Không")
                row("Mã hoá", encryptionText)
                if doc.isMultiVolume || doc.info.isMultiVolume {
                    row("Nhiều phần", doc.info.volumeCount.map { "\($0) phần" } ?? "Có")
                }
                if let characteristics = doc.info.characteristics { row("Đặc tính", characteristics) }
            }
            Section {
                row("Số tệp", "\(doc.root.fileCount)")
                row("Số thư mục", "\(doc.root.folderCount)")
                row("Dung lượng gốc", Format.bytes(doc.root.size))
                row("Dung lượng tệp nén", Format.bytes(doc.info.physicalSize))
                row("Tỉ lệ nén", ratioText)
                row("Ngày sửa", Format.date(modificationDate))
            }
            if let reason = doc.readOnlyReason {
                Section {
                    Label(reason, systemImage: "lock")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var commentTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canEditComment {
                TextEditor(text: $comment)
                    .font(.system(.body, design: .monospaced))
                    .card()
                HStack {
                    Text("Ghi chú được lưu bên trong tệp RAR và hiển thị cho người mở tệp.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Lưu ghi chú") {
                        doc.saveComment(comment)
                        doc.sheet = nil
                    }
                }
            } else if let existing = doc.info.comment, !existing.isEmpty {
                ScrollView {
                    Text(existing)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .card()
            } else {
                EmptyStateView(symbol: "text.bubble", title: "Không có ghi chú",
                               message: doc.format == .rar
                                ? "Cần công cụ RAR để thêm ghi chú cho tệp .rar."
                                : "Chỉ tệp RAR hỗ trợ sửa ghi chú trong RarX.")
            }
        }
        .padding(20)
    }

    private var technical: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(doc.info.rawProperties.enumerated()), id: \.offset) { item in
                    HStack(alignment: .top) {
                        Text(item.element.key)
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .trailing)
                        Text(item.element.value)
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .font(.system(.callout, design: .monospaced))
                }
                if !doc.info.warnings.isEmpty {
                    Divider().padding(.vertical, 6)
                    ForEach(doc.info.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Brand.amber)
                    }
                }
            }
            .padding(20)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private var encryptionText: String {
        if doc.info.headersEncrypted { return "Mã hoá cả tên tệp" }
        if doc.hasEncryptedEntries { return "Mã hoá nội dung tệp" }
        return "Không"
    }

    private var ratioText: String {
        guard doc.root.size > 0 else { return "—" }
        let ratio = Double(doc.info.physicalSize) / Double(doc.root.size) * 100
        return ratio <= 150 ? Format.percent(ratio) : "Tệp nén lớn hơn dữ liệu gốc (dữ liệu quá nhỏ)"
    }

    private var modificationDate: Date? {
        (try? doc.url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
