import AppKit
import QuartzCore

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()

    private var item: NSStatusItem?
    private let menu = NSMenu()
    private var pulseTimer: Timer?
    private var pulseDimmed = false

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
        let state = AppState.shared
        let symbol: String
        let tint: NSColor?
        let tooltip: String
        switch state.status {
        case .idle:
            symbol = "mic"
            tint = nil
            tooltip = "opt-talk · Hold Right Option to dictate"
        case .listening:
            symbol = "mic.circle.fill"
            tint = .systemRed
            tooltip = "opt-talk · Listening"
        case .processing:
            symbol = "waveform.circle.fill"
            tint = .systemOrange
            tooltip = "opt-talk · Transcribing"
        case .paused:
            symbol = "mic.slash"
            tint = nil
            tooltip = "opt-talk · Paused"
        case .needsPermission:
            symbol = "exclamationmark.triangle.fill"
            tint = .systemYellow
            tooltip = "opt-talk · Needs permission"
        case .downloading:
            symbol = "arrow.down.circle"
            tint = nil
            tooltip = "opt-talk · Downloading models"
        }

        item?.button?.image = statusImage(symbol: symbol, tint: tint)
        item?.button?.toolTip = tooltip
        item?.button?.appearsDisabled = state.status == .paused
        setListeningPulse(state.status == .listening)
    }

    private func statusImage(symbol: String, tint: NSColor?) -> NSImage? {
        let weight: NSFont.Weight = tint == nil ? .regular : .semibold
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: weight)
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: "opt-talk")?
            .withSymbolConfiguration(config) else {
            return nil
        }
        guard let tint else {
            base.isTemplate = true
            return base
        }

        let size = base.size
        let rendered = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            tint.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        rendered.isTemplate = false
        return rendered
    }

    private func setListeningPulse(_ active: Bool) {
        guard active else {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulseDimmed = false
            item?.button?.alphaValue = 1
            return
        }
        guard pulseTimer == nil else { return }
        pulseDimmed = false
        item?.button?.alphaValue = 1
        let timer = Timer(timeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tickPulse()
            }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        pulseTimer = timer
        tickPulse()
    }

    private func tickPulse() {
        guard let button = item?.button else { return }
        pulseDimmed.toggle()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.5
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            button.animator().alphaValue = pulseDimmed ? 0.28 : 1
        }
    }
}
