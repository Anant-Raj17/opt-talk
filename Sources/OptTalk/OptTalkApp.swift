import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppBrand.applyApplicationIcon()
        MenuBarController.shared.install()
        DictationController.shared.bootstrap()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        DictationController.shared.rearmHotkeyIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DictationController.shared.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
