import Foundation

enum ConsoleText {
    /// Mô phỏng một màn hình terminal đơn giản để bỏ các ký tự lùi (\b) và \r
    /// mà 7-Zip/RAR dùng khi in phần trăm tiến độ.
    static func clean(_ raw: String) -> String {
        var lines: [String] = []
        var line: [Character] = []
        var cursor = 0
        for character in raw {
            switch character {
            case "\u{8}":
                cursor = max(0, cursor - 1)
            case "\r":
                cursor = 0
            case "\n", "\r\n":
                lines.append(String(line))
                line.removeAll(keepingCapacity: true)
                cursor = 0
            default:
                if cursor < line.count {
                    line[cursor] = character
                } else {
                    line.append(character)
                }
                cursor += 1
            }
        }
        if !line.isEmpty { lines.append(String(line)) }
        return lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isProgressNoise($0) }
            .joined(separator: "\n")
    }

    private static func isProgressNoise(_ line: String) -> Bool {
        line.range(of: #"^\d{1,3}%( .*)?$"#, options: .regularExpression) != nil
            || line.range(of: #"^\d+M Scan"#, options: .regularExpression) != nil
            || (line.hasPrefix("7-Zip") && line.contains("Copyright"))
            || line.hasPrefix("64-bit ") || line.hasPrefix("32-bit ") || line.hasPrefix("OPEN_MAX:")
    }

    /// Lấy các dòng lỗi/cảnh báo quan trọng để báo cho người dùng.
    static func errorSummary(_ raw: String, limit: Int = 8) -> String {
        let text = clean(raw)
        let lines = text.components(separatedBy: "\n")
        var picked: [String] = []
        for line in lines {
            let lower = line.lowercased()
            if lower.contains("error") || lower.contains("warning") || lower.contains("cannot")
                || lower.contains("can not") || lower.contains("unexpected") || lower.contains("not enough") {
                if !picked.contains(line) { picked.append(line) }
            }
            if picked.count >= limit { break }
        }
        if picked.isEmpty {
            picked = Array(lines.suffix(5))
        }
        return picked.joined(separator: "\n")
    }
}

/// Đọc phần trăm tiến độ từ luồng đầu ra (dạng " 45%").
final class PercentParser: @unchecked Sendable {
    private static let regex = try! NSRegularExpression(pattern: #"(\d{1,3})%"#)
    private let lock = NSLock()
    private var tail = ""
    private var lastReported: Double = -1
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func feed(_ data: Data) {
        let chunk = String(decoding: data, as: UTF8.self)
        lock.lock()
        let text = tail + chunk
        tail = String(text.suffix(12))
        var latest: Double?
        let range = NSRange(text.startIndex..., in: text)
        Self.regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match, let numberRange = Range(match.range(at: 1), in: text),
                  let value = Double(text[numberRange]), value <= 100 else { return }
            latest = value / 100
        }
        var shouldReport = false
        if let latest, abs(latest - lastReported) >= 0.004 {
            lastReported = latest
            shouldReport = true
        }
        lock.unlock()
        if shouldReport, let latest { onProgress(latest) }
    }
}
