import Foundation
import ServiceManagement

enum ParakeetVersion: String, CaseIterable, Identifiable {
    case v2
    case v3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .v2: return "Parakeet TDT 0.6B v2 (English)"
        case .v3: return "Parakeet TDT 0.6B v3 (25 languages)"
        }
    }
}

enum S1Styling: String, CaseIterable, Identifiable {
    case casual, semiCasual = "semi-casual", semiFormal = "semi-formal", formal
    var id: String { rawValue }
}

enum S1Structure: String, CaseIterable, Identifiable {
    case prose, lists
    var id: String { rawValue }
}

enum S1Context: String, CaseIterable, Identifiable {
    case general, email
    var id: String { rawValue }
}

final class SettingsStore: @unchecked Sendable {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    var parakeetVersion: ParakeetVersion {
        get { ParakeetVersion(rawValue: defaults.string(forKey: "parakeetVersion") ?? "") ?? .v2 }
        set { defaults.set(newValue.rawValue, forKey: "parakeetVersion") }
    }

    var styling: S1Styling {
        get { S1Styling(rawValue: defaults.string(forKey: "styling") ?? "") ?? .semiFormal }
        set { defaults.set(newValue.rawValue, forKey: "styling") }
    }

    var structure: S1Structure {
        get { S1Structure(rawValue: defaults.string(forKey: "structure") ?? "") ?? .prose }
        set { defaults.set(newValue.rawValue, forKey: "structure") }
    }

    var context: S1Context {
        get { S1Context(rawValue: defaults.string(forKey: "context") ?? "") ?? .general }
        set { defaults.set(newValue.rawValue, forKey: "context") }
    }

    var micUID: String? {
        get { defaults.string(forKey: "micUID") }
        set { defaults.set(newValue, forKey: "micUID") }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("opt-talk login item: \(error.localizedDescription)")
            }
        }
    }

    private init() {}
}
