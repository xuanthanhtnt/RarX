import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Đo hiệu năng nén/giải nén của máy (7-Zip benchmark).
@MainActor
struct BenchmarkView: View {
    @State private var output = ""
    @State private var running = false
    @State private var task: Task<Void, Never>? = nil
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "speedometer")
                    .font(.system(size: 28))
                    .foregroundStyle(Brand.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đo hiệu năng")
                        .font(.title3.weight(.semibold))
                    Text("Đo tốc độ nén (LZMA) và giải nén trên mọi nhân CPU. Mất khoảng 30–60 giây.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                    Button("Dừng") { task?.cancel() }
                } else {
                    Button(output.isEmpty ? "Bắt đầu" : "Đo lại") { start() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            ScrollView {
                Text(output.isEmpty ? "Nhấn “Bắt đầu” để đo." : output)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .card()
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 420)
        .onDisappear { task?.cancel() }
    }

    private func start() {
        output = ""
        errorText = nil
        running = true
        let live = LiveText()
        task = Task { @MainActor in
            let timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                let text = live.value
                Task { @MainActor in output = ConsoleText.clean(text) }
            }
            defer { timer.invalidate() }
            do {
                output = try await ArchiveEngine.benchmark { chunk in live.append(chunk) }
            } catch {
                if !error.isCancellation { errorText = error.userMessage }
            }
            running = false
        }
    }
}

/// Bộ đệm văn bản đa luồng cho đầu ra trực tiếp.
final class LiveText: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock()
        text += chunk
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

/// Tính mã kiểm tra (CRC32, SHA-256…) cho tệp — để đối chiếu tệp tải về.
@MainActor
struct ChecksumView: View {
    @State private var files: [URL]
    @State private var algorithm = "SHA256"
    @State private var output = ""
    @State private var running = false
    @State private var errorText: String? = nil
    @State private var isTargeted = false

    private let algorithms = ["CRC32", "CRC64", "SHA1", "SHA256", "SHA512", "MD5", "BLAKE2sp", "XXH64"]

    init(files: [URL] = []) {
        _files = State(initialValue: files)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "number.square")
                    .font(.system(size: 28))
                    .foregroundStyle(Brand.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mã kiểm tra tệp")
                        .font(.title3.weight(.semibold))
                    Text("Tính CRC/SHA để đối chiếu với mã do nơi phát hành cung cấp.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Spacer()
            }

            HStack {
                Button("Chọn tệp…") { choose() }
                Text(files.isEmpty ? "Hoặc kéo thả tệp vào đây" : files.map(\.lastPathComponent).joined(separator: ", "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Thuật toán", selection: $algorithm) {
                    ForEach(algorithms, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 200)
                Button("Tính") { run() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(files.isEmpty || running)
            }

            ZStack {
                ScrollView {
                    Text(output.isEmpty ? " " : output)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                if running { ProgressView() }
            }
            .card(highlighted: isTargeted)
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                DropLoader.loadURLs(from: providers) { urls in
                    let regular = urls.filter { !FileOps.isDirectory($0) }
                    if !regular.isEmpty { files = regular }
                }
                return true
            }

            HStack {
                if let errorText { Text(errorText).foregroundStyle(.red) }
                Spacer()
                Button("Sao chép kết quả") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(output, forType: .string)
                }
                .disabled(output.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 640, minHeight: 400)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { files = panel.urls }
    }

    private func run() {
        running = true
        errorText = nil
        let targets = files
        let algo = algorithm
        Task { @MainActor in
            do {
                output = try await ArchiveEngine.checksum(files: targets, algorithm: algo)
            } catch {
                errorText = error.userMessage
            }
            running = false
        }
    }
}
