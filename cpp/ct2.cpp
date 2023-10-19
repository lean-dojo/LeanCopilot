#include <ctranslate2/devices.h>
#include <ctranslate2/encoder.h>
#include <ctranslate2/translator.h>
#include <lean/lean.h>

#include <codecvt>
#include <iostream>
#include <locale>
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

std::vector<std::string> byt5_vocab = {
    "\u0000", "\u0001", "\u0002", "\u0003", "\u0004", "\u0005", "\u0006",
    "\u0007", "\\b",    "\t",     "\n",     "\u000b", "\\f",    "\r",
    "\u000e", "\u000f", "\u0010", "\u0011", "\u0012", "\u0013", "\u0014",
    "\u0015", "\u0016", "\u0017", "\u0018", "\u0019", "\u001a", "\u001b",
    "\u001c", "\u001d", "\u001e", "\u001f", " ",      "!",      "\"",
    "#",      "$",      "%",      "&",      "'",      "(",      ")",
    "*",      "+",      ",",      "-",      ".",      "/",      "0",
    "1",      "2",      "3",      "4",      "5",      "6",      "7",
    "8",      "9",      ":",      ";",      "<",      "=",      ">",
    "?",      "@",      "A",      "B",      "C",      "D",      "E",
    "F",      "G",      "H",      "I",      "J",      "K",      "L",
    "M",      "N",      "O",      "P",      "Q",      "R",      "S",
    "T",      "U",      "V",      "W",      "X",      "Y",      "Z",
    "[",      "\\",     "]",      "^",      "_",      "`",      "a",
    "b",      "c",      "d",      "e",      "f",      "g",      "h",
    "i",      "j",      "k",      "l",      "m",      "n",      "o",
    "p",      "q",      "r",      "s",      "t",      "u",      "v",
    "w",      "x",      "y",      "z",      "{",      "|",      "}",
    "~",      "\u007f", "\u0080", "\u0081", "\u0082", "\u0083", "\u0084",
    "\u0085", "\u0086", "\u0087", "\u0088", "\u0089", "\u008a", "\u008b",
    "\u008c", "\u008d", "\u008e", "\u008f", "\u0090", "\u0091", "\u0092",
    "\u0093", "\u0094", "\u0095", "\u0096", "\u0097", "\u0098", "\u0099",
    "\u009a", "\u009b", "\u009c", "\u009d", "\u009e", "\u009f", "\u00a0",
    "\u00a1", "\u00a2", "\u00a3", "\u00a4", "\u00a5", "\u00a6", "\u00a7",
    "\u00a8", "\u00a9", "\u00aa", "\u00ab", "\u00ac", "\u00ad", "\u00ae",
    "\u00af", "\u00b0", "\u00b1", "\u00b2", "\u00b3", "\u00b4", "\u00b5",
    "\u00b6", "\u00b7", "\u00b8", "\u00b9", "\u00ba", "\u00bb", "\u00bc",
    "\u00bd", "\u00be", "\u00bf", "\u00c0", "\u00c1", "\u00c2", "\u00c3",
    "\u00c4", "\u00c5", "\u00c6", "\u00c7", "\u00c8", "\u00c9", "\u00ca",
    "\u00cb", "\u00cc", "\u00cd", "\u00ce", "\u00cf", "\u00d0", "\u00d1",
    "\u00d2", "\u00d3", "\u00d4", "\u00d5", "\u00d6", "\u00d7", "\u00d8",
    "\u00d9", "\u00da", "\u00db", "\u00dc", "\u00dd", "\u00de", "\u00df",
    "\u00e0", "\u00e1", "\u00e2", "\u00e3", "\u00e4", "\u00e5", "\u00e6",
    "\u00e7", "\u00e8", "\u00e9", "\u00ea", "\u00eb", "\u00ec", "\u00ed",
    "\u00ee", "\u00ef", "\u00f0", "\u00f1", "\u00f2", "\u00f3", "\u00f4",
    "\u00f5", "\u00f6", "\u00f7", "\u00f8", "\u00f9", "\u00fa", "\u00fb",
    "\u00fc", "\u00fd", "\u00fe", "\u00ff"};

extern "C" lean_obj_res ct2_generate(b_lean_obj_arg p_input_tokens,
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
  if (min_length < 0 || max_length < 0 || min_length > max_length) {
    throw std::invalid_argument("Invalid min_length or max_length.");
  }
  if (patience < 1.0) {
    throw std::invalid_argument("patience must be at least 1.0.");
  }
  if (temperature <= 0) {
    throw std::invalid_argument("temperature must be positive.");
  }

  ctranslate2::TranslationOptions opts;
  // std::cout << "num_return_sequences: " << num_return_sequences << std::endl;
  opts.num_hypotheses = num_return_sequences;
  // sstd::cout << "beam_size: " << beam_size << std::endl;
  opts.beam_size = beam_size;
  // sstd::cout << "patience: " << patience << std::endl;
  opts.patience = patience;
  // sstd::cout << "length_penalty: " << length_penalty << std::endl;
  opts.length_penalty = length_penalty;
  // sstd::cout << "min_length: " << min_length << std::endl;
  opts.min_decoding_length = min_length;
  // sstd::cout << "max_length: " << max_length << std::endl;
  opts.max_decoding_length = max_length;
  // sstd::cout << "temperature: " << temperature << std::endl;
  opts.sampling_temperature = temperature;
  opts.sampling_topk = 0;
  opts.sampling_topp = 1.0;
  opts.max_input_length = 0;
  opts.use_vmap = true;
  opts.disable_unk = true;
  opts.return_scores = true;

  std::vector<std::string> input_tokens;
  lean_array_object *p_arr = lean_to_array(p_input_tokens);
  for (int i = 0; i < p_arr->m_size; i++) {
    std::string t = lean_string_cstr(p_arr->m_data[i]);
    if (t != "</s>" && std::find(byt5_vocab.begin(), byt5_vocab.end(), t) ==
                           std::end(byt5_vocab)) {
      throw std::invalid_argument("Invalid token: " + t);
    }
    input_tokens.push_back(t);
  }

  const std::vector<std::vector<std::string>> batch = {input_tokens};
  // const std::vector<std::vector<std::string>> batch = {{"x", " ", ":", " ",
  // "\u00e2", "\u0084", "\u009d", "\n", "h", "\u00e2", "\u0082", "\u0080", " ",
  // ":", " ", "x", " ", "=", " ", "1", "\n", "⊢", " ", "x", " ", "=", " ", "1",
  // "</s>"}};

  ctranslate2::TranslationResult results =
      p_translator->translate_batch(batch, opts)[0];
  assert(results.hypotheses.size() == num_return_sequences &&
         results.scores.size() == num_return_sequences);

  lean_array_object *output = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  for (int i = 0; i < num_return_sequences; i++) {
    int l = results.hypotheses[i].size();
    lean_array_object *tokens =
        reinterpret_cast<lean_array_object *>(lean_alloc_array(l, l));
    for (int j = 0; j < l; j++) {
      tokens->m_data[j] = lean_mk_string(results.hypotheses[i][j].c_str());
    }

    double score = std::exp(results.scores[i]);
    assert(0.0 <= score && score <= 1.0);

    output->m_data[i] = lean_mk_pair(reinterpret_cast<lean_obj_arg>(tokens),
                                     lean_box_float(score));
  }

  return reinterpret_cast<lean_obj_res>(output);
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

  /*
  std::vector<long long> s = hidden_state.shape();
  std::cout << s.size() << std::endl;
  for (int i = 0; i < s.size(); i++) {
    std::cout << s[i] << std::endl;
  }
  */

  lean_object *arr = lean_mk_empty_float_array(lean_box(10));
  // Not implemented yet.
  lean_float_array_push(arr, 0.34);
  lean_float_array_push(arr, 0.84);
  lean_float_array_push(arr, 0.57);
  lean_float_array_push(arr, 2.63);
  lean_float_array_push(arr, 0.67);
  return arr;
}
