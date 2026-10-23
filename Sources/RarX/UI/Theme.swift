import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Bảng màu nhận diện của RarX — khớp biểu tượng ứng dụng (nền than xanh, ánh sáng cyan).
enum Brand {
    static let deep = Color(red: 0.03, green: 0.09, blue: 0.12)      // than xanh đậm
    static let panel = Color(red: 0.09, green: 0.27, blue: 0.32)     // nền cột thương hiệu (phía trên)
    static let teal = Color(red: 0.05, green: 0.56, blue: 0.62)      // nhấn chính (xanh cyan)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)     // hổ phách (cảnh báo)
    static let glow = Color(red: 0.55, green: 0.92, blue: 0.96)      // cyan sáng cho chữ/biểu tượng trên nền tối

    static var gradient: LinearGradient {
        LinearGradient(colors: [panel, deep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Định dạng số liệu hiển thị.
enum Format {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    static func bytes(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    static func date(_ value: Date?) -> String {
        guard let value else { return "" }
        return dateFormatter.string(from: value)
    }

    static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }
}

/// Biểu tượng tệp theo phần mở rộng (lấy từ hệ thống, có bộ nhớ đệm).
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for node: ArchiveNode) -> NSImage {
        if node.isDirectory { return folder }
        return icon(forExtension: node.fileExtension)
    }

    static var folder: NSImage {
        if let cached = cache["/folder"] { return cached }
        let image = NSWorkspace.shared.icon(for: .folder)
        cache["/folder"] = image
        return image
    }

    static func icon(forExtension ext: String) -> NSImage {
        if let cached = cache[ext] { return cached }
        let type = ext.isEmpty ? UTType.data : (UTType(filenameExtension: ext) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        cache[ext] = image
        return image
    }

    static func icon(forFile url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }
}

/// Nền "thẻ" mềm dùng ở màn hình chào và các bảng.
struct CardBackground: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(highlighted ? Brand.teal : Color(nsColor: .separatorColor), lineWidth: highlighted ? 2 : 1)
            )
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View {
        modifier(CardBackground(highlighted: highlighted))
    }
}

/// Tải URL tệp từ các NSItemProvider khi người dùng thả tệp vào.
enum DropLoader {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collector = URLCollector()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL { collector.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collector.urls
            Task { @MainActor in completion(urls) }
        }
    }

    private final class URLCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [URL] = []
        func append(_ url: URL) {
            lock.lock()
            storage.append(url)
            lock.unlock()
        }
        var urls: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }
}
