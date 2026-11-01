import Foundation

/// Lỗi chung cho mọi thao tác với tệp nén.
enum ArchiveError: LocalizedError, Equatable {
    case toolMissing(String)
    case launchFailed(String)
    case passwordRequired
    case wrongPassword
    case notAnArchive
    case corrupted(String)
    case diskFull
    /// macOS (Quyền riêng tư ▸ Tệp và thư mục) chặn đọc/ghi đường dẫn này.
    case permissionDenied(String)
    case cancelled
    case unsupported(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .toolMissing(let name):
            return "Không tìm thấy \(name)."
        case .launchFailed(let detail):
            return "Không chạy được công cụ nén: \(detail)"
        case .passwordRequired:
            return "Tệp nén này được bảo vệ bằng mật khẩu."
        case .wrongPassword:
            return "Mật khẩu không đúng."
        case .notAnArchive:
            return "Không mở được tệp này như một tệp nén (định dạng không hỗ trợ hoặc tệp đã hỏng)."
        case .corrupted(let detail):
            return detail.isEmpty ? "Tệp nén bị hỏng hoặc không đầy đủ." : "Tệp nén bị hỏng hoặc không đầy đủ:\n\(detail)"
        case .diskFull:
            return "Ổ đĩa không còn đủ dung lượng."
        case .permissionDenied(let path):
            return path.isEmpty
                ? "macOS chưa cho phép RarX truy cập tệp hoặc thư mục này."
                : "macOS chưa cho phép RarX truy cập thư mục “\(Self.protectedFolderName(for: path))”."
        case .cancelled:
            return "Đã huỷ."
        case .unsupported(let detail):
            return detail
        case .failed(let detail):
            return detail.isEmpty ? "Thao tác không thành công." : detail
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .toolMissing(let name) where name.contains("RAR"):
            return "Mở Cài đặt ▸ Công cụ và bấm “Cài công cụ RAR” — RarX sẽ tải bản chính thức từ rarlab.com."
        case .toolMissing:
            return "Chạy lại ./build.sh để đóng gói 7-Zip vào ứng dụng, hoặc cài bằng Homebrew: brew install sevenzip."
        case .corrupted:
            return "Thử tải lại tệp, hoặc dùng Công cụ ▸ Sửa tệp nén (với .rar/.zip)."
        case .permissionDenied:
            return "Mở Cài đặt hệ thống ▸ Quyền riêng tư & Bảo mật ▸ Tệp và thư mục, bật thư mục này cho RarX "
                + "(hoặc thêm RarX vào Truy cập toàn bộ ổ đĩa), rồi thử lại."
        default:
            return nil
        }
    }

    /// Thư mục được macOS bảo vệ chứa `path` (Tải về, Màn hình nền, Tài liệu, ổ đĩa ngoài…),
    /// để người dùng biết cần bật mục nào trong Cài đặt.
    private static func protectedFolderName(for path: String) -> String {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        for name in ["Downloads", "Desktop", "Documents"] {
            let folder = home.appendingPathComponent(name).path
            if path == folder || path.hasPrefix(folder + "/") { return fileManager.displayName(atPath: folder) }
        }
        let parts = path.split(separator: "/")
        if parts.count > 1 && parts[0] == "Volumes" { return String(parts[1]) }
        return fileManager.displayName(atPath: (path as NSString).deletingLastPathComponent)
    }

    var isPasswordProblem: Bool {
        self == .passwordRequired || self == .wrongPassword
    }
}

extension Error {
    /// Thông điệp thân thiện để hiển thị cho người dùng.
    var userMessage: String {
        if let archiveError = self as? ArchiveError {
            var text = archiveError.errorDescription ?? "Đã xảy ra lỗi."
            if let hint = archiveError.recoverySuggestion { text += "\n\n" + hint }
            return text
        }
        if self is CancellationError { return "Đã huỷ." }
        return (self as NSError).localizedDescription
    }

    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let archiveError = self as? ArchiveError, archiveError == .cancelled { return true }
        return false
    }
}
