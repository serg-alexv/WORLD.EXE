import Foundation
import LlamaBridge

struct NativeCompletion: Sendable {
    let text: String
    let tokens: Int
    let seconds: Double
    let cancelled: Bool
}
struct BrainFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The only concurrent native call is an atomic cancellation flag.
/// Decode, loading, context destruction and model unloading use one serial queue.
final class LlamaRuntime: @unchecked Sendable {
    private let queue = DispatchQueue(label: "org.worldexe.llama", qos: .userInitiated)
    private let engine = we_llama_create()
    deinit { we_llama_destroy(engine) }
    var build: String { String(cString: we_llama_build()) }
    func prepare() { we_llama_reset_cancel(engine) }
    func cancel() { we_llama_cancel(engine) }
    func load(_ path: String, metal: Bool) async throws -> UInt64 {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                var error = [CChar](repeating: 0, count: 512)
                let code = we_llama_load(engine, path, metal ? 1 : 0, &error, 512)
                if code == 0 { continuation.resume(returning: we_llama_model_parameters(engine)) }
                else { continuation.resume(throwing: BrainFailure(message: String(cString: error))) }
            }
        }
    }
    func generate(system: String, prompt: String) async throws -> NativeCompletion {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                var output = [CChar](repeating: 0, count: 32768)
                var error = [CChar](repeating: 0, count: 512)
                var tokens: Int32 = 0
                var seconds: Double = 0
                let code = we_llama_generate(engine, system, prompt, 160, &output, 32768,
                                             &tokens, &seconds, &error, 512)
                if code == 0 || code == -2 {
                    continuation.resume(returning: NativeCompletion(text: String(cString: output),
                        tokens: Int(tokens), seconds: seconds, cancelled: code == -2))
                } else { continuation.resume(throwing: BrainFailure(message: String(cString: error))) }
            }
        }
    }
    func unload() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in we_llama_unload(engine); continuation.resume() }
        }
    }
}
