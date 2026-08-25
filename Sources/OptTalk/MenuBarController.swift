import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = AppBrand.menuBarImage()
        item.button?.imagePosition = .imageOnly
        item.menu = menu
        menu.delegate = self
        self.item = item
        reload()
    }

    func reload() {
        menu.removeAllItems()
        let state = AppState.shared

        let title = NSMenuItem(title: "\(AppBrand.emoji) \(AppBrand.name)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let status = NSMenuItem(title: state.menuStatusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enable = NSMenuItem(
            title: state.enabled ? "Dictation On" : "Dictation Off",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enable.state = state.enabled ? .on : .off
        enable.target = self
        menu.addItem(enable)

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(AppBrand.name)", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        updateButtonAppearance()
    }

    func menuWillOpen(_ menu: NSMenu) {
        PermissionService.refreshStatus()
        if PermissionService.accessibilityGranted, AppState.shared.enabled {
            HotkeyTap.shared.start()
        }
        reload()
    }

    @objc private func toggleEnabled() {
        DictationController.shared.setEnabled(!AppState.shared.enabled)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func updateButtonAppearance() {
        guard let button = item?.button else { return }
        let state = AppState.shared
        let label: String
        let tint: NSColor?
        let tooltip: String
        switch state.status {
        case .idle:
            label = ""
            tint = nil
            tooltip = "\(AppBrand.name) · Hold Right Option to dictate"
        case .listening:
            label = "REC"
            tint = .systemRed
            tooltip = "\(AppBrand.name) · Listening"
        case .processing:
            label = "…"
            tint = .systemOrange
            tooltip = "\(AppBrand.name) · Transcribing"
        case .paused:
            label = ""
            tint = nil
            tooltip = "\(AppBrand.name) · Paused"
        case .needsPermission:
            label = "!"
            tint = .systemYellow
            tooltip = "\(AppBrand.name) · Needs permission"
        case .downloading:
            label = "↓"
            tint = nil
            tooltip = "\(AppBrand.name) · Downloading models"
        }

        button.image = AppBrand.menuBarImage()
        button.imagePosition = label.isEmpty ? .imageOnly : .imageLeading
        button.contentTintColor = tint
        if label.isEmpty {
            button.title = ""
            button.attributedTitle = NSAttributedString()
        } else {
            button.attributedTitle = NSAttributedString(
                string: " \(label)",
                attributes: [
                    .foregroundColor: tint ?? NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold)
                ]
            )
        }
        button.alphaValue = 1
        button.toolTip = tooltip
        button.appearsDisabled = state.status == .paused
        button.needsDisplay = true
    }
}
