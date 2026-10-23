import AppKit
import SwiftUI

/// Quản lý mọi cửa sổ của RarX.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var welcomeController: NSWindowController?
    private var archiveControllers: [ArchiveWindowController] = []
    private var utilityControllers: [String: NSWindowController] = [:]
    private var transientControllers: [NSWindowController] = []

    var hasVisibleWindows: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    // MARK: - Màn hình chào

    func showWelcome() {
        if let window = welcomeController?.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeWindow(title: "RarX", content: WelcomeView(jobs: JobCenter.shared))
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.delegate = self
        let controller = NSWindowController(window: window)
        welcomeController = controller
        window.center()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tệp nén

    func handleOpen(urls: [URL]) {
        var others: [URL] = []
        for url in urls {
            if ArchiveFormat.isArchive(url) {
                openArchive(url)
            } else {
                others.append(url)
            }
        }
        if !others.isEmpty {
            showCreate(sources: others)
        }
    }

    func openArchive(_ url: URL) {
        let detection = ArchiveFormat.detect(url)
            ?? ArchiveFormat.sniff(url).map { ArchiveFormat.Detection(format: $0, isMultiVolume: false, primaryURL: url) }
            ?? ArchiveFormat.Detection(format: .other, isMultiVolume: false, primaryURL: url)
        let target = detection.primaryURL.standardizedFileURL

        if let existing = archiveControllers.first(where: { $0.doc.url.standardizedFileURL == target }) {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let doc = ArchiveDocument(url: target, format: detection.format, isMultiVolume: detection.isMultiVolume)
        let controller = ArchiveWindowController(doc: doc)
        if let previous = archiveControllers.last?.window {
            controller.window?.setFrameTopLeftPoint(NSPoint(x: previous.frame.minX + 26, y: previous.frame.maxY - 26))
        } else {
            controller.window?.center()
        }
        archiveControllers.append(controller)
        controller.showWindow(nil)
        doc.load()

        RecentArchives.add(target)
        NSDocumentController.shared.noteNewRecentDocumentURL(target)
        welcomeController?.close()
        NSApp.activate(ignoringOtherApps: true)
    }

    func archiveWindowDidClose(_ controller: ArchiveWindowController) {
        archiveControllers.removeAll { $0 === controller }
    }

    // MARK: - Tạo tệp nén / giải nén (cửa sổ độc lập)

    func showCreate(sources: [URL]) {
        guard !sources.isEmpty else { return }
        weak var weakController: NSWindowController?
        let view = CreateArchiveView(
            sources: sources,
            onCancel: { weakController?.close() },
            onCreate: { request, extras in
                weakController?.close()
                Workflows.compress(request, extras: extras, window: nil)
                WindowManager.shared.showJobs()
            }
        )
        let window = makeWindow(title: "Tạo tệp nén", content: view)
        window.styleMask = [.titled, .closable]
        let controller = presentTransient(window)
        weakController = controller
    }

    func showExtract(archives: [URL]) {
        let detections = archives.compactMap { url -> ArchiveFormat.Detection? in
            ArchiveFormat.detect(url) ?? ArchiveFormat.sniff(url).map {
                ArchiveFormat.Detection(format: $0, isMultiVolume: false, primaryURL: url)
            }
        }
        guard let first = detections.first else {
            Prompts.showMessage("Không có tệp nén", "Các tệp đã chọn không phải tệp nén RarX nhận biết được.", window: nil)
            return
        }
        // Bỏ trùng các phần của cùng một tệp nhiều phần.
        var seen = Set<String>()
        let unique = detections.filter { seen.insert($0.primaryURL.path).inserted }

        weak var weakController: NSWindowController?
        let view = ExtractWindowView(
            archives: unique.map(\.primaryURL),
            initial: ExtractConfig.defaults(for: first.primaryURL),
            onCancel: { weakController?.close() },
            onConfirm: { config in
                weakController?.close()
                for detection in unique {
                    var perArchive = config
                    if perArchive.baseFolder == first.primaryURL.deletingLastPathComponent() && unique.count > 1 {
                        perArchive.baseFolder = detection.primaryURL.deletingLastPathComponent()
                    }
                    Workflows.extract(archive: detection.primaryURL, format: detection.format, config: perArchive, window: nil)
                }
                WindowManager.shared.showJobs()
            }
        )
        let window = makeWindow(title: "Giải nén", content: view)
        window.styleMask = [.titled, .closable]
        let controller = presentTransient(window)
        weakController = controller
    }

    // MARK: - Hộp chọn tệp

    func chooseFilesToCompress() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Nén"
        panel.message = "Chọn tệp hoặc thư mục cần nén"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        showCreate(sources: panel.urls)
    }

    func chooseArchiveToOpen() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Mở"
        panel.message = "Chọn tệp nén để mở"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openArchive(url) }
    }

    func chooseArchivesToExtract() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Tiếp tục"
        panel.message = "Chọn một hoặc nhiều tệp nén cần giải nén"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }
        showExtract(archives: panel.urls)
    }

    // MARK: - Cửa sổ tiện ích

    func showJobs() {
        showUtility(id: "jobs", title: "Tác vụ", resizable: true) {
            JobsView(center: JobCenter.shared)
        }
    }

    func showSettings() {
        showUtility(id: "settings", title: "Cài đặt RarX", resizable: false) {
            SettingsView()
        }
    }

    func showAbout() {
        showUtility(id: "about", title: "Giới thiệu RarX", resizable: false) {
            AboutView()
        }
    }

    func showBenchmark() {
        showUtility(id: "benchmark", title: "Đo hiệu năng", resizable: true) {
            BenchmarkView()
        }
    }

    func showChecksum(files: [URL] = []) {
        if !files.isEmpty, let existing = utilityControllers["checksum"] {
            existing.close()
            utilityControllers["checksum"] = nil
        }
        showUtility(id: "checksum", title: "Mã kiểm tra", resizable: true) {
            ChecksumView(files: files)
        }
    }

    private func showUtility<Content: View>(id: String, title: String, resizable: Bool,
                                            @ViewBuilder content: () -> Content) {
        if let existing = utilityControllers[id], let window = existing.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = makeWindow(title: title, content: content())
        window.styleMask = resizable
            ? [.titled, .closable, .miniaturizable, .resizable]
            : [.titled, .closable, .miniaturizable]
        window.identifier = NSUserInterfaceItemIdentifier(id)
        window.delegate = self
        window.setFrameAutosaveName("RarX.\(id)")
        let controller = NSWindowController(window: window)
        utilityControllers[id] = controller
        if !window.setFrameUsingName("RarX.\(id)") { window.center() }
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Tiện ích

    private func makeWindow<Content: View>(title: String, content: Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private func presentTransient(_ window: NSWindow) -> NSWindowController {
        window.delegate = self
        let controller = NSWindowController(window: window)
        transientControllers.append(controller)
        window.center()
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === welcomeController?.window {
            welcomeController = nil
        }
        transientControllers.removeAll { $0.window === window }
        for (key, controller) in utilityControllers where controller.window === window {
            utilityControllers[key] = nil
        }
    }
}

/// Cửa sổ giải nén độc lập (giữ trạng thái cấu hình).
@MainActor
struct ExtractWindowView: View {
    let archives: [URL]
    let onCancel: () -> Void
    let onConfirm: (ExtractConfig) -> Void
    @State private var config: ExtractConfig

    init(archives: [URL], initial: ExtractConfig, onCancel: @escaping () -> Void, onConfirm: @escaping (ExtractConfig) -> Void) {
        self.archives = archives
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        _config = State(initialValue: initial)
    }

    var body: some View {
        ExtractOptionsView(
            config: $config,
            archiveNames: archives.map(\.lastPathComponent),
            selectionCount: 0,
            showPasswordField: true,
            onCancel: onCancel,
            onConfirm: { onConfirm(config) }
        )
    }
}
