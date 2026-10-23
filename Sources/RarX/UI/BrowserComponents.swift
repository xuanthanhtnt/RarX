import SwiftUI
import AppKit

// MARK: - Ô tên tệp

@MainActor
struct NameCell: View {
    let node: ArchiveNode
    let showPath: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: FileIcons.icon(for: node))
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showPath && !node.parentPath.isEmpty {
                    Text(node.parentPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            if node.encrypted {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(Brand.amber)
                    .help("Đã mã hoá")
            }
            if node.isSymlink {
                Image(systemName: "link")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help("Liên kết tượng trưng")
            }
        }
    }
}

// MARK: - Bảng danh sách tệp

@MainActor
struct EntriesTable: View {
    @ObservedObject var doc: ArchiveDocument

    var body: some View {
        Table(of: ArchiveNode.self, selection: $doc.selection, sortOrder: $doc.sortOrder) {
            TableColumn("Tên", value: \.name) { node in
                NameCell(node: node, showPath: doc.isSearching)
            }
            .width(min: 180, ideal: 260)

            TableColumn("Kích thước", value: \.size) { node in
                SizeCell(value: node.size)
            }
            .width(min: 64, ideal: 80)

            TableColumn("Sau nén", value: \.packedSize) { node in
                SizeCell(value: node.packedSize)
            }
            .width(min: 64, ideal: 80)

            TableColumn("Tỉ lệ", value: \.ratio) { node in
                RatioCell(ratio: node.ratio)
            }
            .width(min: 40, ideal: 50)

            TableColumn("Loại", value: \.kindDescription) { node in
                Text(node.kindDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 70, ideal: 110)

            TableColumn("Ngày sửa", value: \.modifiedSortKey) { node in
                Text(Format.date(node.modified))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 120)

            TableColumn("CRC32", value: \.crc) { node in
                Text(node.crc)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 64, ideal: 76)
        } rows: {
            ForEach(doc.visibleNodes) { node in
                TableRow(node)
                    .itemProvider { doc.dragProvider(for: node) }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            EntryContextMenu(doc: doc, ids: ids)
        } primaryAction: { ids in
            doc.open(ids)
        }
    }
}

@MainActor
private struct SizeCell: View {
    let value: Int64

    var body: some View {
        Text(value >= 0 ? Format.bytes(value) : "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

@MainActor
private struct RatioCell: View {
    let ratio: Double

    var body: some View {
        Text(ratio <= 1.5 ? Format.percent(ratio * 100) : "—")
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

@MainActor
private struct EntryContextMenu: View {
    @ObservedObject var doc: ArchiveDocument
    let ids: Set<String>

    private var nodes: [ArchiveNode] { ids.compactMap { doc.index[$0] } }

    var body: some View {
        if ids.isEmpty {
            Button("Thêm tệp…") { doc.chooseFilesToAdd() }
                .disabled(!doc.canModify)
            Button("Thư mục mới…") { doc.createFolder() }
                .disabled(!doc.canModify)
            Divider()
            Button("Giải nén tất cả…") {
                doc.selection = []
                doc.presentExtract()
            }
        } else {
            Button("Mở") { doc.open(ids) }
            Button("Xem nhanh") {
                doc.selection = ids
                doc.quickLook()
            }
            .disabled(!nodes.contains { !$0.isDirectory })
            Divider()
            Button("Giải nén mục đã chọn…") {
                doc.selection = ids
                doc.presentExtract()
            }
            Button("Giải nén cạnh tệp nén") {
                doc.selection = ids
                doc.extractHere()
            }
            Divider()
            Button("Đổi tên…") {
                doc.selection = ids
                doc.renameSelection()
            }
            .disabled(!(doc.canModify && doc.format.renamable && ids.count == 1))
            Button("Xoá khỏi tệp nén…") {
                doc.selection = ids
                doc.deleteSelection()
            }
            .disabled(!doc.canModify)
            Divider()
            Button("Sao chép đường dẫn trong tệp nén") {
                let text = nodes.map(\.id).sorted().joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}

// MARK: - Thanh bên (cây thư mục)

@MainActor
struct FolderSidebar: View {
    @ObservedObject var doc: ArchiveDocument

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { doc.isSearching ? nil : doc.currentPath },
            set: { newValue in
                if let path = newValue { doc.navigate(to: path) }
            }
        )
    }

    private var topFolders: [ArchiveNode] {
        let folders = doc.root.childFolders ?? []
        return doc.hideJunk ? folders.filter { !$0.isJunk } : folders
    }

    var body: some View {
        List(selection: selectionBinding) {
            Section("Tệp nén") {
                Label(doc.displayName, systemImage: "archivebox.fill")
                    .lineLimit(1)
                    .tag("")
                OutlineGroup(topFolders, children: \.childFolders) { node in
                    Label(node.name, systemImage: "folder")
                        .lineLimit(1)
                        .tag(node.id)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Thanh đường dẫn

@MainActor
struct PathBar: View {
    @ObservedObject var doc: ArchiveDocument

    var body: some View {
        HStack(spacing: 6) {
            Button {
                doc.goUp()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!doc.canGoUp)
            .help("Lên thư mục cha (⌘↑)")

            Divider().frame(height: 14)

            if doc.isSearching {
                Label("Kết quả tìm “\(doc.searchText)” trong toàn bộ tệp nén", systemImage: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        crumb(name: doc.displayName, path: "", symbol: "archivebox.fill")
                        ForEach(Array(doc.pathComponents.enumerated()), id: \.offset) { item in
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            crumb(name: item.element.name, path: item.element.path, symbol: "folder.fill")
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    private func crumb(name: String, path: String, symbol: String) -> some View {
        Button {
            doc.navigate(to: path)
        } label: {
            Label(name, systemImage: symbol)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(path == doc.currentPath ? Color.accentColor.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Thanh trạng thái

@MainActor
struct StatusBar: View {
    @ObservedObject var doc: ArchiveDocument

    var body: some View {
        HStack(spacing: 10) {
            Text(doc.statusText)
                .lineLimit(1)
            if let reason = doc.readOnlyReason {
                Label("Chỉ đọc", systemImage: "lock")
                    .help(reason)
            }
            Spacer(minLength: 8)
            if let job = doc.activeJob {
                InlineJobView(job: job)
            } else if doc.isLoaded {
                Text(doc.totalsText)
                    .lineLimit(1)
            }
            if doc.isLoaded {
                Text(doc.formatSummary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.12)))
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 26)
    }
}

@MainActor
struct InlineJobView: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(spacing: 6) {
            switch job.state {
            case .running:
                Text(job.title + "…")
                if let progress = job.progress {
                    ProgressView(value: progress)
                        .frame(width: 110)
                    Text(Format.percent(progress * 100))
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    job.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Huỷ")
            case .succeeded(let message):
                Label(message ?? "Xong", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failed:
                Label("\(job.title) không thành công", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .cancelled:
                Label("Đã huỷ", systemImage: "xmark.circle")
            }
        }
    }
}

// MARK: - Các trạng thái đặc biệt

@MainActor
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
                .textSelection(.enabled)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
struct BannerView: View {
    let text: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Brand.amber)
            Text(text)
                .lineLimit(2)
                .font(.callout)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Brand.amber.opacity(0.12))
    }
}
