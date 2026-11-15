#include "LlamaBridge.h"
#include <llama/llama.h>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

struct we_llama {
    llama_model *model = nullptr;
    llama_context *context = nullptr;
    std::atomic<bool> cancelled{false};
    std::string architecture;
};
namespace {
std::once_flag backend_once;
void quiet_log(ggml_log_level, const char *, void *) {}
int fail(char *error, size_t capacity, const char *message, int code = -1) {
    if (error && capacity) std::snprintf(error, capacity, "%s", message);
    return code;
}
bool abort_decode(void *data) { return static_cast<we_llama *>(data)->cancelled.load(); }
bool loading_progress(float, void *data) { return !abort_decode(data); }
using Clock = std::chrono::steady_clock;
}
extern "C" {
we_llama *we_llama_create(void) {
    try { return new we_llama(); } catch (...) { return nullptr; }
}
void we_llama_unload(we_llama *e) {
    if (!e) return;
    if (e->context) { llama_free(e->context); e->context = nullptr; }
    if (e->model) { llama_model_free(e->model); e->model = nullptr; }
    e->architecture.clear();
}
void we_llama_destroy(we_llama *e) { we_llama_unload(e); delete e; }
void we_llama_cancel(we_llama *e) { if (e) e->cancelled.store(true); }
void we_llama_reset_cancel(we_llama *e) { if (e) e->cancelled.store(false); }
uint64_t we_llama_model_parameters(const we_llama *e) {
    return e && e->model ? llama_model_n_params(e->model) : 0;
}
const char *we_llama_build(void) { return "llama.cpp b12398 / d8f30a5b6db9"; }
int we_llama_load(we_llama *e, const char *path, int allow_gpu,
                  char *error, size_t capacity) {
    if (!e || !path) return fail(error, capacity, "Invalid model path or engine.");
    we_llama_unload(e);
    try {
        std::call_once(backend_once, [] { llama_log_set(quiet_log, nullptr); llama_backend_init(); });
        if (e->cancelled.load()) return fail(error, capacity, "Cancelled.", -2);
        auto mp = llama_model_default_params();
        mp.n_gpu_layers = allow_gpu ? -1 : 0;
        mp.load_mode = LLAMA_LOAD_MODE_MMAP;
        mp.progress_callback = loading_progress;
        mp.progress_callback_user_data = e;
        e->model = llama_model_load_from_file(path, mp);
        if (!e->model) return fail(error, capacity, e->cancelled.load() ? "Cancelled." : "GGUF could not be loaded; use a supported, complete model.");
        if (llama_model_n_params(e->model) > 2000000000ULL || llama_model_has_encoder(e->model)) {
            we_llama_unload(e);
            return fail(error, capacity, "Testbed accepts decoder models up to 2 billion parameters.");
        }
        char arch[128] = {};
        llama_model_meta_val_str(e->model, "general.architecture", arch, sizeof(arch));
        e->architecture = arch;
        auto cp = llama_context_default_params();
        cp.n_ctx = 2048;
        cp.n_batch = 128;
        cp.n_ubatch = 128;
        cp.n_seq_max = 1;
        cp.n_threads = 2;
        cp.n_threads_batch = 2;
        cp.offload_kqv = allow_gpu != 0;
        cp.op_offload = allow_gpu != 0;
        cp.abort_callback = abort_decode;
        cp.abort_callback_data = e;
        e->context = llama_init_from_model(e->model, cp);
        if (!e->context || e->cancelled.load()) {
            we_llama_unload(e);
            return fail(error, capacity, "Context allocation failed or cancelled.");
        }
        if (error && capacity) error[0] = '\0';
        return 0;
    } catch (const std::exception &) {
        we_llama_unload(e);
        return fail(error, capacity, "Model runtime rejected the file or could not allocate memory.");
    } catch (...) {
        we_llama_unload(e);
        return fail(error, capacity, "Model runtime failed.");
    }
}
int we_llama_generate(we_llama *e, const char *system, const char *prompt,
                      int max_tokens, char *output, size_t output_capacity,
                      int *generated_tokens, double *elapsed_seconds,
                      char *error, size_t error_capacity) {
    if (generated_tokens) *generated_tokens = 0;
    if (elapsed_seconds) *elapsed_seconds = 0;
    if (output && output_capacity) output[0] = '\0';
    if (!e || !e->model || !e->context || !system || !prompt || !output || output_capacity < 2)
        return fail(error, error_capacity, "Load a model first.");
    if (std::strlen(prompt) > 8192 || std::strlen(system) > 4096)
        return fail(error, error_capacity, "Prompt exceeds the local testbed limit.");
    max_tokens = std::clamp(max_tokens, 1, 256);
    const auto started = Clock::now();
    auto stopped = [&] { return e->cancelled.load() || Clock::now() - started > std::chrono::seconds(60); };
    try {
        std::string text;
        if (e->architecture == "qwen3") {
            text = std::string("<|im_start|>system\n") + system + "<|im_end|>\n<|im_start|>user\n" + prompt +
                "\n/no_think<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n";
        } else {
            const char *tmpl = llama_model_chat_template(e->model, nullptr);
            if (!tmpl) return fail(error, error_capacity, "No chat template. The verified Qwen3 model is recommended.");
            llama_chat_message messages[] = {{"system", system}, {"user", prompt}};
            std::vector<char> buffer(16384);
            int n = llama_chat_apply_template(tmpl, messages, 2, true, buffer.data(), int(buffer.size()));
            if (n <= 0 || n >= int(buffer.size()))
                return fail(error, error_capacity, "Unsupported chat template or excessive context.");
            text.assign(buffer.data(), size_t(n));
        }
        const llama_vocab *vocab = llama_model_get_vocab(e->model);
        int n = -llama_tokenize(vocab, text.c_str(), int(text.size()), nullptr, 0, true, true);
        if (n < 1 || n + max_tokens + 8 > int(llama_n_ctx(e->context)))
            return fail(error, error_capacity, "Prompt is too long for the 2048-token context.");
        std::vector<llama_token> tokens(size_t(n), 0);
        n = llama_tokenize(vocab, text.c_str(), int(text.size()), tokens.data(), n, true, true);
        if (n < 1) return fail(error, error_capacity, "Tokenization failed.");
        llama_memory_clear(llama_get_memory(e->context), true);
        for (int offset = 0; offset < n; offset += 128) {
            if (stopped()) return fail(error, error_capacity, "Cancelled or timed out.", -2);
            const int count = std::min(128, n - offset);
            if (llama_decode(e->context, llama_batch_get_one(tokens.data() + offset, count)) != 0)
                return fail(error, error_capacity, "Prompt evaluation failed or cancelled.");
        }
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(llama_sampler_init_greedy(), llama_sampler_free);
        if (!sampler) return fail(error, error_capacity, "Sampler allocation failed.");
        std::string result;
        result.reserve(2048);
        int produced = 0;
        for (; produced < max_tokens; ++produced) {
            if (stopped()) break;
            auto token = llama_sampler_sample(sampler.get(), e->context, -1);
            if (llama_vocab_is_eog(vocab, token)) break;
            char piece[512];
            int bytes = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, false);
            if (bytes < 0) {
                if (-bytes > 8192) return fail(error, error_capacity, "Token exceeds output budget.");
                std::vector<char> large(static_cast<size_t>(-bytes), '\0');
                bytes = llama_token_to_piece(vocab, token, large.data(), int(large.size()), 0, false);
                if (bytes > 0) result.append(large.data(), size_t(bytes));
            } else if (bytes > 0) result.append(piece, size_t(bytes));
            if (result.size() + 1 >= output_capacity) break;
            if (llama_decode(e->context, llama_batch_get_one(&token, 1)) != 0)
                return fail(error, error_capacity, "Generation failed or cancelled.");
        }
        const size_t count = std::min(output_capacity - 1, result.size());
        std::memcpy(output, result.data(), count); output[count] = '\0';
        if (generated_tokens) *generated_tokens = produced;
        if (elapsed_seconds) *elapsed_seconds = std::chrono::duration<double>(Clock::now() - started).count();
        if (stopped()) return fail(error, error_capacity, "Cancelled or timed out; partial output retained.", -2);
        if (result.empty()) return fail(error, error_capacity, "The model returned no text.");
        if (error && error_capacity) error[0] = '\0';
        return 0;
    } catch (...) {
        return fail(error, error_capacity, "Local generation failed.");
    }
}
}
