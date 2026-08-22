import FluidAudio
import Foundation
import S1Mini

@MainActor
final class DictationController {
    static let shared = DictationController()

    private let recorder = AudioRecorder()
    private let s1 = S1MiniEngine()
    private var asr: AsrManager?
    private var loadedParakeet: ParakeetVersion?
    private var busy = false
    private var listening = false

    private init() {}

    func bootstrap() {
        HotkeyTap.shared.onHoldBegan = { [weak self] in
            Task { @MainActor in self?.beginHold() }
        }
        HotkeyTap.shared.onHoldEnded = { [weak self] in
            Task { @MainActor in self?.endHold() }
        }
        HotkeyTap.shared.start()

        Task {
            _ = await PermissionService.requestMicrophone()
            PermissionService.promptAccessibility()
            PermissionService.refreshStatus()
            await prepareModels()
        }
    }

    func setEnabled(_ enabled: Bool) {
        AppState.shared.enabled = enabled
        if !enabled {
            _ = recorder.stop()
            listening = false
            s1.unload()
            asr = nil
            loadedParakeet = nil
            AppState.shared.status = .paused
            AppState.shared.modelsReady = false
        } else {
            HotkeyTap.shared.start()
            Task { await prepareModels() }
        }
        MenuBarController.shared.reload()
    }

    func prepareModels() async {
        let state = AppState.shared
        guard state.enabled else {
            state.status = .paused
            MenuBarController.shared.reload()
            return
        }

        PermissionService.refreshStatus()
        guard PermissionService.microphoneGranted else {
            MenuBarController.shared.reload()
            return
        }

        state.lastError = nil
        state.status = .downloading
        state.statusDetail = "Fetching S1-mini by Superwhisper"
        MenuBarController.shared.reload()

        do {
            try await ModelStore.downloadS1Mini { fraction in
                Task { @MainActor in
                    AppState.shared.downloadFraction = fraction
                    AppState.shared.statusDetail = "S1-mini by Superwhisper"
                    MenuBarController.shared.reload()
                }
            }

            state.statusDetail = "Loading Parakeet"
            state.downloadFraction = nil
            MenuBarController.shared.reload()

            let version = SettingsStore.shared.parakeetVersion
            if asr == nil || loadedParakeet != version {
                asr = try await ParakeetBridge.load(version: version)
                loadedParakeet = version
            }

            if !s1.isLoaded {
                state.statusDetail = "Loading S1-mini by Superwhisper"
                MenuBarController.shared.reload()
                try await Task.detached { [s1] in
                    try s1.load(modelURL: ModelStore.s1MiniURL)
                }.value
            }

            state.modelsReady = true
            state.status = PermissionService.accessibilityGranted ? .idle : .needsPermission
            state.statusDetail = PermissionService.accessibilityGranted
                ? ""
                : "Need Accessibility for paste and Right Option"
            MenuBarController.shared.reload()
        } catch {
            state.modelsReady = false
            state.lastError = error.localizedDescription
            state.status = .paused
            MenuBarController.shared.reload()
        }
    }

    private func beginHold() {
        guard AppState.shared.enabled, AppState.shared.modelsReady, !busy else { return }
        guard PermissionService.microphoneGranted else { return }
        do {
            try recorder.start()
            listening = true
            AppState.shared.status = .listening
            AppState.shared.lastError = nil
            MenuBarController.shared.reload()
        } catch {
            AppState.shared.lastError = "Mic failed: \(error.localizedDescription)"
            MenuBarController.shared.reload()
        }
    }

    private func endHold() {
        guard listening else { return }
        listening = false
        let samples = recorder.stop()
        guard samples.count > 4800 else {
            AppState.shared.status = .idle
            MenuBarController.shared.reload()
            return
        }
        Task { await transcribeAndPaste(samples: samples) }
    }

    private func transcribeAndPaste(samples: [Float]) async {
        busy = true
        AppState.shared.status = .processing
        MenuBarController.shared.reload()
        defer {
            busy = false
            if AppState.shared.enabled {
                AppState.shared.status = .idle
            }
            MenuBarController.shared.reload()
        }

        do {
            guard let asr else { throw PipelineError.asrMissing }
            var decoderState = try TdtDecoderState()
            let result = try await asr.transcribe(samples, decoderState: &decoderState)
            let trimmed = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let settings = SettingsStore.shared
            let engine = s1
            let styling = settings.styling.rawValue
            let structure = settings.structure.rawValue
            let context = settings.context.rawValue
            let cleaned = try await Task.detached {
                try engine.normalize(
                    transcript: trimmed,
                    styling: styling,
                    structure: structure,
                    context: context
                )
            }.value
            // S1-mini sometimes emits nothing for command-shaped speech
            // ("make the repo public rather than private"). Paste ASR instead.
            let toPaste = cleaned.isEmpty ? trimmed : cleaned
            guard !toPaste.isEmpty else { return }
            PasteService.paste(toPaste)
        } catch {
            AppState.shared.lastError = error.localizedDescription
        }
    }
}

enum PipelineError: Error {
    case asrMissing
}
