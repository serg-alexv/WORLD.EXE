#ifndef WORLD_LLAMA_BRIDGE_H
#define WORLD_LLAMA_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
// All calls except cancel/reset_cancel are confined to one serial executor.
// The handle must outlive concurrent cancellation.
typedef struct we_llama we_llama;
we_llama *we_llama_create(void);
void we_llama_destroy(we_llama *engine);
void we_llama_cancel(we_llama *engine);
void we_llama_reset_cancel(we_llama *engine);
void we_llama_unload(we_llama *engine);
int we_llama_load(we_llama *engine, const char *path, int allow_gpu,
                  char *error, size_t error_capacity);
int we_llama_generate(we_llama *engine, const char *system, const char *prompt,
                      int max_tokens, char *output, size_t output_capacity,
                      int *generated_tokens, double *elapsed_seconds,
                      char *error, size_t error_capacity);
uint64_t we_llama_model_parameters(const we_llama *engine);
const char *we_llama_build(void);
#ifdef __cplusplus
}
#endif
#endif
