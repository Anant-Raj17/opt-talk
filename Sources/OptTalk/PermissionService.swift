import AppKit
import ApplicationServices
import AVFoundation

enum PermissionService {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    static func promptAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    static func refreshStatus() {
        let state = AppState.shared
        if !microphoneGranted || !accessibilityGranted {
            state.status = .needsPermission
            var bits: [String] = []
            if !microphoneGranted { bits.append("Microphone") }
            if !accessibilityGranted { bits.append("Accessibility") }
            state.statusDetail = "Need \(bits.joined(separator: " and "))"
        } else if state.enabled && state.modelsReady {
            if state.status == .needsPermission || state.status == .paused {
                state.status = .idle
                state.statusDetail = ""
            }
        }
    }
}
