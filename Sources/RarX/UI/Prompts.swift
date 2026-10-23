import AppKit

/// Hộp thoại hệ thống (NSAlert) dùng chung, có thể hiện dạng sheet trên cửa sổ hoặc độc lập.
@MainActor
enum Prompts {
    static func present(_ alert: NSAlert, on window: NSWindow?) async -> NSApplication.ModalResponse {
        if let window, window.isVisible, window.attachedSheet == nil {
            return await withCheckedContinuation { continuation in
                alert.beginSheetModal(for: window) { response in
                    continuation.resume(returning: response)
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// Hỏi mật khẩu. Trả về nil nếu người dùng huỷ.
    static func password(for archiveName: String, wrongBefore: Bool, window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = wrongBefore ? "Mật khẩu không đúng" : "Nhập mật khẩu"
        alert.informativeText = wrongBefore
            ? "Hãy thử lại mật khẩu cho “\(archiveName)”."
            : "“\(archiveName)” được bảo vệ bằng mật khẩu."
        alert.alertStyle = wrongBefore ? .warning : .informational
        if let lock = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 40, weight: .regular)
            alert.icon = lock.withSymbolConfiguration(config)
        }
        alert.addButton(withTitle: "Mở khoá")
        alert.addButton(withTitle: "Huỷ")

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = "Mật khẩu"
        alert.accessoryView = field
        alert.layout()
        alert.window.initialFirstResponder = field

        let response = await present(alert, on: window)
        guard response == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    /// Hỏi cách xử lý khi tệp giải nén trùng tên với tệp đã có.
    static func conflict(names: [String], destination: URL, window: NSWindow?) async -> OverwriteMode? {
        let alert = NSAlert()
        alert.alertStyle = .warning
        if names.count == 1 {
            alert.messageText = "“\(names[0])” đã có trong “\(destination.lastPathComponent)”"
        } else {
            alert.messageText = "\(names.count) mục đã có trong “\(destination.lastPathComponent)”"
        }
        let sample = names.prefix(5).map { "• " + $0 }.joined(separator: "\n")
        alert.informativeText = (names.count > 1 ? sample + (names.count > 5 ? "\n…" : "") + "\n\n" : "")
            + "Bạn muốn xử lý thế nào?"
        alert.addButton(withTitle: "Giữ cả hai")
        alert.addButton(withTitle: "Thay thế")
        alert.addButton(withTitle: "Bỏ qua")
        alert.addButton(withTitle: "Huỷ")
        switch await present(alert, on: window) {
        case .alertFirstButtonReturn: return .renameNew
        case .alertSecondButtonReturn: return .overwrite
        case .alertThirdButtonReturn: return .skip
        default: return nil
        }
    }

    static func confirm(title: String, message: String, confirm: String, destructive: Bool = false,
                        window: NSWindow?) async -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .critical : .warning
        let button = alert.addButton(withTitle: confirm)
        if destructive { button.hasDestructiveAction = true }
        alert.addButton(withTitle: "Huỷ")
        return await present(alert, on: window) == .alertFirstButtonReturn
    }

    static func showError(_ error: Error, title: String = "Không thực hiện được", window: NSWindow?) {
        guard !error.isCancellation else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.userMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        Task { _ = await present(alert, on: window) }
    }

    static func showMessage(_ title: String, _ message: String, window: NSWindow?) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        Task { _ = await present(alert, on: window) }
    }

    /// Hỏi tên (đổi tên, tạo thư mục mới…).
    static func text(title: String, message: String, initial: String, confirm: String, window: NSWindow?) async -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Huỷ")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.layout()
        alert.window.initialFirstResponder = field
        guard await present(alert, on: window) == .alertFirstButtonReturn else { return nil }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
