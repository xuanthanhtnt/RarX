import SwiftUI
import QuickLook
import UniformTypeIdentifiers

/// Nội dung cửa sổ duyệt một tệp nén.
@MainActor
struct ArchiveBrowserView: View {
    @ObservedObject var doc: ArchiveDocument
    @State var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            PathBar(doc: doc)
            Divider()
            if let banner = doc.banner {
                BannerView(text: banner) { doc.banner = nil }
                Divider()
            }
            HStack(spacing: 0) {
                if doc.showSidebar {
                    FolderSidebar(doc: doc)
                        .frame(width: 220)
                    Divider()
                }
                mainContent
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            StatusBar(doc: doc)
        }
        .frame(minWidth: 720, minHeight: 420)
        .sheet(item: $doc.sheet) { sheet in
            sheetContent(sheet)
        }
        .quickLookPreview($doc.quickLookURL)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch doc.state {
        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Đang đọc “\(doc.displayName)”…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .locked:
            EmptyStateView(
                symbol: "lock.doc",
                title: "Tệp nén có mật khẩu",
                message: "Nội dung của “\(doc.displayName)” được mã hoá, kể cả tên tệp. Nhập mật khẩu để xem.",
                actionTitle: "Nhập mật khẩu…",
                action: { Task { await doc.unlock() } }
            )
        case .failed(let message):
            EmptyStateView(
                symbol: "exclamationmark.triangle",
                title: "Không mở được tệp nén",
                message: message,
                actionTitle: "Thử lại",
                action: { doc.load() }
            )
        case .loaded:
            tableArea
        }
    }

    private var tableArea: some View {
        EntriesTable(doc: doc)
            .overlay {
                if doc.visibleNodes.isEmpty {
                    Text(doc.isSearching ? "Không tìm thấy mục nào" : "Thư mục trống")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if isDropTargeted && doc.canModify {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Brand.teal, style: StrokeStyle(lineWidth: 3, dash: [8, 5]))
                        .background(Brand.teal.opacity(0.06))
                        .overlay(
                            Label("Thả để thêm vào \(doc.currentPath.isEmpty ? "tệp nén" : "“\(doc.currentFolder.name)”")",
                                  systemImage: "plus.circle.fill")
                                .font(.headline)
                                .padding(10)
                                .background(.regularMaterial, in: Capsule())
                        )
                        .padding(4)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
                guard doc.canModify else { return false }
                DropLoader.loadURLs(from: providers) { urls in
                    guard !urls.isEmpty else { return }
                    doc.addFiles(urls)
                }
                return true
            }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ArchiveSheet) -> some View {
        switch sheet {
        case .extract(let selectionCount):
            ExtractSheet(doc: doc, selectionCount: selectionCount)
        case .info:
            InfoView(doc: doc)
        case .convert:
            ConvertSheet(doc: doc)
        case .testResult(let outcome):
            TestResultView(archiveName: doc.displayName, outcome: outcome) {
                doc.sheet = nil
            }
        }
    }
}

// MARK: - Bảng giải nén (trong cửa sổ duyệt)

@MainActor
struct ExtractSheet: View {
    @ObservedObject var doc: ArchiveDocument
    let selectionCount: Int
    @State var config: ExtractConfig

    init(doc: ArchiveDocument, selectionCount: Int) {
        self.doc = doc
        self.selectionCount = selectionCount
        var config = ExtractConfig.defaults(for: doc.url)
        if selectionCount > 0 {
            config.selectionOnly = true
            config.folderMode = .direct
            config.trashArchiveAfter = false
        }
        config.password = doc.password ?? ""
        _config = State(initialValue: config)
    }

    var body: some View {
        ExtractOptionsView(
            config: $config,
            archiveNames: [doc.displayName],
            selectionCount: selectionCount,
            showPasswordField: doc.hasEncryptedEntries || doc.info.headersEncrypted,
            onCancel: { doc.sheet = nil },
            onConfirm: {
                doc.sheet = nil
                doc.performExtract(config)
            }
        )
    }
}

// MARK: - Kết quả kiểm tra

@MainActor
struct TestResultView: View {
    let archiveName: String
    let outcome: TestOutcome
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: outcome.passed ? "checkmark.seal.fill" : "xmark.octagon.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(outcome.passed ? Color.green : Color.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.passed ? "Tệp nén nguyên vẹn" : "Tệp nén có lỗi")
                        .font(.title3.weight(.semibold))
                    Text(outcome.passed
                         ? "Mọi tệp trong “\(archiveName)” đều đọc được và khớp mã kiểm tra."
                         : "Một số tệp trong “\(archiveName)” bị hỏng hoặc thiếu.")
                        .foregroundStyle(.secondary)
                }
            }
            if !outcome.report.isEmpty {
                ScrollView {
                    Text(outcome.report)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(height: 200)
                .card()
            }
            HStack {
                Spacer()
                Button("Đóng", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }
}
