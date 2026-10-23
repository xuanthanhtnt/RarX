import Foundation

/// Một mục (tệp hoặc thư mục) bên trong tệp nén, như 7-Zip liệt kê.
struct ArchiveEntry: Sendable {
    var path: String
    var isDirectory: Bool
    var size: Int64
    var packedSize: Int64?
    var modified: Date?
    var crc: String?
    var encrypted: Bool
    var method: String?
    var attributes: String?
    var isSymlink: Bool
    var comment: String?
}

/// Thông tin chung về tệp nén.
struct ArchiveInfo: Sendable {
    var typeName: String = ""
    var physicalSize: Int64 = 0
    var method: String?
    var solid: Bool?
    var blocks: Int?
    var isMultiVolume = false
    var volumeCount: Int?
    var comment: String?
    var characteristics: String?
    var headersEncrypted = false
    var warnings: [String] = []
    /// Toàn bộ thuộc tính thô, để hiển thị trong cửa sổ Thông tin.
    var rawProperties: [(key: String, value: String)] = []
}

/// Kết quả liệt kê một tệp nén.
struct ArchiveListing: Sendable {
    var info: ArchiveInfo
    var entries: [ArchiveEntry]
}

/// Yêu cầu giải nén.
struct ExtractRequest: Sendable {
    var archive: URL
    var format: ArchiveFormat
    var password: String?
    /// Đường dẫn đầy đủ các mục cần giải nén; nil = toàn bộ.
    var items: [String]?
    /// Tiền tố thư mục cần bỏ đi (khi giải nén mục đang xem trong một thư mục con).
    var stripPrefix: String = ""
    /// Thư mục đích cuối cùng (đã tính cả thư mục con nếu có).
    var destination: URL
    var overwrite: OverwriteMode = .renameNew
    /// Bỏ thư mục __MACOSX (dữ liệu phụ của macOS) khi giải nén toàn bộ.
    var skipMacJunk = false
}

/// Yêu cầu tạo tệp nén mới.
struct CreateRequest: Sendable {
    var sources: [URL]
    var output: URL
    var format: ArchiveFormat
    var level: CompressionLevel = .normal
    var password: String = ""
    var encryptFileNames = false
    var zipLegacyEncryption = false
    /// Kích thước mỗi phần (byte); nil = không chia.
    var volumeSize: Int64?
    var solid = true
    var excludeJunk = true
    var recoveryRecord = false
    var lockArchive = false
    var comment = ""

    /// Tệp kết quả thực sự (phần đầu nếu chia nhiều phần).
    var resultURL: URL {
        guard volumeSize != nil else { return output }
        switch format {
        case .rar:
            let base = output.deletingPathExtension()
            return base.appendingPathExtension("part1").appendingPathExtension("rar")
        default:
            return output.appendingPathExtension("001")
        }
    }
}

/// Kết quả một lần giải nén.
struct ExtractOutcome: Sendable {
    var destination: URL
    var warnings: [String]
}

/// Kết quả kiểm tra tính toàn vẹn.
struct TestOutcome: Sendable {
    var passed: Bool
    var report: String
}
