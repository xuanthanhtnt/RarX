import AppKit

/// Nhận lệnh từ Finder (chuột phải ▸ Thao tác nhanh / Dịch vụ).
/// Tên các hàm phải khớp với khoá NSMessage trong Info.plist.
@MainActor
final class ServiceProvider: NSObject {
    private func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]) ?? []
    }

    /// RarX: Nén… (mở cửa sổ tuỳ chọn)
    @objc func compressFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        WindowManager.shared.showCreate(sources: urls)
    }

    /// RarX: Nén nhanh thành .zip
    @objc func quickZip(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard)
        guard !urls.isEmpty else { return }
        Workflows.quickZip(urls)
    }

    /// RarX: Giải nén tại đây
    @objc func extractHere(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard).filter(ArchiveFormat.isArchive)
        guard !urls.isEmpty else { return }
        Workflows.extractHere(urls)
    }

    /// RarX: Giải nén vào thư mục riêng
    @objc func extractToFolder(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard).filter(ArchiveFormat.isArchive)
        guard !urls.isEmpty else { return }
        Workflows.extractToOwnFolder(urls)
    }

    /// RarX: Giải nén… (chọn nơi lưu, mật khẩu…)
    @objc func extractWithOptions(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard).filter(ArchiveFormat.isArchive)
        guard !urls.isEmpty else { return }
        WindowManager.shared.showExtract(archives: urls)
    }

    /// RarX: Mã kiểm tra (SHA-256…)
    @objc func checksumFiles(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let urls = fileURLs(from: pasteboard).filter { !FileOps.isDirectory($0) }
        guard !urls.isEmpty else { return }
        WindowManager.shared.showChecksum(files: urls)
    }
}
