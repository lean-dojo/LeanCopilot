#include <ctranslate2/devices.h>
#include <ctranslate2/encoder.h>
#include <ctranslate2/translator.h>
#include <lean/lean.h>

#include <iostream>
#include <stdexcept>

#include "utils.h"

ctranslate2::Translator *p_translator = nullptr;
ctranslate2::Encoder *p_encoder = nullptr;

std::vector<std::string> byt5_tokenize(const char *input) {
  std::vector<std::string> tokens;
  int l = strlen(input);
  for (int i = 0; i < l; i++) {
    tokens.push_back(std::string(1, input[i]));
  }
  return tokens;
}

extern "C" uint8_t init_ct2_generator(b_lean_obj_arg model_path,
                                      b_lean_obj_arg device,
                                      b_lean_obj_arg compute_type) {
  const char *path = lean_string_cstr(model_path);
  if (!exists(path)) {
    return false;
  }
  if (p_translator != nullptr) {
    delete p_translator;
  }
  ctranslate2::Device d = ctranslate2::str_to_device(lean_string_cstr(device));
  p_translator = new ctranslate2::Translator(path, d);
  return true;
}

inline bool is_ct2_generator_initialized_aux() {
  return p_translator != nullptr;
}

extern "C" uint8_t is_ct2_generator_initialized(lean_object *) {
  return is_ct2_generator_initialized_aux();
}

extern "C" lean_obj_res ct2_generate(b_lean_obj_arg input,
                                     uint64_t num_return_sequences,
                                     uint64_t beam_size, uint64_t min_length,
                                     int64_t max_length, double length_penalty,
                                     double patience, double temperature) {
  // Check the arguments.
  if (!is_ct2_generator_initialized_aux()) {
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

  const std::vector<std::vector<std::string>> batch = {
      byt5_tokenize(lean_string_cstr(input))};
  ctranslate2::TranslationResult results =
      p_translator->translate_batch(batch, opts)[0];
  assert(results.hypotheses.size() == num_return_sequences);

  // Return Lean strings.
  lean_array_object *arr = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  for (int i = 0; i < num_return_sequences; i++) {
    std::string tac;
    for (auto &token : results.hypotheses[i]) {
      tac += token;
    }
    arr->m_data[i] =
        lean_mk_pair(lean_mk_string(tac.c_str()), lean_box_float(0.5));
  }

  return reinterpret_cast<lean_obj_res>(arr);
}

extern "C" uint8_t init_ct2_encoder(b_lean_obj_arg model_path) {
  const char *dir = lean_string_cstr(model_path);
  if (!exists(dir)) {
    return false;
  }
  if (p_encoder != nullptr) {
    delete p_encoder;
  }
  p_encoder = new ctranslate2::Encoder(dir, ctranslate2::Device::CPU);
  return true;
}

inline bool is_ct2_encoder_initialized_aux() { return p_encoder != nullptr; }

extern "C" uint8_t is_ct2_encoder_initialized(lean_object *) {
  return is_ct2_encoder_initialized_aux();
}

extern "C" lean_obj_res ct2_encode(b_lean_obj_arg input) {
  const std::vector<std::vector<std::string>> batch = {
      byt5_tokenize(lean_string_cstr(input))};
  ctranslate2::EncoderForwardOutput results =
      p_encoder->forward_batch_async(batch).get();
  ctranslate2::StorageView hidden_state = results.pooler_output.value();

  std::vector<long long> s = hidden_state.shape();
  std::cout << s.size() << std::endl;
  for (int i = 0; i < s.size(); i++) {
    std::cout << s[i] << std::endl;
  }

  lean_object *arr = lean_mk_empty_float_array(lean_box(10));
  // Not implemented yet.
  lean_float_array_push(arr, 0.34);
  lean_float_array_push(arr, 0.84);
  lean_float_array_push(arr, 0.57);
  lean_float_array_push(arr, 2.63);
  lean_float_array_push(arr, 0.67);
  return arr;
}
