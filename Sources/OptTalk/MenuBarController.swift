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

        let symbol: String
        switch state.status {
        case .idle:
            symbol = "mic"
        case .listening:
            symbol = "mic.fill"
        case .processing:
            symbol = "waveform"
        case .paused:
            symbol = "mic.slash"
        case .needsPermission:
            symbol = "exclamationmark.triangle"
        case .downloading:
            symbol = "arrow.down.circle"
        }
        item?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "opt-talk")
        item?.button?.image?.isTemplate = true
        item?.button?.appearsDisabled = state.status == .paused
    }

    func menuWillOpen(_ menu: NSMenu) {
        PermissionService.refreshStatus()
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
}
