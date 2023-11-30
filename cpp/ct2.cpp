#include <ctranslate2/devices.h>
#include <ctranslate2/encoder.h>
#include <ctranslate2/ops/matmul.h>
#include <ctranslate2/ops/topk.h>
#include <ctranslate2/translator.h>
#include <lean/lean.h>

#include <codecvt>
#include <fstream>
#include <iostream>
#include <locale>
#include <stdexcept>
#include <vector>

#include "json.hpp"
#include "npy.hpp"
#include "utils.h"

using json = nlohmann::json;

ctranslate2::Translator *p_translator = nullptr;
ctranslate2::Encoder *p_encoder = nullptr;
ctranslate2::StorageView *premise_embeddings = nullptr;
json *premise_dictionary = nullptr;

const std::string EOS_TOKEN = "</s>";
const std::vector<std::string> byt5_vocab = {
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

std::vector<std::string> byt5_tokenize(const char *input) {
  std::vector<std::string> tokens;
  int l = strlen(input);
  for (int i = 0; i < l; i++) {
    tokens.push_back(std::string(1, input[i]));
  }
  return tokens;
}

extern "C" uint8_t init_ct2_generator(
    b_lean_obj_arg _model_path,    // String
    b_lean_obj_arg _device,        // String
    b_lean_obj_arg _compute_type,  // String
    b_lean_obj_arg _device_index,  // Array UInt64
    uint64_t intra_threads) {      // UInt64
  const char *model_path = lean_string_cstr(_model_path);
  if (!exists(model_path)) {
    return false;
  }

  if (p_translator != nullptr) {
    delete p_translator;
    p_translator = nullptr;
  }

  ctranslate2::Device device =
      ctranslate2::str_to_device(lean_string_cstr(_device));
  ctranslate2::ComputeType compute_type =
      ctranslate2::str_to_compute_type(lean_string_cstr(_compute_type));
  std::vector<int> device_indices;
  const lean_array_object *p_arr = lean_to_array(_device_index);
  for (int i = 0; i < p_arr->m_size; i++) {
    device_indices.push_back(lean_unbox_uint64(p_arr->m_data[i]));
  }
  ctranslate2::ReplicaPoolConfig config;
  config.num_threads_per_replica = intra_threads;

  p_translator = new ctranslate2::Translator(model_path, device, compute_type,
                                             device_indices, config);
  return true;
}

inline bool is_ct2_generator_initialized_aux() {
  return p_translator != nullptr;
}

extern "C" uint8_t is_ct2_generator_initialized(lean_object *) {
  return is_ct2_generator_initialized_aux();
}

std::vector<std::string> convert_tokens(b_lean_obj_arg _tokens) {
  std::vector<std::string> tokens;
  const lean_array_object *p_arr = lean_to_array(_tokens);

  for (int i = 0; i < p_arr->m_size; i++) {
    std::string t = lean_string_cstr(p_arr->m_data[i]);
    if (t != EOS_TOKEN && std::find(byt5_vocab.begin(), byt5_vocab.end(), t) ==
                              std::end(byt5_vocab)) {
      throw std::invalid_argument("Invalid token: " + t);
    }
    tokens.push_back(t);
  }

  return tokens;
}

extern "C" lean_obj_res ct2_generate(
    b_lean_obj_arg _input_tokens,          //  Array String
    b_lean_obj_arg _target_prefix_tokens,  // Array String
    uint64_t num_return_sequences,         // UInt64
    uint64_t beam_size,                    // UInt64
    uint64_t min_length,                   // UInt64
    uint64_t max_length,                   // UInt64
    double length_penalty,                 // Float
    double patience,                       // Float
    double temperature) {                  // Float
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

  // Set beam search's hyperparameters.
  ctranslate2::TranslationOptions opts;
  opts.num_hypotheses = num_return_sequences;
  opts.beam_size = beam_size;
  opts.patience = patience;
  opts.length_penalty = length_penalty;
  opts.min_decoding_length = min_length;
  opts.max_decoding_length = max_length;
  opts.sampling_temperature = temperature;
  opts.sampling_topk = 0;
  opts.sampling_topp = 1.0;
  opts.max_input_length = 0;
  opts.use_vmap = true;
  opts.disable_unk = true;
  opts.return_scores = true;

  // Get the input tokens ready.
  std::vector<std::string> input_tokens = convert_tokens(_input_tokens);
  assert(input_tokens.back() == EOS_TOKEN);
  std::vector<std::string> target_prefix_tokens =
      convert_tokens(_target_prefix_tokens);

  // Generate tactics with beam search.
  ctranslate2::TranslationResult results = p_translator->translate_batch(
      {input_tokens}, {target_prefix_tokens}, opts)[0];
  assert(results.hypotheses.size() == num_return_sequences &&
         results.scores.size() == num_return_sequences);

  // Return the output.
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

extern "C" uint8_t init_ct2_encoder(b_lean_obj_arg model_path,
                                    b_lean_obj_arg _device) {
  const char *dir = lean_string_cstr(model_path);
  if (!exists(dir)) {
    return false;
  }
  if (p_encoder != nullptr) {
    delete p_encoder;
  }

  ctranslate2::Device device =
      ctranslate2::str_to_device(lean_string_cstr(_device));

  p_encoder = new ctranslate2::Encoder(dir, device);

  return true;
}

inline bool is_ct2_encoder_initialized_aux() { return p_encoder != nullptr; }

extern "C" uint8_t is_ct2_encoder_initialized(lean_object *) {
  return is_ct2_encoder_initialized_aux();
}

extern "C" lean_obj_res ct2_encode(b_lean_obj_arg _input_tokens) {
  std::vector<std::string> input_tokens = convert_tokens(_input_tokens);
  // std::vector<std::string> input_tokens = {"n", " ", ":", " ", "\u00e2",
  // "\u0084", "\u0095", "\n", "\u00e2", "\u008a", "\u00a2", " ", "g", "c", "d",
  // " ", "n", " ", "n", " ", "=", " ", "n", EOS_TOKEN};
  assert(input_tokens.back() == EOS_TOKEN);

  ctranslate2::EncoderForwardOutput results =
      p_encoder->forward_batch_async({input_tokens}).get();
  ctranslate2::StorageView hidden_state = results.last_hidden_state;

  assert(hidden_state.dim(0) == 1);
  int l = hidden_state.dim(1);
  int d = hidden_state.dim(2);
  lean_object *arr = lean_mk_empty_float_array(lean_box(d));

  for (ctranslate2::dim_t i = 0; i < d; i++) {
    double sum = 0.0;
    for (ctranslate2::dim_t j = 0; j < l; j++) {
      sum += hidden_state.scalar_at<float>({0, j, i});
    }
    lean_float_array_push(arr, sum / l);
  }

  return arr;
}

extern "C" uint8_t init_premise_embeddings(b_lean_obj_arg embeddings_path,
                                           b_lean_obj_arg _device) {
  const char *emb_path = lean_string_cstr(embeddings_path);
  if (!exists(emb_path)) {
    return false;
  }
  if (premise_embeddings != nullptr) {
    delete premise_embeddings;
  }

  ctranslate2::Device device =
      ctranslate2::str_to_device(lean_string_cstr(_device));
  device = ctranslate2::Device::CPU;  // [TODO]: We should remove this line when
                                      // everything can work well on CUDA.

  auto d = npy::read_npy<double>(emb_path);
  std::vector<double> data = d.data;
  std::vector<unsigned long> shape = d.shape;
  bool fortran_order = d.fortran_order;

  std::vector<float> data_f;
  data_f.resize(data.size());
  std::transform(data.begin(), data.end(), data_f.begin(),
                 [](double d) { return static_cast<float>(d); });

  std::vector<int64_t> shape_i64;
  shape_i64.resize(shape.size());
  std::transform(shape.begin(), shape.end(), shape_i64.begin(),
                 [](unsigned long ul) { return static_cast<int64_t>(ul); });

  premise_embeddings = new ctranslate2::StorageView(shape_i64, data_f, device);
  return true;
}

inline bool is_premise_embeddings_initialized_aux() {
  return premise_embeddings != nullptr;
}

extern "C" uint8_t is_premise_embeddings_initialized(lean_object *) {
  return is_premise_embeddings_initialized_aux();
}

extern "C" uint8_t init_premise_dictionary(b_lean_obj_arg dictionary_path) {
  const char *dict_path = lean_string_cstr(dictionary_path);
  if (!exists(dict_path)) {
    return false;
  }
  if (premise_dictionary != nullptr) {
    delete premise_dictionary;
  }

  std::ifstream f(dict_path);
  premise_dictionary = new json(json::parse(f));

  return true;
}

inline bool is_premise_dictionary_initialized_aux() {
  return premise_dictionary != nullptr;
}

extern "C" uint8_t is_premise_dictionary_initialized(lean_object *) {
  return is_premise_dictionary_initialized_aux();
}

extern "C" lean_obj_res ct2_retrieve(b_lean_obj_arg _encoded_state) {
  const lean_array_object *p_arr = lean_to_array(_encoded_state);

  assert(static_cast<int64_t>(p_arr->m_size) == premise_embeddings->dim(1));
  assert(premise_embeddings != nullptr);

  std::vector<float> state_embedding_data;
  for (int i = 0; i < p_arr->m_size; i++) {
    state_embedding_data.push_back(
        static_cast<float>(lean_unbox_float(p_arr->m_data[i])));
  }

  std::vector<int64_t> state_embedding_shape{
      static_cast<int64_t>(p_arr->m_size), 1};

  ctranslate2::StorageView *state_embedding =
      new ctranslate2::StorageView(state_embedding_shape, state_embedding_data,
                                   premise_embeddings->device());

  int k = 10;
  ctranslate2::ops::MatMul matmul(false, false, 1.0);
  ctranslate2::ops::TopK topk(k, -1);

  std::vector<int64_t> probs_shape{premise_embeddings->dim(0), 1};

  ctranslate2::StorageView *probs =
      new ctranslate2::StorageView(probs_shape, ctranslate2::DataType::FLOAT32,
                                   premise_embeddings->device());

  matmul(*premise_embeddings, *state_embedding, *probs);
  probs->resize({premise_embeddings->dim(0)});

  ctranslate2::StorageView *topk_values = new ctranslate2::StorageView(
      {k}, ctranslate2::DataType::FLOAT32, premise_embeddings->device());
  ctranslate2::StorageView *topk_indices = new ctranslate2::StorageView(
      {k}, ctranslate2::DataType::INT32, premise_embeddings->device());
  topk(*probs, *topk_values, *topk_indices);

  lean_array_object *output =
      reinterpret_cast<lean_array_object *>(lean_alloc_array(k, k));
  int *topk_indices_ptr = topk_indices->data<int>();
  float *topk_values_ptr = topk_values->data<float>();

  for (int i = 0; i < k; i++) {
    assert(topk_indices_ptr[i] >= 0 &&
           topk_indices_ptr[i] < premise_embeddings->dim(0));
    // [NOTE]: This is where the server crash occurs on CUDA.
    std::string this_premise =
        (*premise_dictionary)[std::to_string(*(topk_indices_ptr + i))]["full_name"];
    std::string this_path =
        (*premise_dictionary)[std::to_string(*(topk_indices_ptr + i))]["path"];
    std::string this_code =
        (*premise_dictionary)[std::to_string(*(topk_indices_ptr + i))]["code"];

    output->m_data[i] =
        lean_mk_pair(lean_mk_string(this_premise.c_str()),
                     lean_mk_pair(
                         lean_mk_string(this_path.c_str()),
                         lean_mk_pair(
                         lean_mk_string(this_code.c_str()),
                         lean_box_float(static_cast<double>(topk_values_ptr[i])))));
    
    
  }
  
  return reinterpret_cast<lean_obj_res>(output);
}
