import Foundation

/// Một lệnh cần chạy (đường dẫn công cụ + tham số).
struct Command: Sendable {
    var executable: URL
    var arguments: [String]
    var currentDirectory: URL?

    init(_ executable: URL, _ arguments: [String], in currentDirectory: URL? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.currentDirectory = currentDirectory
    }
}

/// Kết quả sau khi một tiến trình kết thúc.
struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
    let wasCancelled: Bool

    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

/// Bộ đệm an toàn đa luồng để gom dữ liệu đầu ra.
final class DataCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) {
        lock.lock()
        buffer.append(data)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}

/// Giữ tham chiếu tới các tiến trình để có thể huỷ.
final class ProcessCanceller: @unchecked Sendable {
    private let lock = NSLock()
    private var processes: [Process] = []
    private var _cancelled = false

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _cancelled
    }

    func track(_ process: Process) {
        lock.lock()
        processes.append(process)
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        _cancelled = true
        let list = processes
        lock.unlock()
        for process in list where process.isRunning {
            process.interrupt() // SIGINT: 7-Zip/RAR dọn tệp tạm rồi thoát
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            for process in list where process.isRunning {
                process.terminate()
            }
        }
    }
}

enum ProcessRunner {
    /// Môi trường chạy công cụ: ép UTF-8 để tên tệp tiếng Việt hiển thị đúng.
    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "en_US.UTF-8"
        env["LANG"] = "en_US.UTF-8"
        env["COPYFILE_DISABLE"] = "1" // không tạo tệp ._ khi đóng gói tar
        for (key, value) in extra { env[key] = value }
        return env
    }

    /// Chạy một lệnh, thu toàn bộ stdout/stderr; có thể theo dõi đầu ra theo thời gian thực.
    static func run(
        _ command: Command,
        stdin: Data? = nil,
        onStdout: (@Sendable (Data) -> Void)? = nil,
        onStderr: (@Sendable (Data) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        if let dir = command.currentDirectory { process.currentDirectoryURL = dir }
        process.environment = environment()

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        let inPipe: Pipe? = stdin == nil ? nil : Pipe()
        if let inPipe {
            process.standardInput = inPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        let outBuffer = DataCollector()
        let errBuffer = DataCollector()
        let group = DispatchGroup()
        group.enter() // stdout EOF
        group.enter() // stderr EOF
        group.enter() // kết thúc tiến trình

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                outBuffer.append(chunk)
                onStdout?(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                group.leave()
            } else {
                errBuffer.append(chunk)
                onStderr?(chunk)
            }
        }
        process.terminationHandler = { _ in group.leave() }

        let canceller = ProcessCanceller()
        canceller.track(process)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                if Task.isCancelled {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ArchiveError.cancelled)
                    return
                }
                do {
                    try process.run()
                } catch {
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: ArchiveError.launchFailed(error.localizedDescription))
                    return
                }
                if let inPipe, let stdin {
                    DispatchQueue.global().async {
                        let writer = inPipe.fileHandleForWriting
                        try? writer.write(contentsOf: stdin)
                        try? writer.close()
                    }
                }
                group.notify(queue: .global()) {
                    continuation.resume(returning: ProcessResult(
                        exitCode: process.terminationStatus,
                        stdout: outBuffer.data,
                        stderr: errBuffer.data,
                        wasCancelled: canceller.cancelled
                    ))
                }
            }
        } onCancel: {
            canceller.cancel()
        }
    }

    /// Chạy hai lệnh nối nhau: stdout của lệnh đầu → stdin của lệnh sau
    /// (dùng cho .tar.gz / .tar.xz …: giải nén lớp ngoài rồi xử lý tar bên trong).
    static func runPipeline(
        _ first: Command,
        _ second: Command,
        onFirstStderr: (@Sendable (Data) -> Void)? = nil,
        onSecondStdout: (@Sendable (Data) -> Void)? = nil
    ) async throws -> (first: ProcessResult, second: ProcessResult) {
        let producer = Process()
        producer.executableURL = first.executable
        producer.arguments = first.arguments
        if let dir = first.currentDirectory { producer.currentDirectoryURL = dir }
        producer.environment = environment()

        let consumer = Process()
        consumer.executableURL = second.executable
        consumer.arguments = second.arguments
        if let dir = second.currentDirectory { consumer.currentDirectoryURL = dir }
        consumer.environment = environment()

        let link = Pipe()
        let producerErr = Pipe()
        let consumerOut = Pipe()
        let consumerErr = Pipe()
        producer.standardInput = FileHandle.nullDevice
        producer.standardOutput = link
        producer.standardError = producerErr
        consumer.standardInput = link
        consumer.standardOutput = consumerOut
        consumer.standardError = consumerErr

        let producerErrBuffer = DataCollector()
        let consumerOutBuffer = DataCollector()
        let consumerErrBuffer = DataCollector()
        let group = DispatchGroup()
        for _ in 0..<5 { group.enter() } // 3 luồng EOF + 2 tiến trình

        func attach(_ pipe: Pipe, _ buffer: DataCollector, _ callback: (@Sendable (Data) -> Void)?) {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                    group.leave()
                } else {
                    buffer.append(chunk)
                    callback?(chunk)
                }
            }
        }
        attach(producerErr, producerErrBuffer, onFirstStderr)
        attach(consumerOut, consumerOutBuffer, onSecondStdout)
        attach(consumerErr, consumerErrBuffer, nil)
        producer.terminationHandler = { _ in group.leave() }
        consumer.terminationHandler = { _ in group.leave() }

        let canceller = ProcessCanceller()
        canceller.track(producer)
        canceller.track(consumer)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(first: ProcessResult, second: ProcessResult), Error>) in
                func detachAll() {
                    producerErr.fileHandleForReading.readabilityHandler = nil
                    consumerOut.fileHandleForReading.readabilityHandler = nil
                    consumerErr.fileHandleForReading.readabilityHandler = nil
                }
                if Task.isCancelled {
                    detachAll()
                    continuation.resume(throwing: ArchiveError.cancelled)
                    return
                }
                do {
                    try consumer.run()
                } catch {
                    detachAll()
                    continuation.resume(throwing: ArchiveError.launchFailed(error.localizedDescription))
                    return
                }
                do {
                    try producer.run()
                } catch {
                    consumer.terminate()
                    detachAll()
                    continuation.resume(throwing: ArchiveError.launchFailed(error.localizedDescription))
                    return
                }
                group.notify(queue: .global()) {
                    let cancelled = canceller.cancelled
                    let firstResult = ProcessResult(exitCode: producer.terminationStatus, stdout: Data(), stderr: producerErrBuffer.data, wasCancelled: cancelled)
                    let secondResult = ProcessResult(exitCode: consumer.terminationStatus, stdout: consumerOutBuffer.data, stderr: consumerErrBuffer.data, wasCancelled: cancelled)
                    continuation.resume(returning: (first: firstResult, second: secondResult))
                }
            }
        } onCancel: {
            canceller.cancel()
        }
    }
}
