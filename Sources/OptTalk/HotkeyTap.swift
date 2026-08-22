import CoreGraphics
import Foundation

/// Hold Right Option to talk. Swallows Right Option so it does not type Option-characters.
final class HotkeyTap: @unchecked Sendable {
    static let shared = HotkeyTap()

    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?

    private var tap: CFMachPort?
    private var holding = false
    private let rightOptionKeyCode: Int64 = 61
    private let rightOptionDeviceBit: UInt64 = 0x00000040

    private init() {}

    func start() {
        stop()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
                return tap.handle(type: type, event: event)
            },
            userInfo: pointer
        ) else {
            Task { @MainActor in
                AppState.shared.status = .needsPermission
                AppState.shared.statusDetail = "Accessibility is required for Right Option"
                AppState.shared.lastError = "Could not install the key tap. Enable Accessibility for opt-talk."
            }
            return
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        tap = nil
        holding = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        let enabled = MainActor.assumeIsolatedIfAvailable {
            AppState.shared.enabled && AppState.shared.modelsReady && AppState.shared.status != .needsPermission
        }

        guard enabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == rightOptionKeyCode else {
            return Unmanaged.passUnretained(event)
        }

        let down = event.flags.rawValue & rightOptionDeviceBit != 0
        if down && !holding {
            holding = true
            DispatchQueue.main.async { [weak self] in
                self?.onHoldBegan?()
            }
        } else if !down && holding {
            holding = false
            DispatchQueue.main.async { [weak self] in
                self?.onHoldEnded?()
            }
        }

        return nil
    }
}

private extension MainActor {
    static func assumeIsolatedIfAvailable(_ body: @MainActor () -> Bool) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(body)
        }
        var result = false
        DispatchQueue.main.sync {
            result = body()
        }
        return result
    }
}
