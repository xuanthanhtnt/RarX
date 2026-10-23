import AppKit
import Combine

/// Một tác vụ chạy nền (nén, giải nén, kiểm tra…).
@MainActor
final class Job: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case succeeded(String?)
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let title: String
    let symbol: String
    let startedAt = Date()
    @Published var detail: String
    /// 0…1; nil = chưa biết (thanh tiến độ chạy liên tục).
    @Published var progress: Double? = nil
    @Published var state: State = .running
    /// Tệp/thư mục kết quả để mở nhanh khi xong.
    @Published var resultURL: URL? = nil
    fileprivate var task: Task<Void, Never>?

    init(title: String, detail: String, symbol: String) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
    }

    var isRunning: Bool { state == .running }

    func cancel() { task?.cancel() }

    /// Bộ nhận tiến độ an toàn đa luồng, tự đưa về luồng chính.
    nonisolated func progressHandler(scale: Double = 1, offset: Double = 0) -> @Sendable (Double) -> Void {
        { [weak self] value in
            Task { @MainActor in
                guard let self, self.state == .running else { return }
                self.progress = min(1, offset + value * scale)
            }
        }
    }
}

/// Quản lý toàn bộ tác vụ của ứng dụng.
@MainActor
final class JobCenter: ObservableObject {
    static let shared = JobCenter()

    @Published private(set) var jobs: [Job] = []

    var hasRunningJobs: Bool { jobs.contains { $0.isRunning } }
    var runningCount: Int { jobs.filter { $0.isRunning }.count }

    /// Bắt đầu một tác vụ. `operation` trả về thông điệp kết quả (tuỳ chọn).
    @discardableResult
    func start(
        title: String,
        detail: String,
        symbol: String = "gearshape.2",
        operation: @escaping @MainActor (Job) async throws -> String?,
        completion: (@MainActor (Job, Error?) -> Void)? = nil
    ) -> Job {
        let job = Job(title: title, detail: detail, symbol: symbol)
        jobs.insert(job, at: 0)
        job.task = Task { @MainActor in
            do {
                let message = try await operation(job)
                job.progress = 1
                job.state = .succeeded(message)
                completion?(job, nil)
            } catch {
                if error.isCancellation {
                    job.state = .cancelled
                } else {
                    job.state = .failed(error.userMessage)
                }
                completion?(job, error)
            }
            if !NSApp.isActive && !(job.state == .cancelled) {
                NSApp.requestUserAttention(.informationalRequest)
            }
            // Báo cho giao diện cập nhật số tác vụ đang chạy.
            self.objectWillChange.send()
            self.trimFinished()
        }
        return job
    }

    func cancelAll() {
        for job in jobs where job.isRunning { job.cancel() }
    }

    func clearFinished() {
        jobs.removeAll { !$0.isRunning }
    }

    private func trimFinished() {
        let finished = jobs.filter { !$0.isRunning }
        if finished.count > 40 {
            let drop = Set(finished.suffix(finished.count - 40).map(\.id))
            jobs.removeAll { drop.contains($0.id) }
        }
    }
}
