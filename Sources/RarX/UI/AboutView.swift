import SwiftUI
import AppKit

/// Cửa sổ “Giới thiệu RarX”: phiên bản, cập nhật từ GitHub, thông tin nhà phát triển và ghi công.
@MainActor
struct AboutView: View {
    @ObservedObject private var updater = AppUpdater.shared
    @AppStorage(Prefs.autoCheckUpdates) private var autoCheck = true

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    updateCard
                    developerCard
                    creditsCard
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            // Mở cửa sổ lần đầu thì tự kiểm tra một lần.
            if updater.phase == .idle { await updater.check() }
        }
    }

    // MARK: Đầu trang

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .shadow(color: .black.opacity(0.35), radius: 10, y: 5)
            Text(AppInfo.name)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
            Text(versionLine)
                .font(.callout)
                .opacity(0.8)
            Text("Trình nén và giải nén cho macOS")
                .font(.caption)
                .opacity(0.65)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .background(Brand.gradient)
    }

    private var versionLine: String {
        let build = AppInfo.build
        return build.isEmpty ? "Phiên bản \(AppInfo.version)" : "Phiên bản \(AppInfo.version) (bản dựng \(build))"
    }

    // MARK: Cập nhật

    private var updateCard: some View {
        Card(title: "Cập nhật", symbol: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    statusIcon
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusTitle).font(.headline)
                        Text(statusDetail)
                            .font(.callout)
                            .foregroundStyle(statusIsError ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    primaryButton
                }

                if case .downloading(let fraction) = updater.phase {
                    if fraction >= 0 {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                } else if case .installing = updater.phase {
                    ProgressView().progressViewStyle(.linear)
                }

                if case .available = updater.phase, let release = updater.release {
                    if !release.notes.isEmpty {
                        ScrollView {
                            Text(release.notes)
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(height: 110)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
                    }
                    HStack {
                        Button("Xem trên GitHub") { NSWorkspace.shared.open(release.pageURL) }
                        Button("Bỏ qua bản này") { updater.skipCurrentRelease() }
                        Spacer()
                    }
                    .controlSize(.small)
                }

                Toggle("Tự động kiểm tra cập nhật khi mở RarX", isOn: $autoCheck)
                    .font(.callout)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch updater.phase {
        case .checking:
            ProgressView().controlSize(.small).frame(width: 26)
        case .available:
            Image(systemName: "arrow.down.circle.fill").font(.title).foregroundStyle(Brand.teal).frame(width: 26)
        case .downloading, .installing:
            Image(systemName: "arrow.down.circle").font(.title).foregroundStyle(Brand.teal).frame(width: 26)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").font(.title).foregroundStyle(Brand.amber).frame(width: 26)
        case .upToDate:
            Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green).frame(width: 26)
        case .idle:
            Image(systemName: "questionmark.circle").font(.title).foregroundStyle(.secondary).frame(width: 26)
        }
    }

    private var statusTitle: String {
        switch updater.phase {
        case .idle: return "Chưa kiểm tra"
        case .checking: return "Đang kiểm tra trên GitHub…"
        case .upToDate: return "RarX đã là bản mới nhất"
        case .available:
            if let release = updater.release { return "Có phiên bản mới: \(release.version)" }
            return "Có phiên bản mới"
        case .downloading(let fraction):
            return fraction >= 0 ? "Đang tải bản mới… \(Int(fraction * 100))%" : "Đang tải bản mới…"
        case .installing: return "Đang cài đặt…"
        case .failed: return "Không cập nhật được"
        }
    }

    private var statusDetail: String {
        switch updater.phase {
        case .idle:
            return "Bạn đang dùng bản \(AppInfo.version)."
        case .checking:
            return "Bản đang dùng: \(AppInfo.version)."
        case .upToDate:
            if let checked = updater.lastChecked {
                return "Bản \(AppInfo.version) · kiểm tra lúc \(checked.formatted(date: .omitted, time: .shortened))."
            }
            return "Bản \(AppInfo.version)."
        case .available:
            var text = "Bạn đang dùng \(AppInfo.version)."
            if let release = updater.release {
                if let date = release.publishedAt { text += " Phát hành \(date.formatted(date: .abbreviated, time: .omitted))." }
                if release.assetSize > 0 { text += " Gói \(Format.bytes(release.assetSize))." }
            }
            return text
        case .downloading:
            return "Sau khi tải xong, RarX sẽ tự thay bản cũ và khởi động lại."
        case .installing:
            return "RarX sẽ tự đóng và mở lại trong giây lát."
        case .failed(let message):
            return message
        }
    }

    private var statusIsError: Bool {
        if case .failed = updater.phase { return true }
        return false
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch updater.phase {
        case .available:
            Button("Cập nhật ngay") { Task { await updater.installUpdate() } }
                .buttonStyle(.borderedProminent)
                .tint(Brand.teal)
        case .checking, .downloading, .installing:
            EmptyView()
        case .failed:
            Button("Thử lại") { Task { await updater.check() } }
        case .idle, .upToDate:
            Button("Kiểm tra ngay") { Task { await updater.check() } }
        }
    }

    // MARK: Nhà phát triển

    private var developerCard: some View {
        Card(title: "Nhà phát triển", symbol: "person.crop.circle") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppInfo.developer).font(.headline)
                    Spacer()
                }
                LinkRow(symbol: "chevron.left.forwardslash.chevron.right", title: "Mã nguồn và các bản phát hành", url: AppInfo.repositoryURL)
                LinkRow(symbol: "person", title: "Trang GitHub của nhà phát triển", url: AppInfo.developerURL)
                LinkRow(symbol: "ladybug", title: "Báo lỗi hoặc góp ý", url: AppInfo.issuesURL)
            }
        }
    }

    // MARK: Ghi công

    private var creditsCard: some View {
        Card(title: "Thành phần và bản quyền", symbol: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                Text("**7-Zip** © Igor Pavlov — GNU LGPL, kèm giới hạn unRAR. Lõi nén và giải nén của RarX.")
                    .font(.callout)
                Text("**RAR** © Alexander Roshal / RARLAB. RarX gọi công cụ dòng lệnh `rar` chính thức do RARLAB phát hành (tải từ rarlab.com) để tạo và sửa tệp .rar.")
                    .font(.callout)
                Text("RarX là ứng dụng độc lập, không liên kết với RARLAB hay WinRAR.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Link("7-zip.org", destination: URL(string: "https://www.7-zip.org")!)
                    Link("rarlab.com", destination: URL(string: "https://www.rarlab.com")!)
                }
                .font(.callout)
            }
        }
    }
}

/// Khung nhóm có tiêu đề cho cửa sổ Giới thiệu.
private struct Card<Content: View>: View {
    let title: String
    let symbol: String
    let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.7))
        )
    }
}

private struct LinkRow: View {
    let symbol: String
    let title: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 18).foregroundStyle(Brand.teal)
                Text(title)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
    }
}
