import Foundation

/// Pauses Now Playing for a hold, then resumes only if we paused it.
///
/// Direct MediaRemote calls from this process no-op on macOS 15.4+.
/// `/usr/bin/osascript` is still allowed to talk to the daemon. SendCommand
/// also needs a short run-loop spin or the pause never reaches the player.
@MainActor
final class MediaPauseService {
    static let shared = MediaPauseService()

    private var sessionID: UInt64 = 0
    private var didPauseForHold = false

    private init() {}

    func pauseIfPlaying() {
        sessionID &+= 1
        didPauseForHold = false
        let id = sessionID
        Task { [weak self] in
            let result = await Self.run(action: "pause-if-playing")
            guard let self else { return }
            if self.sessionID != id {
                if result == "paused" {
                    _ = await Self.run(action: "play")
                }
                return
            }
            self.didPauseForHold = result == "paused"
        }
    }

    func resumeIfWePaused() {
        sessionID &+= 1
        let shouldPlay = didPauseForHold
        didPauseForHold = false
        guard shouldPlay else { return }
        Task {
            _ = await Self.run(action: "play")
        }
    }

    private static func run(action: String) async -> String {
        let script = jxa
        return await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-l", "JavaScript", "-e", script, action]
            let out = Pipe()
            proc.standardOutput = out
            proc.standardError = Pipe()
            do {
                try proc.run()
                proc.waitUntilExit()
            } catch {
                return ""
            }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }.value
    }

    private static let jxa = """
    function run(argv) {
      ObjC.import('Foundation');
      const bundle = $.NSBundle.bundleWithPath(
        '/System/Library/PrivateFrameworks/MediaRemote.framework/'
      );
      bundle.load;
      const action = argv[0] || '';
      const Request = $.NSClassFromString('MRNowPlayingRequest');

      function rate() {
        try {
          const info = Request.localNowPlayingItem.nowPlayingInfo;
          const r = info.valueForKey('kMRMediaRemoteNowPlayingInfoPlaybackRate');
          return r ? Number(r.js) : 0;
        } catch (e) {
          return 0;
        }
      }

      function send(cmd) {
        ObjC.bindFunction('MRMediaRemoteSendCommand', ['B', ['q', '@']]);
        $.MRMediaRemoteSendCommand(cmd, $.NSDictionary.dictionary);
        $.NSRunLoop.currentRunLoop.runUntilDate(
          $.NSDate.dateWithTimeIntervalSinceNow(0.4)
        );
      }

      if (action === 'pause-if-playing') {
        if (rate() <= 0) return 'idle';
        send(1);
        return rate() > 0 ? 'still-playing' : 'paused';
      }
      if (action === 'play') {
        send(0);
        return 'ok';
      }
      return 'bad-action';
    }
    """
}
