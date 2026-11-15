import Foundation
import LlamaBridge

// Same C bridge as the iOS app; the test is executed with network denied on macOS.
guard CommandLine.arguments.count == 2, let engine = we_llama_create() else {
    fatalError("Expected one verified GGUF path and a native engine")
}
defer { we_llama_destroy(engine) }
var error = [CChar](repeating: 0, count: 512)
we_llama_reset_cancel(engine)
let loaded = we_llama_load(engine, CommandLine.arguments[1], 0, &error, 512)
guard loaded == 0 else { fatalError("Model load failed: \(String(cString: error))") }
var output = [CChar](repeating: 0, count: 32768)
var tokens: Int32 = 0
var elapsed: Double = 0
let result = we_llama_generate(engine, "You are a concise spaceship assistant. Answer in one short sentence.",
                               "Tell the crew the capsule is ready. /no_think", 32,
                               &output, 32768, &tokens, &elapsed, &error, 512)
guard result == 0, tokens > 0, !String(cString: output).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
    fatalError("Native inference produced no valid completion: \(String(cString: error))")
}
let record: [String: Any] = ["engine": String(cString: we_llama_build()), "tokens": tokens,
    "seconds": elapsed, "parameters": we_llama_model_parameters(engine), "network": "denied by sandbox-exec",
    "output": String(cString: output), "scope": "native macOS CPU bridge smoke test; not iPhone performance"]
print(String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
we_llama_cancel(engine)
let cancelled = we_llama_generate(engine, "Assistant", "This operation must be cancelled", 16,
                                 &output, 32768, &tokens, &elapsed, &error, 512)
guard cancelled != 0 else { fatalError("Cancellation failed") }
we_llama_unload(engine)
guard we_llama_model_parameters(engine) == 0 else { fatalError("Model was not unloaded") }
print("LLAMA_NATIVE_SMOKE_PASS generation cancellation unload")
