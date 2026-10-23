import AppKit

/// Dựng thanh menu của ứng dụng bằng mã.
/// Các mục gửi hành động tới "first responder": cửa sổ tệp nén đang mở (ArchiveWindowController)
/// hoặc AppDelegate cho các thao tác chung.
@MainActor
enum MainMenu {
    static func build(recentMenuDelegate: NSMenuDelegate) -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu("RarX", appMenu()))
        main.addItem(submenu("Tệp", fileMenu(recentMenuDelegate: recentMenuDelegate)))
        main.addItem(submenu("Sửa", editMenu()))
        main.addItem(submenu("Xem", viewMenu()))
        main.addItem(submenu("Công cụ", toolsMenu()))
        let window = windowMenu()
        main.addItem(submenu("Cửa sổ", window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu("Trợ giúp", help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menu.title = title
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Giới thiệu RarX", #selector(AppDelegate.rxAbout(_:))))
        menu.addItem(item("Kiểm tra cập nhật…", #selector(AppDelegate.rxCheckForUpdates(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Cài đặt…", #selector(AppDelegate.rxShowSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu()
        menu.addItem(submenu("Dịch vụ", services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Ẩn RarX", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Ẩn ứng dụng khác", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Hiện tất cả", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Thoát RarX", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu(recentMenuDelegate: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Tạo tệp nén mới…", #selector(AppDelegate.rxNewArchive(_:)), "n"))
        menu.addItem(item("Mở tệp nén…", #selector(AppDelegate.rxOpenArchive(_:)), "o"))
        let recent = NSMenu()
        recent.delegate = recentMenuDelegate
        menu.addItem(submenu("Mở gần đây", recent))
        menu.addItem(.separator())
        menu.addItem(item("Giải nén…", #selector(ArchiveWindowController.rxExtract(_:)), "e"))
        menu.addItem(item("Giải nén tại đây", #selector(ArchiveWindowController.rxExtractHere(_:)), "e", [.command, .shift]))
        menu.addItem(item("Giải nén vào thư mục riêng", #selector(ArchiveWindowController.rxExtractToOwnFolder(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Thêm tệp vào tệp nén…", #selector(ArchiveWindowController.rxAddFiles(_:)), "a", [.command, .shift]))
        menu.addItem(item("Thư mục mới trong tệp nén…", #selector(ArchiveWindowController.rxNewFolder(_:)), "n", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Kiểm tra tệp nén", #selector(ArchiveWindowController.rxTest(_:)), "t"))
        menu.addItem(item("Thông tin tệp nén", #selector(ArchiveWindowController.rxShowInfo(_:)), "i"))
        menu.addItem(item("Chuyển đổi định dạng…", #selector(ArchiveWindowController.rxConvert(_:))))
        menu.addItem(item("Sửa tệp nén hỏng…", #selector(ArchiveWindowController.rxRepair(_:))))
        menu.addItem(item("Khoá tệp RAR…", #selector(ArchiveWindowController.rxLock(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Hiện trong Finder", #selector(ArchiveWindowController.rxReveal(_:)), "r", [.command, .option]))
        menu.addItem(item("Đóng cửa sổ", #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Hoàn tác", Selector(("undo:")), "z"))
        menu.addItem(item("Làm lại", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cắt", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Sao chép", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Dán", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Chọn tất cả", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        let delete = item("Xoá khỏi tệp nén…", #selector(ArchiveWindowController.rxDeleteItems(_:)), "\u{8}")
        menu.addItem(delete)
        menu.addItem(item("Đổi tên…", #selector(ArchiveWindowController.rxRename(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Tìm trong tệp nén", #selector(ArchiveWindowController.rxFind(_:)), "f"))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Ẩn thanh bên", #selector(ArchiveWindowController.rxToggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Hiện tệp rác hệ thống", #selector(ArchiveWindowController.rxToggleJunk(_:))))
        menu.addItem(.separator())
        let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
        let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
        menu.addItem(item("Lên thư mục cha", #selector(ArchiveWindowController.rxGoUp(_:)), up))
        menu.addItem(item("Mở mục đã chọn", #selector(ArchiveWindowController.rxOpenSelection(_:)), down))
        menu.addItem(item("Xem nhanh", #selector(ArchiveWindowController.rxQuickLook(_:)), "y"))
        menu.addItem(.separator())
        menu.addItem(item("Tải lại", #selector(ArchiveWindowController.rxRefresh(_:)), "r"))
        menu.addItem(.separator())
        let fullScreen = item("Toàn màn hình", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        menu.addItem(fullScreen)
        return menu
    }

    private static func toolsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Tác vụ đang chạy", #selector(AppDelegate.rxShowJobs(_:)), "j", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Tính mã kiểm tra tệp…", #selector(AppDelegate.rxChecksum(_:))))
        menu.addItem(item("Đo hiệu năng nén…", #selector(AppDelegate.rxBenchmark(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Màn hình chào", #selector(AppDelegate.rxShowWelcome(_:)), "0", [.command, .shift]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Thu nhỏ", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Phóng to", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Đưa tất cả ra trước", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Hướng dẫn sử dụng RarX", #selector(AppDelegate.rxHelp(_:)), "?"))
        menu.addItem(.separator())
        menu.addItem(item("Trang tải 7-Zip", #selector(AppDelegate.rxOpen7ZipSite(_:))))
        menu.addItem(item("Tải công cụ RAR cho macOS", #selector(AppDelegate.rxOpenRarSite(_:))))
        return menu
    }
}
