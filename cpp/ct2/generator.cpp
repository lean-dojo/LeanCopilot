#include <lean/lean.h>
#include <ctranslate2/translator.h>

#include <stdexcept>

ctranslate2::Translator *p_translator = nullptr;

inline bool exists(const std::string &path) {
  std::ifstream f(path.c_str());
  return f.good();
}

extern "C" uint8_t init_ct2_generator(b_lean_obj_arg model_dir) {
  const char *dir = lean_string_cstr(model_dir);
  if (!exists(dir)) {
    return false;
  }

  if (p_translator != nullptr) {
    delete p_translator;
  }
 
  p_translator = new ctranslate2::Translator(dir, ctranslate2::Device::CPU);
  return true; 
}

inline bool is_ct2_initialized_aux() {
  return p_translator != nullptr;
}

extern "C" uint8_t is_ct2_initialized(lean_object *) {
  return is_ct2_initialized_aux();
}

static lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}

extern "C" lean_obj_res ct2_generate(b_lean_obj_arg input,
                                     uint64_t num_return_sequences,
                                     uint64_t beam_size, uint64_t min_length,
                                     int64_t max_length, double length_penalty,
                                     double patience, double temperature) {
  // Check the arguments.
  if (!is_ct2_initialized_aux()) {
    throw std::runtime_error("CT2 generator is not initialized.");
  }
  if (num_return_sequences <= 0) {
    throw std::invalid_argument("num_return_sequences must be positive.");
  }
  if (beam_size <= 0) {
    throw std::invalid_argument("beam_size must be positive.");
  }
  if (min_length <= 0 || max_length <= 0 || min_length > max_length) {
    throw std::invalid_argument("Invalid min_length or max_length.");
  }
  if (length_penalty < 0) {
    throw std::invalid_argument("length_penalty must be non-negative.");
  }
  if (patience < 1.0) {
    throw std::invalid_argument("patience must be at least 1.0.");
  }
  if (temperature <= 0) {
    throw std::invalid_argument("temperature must be positive.");
  }

  ctranslate2::TranslationOptions opts;
  opts.num_hypotheses = num_return_sequences;
  opts.beam_size = beam_size;
  opts.patience = patience;
  opts.length_penalty = length_penalty;
  opts.min_decoding_length = min_length;
  opts.max_decoding_length = max_length;
  opts.sampling_temperature = temperature;

  const char *s = lean_string_cstr(input);
  std::vector<std::string> input_tokens;
  for (int i = 0; i < strlen(s); i++) {
    input_tokens.push_back(std::string(1, s[i]));
  }

  const std::vector<std::vector<std::string>> batch = {input_tokens};
  ctranslate2::TranslationResult results = p_translator->translate_batch(batch, opts)[0];
  assert(results.hypotheses.size() == num_return_sequences);

  // Return Lean strings.
  lean_array_object *arr = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  for (int i = 0; i < num_return_sequences; i++) {
    std::string tac;
    for (auto &token : results.hypotheses[i]) {
      tac += token;
    }
    arr->m_data[i] = lean_mk_pair(lean_mk_string(tac.c_str()),
                                  lean_box_float(0.5));
  }

  return reinterpret_cast<lean_obj_res>(arr);
}
