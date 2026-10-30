import AppKit

/// Điểm khởi động của RarX (vòng đời AppKit, giao diện SwiftUI bên trong cửa sổ).
@main
enum RarXMain {
    @MainActor
    static func main() {
        // Không để ứng dụng bị tắt khi công cụ nén đóng đường ống sớm.
        signal(SIGPIPE, SIG_IGN)

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Mặc định chạy ngầm, không hiện trên Dock; WindowManager.updateDockIcon() bật lại khi có cửa sổ.
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
