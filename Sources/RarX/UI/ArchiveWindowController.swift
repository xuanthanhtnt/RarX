import AppKit
import SwiftUI
import Combine

/// Cửa sổ duyệt một tệp nén: thanh công cụ AppKit + nội dung SwiftUI.
/// Các hành động (rx…) cũng được menu chính gọi qua chuỗi phản hồi (responder chain).
@MainActor
final class ArchiveWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate,
                                     NSToolbarItemValidation, NSMenuItemValidation, NSSearchFieldDelegate {
    let doc: ArchiveDocument
    private var cancellables = Set<AnyCancellable>()
    private weak var searchItem: NSSearchToolbarItem?

    private enum ItemID {
        static let sidebar = NSToolbarItem.Identifier("rarx.sidebar")
        static let add = NSToolbarItem.Identifier("rarx.add")
        static let extract = NSToolbarItem.Identifier("rarx.extract")
        static let test = NSToolbarItem.Identifier("rarx.test")
        static let view = NSToolbarItem.Identifier("rarx.view")
        static let delete = NSToolbarItem.Identifier("rarx.delete")
        static let info = NSToolbarItem.Identifier("rarx.info")
        static let tools = NSToolbarItem.Identifier("rarx.tools")
        static let search = NSToolbarItem.Identifier("rarx.search")
    }

    init(doc: ArchiveDocument) {
        self.doc = doc
        let hosting = NSHostingController(rootView: ArchiveBrowserView(doc: doc))
        hosting.sizingOptions = [.minSize]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.minSize = NSSize(width: 720, height: 460)
        window.title = doc.displayName
        window.subtitle = doc.url.deletingLastPathComponent().path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        window.representedURL = doc.url
        window.isReleasedWhenClosed = false
        window.tabbingMode = .automatic
        super.init(window: window)
        window.delegate = self
        doc.window = window
        setupToolbar()

        doc.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.window?.toolbar?.validateVisibleItems() }
            .store(in: &cancellables)
        doc.$searchText
            .receive(on: RunLoop.main)
            .sink { [weak self] text in
                guard let field = self?.searchItem?.searchField, field.stringValue != text else { return }
                field.stringValue = text
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) không được hỗ trợ")
    }

    // MARK: - Cửa sổ

    func windowWillClose(_ notification: Notification) {
        cancellables.removeAll()
        WindowManager.shared.archiveWindowDidClose(self)
    }

    // MARK: - Thanh công cụ

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "RarXArchiveToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar
        window?.toolbarStyle = .expanded
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ItemID.sidebar, ItemID.add, ItemID.extract, ItemID.test, ItemID.view, ItemID.delete, ItemID.info,
         ItemID.tools, .flexibleSpace, ItemID.search]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case ItemID.sidebar:
            return button(itemIdentifier, "Thanh bên", "sidebar.left", "Ẩn/hiện cây thư mục", #selector(rxToggleSidebar(_:)))
        case ItemID.add:
            return button(itemIdentifier, "Thêm", "doc.badge.plus", "Thêm tệp hoặc thư mục vào tệp nén", #selector(rxAddFiles(_:)))
        case ItemID.extract:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            configure(item, "Giải nén", "arrow.down.doc", "Giải nén tới thư mục bạn chọn", #selector(rxExtract(_:)))
            let menu = NSMenu()
            menu.addItem(menuItem("Giải nén tới…", #selector(rxExtract(_:))))
            menu.addItem(menuItem("Giải nén tại đây", #selector(rxExtractHere(_:))))
            menu.addItem(menuItem("Giải nén vào thư mục “\(ArchiveFormat.baseName(of: doc.url))”", #selector(rxExtractToOwnFolder(_:))))
            item.menu = menu
            item.showsIndicator = true
            return item
        case ItemID.test:
            return button(itemIdentifier, "Kiểm tra", "checkmark.shield", "Kiểm tra tệp nén có bị hỏng không", #selector(rxTest(_:)))
        case ItemID.view:
            return button(itemIdentifier, "Xem nhanh", "eye", "Xem nhanh tệp đang chọn (⌘Y)", #selector(rxQuickLook(_:)))
        case ItemID.delete:
            return button(itemIdentifier, "Xoá", "trash", "Xoá mục đang chọn khỏi tệp nén", #selector(rxDeleteItems(_:)))
        case ItemID.info:
            return button(itemIdentifier, "Thông tin", "info.circle", "Thông tin tệp nén", #selector(rxShowInfo(_:)))
        case ItemID.tools:
            let item = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            configure(item, "Công cụ", "ellipsis.circle", "Thêm thao tác", nil)
            let menu = NSMenu()
            menu.addItem(menuItem("Thư mục mới…", #selector(rxNewFolder(_:))))
            menu.addItem(menuItem("Đổi tên…", #selector(rxRename(_:))))
            menu.addItem(.separator())
            menu.addItem(menuItem("Chuyển đổi định dạng…", #selector(rxConvert(_:))))
            menu.addItem(menuItem("Sửa tệp nén hỏng…", #selector(rxRepair(_:))))
            menu.addItem(menuItem("Khoá tệp RAR…", #selector(rxLock(_:))))
            menu.addItem(.separator())
            menu.addItem(menuItem("Tải lại", #selector(rxRefresh(_:))))
            menu.addItem(menuItem("Hiện trong Finder", #selector(rxReveal(_:))))
            item.menu = menu
            item.showsIndicator = true
            return item
        case ItemID.search:
            let item = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
            item.searchField.placeholderString = "Tìm trong tệp nén"
            item.searchField.delegate = self
            item.label = "Tìm"
            item.preferredWidthForSearchField = 220
            searchItem = item
            return item
        default:
            return nil
        }
    }

    private func configure(_ item: NSToolbarItem, _ label: String, _ symbol: String, _ tip: String, _ action: Selector?) {
        item.label = label
        item.paletteLabel = label
        item.toolTip = tip
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.isBordered = true
        if let action {
            item.target = self
            item.action = action
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ tip: String, _ action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        configure(item, label, symbol, tip, action)
        return item
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        validate(action: item.action)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(rxToggleSidebar(_:)) {
            menuItem.title = doc.showSidebar ? "Ẩn thanh bên" : "Hiện thanh bên"
        }
        if menuItem.action == #selector(rxToggleJunk(_:)) {
            menuItem.state = doc.hideJunk ? .off : .on
        }
        return validate(action: menuItem.action)
    }

    private var isEditingText: Bool {
        window?.firstResponder is NSText
    }

    private func validate(action: Selector?) -> Bool {
        guard let action else { return true }
        let loaded = doc.isLoaded
        let idle = !doc.isBusy
        let hasSelection = !doc.selection.isEmpty
        switch action {
        case #selector(rxAddFiles(_:)), #selector(rxNewFolder(_:)):
            return doc.canModify
        case #selector(rxDeleteItems(_:)):
            return doc.canModify && hasSelection && !isEditingText
        case #selector(rxRename(_:)):
            return doc.canRename
        case #selector(rxExtract(_:)), #selector(rxExtractHere(_:)), #selector(rxExtractToOwnFolder(_:)),
             #selector(rxTest(_:)), #selector(rxConvert(_:)):
            return loaded && idle
        case #selector(rxQuickLook(_:)):
            return loaded && doc.selectedNodes.contains { !$0.isDirectory }
        case #selector(rxOpenSelection(_:)):
            return loaded && hasSelection && !isEditingText
        case #selector(rxShowInfo(_:)):
            return loaded
        case #selector(rxRepair(_:)):
            return doc.canRepair
        case #selector(rxLock(_:)):
            return doc.canLock
        case #selector(rxGoUp(_:)):
            return doc.canGoUp
        default:
            return true
        }
    }

    // MARK: - Tìm kiếm

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        doc.searchText = field.stringValue
    }

    // MARK: - Hành động

    @objc func rxToggleSidebar(_ sender: Any?) { doc.showSidebar.toggle() }
    @objc func rxAddFiles(_ sender: Any?) { doc.chooseFilesToAdd() }
    @objc func rxExtract(_ sender: Any?) { doc.presentExtract() }
    @objc func rxExtractHere(_ sender: Any?) { doc.extractHere() }

    @objc func rxExtractToOwnFolder(_ sender: Any?) {
        var config = ExtractConfig.defaults(for: doc.url)
        config.baseFolder = doc.url.deletingLastPathComponent()
        config.folderMode = .alwaysFolder
        config.trashArchiveAfter = false
        config.selectionOnly = !doc.selection.isEmpty
        doc.performExtract(config)
    }

    @objc func rxTest(_ sender: Any?) { doc.test() }
    @objc func rxQuickLook(_ sender: Any?) { doc.quickLook() }
    @objc func rxDeleteItems(_ sender: Any?) { doc.deleteSelection() }
    @objc func rxShowInfo(_ sender: Any?) { doc.sheet = .info }
    @objc func rxNewFolder(_ sender: Any?) { doc.createFolder() }
    @objc func rxRename(_ sender: Any?) { doc.renameSelection() }
    @objc func rxConvert(_ sender: Any?) { doc.sheet = .convert }
    @objc func rxRepair(_ sender: Any?) { doc.repair() }
    @objc func rxLock(_ sender: Any?) { doc.lockArchive() }
    @objc func rxRefresh(_ sender: Any?) { doc.load(keepPath: true) }
    @objc func rxReveal(_ sender: Any?) { doc.revealInFinder() }
    @objc func rxGoUp(_ sender: Any?) { doc.goUp() }
    @objc func rxOpenSelection(_ sender: Any?) { doc.openSelection() }
    @objc func rxToggleJunk(_ sender: Any?) { doc.hideJunk.toggle() }

    @objc func rxFind(_ sender: Any?) {
        if let item = searchItem {
            item.beginSearchInteraction()
        }
    }
}
