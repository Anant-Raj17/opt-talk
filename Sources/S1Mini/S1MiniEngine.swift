import Foundation
import LlamaSwift

/// Runs Superwhisper S1-mini (GGUF) with greedy decoding and thinking off.
public final class S1MiniEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var backendReady = false

    public init() {}

    deinit {
        unload()
        if backendReady {
            llama_backend_free()
        }
    }

    public var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return model != nil && context != nil
    }

    public func load(modelURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }

        unloadLocked()

        if !backendReady {
            llama_backend_init()
            backendReady = true
        }

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99

        let path = modelURL.path
        guard let loaded = llama_model_load_from_file(path, modelParams) else {
            throw S1MiniError.loadFailed(path)
        }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = 4096
        ctxParams.n_batch = 512
        ctxParams.n_threads = max(2, Int32(ProcessInfo.processInfo.activeProcessorCount / 2))
        ctxParams.n_threads_batch = ctxParams.n_threads

        guard let ctx = llama_init_from_model(loaded, ctxParams) else {
            llama_model_free(loaded)
            throw S1MiniError.contextFailed
        }

        model = loaded
        context = ctx
    }

    public func unload() {
        lock.lock()
        defer { lock.unlock() }
        unloadLocked()
    }

    public func normalize(
        transcript: String,
        styling: String,
        structure: String,
        context: String
    ) throws -> String {
        let prompt = Self.buildPrompt(
            transcript: transcript,
            styling: styling,
            structure: structure,
            context: context
        )
        return try generate(prompt: prompt)
    }

    private func unloadLocked() {
        if let context {
            llama_free(context)
            self.context = nil
        }
        if let model {
            llama_model_free(model)
            self.model = nil
        }
    }

    private func generate(prompt: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let model, let context else {
            throw S1MiniError.notLoaded
        }

        guard let vocab = llama_model_get_vocab(model) else {
            throw S1MiniError.notLoaded
        }
        let promptTokens = try tokenize(vocab: vocab, text: prompt, addSpecial: true)
        let nCtx = Int(llama_n_ctx(context))
        guard promptTokens.count < nCtx - 8 else {
            throw S1MiniError.promptTooLong
        }

        llama_memory_clear(llama_get_memory(context), true)

        let nBatch = 512
        var batch = llama_batch_init(Int32(nBatch), 0, 1)
        defer { llama_batch_free(batch) }

        var filled = 0
        while filled < promptTokens.count {
            let end = min(filled + nBatch, promptTokens.count)
            try decodeTokens(
                context: context,
                batch: &batch,
                tokens: promptTokens,
                range: filled..<end
            )
            filled = end
        }

        var output = ""
        output.reserveCapacity(256)
        var pos = promptTokens.count
        let maxNew = max(0, nCtx - promptTokens.count - 1)
        let eos = llama_vocab_eos(vocab)
        let eot = llama_vocab_eot(vocab)

        for _ in 0..<maxNew {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else {
                throw S1MiniError.decodeFailed
            }

            let vocabSize = Int(llama_vocab_n_tokens(vocab))
            var best: llama_token = 0
            var bestLogit = logits[0]
            for i in 1..<vocabSize {
                let value = logits[i]
                if value > bestLogit {
                    bestLogit = value
                    best = llama_token(i)
                }
            }

            if best == eos || (eot != 0 && best == eot) {
                break
            }

            if let piece = detokenize(vocab: vocab, token: best) {
                if piece.contains("<|im_end|>") {
                    break
                }
                output.append(piece)
            }

            pos += 1
            try decodeTokens(
                context: context,
                batch: &batch,
                tokens: [best],
                range: 0..<1,
                startPos: pos - 1
            )
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeTokens(
        context: OpaquePointer,
        batch: inout llama_batch,
        tokens: [llama_token],
        range: Range<Int>,
        startPos: Int? = nil
    ) throws {
        let count = range.count
        guard count > 0 else { return }
        let posBase = startPos ?? range.lowerBound
        batch.n_tokens = Int32(count)
        for i in 0..<count {
            batch.token[i] = tokens[range.lowerBound + i]
            batch.pos[i] = Int32(posBase + i)
            batch.n_seq_id[i] = 1
            if let seqIds = batch.seq_id, let seq = seqIds[i] {
                seq[0] = 0
            }
            batch.logits[i] = i == count - 1 ? 1 : 0
        }
        guard llama_decode(context, batch) == 0 else {
            throw S1MiniError.decodeFailed
        }
    }

    private func tokenize(vocab: OpaquePointer, text: String, addSpecial: Bool) throws -> [llama_token] {
        let utf8 = Array(text.utf8)
        let maxCount = utf8.count + 32
        var tokens = [llama_token](repeating: 0, count: maxCount)
        let count = utf8.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: utf8.count) { cstr in
                llama_tokenize(
                    vocab,
                    cstr,
                    Int32(utf8.count),
                    &tokens,
                    Int32(maxCount),
                    addSpecial,
                    true
                )
            }
        }
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            let retry = utf8.withUnsafeBufferPointer { buffer in
                buffer.baseAddress!.withMemoryRebound(to: CChar.self, capacity: utf8.count) { cstr in
                    llama_tokenize(
                        vocab,
                        cstr,
                        Int32(utf8.count),
                        &tokens,
                        Int32(tokens.count),
                        addSpecial,
                        true
                    )
                }
            }
            guard retry > 0 else { throw S1MiniError.tokenizeFailed }
            return Array(tokens.prefix(Int(retry)))
        }
        guard count > 0 else { throw S1MiniError.tokenizeFailed }
        return Array(tokens.prefix(Int(count)))
    }

    private func detokenize(vocab: OpaquePointer, token: llama_token) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        var length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length) + 1)
            length = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, true)
        }
        guard length > 0 else { return nil }
        let bytes = buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8)
    }

    /// Exact training prefix from the S1-mini model card, thinking off.
    public static func buildPrompt(
        transcript: String,
        styling: String,
        structure: String,
        context: String
    ) -> String {
        let system = """
        You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text.
        """
        let control = "[Styling: \(styling)] [Structure: \(structure)] [Context: \(context)]"
        return """
        <|im_start|>system
        \(system)<|im_end|>
        <|im_start|>user
        \(control)
        \(transcript)<|im_end|>
        <|im_start|>assistant
        <think>

        </think>

        """
    }
}

public enum S1MiniError: Error, LocalizedError {
    case loadFailed(String)
    case contextFailed
    case notLoaded
    case tokenizeFailed
    case decodeFailed
    case promptTooLong

    public var errorDescription: String? {
        switch self {
        case .loadFailed(let path):
            return "Could not load S1-mini at \(path)"
        case .contextFailed:
            return "Could not create an S1-mini context"
        case .notLoaded:
            return "S1-mini is not loaded"
        case .tokenizeFailed:
            return "S1-mini failed to tokenize"
        case .decodeFailed:
            return "S1-mini decode failed"
        case .promptTooLong:
            return "Transcript is too long for S1-mini"
        }
    }
}
