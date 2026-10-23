import Foundation

/// Thông tin ứng dụng và nhà phát triển.
/// Muốn đổi tên/liên kết hiển thị trong cửa sổ “Giới thiệu”, hoặc trỏ cập nhật sang kho GitHub khác, hãy sửa tại đây.
enum AppInfo {
    static let name = "RarX"
    static let developer = "xuanthanhtnt"
    static let githubOwner = "xuanthanhtnt"
    static let githubRepo = "RarX"

    static var repositoryURL: URL { URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")! }
    static var releasesPageURL: URL { URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/releases")! }
    static var issuesURL: URL { URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/issues")! }
    static var developerURL: URL { URL(string: "https://github.com/\(githubOwner)")! }
    /// Điểm cuối của GitHub cho bản phát hành mới nhất (không cần đăng nhập với kho công khai).
    static var latestReleaseAPI: URL {
        URL(string: "https://api.github.com/repos/\(githubOwner)/\(githubRepo)/releases/latest")!
    }

    static var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
    }

    static var userAgent: String { "RarX/\(version) (macOS)" }
}

/// So sánh số phiên bản dạng 1.2.3 (chấp nhận tiền tố “v”, bỏ phần hậu tố sau “-” hoặc “+”).
struct SemanticVersion: Comparable, CustomStringConvertible, Sendable {
    let parts: [Int]

    init?(_ string: String) {
        var text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("v") { text.removeFirst() }
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" || $0 == " " }) {
            text = String(text[..<cut])
        }
        var numbers: [Int] = []
        for piece in text.split(separator: ".") {
            guard let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        guard !numbers.isEmpty else { return nil }
        parts = numbers
    }

    private static func component(_ version: SemanticVersion, _ index: Int) -> Int {
        index < version.parts.count ? version.parts[index] : 0
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count where component(lhs, index) != component(rhs, index) { return false }
        return true
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let a = component(lhs, index)
            let b = component(rhs, index)
            if a != b { return a < b }
        }
        return false
    }

    var description: String { parts.map(String.init).joined(separator: ".") }
}

/// Lỗi tải/cập nhật với thông điệp tiếng Việt.
enum UpdateError: LocalizedError {
    case network(String)
    case http(Int)
    case noRelease
    case rateLimited
    case badResponse
    case noPackage
    case extractFailed(String)
    case invalidPackage(String)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .network(let detail): return "Không kết nối được mạng: \(detail)"
        case .http(let code): return "Máy chủ trả về lỗi \(code)."
        case .noRelease: return "Kho GitHub của RarX chưa có bản phát hành nào."
        case .rateLimited: return "GitHub tạm giới hạn số lần kiểm tra. Hãy thử lại sau ít phút."
        case .badResponse: return "Không đọc được thông tin phát hành."
        case .noPackage: return "Bản phát hành này chưa đính kèm gói cài đặt (.zip hoặc .dmg) cho macOS."
        case .extractFailed(let detail): return "Không giải nén được gói cập nhật: \(detail)"
        case .invalidPackage(let detail): return "Gói cập nhật không hợp lệ: \(detail)"
        case .notWritable(let path): return "Không có quyền ghi vào “\(path)”."
        }
    }
}

/// Tải tệp về đĩa kèm báo tiến độ (URLSession + delegate).
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var lastReported = -1.0

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        super.init()
    }

    func download(_ request: URLRequest) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.start(request, continuation: continuation)
        }
    }

    private func start(_ request: URLRequest, continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        self.session = session
        lock.unlock()
        session.downloadTask(with: request).resume()
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        let activeSession = session
        session = nil
        lock.unlock()
        activeSession?.finishTasksAndInvalidate()
        pending?.resume(with: result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else {
            onProgress(-1)
            return
        }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        if fraction - lastReported >= 0.01 || fraction >= 1 {
            lastReported = fraction
            onProgress(fraction)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(.failure(UpdateError.http(http.statusCode)))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(UpdateError.network(error.localizedDescription))) }
    }
}
