import CoreGraphics
import Foundation

/// Hold Right Option to talk. Swallows Right Option so it does not type Option-characters.
final class HotkeyTap: @unchecked Sendable {
    static let shared = HotkeyTap()

    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?

    private var tap: CFMachPort?
    private var holding = false
    private let lock = NSLock()
    private var dictationOn = true
    private let rightOptionKeyCode: Int64 = 61
    private let rightOptionDeviceBit: UInt64 = 0x00000040

    private init() {}

    func setDictationOn(_ on: Bool) {
        lock.lock()
        dictationOn = on
        lock.unlock()
        if !on {
            holding = false
        }
    }

    func start() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            return
        }
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
                MenuBarController.shared.reload()
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

        lock.lock()
        let armed = dictationOn
        lock.unlock()
        guard armed else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let deviceRightAlt = flags.rawValue & rightOptionDeviceBit != 0
        let isRightOptionKey = keyCode == rightOptionKeyCode
        let rightAltEdge = deviceRightAlt != holding && (keyCode == 0 || deviceRightAlt || isRightOptionKey)
        guard isRightOptionKey || rightAltEdge else {
            return Unmanaged.passUnretained(event)
        }

        let down: Bool
        if isRightOptionKey {
            down = flags.contains(.maskAlternate) || deviceRightAlt
        } else {
            down = deviceRightAlt
        }

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
