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

using json = nlohmann::json;

std::map<std::string, std::unique_ptr<ctranslate2::Translator>> generators;
std::map<std::string, std::unique_ptr<ctranslate2::Encoder>> encoders;

ctranslate2::StorageView *p_premise_embeddings = nullptr;
json *p_premise_dictionary = nullptr;

inline bool exists(const std::string &path) {
  std::ifstream f(path.c_str());
  return f.good();
}

inline lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}

template<typename T>
bool is_initialized_aux(const std::string &name);

template<>
bool is_initialized_aux<ctranslate2::Translator>(const std::string &name) {
  return generators.find(name) != generators.end();
}

template<>
bool is_initialized_aux<ctranslate2::Encoder>(const std::string &name) {
  return encoders.find(name) != encoders.end();
}

extern "C" uint8_t is_generator_initialized(b_lean_obj_arg _name) {
  std::string name = std::string(lean_string_cstr(_name));
  return is_initialized_aux<ctranslate2::Translator>(name);
}

extern "C" uint8_t is_encoder_initialized(b_lean_obj_arg _name) {
  std::string name = std::string(lean_string_cstr(_name));
  return is_initialized_aux<ctranslate2::Encoder>(name);
}

template <typename T>
bool init_model(b_lean_obj_arg _name,          // String
                b_lean_obj_arg _model_path,    // String
                b_lean_obj_arg _device,        // String
                b_lean_obj_arg _compute_type,  // String
                b_lean_obj_arg _device_index,  // Array UInt64
                std::map<std::string, std::unique_ptr<T>> &models) {
  std::string name = std::string(lean_string_cstr(_name));
  if (is_initialized_aux<T>(name)) {
    throw std::runtime_error(name + " already exists.");
  }

  std::string model_path = std::string(lean_string_cstr(_model_path));
  if (!exists(model_path)) {  // Cannot find the model.
    return false;
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

  auto p_model =
      std::make_unique<T>(model_path, device, compute_type, device_indices);
  models.emplace(name, std::move(p_model));
  return true;
}

extern "C" uint8_t init_generator(
    b_lean_obj_arg _name,            // String
    b_lean_obj_arg _model_path,      // String
     b_lean_obj_arg _compute_type,    // String
    b_lean_obj_arg _device,          // String
    b_lean_obj_arg _device_index) {  // Array UInt64
  return init_model(_name, _model_path, _device, _compute_type, _device_index,
                    generators);
}

extern "C" uint8_t init_encoder(b_lean_obj_arg _name,            // String
                                b_lean_obj_arg _model_path,      // String
                                b_lean_obj_arg _compute_type,    // String
                                b_lean_obj_arg _device,          // String
                                b_lean_obj_arg _device_index) {  // Array UInt64
  return init_model(_name, _model_path, _device, _compute_type, _device_index,
                    encoders);
}

inline std::vector<std::string> convert_tokens(b_lean_obj_arg _tokens) {
  std::vector<std::string> tokens;
  const lean_array_object *p_arr = lean_to_array(_tokens);
  for (int i = 0; i < p_arr->m_size; i++) {
    tokens.emplace_back(lean_string_cstr(p_arr->m_data[i]));
  }
  return tokens;
}

extern "C" lean_obj_res generate(
    b_lean_obj_arg _name,                  // String
    b_lean_obj_arg _input_tokens,          // Array String
    b_lean_obj_arg _target_prefix_tokens,  // Array String
    uint64_t num_return_sequences,         // UInt64
    uint64_t beam_size,                    // UInt64
    uint64_t min_length,                   // UInt64
    uint64_t max_length,                   // UInt64
    double length_penalty,                 // Float
    double patience,                       // Float
    double temperature) {                  // Float
  // Check the arguments.
  std::string name = std::string(lean_string_cstr(_name));
  if (!is_initialized_aux<ctranslate2::Translator>(name)) {
    throw std::runtime_error(name + " hasn't been initialized.");
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
  std::vector<std::string> target_prefix_tokens =
      convert_tokens(_target_prefix_tokens);

  // Generate tactics with beam search.
  ctranslate2::TranslationResult results = generators.at(name)->translate_batch(
      {input_tokens}, {target_prefix_tokens}, opts)[0];
  assert(results.hypotheses.size() == num_return_sequences &&
         results.scores.size() == num_return_sequences);

  // Return the output.
  lean_object *output = lean_mk_empty_array();

  for (int i = 0; i < num_return_sequences; i++) {
    int l = results.hypotheses[i].size();

    lean_object *tokens = lean_mk_empty_array();
    for (int j = 0; j < l; j++) {
      tokens = lean_array_push(
          tokens, lean_mk_string(results.hypotheses[i][j].c_str()));
    }
    double score = std::exp(results.scores[i]);
    assert(0.0 <= score && score <= 1.0);
    output =
        lean_array_push(output, lean_mk_pair(tokens, lean_box_float(score)));
  }

  return output;
}

extern "C" lean_obj_res encode(b_lean_obj_arg _name,            // String
                               b_lean_obj_arg _input_tokens) {  // Array String
  std::string name = std::string(lean_string_cstr(_name));
  if (!is_initialized_aux<ctranslate2::Encoder>(name)) {
    throw std::runtime_error(name + " hasn't been initialized.");
  }

  std::vector<std::string> input_tokens = convert_tokens(_input_tokens);
  ctranslate2::EncoderForwardOutput results =
      encoders.at(name)->forward_batch_async({input_tokens}).get();
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

extern "C" uint8_t init_p_premise_embeddings(
    b_lean_obj_arg _path,      // String
    b_lean_obj_arg _device) {  // String
  std::string path = std::string(lean_string_cstr(_path));
  if (!exists(path)) {
    return false;
  }
  if (p_premise_embeddings != nullptr) {
    delete p_premise_embeddings;
  }

  // ctranslate2::Device device =
  // ctranslate2::str_to_device(lean_string_cstr(_device));
  // TODO: We should remove this line when everything can work well on CUDA.
  ctranslate2::Device device = ctranslate2::Device::CPU;

  const auto &d = npy::read_npy<double>(path);
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

  p_premise_embeddings =
      new ctranslate2::StorageView(shape_i64, data_f, device);
  return true;
}

inline bool is_p_premise_embeddings_initialized_aux() {
  return p_premise_embeddings != nullptr;
}

extern "C" uint8_t is_p_premise_embeddings_initialized(lean_object *) {
  return is_p_premise_embeddings_initialized_aux();
}

extern "C" uint8_t init_premise_dictionary(b_lean_obj_arg _path) {
  std::string path = std::string(lean_string_cstr(_path));
  if (!exists(path)) {
    return false;
  }
  if (p_premise_dictionary != nullptr) {
    delete p_premise_dictionary;
  }

  std::ifstream f(path);
  p_premise_dictionary = new json(json::parse(f));

  return true;
}

inline bool is_premise_dictionary_initialized_aux() {
  return p_premise_dictionary != nullptr;
}

extern "C" uint8_t is_premise_dictionary_initialized(lean_object *) {
  return is_premise_dictionary_initialized_aux();
}

extern "C" lean_obj_res retrieve(b_lean_obj_arg _query_emb,
                                 uint64_t _k) {  // FloatArray
  // lean_object *arr
  // assert(p_premise_embeddings && static_cast<int64_t>(p_arr->m_size) ==
  // p_premise_embeddings->dim(1));

  int64_t d = lean_unbox(lean_float_array_size(_query_emb));
  std::vector<float> query_emb_data;
  for (int i = 0; i < d; i++) {
    query_emb_data.push_back(lean_float_array_uget(_query_emb, i));
  }

  ctranslate2::Device device = p_premise_embeddings->device();
  ctranslate2::StorageView query_emb =
      ctranslate2::StorageView({d, 1}, query_emb_data, device);

  // TODO:
  ctranslate2::ops::MatMul matmul(false, false, 1.0);
  long int k = static_cast<long int>(_k);
  ctranslate2::ops::TopK topk(k, -1);

  int num_premises = p_premise_embeddings->dim(0);
  std::vector<int64_t> probs_shape{num_premises, 1};

  ctranslate2::StorageView probs = ctranslate2::StorageView(
      probs_shape, ctranslate2::DataType::FLOAT32, device);
  matmul(*p_premise_embeddings, query_emb, probs);
  probs.resize({num_premises});

  ctranslate2::StorageView topk_values =
      ctranslate2::StorageView({k}, ctranslate2::DataType::FLOAT32, device);
  ctranslate2::StorageView topk_indices =
      ctranslate2::StorageView({k}, ctranslate2::DataType::INT32, device);
  topk(probs, topk_values, topk_indices);

  lean_object *output = lean_mk_empty_array();
  const int *p_topk_indices = topk_indices.data<int>();
  const float *p_topk_values = topk_values.data<float>();

  for (int i = 0; i < k; i++) {
    int idx = p_topk_indices[i];
    assert(0 < idx && idx < num_premises);
    // [NOTE]: This is where the server crash occurs on CUDA.
    const std::string this_premise = (*p_premise_dictionary)[std::to_string(idx)]["full_name"];
    const std::string this_path = (*p_premise_dictionary)[std::to_string(idx)]["path"];
    const std::string this_code = (*p_premise_dictionary)[std::to_string(idx)]["code"];

    output = lean_array_push(output, lean_mk_pair(
        lean_mk_string(this_premise.c_str()),
        lean_mk_pair(lean_mk_string(this_path.c_str()),
                     lean_mk_pair(lean_mk_string(this_code.c_str()),
                                  lean_box_float(p_topk_values[i])))));
  }

  return output;
}
