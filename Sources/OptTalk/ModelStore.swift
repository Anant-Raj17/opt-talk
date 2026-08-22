import FluidAudio
import Foundation

enum ModelStore {
    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("opt-talk", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var s1MiniURL: URL {
        supportDirectory.appendingPathComponent("s1-mini-q4_k_m.gguf")
    }

    static var s1MiniPresent: Bool {
        let size = (try? s1MiniURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 10_000_000
    }

    static func downloadS1Mini(progress: @escaping @Sendable (Double) -> Void) async throws {
        if s1MiniPresent {
            progress(1)
            return
        }

        let remote = URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf?download=true")!
        let dest = s1MiniURL
        let monitor = ProgressMonitor(handler: progress)
        let (temp, response) = try await URLSession.shared.download(from: remote, delegate: monitor)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw DownloadError.http(http.statusCode)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: temp, to: dest)
        progress(1)
    }
}

private final class ProgressMonitor: NSObject, URLSessionTaskDelegate, URLSessionDownloadDelegate, Sendable {
    let handler: @Sendable (Double) -> Void

    init(handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        handler(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

enum DownloadError: Error, LocalizedError {
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .http(let code):
            return "S1-mini download failed (HTTP \(code))"
        }
    }
}

enum ParakeetBridge {
    static func load(version: ParakeetVersion) async throws -> AsrManager {
        let models = try await AsrModels.downloadAndLoad(version: version == .v2 ? .v2 : .v3)
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return manager
    }
}
