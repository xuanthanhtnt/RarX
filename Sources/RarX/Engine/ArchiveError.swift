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
        default:
            return nil
        }
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
