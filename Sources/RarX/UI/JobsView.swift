import SwiftUI
import AppKit

/// Cửa sổ "Tác vụ": theo dõi mọi lần nén/giải nén đang chạy và đã xong.
@MainActor
struct JobsView: View {
    @ObservedObject var center: JobCenter

    var body: some View {
        VStack(spacing: 0) {
            if center.jobs.isEmpty {
                EmptyStateView(symbol: "tray", title: "Chưa có tác vụ nào",
                               message: "Các lần nén, giải nén, kiểm tra sẽ hiện ở đây kèm tiến độ.")
            } else {
                List {
                    ForEach(center.jobs) { job in
                        JobRow(job: job)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            HStack {
                Text(center.runningCount > 0 ? "\(center.runningCount) tác vụ đang chạy" : "Không có tác vụ đang chạy")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Huỷ tất cả") { center.cancelAll() }
                    .disabled(center.runningCount == 0)
                Button("Xoá mục đã xong") { center.clearFinished() }
                    .disabled(center.jobs.allSatisfy { $0.isRunning })
            }
            .padding(10)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 300, idealHeight: 380)
    }
}

@MainActor
struct JobRow: View {
    @ObservedObject var job: Job

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: job.symbol)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(job.title)
                        .font(.headline)
                    Spacer()
                    Text(job.startedAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(job.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusLine
            }
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch job.state {
        case .running: return Brand.teal
        case .succeeded: return .green
        case .failed: return .orange
        case .cancelled: return .secondary
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch job.state {
        case .running:
            HStack(spacing: 8) {
                if let progress = job.progress {
                    ProgressView(value: progress)
                    Text(Format.percent(progress * 100))
                        .monospacedDigit()
                        .font(.caption)
                        .frame(width: 38, alignment: .trailing)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                }
                Button("Huỷ") { job.cancel() }
                    .controlSize(.small)
            }
        case .succeeded(let message):
            HStack {
                Label(message ?? "Hoàn tất", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
                    .lineLimit(2)
                Spacer()
                if let url = job.resultURL {
                    Button("Hiện trong Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .controlSize(.small)
                    if ArchiveFormat.isArchive(url) {
                        Button("Mở") { WindowManager.shared.openArchive(url) }
                            .controlSize(.small)
                    }
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)
        case .cancelled:
            Label("Đã huỷ", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }
}
