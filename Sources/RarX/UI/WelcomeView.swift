import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Màn hình chào: thả tệp để nén/mở, các thao tác chính và tệp gần đây.
@MainActor
struct WelcomeView: View {
    @ObservedObject var jobs: JobCenter
    @State var recents: [URL] = RecentArchives.urls
    @State var isTargeted = false
    @State var sevenZip = ToolLocator.shared.sevenZip
    @State var rar = ToolLocator.shared.rar
    @ObservedObject private var rarManager = RarToolManager.shared

    var body: some View {
        HStack(spacing: 0) {
            brandPanel
                .frame(width: 250)
            VStack(alignment: .leading, spacing: 18) {
                dropZone
                HStack(spacing: 12) {
                    ActionCard(symbol: "plus.square.on.square", title: "Tạo tệp nén", subtitle: "Chọn tệp, thư mục", shortcut: "⌘N") {
                        WindowManager.shared.chooseFilesToCompress()
                    }
                    ActionCard(symbol: "archivebox", title: "Mở tệp nén", subtitle: "Xem và lấy từng tệp", shortcut: "⌘O") {
                        WindowManager.shared.chooseArchiveToOpen()
                    }
                    ActionCard(symbol: "arrow.down.doc", title: "Giải nén", subtitle: "Một hoặc nhiều tệp", shortcut: "⌘E") {
                        WindowManager.shared.chooseArchivesToExtract()
                    }
                }
                recentSection
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .frame(width: 820, height: 530)
        // Nền xanh của cột trái kéo dài lên cả thanh tiêu đề trong suốt.
        .background(alignment: .leading) {
            Brand.gradient
                .frame(width: 250)
                .ignoresSafeArea()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recentArchivesChanged)) { _ in
            recents = RecentArchives.urls
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolsChanged)) { _ in
            sevenZip = ToolLocator.shared.sevenZip
            rar = ToolLocator.shared.rar
        }
    }

    // MARK: Cột thương hiệu

    private var brandPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            Text("RarX")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
            Text("Nén và giải nén mọi định dạng phổ biến trên Mac.")
                .font(.callout)
                .opacity(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                toolLine(ok: sevenZip != nil,
                         title: "Lõi 7-Zip",
                         detail: sevenZip == nil ? "Chưa tìm thấy — xem Cài đặt ▸ Công cụ" : "Nén, giải nén 7Z, ZIP, RAR, TAR…")
                toolLine(ok: rar != nil, title: "Công cụ RAR", detail: rarDetail)
            }

            if jobs.runningCount > 0 {
                Button {
                    WindowManager.shared.showJobs()
                } label: {
                    Label("\(jobs.runningCount) tác vụ đang chạy", systemImage: "gearshape.2.fill")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }

            Text("Phiên bản \(AppInfo.version)")
                .font(.caption)
                .opacity(0.6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var rarDetail: String {
        if rar != nil {
            let version = rarManager.installedText ?? "RAR"
            return rarManager.updateAvailable ? "\(version) — có bản mới, xem Cài đặt ▸ Công cụ" : "\(version) — tạo và sửa tệp .rar"
        }
        switch rarManager.phase {
        case .checking, .downloading, .installing: return "Đang tải và cài đặt…"
        case .failed: return "Chưa cài được — xem Cài đặt ▸ Công cụ"
        case .idle: return "Tự cài khi có mạng — chỉ cần để tạo .rar"
        }
    }

    private func toolLine(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Brand.glow : Color.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).opacity(0.75)
            }
        }
    }

    // MARK: Vùng thả tệp

    private var dropZone: some View {
        Button {
            WindowManager.shared.chooseFilesToCompress()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(isTargeted ? Brand.teal : Color.secondary)
                Text("Thả tệp vào đây")
                    .font(.title3.weight(.semibold))
                Text("Tệp hoặc thư mục → tạo tệp nén mới   ·   Tệp nén → mở ra xem")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 170)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isTargeted ? Brand.teal.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isTargeted ? Brand.teal : Color(nsColor: .separatorColor),
                                  style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: [7, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            DropLoader.loadURLs(from: providers) { urls in
                WindowManager.shared.handleOpen(urls: urls)
            }
            return true
        }
    }

    // MARK: Gần đây

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Mở gần đây")
                    .font(.headline)
                Spacer()
                if !recents.isEmpty {
                    Button("Xoá danh sách") { RecentArchives.clear() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
            }
            if recents.isEmpty {
                Text("Các tệp nén bạn mở sẽ xuất hiện ở đây.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(recents.prefix(8), id: \.self) { url in
                            RecentRow(url: url)
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

@MainActor
private struct ActionCard: View {
    let symbol: String
    let title: String
    let subtitle: String
    let shortcut: String
    let action: () -> Void
    @State var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 20))
                        .foregroundStyle(Brand.teal)
                    Spacer()
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(highlighted: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

@MainActor
private struct RecentRow: View {
    let url: URL
    @State var hovering = false

    var body: some View {
        Button {
            WindowManager.shared.openArchive(url)
        } label: {
            HStack(spacing: 10) {
                Image(nsImage: FileIcons.icon(forFile: url))
                    .resizable()
                    .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(hovering ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Mở") { WindowManager.shared.openArchive(url) }
            Button("Giải nén tại đây") { Workflows.extractHere([url]) }
            Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
