import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let root = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: root)
            window.title = "\(AppBrand.emoji) \(AppBrand.name)"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 520))
            window.center()
            self.window = window
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsView: View {
    @State private var version = SettingsStore.shared.parakeetVersion
    @State private var styling = SettingsStore.shared.styling
    @State private var structure = SettingsStore.shared.structure
    @State private var context = SettingsStore.shared.context
    @State private var launchAtLogin = SettingsStore.shared.launchAtLogin
    @State private var mics: [AVCaptureDevice] = []
    @State private var selectedMic = SettingsStore.shared.micUID ?? ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(AppBrand.emoji)
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppBrand.name)
                            .font(.title2.weight(.semibold))
                        Text("Local hold-to-talk dictation")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(AppBrand.name)")
            }

            Section("Speech to text") {
                Picker("Parakeet", selection: $version) {
                    ForEach(ParakeetVersion.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("Microphone", selection: $selectedMic) {
                    Text("System default").tag("")
                    ForEach(mics, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID)
                    }
                }
            }
            Section("S1-mini by Superwhisper") {
                Picker("Styling", selection: $styling) {
                    ForEach(S1Styling.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("Structure", selection: $structure) {
                    ForEach(S1Structure.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                Picker("Context", selection: $context) {
                    ForEach(S1Context.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
            }
            Section("Permissions") {
                Button("Request Accessibility") {
                    PermissionService.promptAccessibility()
                    PermissionService.openAccessibilitySettings()
                }
                Button("Microphone settings") {
                    PermissionService.openMicrophoneSettings()
                }
                Button("Input Monitoring settings") {
                    PermissionService.openInputMonitoringSettings()
                }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                Text("Hold Right Option. Release to paste into the field that has the text cursor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
        .onAppear {
            mics = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.microphone],
                mediaType: .audio,
                position: .unspecified
            ).devices
            selectedMic = SettingsStore.shared.micUID ?? ""
        }
        .onChange(of: version) { _, value in
            SettingsStore.shared.parakeetVersion = value
            Task { await DictationController.shared.prepareModels() }
        }
        .onChange(of: styling) { _, value in SettingsStore.shared.styling = value }
        .onChange(of: structure) { _, value in SettingsStore.shared.structure = value }
        .onChange(of: context) { _, value in SettingsStore.shared.context = value }
        .onChange(of: selectedMic) { _, value in
            SettingsStore.shared.micUID = value.isEmpty ? nil : value
        }
        .onChange(of: launchAtLogin) { _, value in
            SettingsStore.shared.launchAtLogin = value
        }
    }
}
