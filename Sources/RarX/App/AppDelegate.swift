import AppKit
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let services = ServiceProvider()
    /// Ứng dụng được mở để xử lý tệp (Finder, Dock, Dịch vụ) — không cần hiện màn hình chào.
    static var launchedForWork = false
    /// Đang thoát để RarX tự thay bằng bản cập nhật — bỏ qua hộp thoại “đang có tác vụ chạy”.
    static var isRelaunchingForUpdate = false

    // MARK: - Vòng đời

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        NSApp.mainMenu = MainMenu.build(recentMenuDelegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
        // Bản chạy thử từ Xcode không nằm trong .app nên chưa có biểu tượng — lấy từ thư mục mã nguồn.
        if Bundle.main.bundleURL.pathExtension != "app",
           let icon = NSImage(contentsOf: ToolLocator.sourceRoot.appendingPathComponent("Resources/AppIcon.icns")) {
            NSApp.applicationIconImage = icon
        }
        ToolLocator.shared.refresh()
        DispatchQueue.global(qos: .utility).async { TempSpace.purgeStale() }
        claimUnhandledArchiveTypes()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            if !AppDelegate.launchedForWork && !WindowManager.shared.hasVisibleWindows {
                WindowManager.shared.showWelcome()
            }
            if ToolLocator.shared.sevenZip == nil {
                Prompts.showMessage(
                    "Chưa tìm thấy 7-Zip",
                    "RarX dùng 7-Zip làm lõi nén/giải nén. Hãy chạy lại ./build.sh (tự tải và đóng gói 7-Zip), hoặc cài bằng Homebrew: brew install sevenzip — rồi mở lại RarX.",
                    window: nil
                )
            }
        }

        // Công cụ RAR: tự cài lần đầu (từ rarlab.com) và tự kiểm tra bản mới; sau đó kiểm tra bản RarX mới trên GitHub.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await RarToolManager.shared.runLaunchTasks()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await AppUpdater.shared.autoCheckOnLaunch()
        }
    }

    /// Đặt RarX làm ứng dụng mặc định cho các định dạng mà macOS không tự mở được (RAR, 7Z…),
    /// để Finder hiện biểu tượng tệp của RarX thay vì trang trắng.
    /// Định dạng nào đang được một ứng dụng khác (Keka, The Unarchiver…) nhận thì giữ nguyên.
    private func claimUnhandledArchiveTypes() {
        let me = Bundle.main.bundleURL.standardizedFileURL
        guard me.pathExtension == "app" else { return }
        let identifiers = [
            "com.rarlab.rar-archive", "org.7-zip.7-zip-archive", "com.facebook.zstandard-archive",
            "com.microsoft.cab", "com.microsoft.wim-archive", "com.rarx.archive-volume", "com.rarx.other-archive",
        ]
        Task { @MainActor in
            for identifier in identifiers {
                guard let type = UTType(identifier) else { continue }
                if let current = NSWorkspace.shared.urlForApplication(toOpen: type) {
                    if current.standardizedFileURL == me { continue }          // đã là RarX này
                    // Archive Utility của macOS nhận .7z nhưng không có biểu tượng cho nó (tệp hiện trống),
                    // nên RarX được phép thay. Ứng dụng nén khác do người dùng cài thì giữ nguyên.
                    let replaceable = ["RarX.app", "Archive Utility.app"]
                    if !replaceable.contains(current.lastPathComponent) { continue }
                }
                try? await NSWorkspace.shared.setDefaultApplication(at: me, toOpen: type)
            }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AppDelegate.launchedForWork = true
        WindowManager.shared.handleOpen(urls: urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WindowManager.shared.showWelcome() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if AppDelegate.isRelaunchingForUpdate { return .terminateNow }
        guard JobCenter.shared.hasRunningJobs else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Đang có tác vụ chạy"
        alert.informativeText = "Thoát bây giờ sẽ huỷ các tác vụ nén/giải nén đang dở. Bạn vẫn muốn thoát?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Thoát")
        alert.addButton(withTitle: "Ở lại")
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        JobCenter.shared.cancelAll()
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        TempSpace.cleanAll()
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Tạo tệp nén mới…", action: #selector(rxNewArchive(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Mở tệp nén…", action: #selector(rxOpenArchive(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Giải nén…", action: #selector(rxExtract(_:)), keyEquivalent: ""))
        for item in menu.items { item.target = self }
        return menu
    }

    // MARK: - Menu "Mở gần đây"

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = RecentArchives.urls
        if urls.isEmpty {
            let empty = NSMenuItem(title: "Chưa có tệp nào", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for url in urls {
                let item = NSMenuItem(title: url.lastPathComponent, action: #selector(rxOpenRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
                item.toolTip = url.path
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Xoá danh sách", action: #selector(rxClearRecent(_:)), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !urls.isEmpty
        menu.addItem(clear)
    }

    // MARK: - Hành động chung

    @objc func rxAbout(_ sender: Any?) {
        WindowManager.shared.showAbout()
    }

    @objc func rxCheckForUpdates(_ sender: Any?) {
        WindowManager.shared.showAbout()
        Task { @MainActor in await AppUpdater.shared.check() }
    }

    @objc func rxShowSettings(_ sender: Any?) { WindowManager.shared.showSettings() }
    @objc func rxNewArchive(_ sender: Any?) { WindowManager.shared.chooseFilesToCompress() }
    @objc func rxOpenArchive(_ sender: Any?) { WindowManager.shared.chooseArchiveToOpen() }
    /// Khi không có cửa sổ tệp nén nào đang chọn: chọn tệp nén để giải nén.
    @objc func rxExtract(_ sender: Any?) { WindowManager.shared.chooseArchivesToExtract() }
    @objc func rxShowJobs(_ sender: Any?) { WindowManager.shared.showJobs() }
    @objc func rxBenchmark(_ sender: Any?) { WindowManager.shared.showBenchmark() }
    @objc func rxChecksum(_ sender: Any?) { WindowManager.shared.showChecksum() }
    @objc func rxShowWelcome(_ sender: Any?) { WindowManager.shared.showWelcome() }

    @objc func rxOpenRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        WindowManager.shared.openArchive(url)
    }

    @objc func rxClearRecent(_ sender: Any?) {
        RecentArchives.clear()
        NSDocumentController.shared.clearRecentDocuments(nil)
    }

    @objc func rxHelp(_ sender: Any?) {
        if let readme = Bundle.main.url(forResource: "HuongDan", withExtension: "html") {
            NSWorkspace.shared.open(readme)
        } else {
            Prompts.showMessage(
                "Hướng dẫn nhanh",
                """
                • Nén: kéo tệp/thư mục vào cửa sổ chào hoặc biểu tượng RarX trên Dock, chọn định dạng rồi bấm Nén.
                • Mở tệp nén: nhấp đúp tệp .zip/.rar/.7z… (Mở bằng ▸ RarX), duyệt như Finder, kéo tệp ra ngoài để lấy.
                • Giải nén: nút Giải nén trên thanh công cụ, hoặc Finder ▸ chuột phải ▸ Thao tác nhanh ▸ RarX.
                • Thêm/xoá/đổi tên bên trong tệp 7Z, ZIP, TAR (RAR cần công cụ RAR).
                • Tạo tệp .rar cần công cụ RAR — RarX tự cài từ rarlab.com (Cài đặt ▸ Công cụ).
                """,
                window: NSApp.keyWindow
            )
        }
    }

    @objc func rxOpen7ZipSite(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://www.7-zip.org/download.html")!)
    }

    @objc func rxOpenRarSite(_ sender: Any?) {
        NSWorkspace.shared.open(URL(string: "https://www.rarlab.com/download.htm")!)
    }
}
