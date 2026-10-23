import Foundation

/// Khoá cài đặt (dùng chung cho @AppStorage và UserDefaults).
enum Prefs {
    static let defaultFormat = "compress.defaultFormat"
    static let defaultLevel = "compress.defaultLevel"
    static let excludeJunk = "compress.excludeJunk"
    static let testAfterCompress = "compress.testAfter"
    static let zipLegacyEncryption = "compress.zipLegacyEncryption"
    static let trashSourcesAfterCompress = "compress.trashSources"

    static let extractFolderMode = "extract.folderMode"
    static let overwriteMode = "extract.overwriteMode"
    static let openFolderAfterExtract = "extract.openFolder"
    static let trashArchiveAfterExtract = "extract.trashArchive"
    static let extractLocation = "extract.location"          // same | ask | fixed
    static let extractFixedFolder = "extract.fixedFolder"

    static let hideJunkInBrowser = "browser.hideJunk"
    static let confirmDelete = "browser.confirmDelete"
    static let showSidebar = "browser.showSidebar"

    static let recentArchives = "recentArchives"

    // Cập nhật & công cụ RAR
    static let autoCheckUpdates = "updates.autoCheck"
    static let lastUpdateCheck = "updates.lastCheck"
    static let skippedVersion = "updates.skippedVersion"
    static let autoInstallRar = "tools.rarAutoInstall"
    static let lastRarCheck = "tools.rarLastCheck"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            defaultFormat: ArchiveFormat.zip.rawValue,
            defaultLevel: CompressionLevel.normal.rawValue,
            excludeJunk: true,
            testAfterCompress: false,
            zipLegacyEncryption: false,
            trashSourcesAfterCompress: false,
            extractFolderMode: ExtractFolderMode.smart.rawValue,
            overwriteMode: OverwriteMode.ask.rawValue,
            openFolderAfterExtract: true,
            trashArchiveAfterExtract: false,
            extractLocation: "same",
            hideJunkInBrowser: true,
            confirmDelete: true,
            showSidebar: true,
            autoCheckUpdates: true,
            autoInstallRar: true,
        ])
    }

    static var defaults: UserDefaults { .standard }

    static var preferredFormat: ArchiveFormat {
        ArchiveFormat(rawValue: defaults.string(forKey: defaultFormat) ?? "") ?? .zip
    }

    static var preferredLevel: CompressionLevel {
        CompressionLevel(rawValue: defaults.integer(forKey: defaultLevel)) ?? .normal
    }

    static var folderMode: ExtractFolderMode {
        ExtractFolderMode(rawValue: defaults.string(forKey: extractFolderMode) ?? "") ?? .smart
    }

    static var overwrite: OverwriteMode {
        OverwriteMode(rawValue: defaults.string(forKey: overwriteMode) ?? "") ?? .ask
    }

    static func bool(_ key: String) -> Bool { defaults.bool(forKey: key) }

    /// Thư mục đích mặc định khi giải nén một tệp nén.
    static func defaultExtractBase(for archive: URL) -> URL {
        if defaults.string(forKey: extractLocation) == "fixed",
           let path = defaults.string(forKey: extractFixedFolder), !path.isEmpty,
           FileOps.isDirectory(URL(fileURLWithPath: path)) {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return archive.deletingLastPathComponent()
    }
}

/// Danh sách tệp nén mở gần đây.
enum RecentArchives {
    static let limit = 12

    static var urls: [URL] {
        let paths = UserDefaults.standard.stringArray(forKey: Prefs.recentArchives) ?? []
        return paths.map { URL(fileURLWithPath: $0) }.filter { FileOps.exists($0) }
    }

    static func add(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: Prefs.recentArchives) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(limit)), forKey: Prefs.recentArchives)
        NotificationCenter.default.post(name: .recentArchivesChanged, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: Prefs.recentArchives)
        NotificationCenter.default.post(name: .recentArchivesChanged, object: nil)
    }
}

extension Notification.Name {
    static let recentArchivesChanged = Notification.Name("RarX.recentArchivesChanged")
    static let toolsChanged = Notification.Name("RarX.toolsChanged")
}
