import Foundation

/// Các định dạng tệp nén RarX nhận biết.
enum ArchiveFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case sevenZip = "7z"
    case zip
    case rar
    case tar
    case tarGz = "tar.gz"
    case tarBz2 = "tar.bz2"
    case tarXz = "tar.xz"
    case tarZst = "tar.zst"
    case gzip = "gz"
    case bzip2 = "bz2"
    case xz
    case zstd = "zst"
    case iso
    case dmg
    case cab
    case wim
    case other

    var id: String { rawValue }

    /// Định dạng có thể tạo mới (RAR cần công cụ RAR chính chủ).
    static let creatable: [ArchiveFormat] = [.sevenZip, .zip, .rar, .tar, .tarGz, .tarXz, .tarBz2]

    var displayName: String {
        switch self {
        case .sevenZip: return "7Z"
        case .zip: return "ZIP"
        case .rar: return "RAR"
        case .tar: return "TAR"
        case .tarGz: return "TAR.GZ"
        case .tarBz2: return "TAR.BZ2"
        case .tarXz: return "TAR.XZ"
        case .tarZst: return "TAR.ZST"
        case .gzip: return "GZIP"
        case .bzip2: return "BZIP2"
        case .xz: return "XZ"
        case .zstd: return "ZSTD"
        case .iso: return "ISO"
        case .dmg: return "DMG"
        case .cab: return "CAB"
        case .wim: return "WIM"
        case .other: return "Tệp nén"
        }
    }

    /// Mô tả ngắn hiển thị khi chọn định dạng để nén.
    var blurb: String {
        switch self {
        case .sevenZip: return "Tỉ lệ nén cao nhất, mã hoá AES-256, có thể ẩn cả tên tệp."
        case .zip: return "Phổ biến nhất — mở được trên mọi máy Mac, Windows, điện thoại."
        case .rar: return "Có bản ghi khôi phục, khoá tệp nén. Cần công cụ RAR của RARLAB."
        case .tar: return "Gom tệp, không nén. Giữ nguyên quyền truy cập Unix."
        case .tarGz: return "Chuẩn trên Linux/macOS, nén nhanh."
        case .tarXz: return "Nén mạnh hơn tar.gz, chậm hơn."
        case .tarBz2: return "Định dạng cũ, tương thích rộng."
        default: return ""
        }
    }

    /// Phần mở rộng dùng khi tạo tệp.
    var fileExtension: String {
        switch self {
        case .other: return "7z"
        default: return rawValue
        }
    }

    /// tar được bọc trong một lớp nén (gz/bz2/xz/zst).
    var isCompressedTar: Bool {
        [.tarGz, .tarBz2, .tarXz, .tarZst].contains(self)
    }

    /// Kiểu `-t` của 7-Zip cho lớp nén ngoài của tar.
    var outerStreamType: String? {
        switch self {
        case .tarGz: return "gzip"
        case .tarBz2: return "bzip2"
        case .tarXz: return "xz"
        case .tarZst: return "zstd"
        default: return nil
        }
    }

    /// Kiểu `-t` của 7-Zip khi tạo/sửa.
    var sevenZipType: String? {
        switch self {
        case .sevenZip: return "7z"
        case .zip: return "zip"
        case .tar: return "tar"
        case .wim: return "wim"
        default: return nil
        }
    }

    var supportsPassword: Bool { [.sevenZip, .zip, .rar].contains(self) }
    var supportsEncryptedNames: Bool { [.sevenZip, .rar].contains(self) }
    var supportsSolid: Bool { [.sevenZip, .rar].contains(self) }
    var supportsVolumes: Bool { [.sevenZip, .zip, .rar].contains(self) }
    var supportsCompressionLevel: Bool { self != .tar }

    /// Sửa (thêm/xoá) được bằng 7-Zip.
    var modifiableBySevenZip: Bool { [.sevenZip, .zip, .tar, .wim].contains(self) }
    /// Đổi tên mục bên trong được (7-Zip hỗ trợ lệnh rn cho các định dạng này).
    var renamable: Bool { [.sevenZip, .zip, .tar, .wim].contains(self) }

    // MARK: - Nhận diện

    /// Kết quả nhận diện một tệp.
    struct Detection: Sendable {
        var format: ArchiveFormat
        var isMultiVolume: Bool
        /// Tệp nên mở (phần đầu tiên nếu là tệp chia nhiều phần).
        var primaryURL: URL
    }

    private static let simpleExtensions: [String: ArchiveFormat] = [
        "7z": .sevenZip,
        "zip": .zip, "zipx": .zip, "cbz": .zip,
        "rar": .rar, "cbr": .rar,
        "tar": .tar,
        "tgz": .tarGz, "taz": .tarGz,
        "tbz": .tarBz2, "tbz2": .tarBz2, "tb2": .tarBz2,
        "txz": .tarXz,
        "tzst": .tarZst,
        "iso": .iso,
        "dmg": .dmg,
        "cab": .cab,
        "wim": .wim, "swm": .wim, "esd": .wim,
        "arj": .other, "lzh": .other, "lha": .other, "cpio": .other, "rpm": .other,
        "deb": .other, "xar": .other, "lzma": .other, "z": .other, "cb7": .sevenZip,
    ]

    /// Nhận diện theo tên tệp. Trả về nil nếu không phải tệp nén quen thuộc.
    static func detect(_ url: URL) -> Detection? {
        let name = url.lastPathComponent.lowercased()
        let ext = url.pathExtension.lowercased()

        // Tệp chia phần dạng .001, .002 … (tên.7z.001, tên.zip.001)
        if ext.count == 3, ext.allSatisfy(\.isNumber) {
            let inner = url.deletingPathExtension()
            let innerFormat = detect(inner)?.format ?? .other
            let first = inner.appendingPathExtension("001")
            let primary = FileManager.default.fileExists(atPath: first.path) ? first : url
            return Detection(format: innerFormat, isMultiVolume: true, primaryURL: primary)
        }

        // RAR nhiều phần: tên.part1.rar, tên.part02.rar
        if ext == "rar", let match = name.range(of: #"\.part(\d+)\.rar$"#, options: .regularExpression) {
            let digits = name[match].filter(\.isNumber)
            let firstDigits = String(repeating: "0", count: max(0, digits.count - 1)) + "1"
            let baseName = String(url.lastPathComponent.dropLast(name.distance(from: match.lowerBound, to: name.endIndex)))
            let first = url.deletingLastPathComponent().appendingPathComponent("\(baseName).part\(firstDigits).rar")
            let primary = FileManager.default.fileExists(atPath: first.path) ? first : url
            return Detection(format: .rar, isMultiVolume: true, primaryURL: primary)
        }

        switch ext {
        case "gz":
            return Detection(format: name.hasSuffix(".tar.gz") ? .tarGz : .gzip, isMultiVolume: false, primaryURL: url)
        case "bz2":
            return Detection(format: name.hasSuffix(".tar.bz2") ? .tarBz2 : .bzip2, isMultiVolume: false, primaryURL: url)
        case "xz":
            return Detection(format: name.hasSuffix(".tar.xz") ? .tarXz : .xz, isMultiVolume: false, primaryURL: url)
        case "zst":
            return Detection(format: name.hasSuffix(".tar.zst") ? .tarZst : .zstd, isMultiVolume: false, primaryURL: url)
        default:
            break
        }

        if let format = simpleExtensions[ext] {
            return Detection(format: format, isMultiVolume: false, primaryURL: url)
        }
        return nil
    }

    /// Nhận diện bằng "chữ ký" đầu tệp khi phần mở rộng không rõ.
    static func sniff(_ url: URL) -> ArchiveFormat? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8), head.count >= 4 else { return nil }
        let bytes = [UInt8](head)
        if bytes.starts(with: [0x37, 0x7A, 0xBC, 0xAF]) { return .sevenZip }
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) || bytes.starts(with: [0x50, 0x4B, 0x05, 0x06]) { return .zip }
        if bytes.starts(with: [0x52, 0x61, 0x72, 0x21]) { return .rar }
        if bytes.starts(with: [0x1F, 0x8B]) { return .gzip }
        if bytes.starts(with: [0x42, 0x5A, 0x68]) { return .bzip2 }
        if bytes.starts(with: [0xFD, 0x37, 0x7A, 0x58]) { return .xz }
        return nil
    }

    /// Có phải tệp nén (theo tên) không.
    static func isArchive(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue { return false }
        return detect(url) != nil
    }

    /// Tên gốc của tệp nén, bỏ các đuôi: "anh.tar.gz" → "anh", "phim.part1.rar" → "phim".
    static func baseName(of url: URL) -> String {
        var name = url.lastPathComponent
        let patterns = [
            #"\.part\d+\.rar$"#,
            #"\.(7z|zip|rar|tar)\.\d{3}$"#,
            #"\.\d{3}$"#,
            #"\.tar\.(gz|bz2|xz|zst)$"#,
        ]
        for pattern in patterns {
            if let range = name.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                name.removeSubrange(range)
                return name.isEmpty ? "Giải nén" : name
            }
        }
        let stripped = (name as NSString).deletingPathExtension
        return stripped.isEmpty ? "Giải nén" : stripped
    }

    /// Tất cả các phần của một tệp nén chia nhiều phần (để chuyển vào Thùng rác).
    static func volumeSiblings(of url: URL) -> [URL] {
        guard let detection = detect(url), detection.isMultiVolume else { return [url] }
        let folder = url.deletingLastPathComponent()
        let name = url.lastPathComponent
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return [url] }
        var prefix: String
        var pattern: String
        if let range = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) {
            prefix = String(name[..<range.lowerBound])
            pattern = #"^\.part\d+\.rar$"#
        } else {
            prefix = (name as NSString).deletingPathExtension
            pattern = #"^\.\d{3}$"#
        }
        let matches = items.filter { item in
            guard item.hasPrefix(prefix) else { return false }
            let rest = String(item.dropFirst(prefix.count))
            return rest.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let urls = matches.map { folder.appendingPathComponent($0) }
        return urls.isEmpty ? [url] : urls
    }
}

/// Mức nén chung, ánh xạ sang tham số của 7-Zip và RAR.
enum CompressionLevel: Int, CaseIterable, Identifiable, Codable, Sendable {
    case store = 0, fastest, fast, normal, maximum, ultra

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .store: return "Chỉ lưu (không nén)"
        case .fastest: return "Nhanh nhất"
        case .fast: return "Nhanh"
        case .normal: return "Bình thường"
        case .maximum: return "Tối đa"
        case .ultra: return "Siêu nén"
        }
    }

    /// Giá trị -mx của 7-Zip.
    var sevenZipValue: Int {
        switch self {
        case .store: return 0
        case .fastest: return 1
        case .fast: return 3
        case .normal: return 5
        case .maximum: return 7
        case .ultra: return 9
        }
    }

    /// Giá trị -mx cho lớp nén gz/bz2/xz (không có chế độ "chỉ lưu").
    var streamValue: Int { max(1, sevenZipValue) }

    /// Giá trị -m của RAR (0…5).
    var rarValue: Int { rawValue }
}

/// Cách xử lý khi tệp giải nén trùng tên với tệp đã có.
enum OverwriteMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case ask, overwrite, skip, renameNew, renameExisting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "Hỏi tôi"
        case .overwrite: return "Ghi đè"
        case .skip: return "Bỏ qua tệp đã có"
        case .renameNew: return "Giữ cả hai (đổi tên tệp mới)"
        case .renameExisting: return "Giữ cả hai (đổi tên tệp cũ)"
        }
    }

    /// Tham số -ao của 7-Zip.
    var sevenZipSwitch: String {
        switch self {
        case .ask, .overwrite: return "-aoa"
        case .skip: return "-aos"
        case .renameNew: return "-aou"
        case .renameExisting: return "-aot"
        }
    }
}

/// Cách đặt thư mục khi giải nén.
enum ExtractFolderMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case smart, alwaysFolder, direct

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Tự tạo thư mục riêng khi cần"
        case .alwaysFolder: return "Luôn tạo thư mục mang tên tệp nén"
        case .direct: return "Giải nén thẳng vào thư mục đích"
        }
    }
}
