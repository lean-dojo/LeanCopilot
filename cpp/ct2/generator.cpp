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

inline bool is_ct2_initialized_aux() { return false; }

extern "C" uint8_t is_ct2_initialized(lean_object *) {
  return is_ct2_initialized_aux();
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

  // Return Lean strings.
  lean_array_object *arr = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  return reinterpret_cast<lean_obj_res>(arr);
}
