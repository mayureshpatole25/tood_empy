import AppKit

/// Builds and keeps the menu-bar item's menu in sync with the sticky set.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let manager: StickyManager
    private weak var appDelegate: AppDelegate?

    init(manager: StickyManager, appDelegate: AppDelegate) {
        self.manager = manager
        self.appDelegate = appDelegate
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeMenuBarIcon()
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    // Rebuild every time the menu opens so the sticky list stays current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(withTitle: "Open Today", action: #selector(openHome), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())

        menu.addItem(withTitle: "New Sticky", action: #selector(newSticky), keyEquivalent: "n")
            .target = self
        menu.addItem(withTitle: "Show Active Sticky", action: #selector(showActiveSticky), keyEquivalent: "")
            .target = self

        let stickies = manager.stickyList()
        if !stickies.isEmpty {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "Your Stickies", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for sticky in stickies {
                let item = NSMenuItem(title: "  \(sticky.title)",
                                      action: #selector(focusSticky(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = sticky.id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Show All", action: #selector(showAll), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Hide All", action: #selector(hideAll), keyEquivalent: "")
            .target = self
        let deleteAll = menu.addItem(withTitle: "Delete All", action: #selector(deleteAll), keyEquivalent: "")
        deleteAll.target = self
        deleteAll.isEnabled = !stickies.isEmpty

        menu.addItem(.separator())
        let colorItem = NSMenuItem(title: "Default Color", action: nil, keyEquivalent: "")
        colorItem.submenu = defaultColorMenu()
        menu.addItem(colorItem)

        let fontItem = NSMenuItem(title: "Default Font", action: nil, keyEquivalent: "")
        fontItem.submenu = defaultFontMenu()
        menu.addItem(fontItem)

        let positionItem = NSMenuItem(title: "New Sticky Position", action: nil, keyEquivalent: "")
        positionItem.submenu = startCornerMenu()
        menu.addItem(positionItem)

        menu.addItem(.separator())
        let archiveInfo = NSMenuItem(title: "Archived: \(manager.archive.count)",
                                     action: nil, keyEquivalent: "")
        archiveInfo.isEnabled = false
        menu.addItem(archiveInfo)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Today", action: #selector(quit), keyEquivalent: "q")
            .target = self
    }

    // MARK: - Actions

    @objc private func openHome() { appDelegate?.showHome() }
    @objc private func openSettings() { appDelegate?.showSettings() }
    @objc private func showActiveSticky() { manager.showActiveSticky() }
    @objc private func newSticky() { manager.newSticky() }
    @objc private func showAll() { manager.showAll() }
    @objc private func hideAll() { manager.hideAll() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func deleteAll() {
        let alert = NSAlert()
        alert.messageText = "Delete All Stickies?"
        alert.informativeText = "This deletes every sticky for good — same as closing each one. This can't be undone."
        alert.addButton(withTitle: "Delete All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            manager.removeAll()
        }
    }

    @objc private func focusSticky(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        manager.bringToFront(id)
    }

    /// The color new stickies (via "New Sticky" or the panel's + button) are
    /// created with — "Cycle" (the default) rotates through the pack.
    private func defaultColorMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = StickyColor.defaultColor

        let randomItem = NSMenuItem(title: "Cycle", action: #selector(setDefaultColorRandom),
                                    keyEquivalent: "")
        randomItem.target = self
        randomItem.state = current == nil ? .on : .off
        submenu.addItem(randomItem)
        submenu.addItem(.separator())

        // Owned colors only — the status-bar menu isn't a place to build
        // paywall UI; buying a pack happens from a sticky's own picker.
        let ownedColors = StickyColor.allCases.filter { $0.pack == nil || ColorPackStore.shared.isUnlocked($0.pack!) }
        for c in ownedColors {
            let item = NSMenuItem(title: c.displayName, action: #selector(setDefaultColor(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.state = c == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setDefaultColorRandom() { StickyColor.defaultColor = nil }

    @objc private func setDefaultColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? StickyColor else { return }
        StickyColor.defaultColor = color
    }

    /// The font new stickies are created with.
    private func defaultFontMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = StickyFont.defaultFont
        for f in StickyFont.allCases {
            let item = NSMenuItem(title: f.displayName, action: #selector(setDefaultFont(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = f
            item.state = f == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setDefaultFont(_ sender: NSMenuItem) {
        guard let font = sender.representedObject as? StickyFont else { return }
        StickyFont.defaultFont = font
    }

    /// Which screen corner new stickies are tiled from.
    private func startCornerMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = StickyCorner.startCorner
        for c in StickyCorner.allCases {
            let item = NSMenuItem(title: c.displayName, action: #selector(setStartCorner(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = c
            item.state = c == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setStartCorner(_ sender: NSMenuItem) {
        guard let corner = sender.representedObject as? StickyCorner else { return }
        StickyCorner.startCorner = corner
    }

    /// A small "To / Do" wordmark, stacked like the sticky's own title, in
    /// place of a generic system-symbol icon for the menu bar.
    private static func makeMenuBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 20)
        let image = NSImage(size: size, flipped: false) { rect in
            let font = NSFont(name: "HelveticaNeue-Bold", size: 9) ?? NSFont.boldSystemFont(ofSize: 9)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black,
                .paragraphStyle: paragraph
            ]
            let lineHeight: CGFloat = 10
            ("To" as NSString).draw(in: NSRect(x: 0, y: lineHeight, width: rect.width, height: lineHeight),
                                    withAttributes: attrs)
            ("Do" as NSString).draw(in: NSRect(x: 0, y: 0, width: rect.width, height: lineHeight),
                                    withAttributes: attrs)
            return true
        }
        image.isTemplate = true // adapts to light/dark menu bar automatically
        return image
    }
}
