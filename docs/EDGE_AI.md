# WORLD.EXE / Edge Tactical Intelligence

## Deployment boundary
This feature is an **optional advisory layer**, never the authoritative game engine.
- `WorldCore.TacticalAdvisor`: deterministic, offline, testable, legal move/recover/extract/turn suggestions.
- `TacticalNarrator`: Apple Foundation Models on supported iOS 26+ hardware when available; otherwise rules-engine fallback. Generated text cannot mutate the mission.
- `GGUFModelStore`: opt-in verified HTTPS GGUF download, SHA-256 verification, local protected storage and deletion. **No GGUF inference is enabled yet.**
- Future `llama.cpp` adapter: use the upstream version-pinned XCFramework with Metal, not a background network server. Isolate inference in a serial actor and support cancellation.

## WWDC26 / iOS 27 roadmap
Evaluate Apple's updated Foundation Models `LanguageModel` abstraction, Core AI/MLX adapters, dynamic profiles, structured `@Generable` output, multimodal inputs, token accounting, evaluations and Instruments. Do not ship untested beta-only API on the stable Xcode 26.3 pipeline. Keep the iOS 18 training fallback.

## Model acquisition and provenance
Use a pinned Hugging Face revision and a specific GGUF file. Keep a signed/reviewed model manifest with repo, revision, filename, SHA-256, upstream license, model card, quantization, tokenizer/template, context length and source URL. Do not silently download gigabytes or bundle weights without license review. `GGUFModelStore` requires explicit approved URL and SHA-256. Link or delete model only through user-visible controls. No model weights are committed to Git.

Candidate for profiling only (not selected/benchmarked): ggml-org/Qwen3.5-0.8B-GGUF. Verify license, files, exact commit and SHA before selecting. Test a 0.5–1.5B parameter Q4 model first. Quantization is not distillation: distillation requires an independently licensed teacher/student training and evaluation pipeline. No model has been distilled.

## Rheknel boundary
Rheknel is a separate legacy project. Do not import its verdict/ABI/execution paths into WORLD.EXE. Define an original `TacticalDecisionPolicy` interface and separately review any future integration. Never claim an authoritative Rheknel verdict from this prototype.

## Performance budget (targets, not measured)
- Game renderer: adaptive 30/60 fps; degrade particles/shadows before losing touch responsiveness.
- LiDAR/RoomPlan: run only in active sensor mode, stop on background/mode switch.
- Inference: asynchronous, user-triggered, cancellable; avoid continuous token generation during scanning.
- RAM: model memory + KV cache + render buffers must be profiled on physical device; 512 GB storage is **not** 512 GB RAM.
- Power/thermal: use ProcessInfo.thermalState and Low Power Mode; stop optional LLM on serious/critical thermal pressure.
- Quality gates: first-token latency, tokens/s, peak resident memory, frame-time p95, thermal state, battery draw, deterministic legality rate, hallucinated sensor-data rate.
- Device: verify actual capabilities at runtime; do not infer RAM, Neural Engine throughput, LiDAR mode or WWDC API availability from the marketing name.

## Release gates
1. WorldCore unit tests, deterministic legality and persistence tests pass.
2. macOS CI compiles and simulator launches; physical LiDAR requires real device.
3. Apple Foundation Models narration tested on device and verified to fall back.
4. GGUF store tested with approved small test fixture and corrupt/oversized/checksum mismatch cases.
5. Only after a pinned llama.cpp XCFramework builds on iOS, add GGUF inference and benchmark it against Apple models.
6. Sign and upload to a **separate** App Store Connect app and provisioning profile. Existing Rhea profile is not compatible with org.worldexe.prototype.
