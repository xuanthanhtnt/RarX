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
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
