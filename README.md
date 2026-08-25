# opt-talk

Local hold-to-talk dictation for Apple Silicon Macs. Menu bar only. No floating pill.

Hold **Right Option**. Speak. Release. The cleaned text is pasted into whichever field currently has the text cursor.

Speech to text is NVIDIA Parakeet TDT 0.6B through [FluidAudio](https://github.com/FluidInference/FluidAudio) (Core ML, Neural Engine). Cleanup is [S1-mini by Superwhisper](https://huggingface.co/superwhisper/s1-mini).

## Requirements

- Apple Silicon
- macOS 14+
- Xcode / Swift 6 toolchain
- Microphone, Accessibility (and Input Monitoring if macOS asks)

## Build

```bash
make app
open dist/opt-talk.app
```

First launch downloads Parakeet and `s1-mini-q4_k_m.gguf` into `~/Library/Application Support/opt-talk`. After that it runs offline.

## Settings

Menu bar icon (🗣️): toggle dictation, Settings, Quit.

S1-mini control line (styling / structure / context) lives in Settings. The system prompt is the one from the S1-mini model card. Decoding is greedy with thinking off.

## License

App code is MIT. S1-mini is Apache 2.0 plus Superwhisper's naming clause; keep the name **S1-mini** by **Superwhisper**. Parakeet weights follow NVIDIA's model license.
