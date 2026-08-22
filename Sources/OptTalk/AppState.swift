import Foundation

enum AppStatus: String {
    case paused
    case idle
    case listening
    case processing
    case needsPermission
    case downloading
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var enabled: Bool {
        didSet { SettingsStore.shared.enabled = enabled }
    }
    @Published var status: AppStatus = .paused
    @Published var statusDetail: String = ""
    @Published var modelsReady: Bool = false
    @Published var downloadFraction: Double?
    @Published var lastError: String?

    private init() {
        enabled = SettingsStore.shared.enabled
    }

    var menuStatusText: String {
        if let lastError {
            return lastError
        }
        switch status {
        case .paused:
            return "Paused"
        case .idle:
            return "Hold Right Option to dictate"
        case .listening:
            return "Listening…"
        case .processing:
            return "Transcribing…"
        case .needsPermission:
            return statusDetail.isEmpty ? "Grant mic and Accessibility" : statusDetail
        case .downloading:
            if let downloadFraction {
                return "Downloading models \(Int(downloadFraction * 100))%"
            }
            return statusDetail.isEmpty ? "Downloading models…" : statusDetail
        }
    }
}
