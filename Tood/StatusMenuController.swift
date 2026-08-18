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

        menu.addItem(withTitle: "Open \(AppIdentity.displayName)", action: #selector(openHome), keyEquivalent: "")
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

        let titleSizeItem = NSMenuItem(title: "Default Title Size", action: nil, keyEquivalent: "")
        titleSizeItem.submenu = defaultTitleSizeMenu()
        menu.addItem(titleSizeItem)

        let closeBehaviorItem = NSMenuItem(title: "When Closing a Sticky", action: nil, keyEquivalent: "")
        closeBehaviorItem.submenu = closeBehaviorMenu()
        menu.addItem(closeBehaviorItem)

        let positionItem = NSMenuItem(title: "New Sticky Position", action: nil, keyEquivalent: "")
        positionItem.submenu = startCornerMenu()
        menu.addItem(positionItem)

        let focusItem = NSMenuItem(title: "Focus Sound", action: nil, keyEquivalent: "")
        focusItem.submenu = focusSoundMenu()
        menu.addItem(focusItem)

        menu.addItem(.separator())
        let archiveInfo = NSMenuItem(title: "Archived: \(manager.archive.count)",
                                     action: nil, keyEquivalent: "")
        archiveInfo.isEnabled = false
        menu.addItem(archiveInfo)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(AppIdentity.displayName)", action: #selector(quit), keyEquivalent: "q")
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
        alert.informativeText = "This deletes every sticky for good, same as closing each one. This can't be undone."
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

    /// The title size (ceiling) new stickies are created with — same
    /// setting as Settings' "Title Size" segmented picker.
    private func defaultTitleSizeMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = AppSettings.shared.titleSize
        for size in StickyTitleSize.allCases {
            let item = NSMenuItem(title: size.displayName, action: #selector(setDefaultTitleSize(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = size
            item.state = size == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setDefaultTitleSize(_ sender: NSMenuItem) {
        guard let size = sender.representedObject as? StickyTitleSize else { return }
        AppSettings.shared.titleSize = size
    }

    /// What closing a sticky does — same setting the close dialog's own
    /// "Don't ask me again" checkbox can set in the moment.
    private func closeBehaviorMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = AppSettings.shared.closeBehavior
        for behavior in StickyCloseBehavior.allCases {
            let item = NSMenuItem(title: behavior.displayName, action: #selector(setCloseBehavior(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = behavior
            item.state = behavior == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setCloseBehavior(_ sender: NSMenuItem) {
        guard let behavior = sender.representedObject as? StickyCloseBehavior else { return }
        AppSettings.shared.closeBehavior = behavior
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

    /// Ambient focus sound, synthesized live (see `FocusSoundPlayer`) —
    /// "Off" plus each `FocusSound`, checkmarked on whichever is playing.
    private func focusSoundMenu() -> NSMenu {
        let submenu = NSMenu()
        let current = FocusSoundPlayer.shared.currentSound

        let offItem = NSMenuItem(title: "Off", action: #selector(setFocusSoundOff), keyEquivalent: "")
        offItem.target = self
        offItem.state = current == nil ? .on : .off
        submenu.addItem(offItem)
        submenu.addItem(.separator())

        for sound in FocusSound.allCases {
            let item = NSMenuItem(title: sound.displayName, action: #selector(setFocusSound(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = sound
            item.state = sound == current ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    @objc private func setFocusSoundOff() { FocusSoundPlayer.shared.stop() }

    @objc private func setFocusSound(_ sender: NSMenuItem) {
        guard let sound = sender.representedObject as? FocusSound else { return }
        FocusSoundPlayer.shared.play(sound)
    }

    /// The frog glyph — same outline mark as the app/dock icon — drawn as a
    /// template image so AppKit fills it black on a light menu bar and white
    /// on a dark one automatically.
    private static func makeMenuBarIcon() -> NSImage {
        let source = NSImage(named: "MenuBarFrog") ?? NSImage()
        let aspect = source.size.width > 0 ? source.size.height / source.size.width : 1
        let size = NSSize(width: 20, height: 20 * aspect)
        let image = NSImage(size: size, flipped: false) { rect in
            source.draw(in: rect)
            return true
        }
        image.isTemplate = true // adapts to light/dark menu bar automatically
        return image
    }
}
