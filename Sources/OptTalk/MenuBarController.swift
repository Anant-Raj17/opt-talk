import AppKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private let menu = NSMenu()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "opt-talk")
        item.button?.image?.isTemplate = true
        item.menu = menu
        menu.delegate = self
        self.item = item
        reload()
    }

    func reload() {
        menu.removeAllItems()
        let state = AppState.shared

        let title = NSMenuItem(title: "opt-talk", action: nil, keyEquivalent: "")
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
        let quit = NSMenuItem(title: "Quit opt-talk", action: #selector(quit), keyEquivalent: "q")
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
        let symbol: String
        let label: String
        let tint: NSColor?
        let tooltip: String
        switch state.status {
        case .idle:
            symbol = "mic"
            label = ""
            tint = nil
            tooltip = "opt-talk · Hold Right Option to dictate"
        case .listening:
            symbol = "mic.fill"
            label = "REC"
            tint = .systemRed
            tooltip = "opt-talk · Listening"
        case .processing:
            symbol = "waveform"
            label = "…"
            tint = .systemOrange
            tooltip = "opt-talk · Transcribing"
        case .paused:
            symbol = "mic.slash"
            label = ""
            tint = nil
            tooltip = "opt-talk · Paused"
        case .needsPermission:
            symbol = "exclamationmark.triangle.fill"
            label = "!"
            tint = .systemYellow
            tooltip = "opt-talk · Needs permission"
        case .downloading:
            symbol = "arrow.down.circle"
            label = ""
            tint = nil
            tooltip = "opt-talk · Downloading models"
        }

        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "opt-talk")
        image?.isTemplate = true
        button.image = image
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
