import AppKit
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
    private var holdActive = false
    private var statusBeforeHold: AppStatus?
    private var s1LoadTask: Task<Void, Error>?
    private var idleUnloadTask: Task<Void, Never>?
    private var tapActivity: NSObjectProtocol?
    private var wakeObservers: [NSObjectProtocol] = []

    private init() {}

    func bootstrap() {
        HotkeyTap.shared.onHoldBegan = { [weak self] in
            Task { @MainActor in self?.beginHold() }
        }
        HotkeyTap.shared.onHoldEnded = { [weak self] in
            Task { @MainActor in self?.endHold() }
        }
        HotkeyTap.shared.setDictationOn(AppState.shared.enabled)
        if AppState.shared.enabled {
            beginTapActivity()
        }
        HotkeyTap.shared.start()
        observeWake()

        Task {
            _ = await PermissionService.requestMicrophone()
            PermissionService.promptAccessibility()
            PermissionService.refreshStatus()
            await prepareModels()
            if AppState.shared.enabled, PermissionService.accessibilityGranted {
                HotkeyTap.shared.start()
            }
        }
    }

    func rearmHotkeyIfNeeded() {
        guard AppState.shared.enabled, PermissionService.accessibilityGranted else { return }
        HotkeyTap.shared.setDictationOn(true)
        beginTapActivity()
        HotkeyTap.shared.start()
    }

    func handleSystemWake() {
        recorder.reset()
        guard AppState.shared.enabled, PermissionService.accessibilityGranted else { return }
        HotkeyTap.shared.setDictationOn(true)
        beginTapActivity()
        HotkeyTap.shared.recreate()
        guard AppState.shared.modelsReady else { return }
        warmupS1()
    }

    func shutdown() {
        endTapActivity()
        HotkeyTap.shared.stop()
        recorder.reset()
        for observer in wakeObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        wakeObservers.removeAll()
    }

    func setEnabled(_ enabled: Bool) {
        AppState.shared.enabled = enabled
        HotkeyTap.shared.setDictationOn(enabled)
        if !enabled {
            endTapActivity()
            HotkeyTap.shared.stop()
            MediaPauseService.shared.resumeIfWePaused()
            _ = recorder.stop()
            listening = false
            holdActive = false
            statusBeforeHold = nil
            cancelIdleUnload()
            s1LoadTask?.cancel()
            s1LoadTask = nil
            s1.unload()
            asr = nil
            loadedParakeet = nil
            AppState.shared.status = .paused
            AppState.shared.modelsReady = false
        } else {
            beginTapActivity()
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

            state.modelsReady = true
            state.status = PermissionService.accessibilityGranted ? .idle : .needsPermission
            state.statusDetail = PermissionService.accessibilityGranted
                ? ""
                : "Need Accessibility for paste and Right Option"
            if PermissionService.accessibilityGranted {
                HotkeyTap.shared.setDictationOn(true)
                beginTapActivity()
                HotkeyTap.shared.start()
            }
            MenuBarController.shared.reload()
        } catch {
            state.modelsReady = false
            state.lastError = error.localizedDescription
            state.status = .paused
            MenuBarController.shared.reload()
        }
    }

    private func beginHold() {
        guard AppState.shared.enabled else { return }
        if !holdActive {
            statusBeforeHold = AppState.shared.status
        }
        holdActive = true
        AppState.shared.status = .listening
        AppState.shared.lastError = nil
        MenuBarController.shared.reload()

        guard AppState.shared.modelsReady, !busy else {
            return
        }
        guard PermissionService.microphoneGranted else {
            return
        }
        cancelIdleUnload()
        warmupS1()
        MediaPauseService.shared.pauseIfPlaying()
        do {
            try recorder.start()
            listening = true
        } catch {
            listening = false
            MediaPauseService.shared.resumeIfWePaused()
            AppState.shared.lastError = "Mic failed: \(error.localizedDescription)"
            MenuBarController.shared.reload()
            scheduleIdleUnload()
        }
    }

    private func endHold() {
        guard holdActive else { return }
        holdActive = false
        guard listening else {
            if AppState.shared.enabled {
                let restored = statusBeforeHold == .listening ? .idle : (statusBeforeHold ?? .idle)
                AppState.shared.status = restored
            }
            statusBeforeHold = nil
            MenuBarController.shared.reload()
            return
        }
        MediaPauseService.shared.resumeIfWePaused()
        listening = false
        let samples = recorder.stop()
        guard samples.count > 4800 else {
            AppState.shared.status = .idle
            MenuBarController.shared.reload()
            scheduleIdleUnload()
            return
        }
        Task { await transcribeAndPaste(samples: samples) }
    }

    private func transcribeAndPaste(samples: [Float]) async {
        busy = true
        cancelIdleUnload()
        AppState.shared.status = .processing
        MenuBarController.shared.reload()
        defer {
            busy = false
            if AppState.shared.enabled {
                AppState.shared.status = .idle
                scheduleIdleUnload()
            }
            MenuBarController.shared.reload()
        }

        do {
            guard let asr else { throw PipelineError.asrMissing }
            var decoderState = try TdtDecoderState()
            let result = try await asr.transcribe(samples, decoderState: &decoderState)
            let trimmed = result.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            try await ensureS1Loaded()

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

    private func observeWake() {
        let center = NSWorkspace.shared.notificationCenter
        let handler: @Sendable (Notification) -> Void = { _ in
            Task { @MainActor in
                DictationController.shared.handleSystemWake()
            }
        }
        wakeObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main,
            using: handler
        ))
        wakeObservers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main,
            using: handler
        ))
    }

    private func beginTapActivity() {
        guard tapActivity == nil else { return }
        tapActivity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Right Option tap"
        )
    }

    private func endTapActivity() {
        if let tapActivity {
            ProcessInfo.processInfo.endActivity(tapActivity)
            self.tapActivity = nil
        }
    }

    private func warmupS1() {
        guard !s1.isLoaded else { return }
        Task { try? await ensureS1Loaded() }
    }

    private func ensureS1Loaded() async throws {
        if s1.isLoaded { return }
        if let s1LoadTask {
            try await s1LoadTask.value
            return
        }
        let task = Task.detached { [s1] in
            try s1.load(modelURL: ModelStore.s1MiniURL)
        }
        s1LoadTask = task
        do {
            try await task.value
        } catch {
            s1LoadTask = nil
            throw error
        }
    }

    private func cancelIdleUnload() {
        idleUnloadTask?.cancel()
        idleUnloadTask = nil
    }

    private func scheduleIdleUnload() {
        cancelIdleUnload()
        idleUnloadTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            guard AppState.shared.enabled, !busy, !listening else { return }
            s1.unload()
            s1LoadTask = nil
        }
    }
}

enum PipelineError: Error {
    case asrMissing
}
