// A deliberately tiny C ABI over llama.cpp, for Dart FFI.
//
// The alternative — binding llama.cpp's own API from Dart — means replicating
// its parameter structs field-for-field, and those structs change layout
// between releases. A wrong offset does not error; it misreads memory. This
// shim pins the surface to four functions with C's simplest types, so the
// Dart side cannot be wrong about layout, and a llama.cpp upgrade is a
// rebuild of this file rather than a re-audit of a Dart struct mirror.
//
// Scope is equally deliberate: load, complete one chat turn, free. No
// streaming, no sessions, no sampling zoo — the app's contract with a model
// is "rewrite this sentence", and the shim's contract is exactly big enough
// for that.

#include "llama.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>

typedef struct {
    struct llama_model   * model;
    struct llama_context * ctx;
    const struct llama_vocab * vocab;
    int n_ctx;
} clinical_llm;

void * clinical_llm_load(const char * path, int n_ctx, int n_threads) {
    llama_backend_init();

    struct llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0; // CPU only: predictable memory on a clinic tablet.

    struct llama_model * model = llama_model_load_from_file(path, mparams);
    if (model == NULL) return NULL;

    struct llama_context_params cparams = llama_context_default_params();
    cparams.n_ctx     = (uint32_t) n_ctx;
    cparams.n_batch   = (uint32_t) n_ctx;
    cparams.n_threads = n_threads;
    cparams.n_threads_batch = n_threads;

    struct llama_context * ctx = llama_init_from_model(model, cparams);
    if (ctx == NULL) {
        llama_model_free(model);
        return NULL;
    }

    clinical_llm * llm = calloc(1, sizeof(clinical_llm));
    llm->model = model;
    llm->ctx   = ctx;
    llm->vocab = llama_model_get_vocab(model);
    llm->n_ctx = n_ctx;
    return llm;
}

void clinical_llm_free(void * handle) {
    if (handle == NULL) return;
    clinical_llm * llm = (clinical_llm *) handle;
    if (llm->ctx)   llama_free(llm->ctx);
    if (llm->model) llama_model_free(llm->model);
    free(llm);
}

void clinical_llm_free_text(char * text) {
    free(text);
}

// One chat turn: system + user in, assistant text out (malloc'd, UTF-8,
// NUL-terminated; caller frees with clinical_llm_free_text). NULL on any
// failure — the Dart side treats every NULL identically as "the model could
// not answer", which is the only distinction the app acts on.
char * clinical_llm_complete(
        void * handle,
        const char * system_prompt,
        const char * user_prompt,
        int max_tokens,
        float temperature) {
    if (handle == NULL || user_prompt == NULL) return NULL;
    clinical_llm * llm = (clinical_llm *) handle;

    // The model's own chat template, so Qwen, Gemma and Llama each get the
    // control tokens they were trained with. A model that ships none gets
    // ChatML, the nearest thing to a lingua franca.
    const char * tmpl = llama_model_chat_template(llm->model, NULL);
    if (tmpl == NULL) tmpl = "chatml";

    struct llama_chat_message messages[2];
    size_t n_msg = 0;
    if (system_prompt != NULL && system_prompt[0] != '\0') {
        messages[n_msg].role    = "system";
        messages[n_msg].content = system_prompt;
        n_msg++;
    }
    messages[n_msg].role    = "user";
    messages[n_msg].content = user_prompt;
    n_msg++;

    int32_t buf_len = (int32_t) (2 * (strlen(user_prompt)
            + (system_prompt ? strlen(system_prompt) : 0)) + 1024);
    char * prompt = malloc((size_t) buf_len);
    if (prompt == NULL) return NULL;

    int32_t written = llama_chat_apply_template(
            tmpl, messages, n_msg, /*add_ass=*/true, prompt, buf_len);
    if (written < 0 || written >= buf_len) { free(prompt); return NULL; }
    prompt[written] = '\0';

    // Tokenise. Two-pass: ask for the size, then fill.
    int32_t n_prompt = -llama_tokenize(
            llm->vocab, prompt, written, NULL, 0, /*add_special=*/true, /*parse_special=*/true);
    if (n_prompt <= 0 || n_prompt >= llm->n_ctx - max_tokens) {
        free(prompt);
        return NULL; // A prompt that leaves no room to answer is a bug upstream.
    }
    llama_token * tokens = malloc(sizeof(llama_token) * (size_t) n_prompt);
    if (tokens == NULL) { free(prompt); return NULL; }
    if (llama_tokenize(llm->vocab, prompt, written, tokens, n_prompt, true, true) < 0) {
        free(prompt); free(tokens); return NULL;
    }
    free(prompt);

    // Fresh sampler per call; the chain owns its members.
    struct llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    struct llama_sampler * sampler = llama_sampler_chain_init(sparams);
    if (temperature <= 0.0f) {
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy());
    } else {
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(0xC1121CA1u));
    }

    // A fresh conversation per call: this shim serves one-shot rewrites, and
    // clearing state is what makes calls independent and results reproducible.
    llama_memory_clear(llama_get_memory(llm->ctx), true);

    char * out = malloc((size_t) max_tokens * 8 + 1);
    if (out == NULL) { llama_sampler_free(sampler); free(tokens); return NULL; }
    size_t out_len = 0;

    struct llama_batch batch = llama_batch_get_one(tokens, n_prompt);
    int produced = 0;
    int failed = 0;

    while (produced < max_tokens) {
        if (llama_decode(llm->ctx, batch) != 0) { failed = 1; break; }

        llama_token token = llama_sampler_sample(sampler, llm->ctx, -1);
        if (llama_vocab_is_eog(llm->vocab, token)) break;

        char piece[128];
        int32_t piece_len = llama_token_to_piece(
                llm->vocab, token, piece, sizeof(piece), 0, /*special=*/false);
        if (piece_len < 0) { failed = 1; break; }
        memcpy(out + out_len, piece, (size_t) piece_len);
        out_len += (size_t) piece_len;
        produced++;

        batch = llama_batch_get_one(&token, 1);
    }

    llama_sampler_free(sampler);
    free(tokens);

    if (failed) { free(out); return NULL; }
    out[out_len] = '\0';
    return out;
}
