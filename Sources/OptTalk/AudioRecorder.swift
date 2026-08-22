@preconcurrency import AVFoundation
import Foundation

final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var recording = false

    func start() throws {
        _ = stop()
        lock.lock()
        samples = []
        recording = true
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            throw RecorderError.badFormat
        }
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer: buffer, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() -> [Float] {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        recording = false
        let captured = samples
        samples = []
        lock.unlock()
        return captured
    }

    private func append(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        lock.lock()
        let isRecording = recording
        let converter = converter
        lock.unlock()
        guard isRecording, let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
            return
        }

        var error: NSError?
        var consumed = false
        let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = outBuffer.floatChannelData?[0] else { return }
        let count = Int(outBuffer.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: count))
        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()
    }
}

enum RecorderError: Error {
    case badFormat
}
