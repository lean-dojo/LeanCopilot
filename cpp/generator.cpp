#include <lean/lean.h>
#include <onnxruntime_cxx_api.h>

#include <set>
#include <locale>
#include <random>
#include <string>
#include <vector>
#include <fstream>
#include <cassert>
#include <codecvt>
#include <iostream>
#include <algorithm>
#include <stdexcept>


/* Constants */
constexpr int64_t NUM_SPECIAL_TOKENS = 3;  // PAD, EOS, UNK
constexpr int64_t PAD_TOKEN_ID = 0;
constexpr int64_t EOS_TOKEN_ID = 1;
constexpr int64_t UNK_TOKEN_ID = 2;
constexpr int64_t DECODER_START_TOKEN_ID = 0;
constexpr int64_t VOCAB_SIZE = 384;
constexpr int64_t NUM_VALID_TOKENS = 256;
constexpr int64_t BATCH_SIZE = 1;
constexpr int64_t ATTENTION_MASL_VALID = 1;

const std::vector<const char *> ENCODER_INPUT_NAMES = {"input_ids",
                                                       "attention_mask"};
const std::vector<const char *> ENCODER_OUTPUT_NAMES = {"last_hidden_state"};
const std::vector<const char *> DECODER_RAW_INPUT_NAMES = {
    "encoder_attention_mask", "input_ids", "encoder_hidden_states"};
const std::vector<const char *> DECODER_RAW_OUTPUT_NAMES = {
    "logits",
    "present.0.decoder.key",
    "present.0.decoder.value",
    "present.0.encoder.key",
    "present.0.encoder.value",
    "present.1.decoder.key",
    "present.1.decoder.value",
    "present.1.encoder.key",
    "present.1.encoder.value",
    "present.2.decoder.key",
    "present.2.decoder.value",
    "present.2.encoder.key",
    "present.2.encoder.value",
    "present.3.decoder.key",
    "present.3.decoder.value",
    "present.3.encoder.key",
    "present.3.encoder.value",
};
const std::vector<const char *> DECODER_WITH_PAST_INPUT_NAMES = {
    "encoder_attention_mask",          "input_ids",
    "encoder_hidden_states",           "past_key_values.0.decoder.key",
    "past_key_values.0.decoder.value", "past_key_values.0.encoder.key",
    "past_key_values.0.encoder.value", "past_key_values.1.decoder.key",
    "past_key_values.1.decoder.value", "past_key_values.1.encoder.key",
    "past_key_values.1.encoder.value", "past_key_values.2.decoder.key",
    "past_key_values.2.decoder.value", "past_key_values.2.encoder.key",
    "past_key_values.2.encoder.value", "past_key_values.3.decoder.key",
    "past_key_values.3.decoder.value", "past_key_values.3.encoder.key",
    "past_key_values.3.encoder.value",
};
const std::vector<const char *> DECODER_WITH_PAST_OUTPUT_NAMES = {
    "logits",
    "present.0.decoder.key",
    "present.0.decoder.value",
    "present.1.decoder.key",
    "present.1.decoder.value",
    "present.2.decoder.key",
    "present.2.decoder.value",
    "present.3.decoder.key",
    "present.3.decoder.value",
};

/* Global variables */
Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "test");
Ort::SessionOptions opts;
Ort::MemoryInfo mem_info = Ort::MemoryInfo::CreateCpu(
    OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);
Ort::Session *p_encoder_session = nullptr;
Ort::Session *p_decoder_raw_session = nullptr;
Ort::Session *p_decoder_with_past_session = nullptr;

/* Simulated Byt5 tokenizer */
std::vector<int64_t> tokenize(const char *input) {
  setlocale(LC_ALL, "");
  size_t l = strlen(input) + 1;
  wchar_t *input_wide = new wchar_t[l];
  mbstowcs(input_wide, input, l);

  std::vector<int64_t> tokens;
  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;

  for (unsigned char byte : converter.to_bytes(input_wide)) {
    tokens.push_back(static_cast<int64_t>(byte) + NUM_SPECIAL_TOKENS);
  }
  tokens.push_back(EOS_TOKEN_ID);

  delete[] input_wide;
  return tokens;
}

/* Simulated Byt5 detokenizer that reverses the effects of its tokenizer */
std::string detokenize(const std::vector<int64_t> &tokens) {
  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  std::string s_utf8;

  for (size_t i = 0; i < tokens.size(); i++) {
    assert(NUM_SPECIAL_TOKENS <= tokens[i] &&
           tokens[i] < NUM_SPECIAL_TOKENS + NUM_VALID_TOKENS);
    s_utf8.push_back(
        static_cast<unsigned char>(tokens[i] - NUM_SPECIAL_TOKENS));
  }

  try {
    std::wstring ws = converter.from_bytes(s_utf8);
    int l = wcstombs(nullptr, ws.c_str(), 0);
    char *buf = new char[l + 1];
    wcstombs(buf, ws.c_str(), l + 1);
    std::string s(buf);
    delete[] buf;
    return s;
  } catch (std::range_error) {
    return "";
  }
}

inline bool str_eq(const char *s1, const char *s2) {
  return strcmp(s1, s2) == 0;
}

std::vector<float> get_logits(std::vector<Ort::Value> &output_tensors) {
  assert(str_eq(DECODER_RAW_OUTPUT_NAMES[0], "logits") &&
         str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[0], "logits"));
  const float *p = output_tensors[0].GetTensorMutableData<float>();
  return std::vector<float>(p, p + VOCAB_SIZE);
}

double sum(const std::vector<double> &v) {
  return std::accumulate(v.cbegin(), v.cend(), 0.0);
}

/* Greedy search algorithm with multinomial sampling */
int64_t sample(const std::vector<float> &logits, double temperature) {
  // Calculate `probs` as the softmax of `logits`.
  assert(logits.size() == VOCAB_SIZE);
  std::vector<double> probs;

  for (int i = 0; i < VOCAB_SIZE; i++) {
    if (i == PAD_TOKEN_ID || i == UNK_TOKEN_ID ||
        i > NUM_SPECIAL_TOKENS + NUM_VALID_TOKENS) {
      probs.push_back(0.0);
      continue;
    }
    double v = static_cast<double>(logits[i]);
    assert(std::isnormal(v));
    probs.push_back(std::exp(v / temperature));
  }

  double eps = 1e-5;
  double sum_probs = sum(probs);
  assert(sum_probs > eps);
  for (double &p : probs) {
    p /= sum_probs;
  }
  assert(std::abs(sum(probs) - 1.0) < eps);

  std::random_device rd;
  std::mt19937 gen(rd());
  std::discrete_distribution<int64_t> distribution(probs.cbegin(),
                                                   probs.cend());

  int64_t sampled_token = distribution(gen);
  assert(0 <= sampled_token && sampled_token < VOCAB_SIZE);
  return sampled_token;
}

template <typename T>
void set_tensor(std::vector<Ort::Value> &a, int i, Ort::Value &x) {
  a[i] = Ort::Value::CreateTensor<T>(
      mem_info, x.GetTensorMutableData<T>(),
      x.GetTensorTypeAndShapeInfo().GetElementCount(),
      x.GetTensorTypeAndShapeInfo().GetShape().data(),
      x.GetTensorTypeAndShapeInfo().GetShape().size());
}

template <typename T>
void append_tensor(std::vector<Ort::Value> &a, Ort::Value &x) {
  a.push_back(Ort::Value::CreateTensor<T>(
      mem_info, x.GetTensorMutableData<T>(),
      x.GetTensorTypeAndShapeInfo().GetElementCount(),
      x.GetTensorTypeAndShapeInfo().GetShape().data(),
      x.GetTensorTypeAndShapeInfo().GetShape().size()));
}

void check_tensors(const std::vector<Ort::Value> &ts) {
  assert(std::all_of(ts.begin(), ts.end(),
                     [](const Ort::Value &t) { return t.IsTensor(); }));
}

template <typename T>
Ort::Value create_tensor(std::vector<T> &v, std::vector<T> &dim) {
  assert(v.size() ==
         std::accumulate(begin(dim), end(dim), 1, std::multiplies<T>()));
  return Ort::Value::CreateTensor<T>(mem_info, v.data(), v.size(), dim.data(),
                                     dim.size());
}

inline std::vector<Ort::Value> run_onnx(
    Ort::Session &sess, const std::vector<Ort::Value> &input_tensors,
    const std::vector<const char *> &input_names,
    const std::vector<const char *> &output_names) {
  return sess.Run(Ort::RunOptions{nullptr}, input_names.data(),
                  input_tensors.data(), input_names.size(), output_names.data(),
                  output_names.size());
}

std::vector<Ort::Value> run_encoder(std::vector<int64_t> &input_ids,
                                    std::vector<int64_t> &attention_mask,
                                    int64_t batch_size) {
  // Prepare the encoder's input.
  int64_t l = input_ids.size();
  std::vector<int64_t> dim = {batch_size, l};

  std::vector<Ort::Value> input_tensors;
  input_tensors.push_back(create_tensor(input_ids, dim));
  input_tensors.push_back(create_tensor(attention_mask, dim));

  // Run the encoder and return last_hidden_state.
  std::vector<Ort::Value> output_tensors =
      run_onnx(*p_encoder_session, input_tensors, ENCODER_INPUT_NAMES,
               ENCODER_OUTPUT_NAMES);
  return output_tensors;
}

std::vector<Ort::Value> run_decoder_raw(
    Ort::Value &last_hidden_state, std::vector<int64_t> &attention_mask,
    std::vector<int64_t> &encoder_input_dim) {
  // Prepare the decoder's input.
  std::vector<int64_t> input_ids = {DECODER_START_TOKEN_ID};
  std::vector<int64_t> dim = {BATCH_SIZE, 1};

  std::vector<Ort::Value> input_tensors;
  input_tensors.push_back(create_tensor(attention_mask, encoder_input_dim));
  input_tensors.push_back(create_tensor(input_ids, dim));
  append_tensor<float>(input_tensors, last_hidden_state);

  // Run the decoder.
  std::vector<Ort::Value> output_tensors =
      run_onnx(*p_decoder_raw_session, input_tensors, DECODER_RAW_INPUT_NAMES,
               DECODER_RAW_OUTPUT_NAMES);
  check_tensors(output_tensors);
  return output_tensors;
}

std::vector<int64_t> run_decoder(Ort::Value &last_hidden_state,
                                 std::vector<int64_t> &attention_mask,
                                 std::vector<int64_t> &encoder_input_dim,
                                 size_t max_length, double temperature) {
  std::vector<Ort::Value> raw_output_tensors =
      run_decoder_raw(last_hidden_state, attention_mask, encoder_input_dim);
  check_tensors(raw_output_tensors);

  std::vector<float> logits = get_logits(raw_output_tensors);
  int64_t next_token = sample(logits, temperature);
  if (next_token == EOS_TOKEN_ID) {
    return {};
  }

  std::vector<int64_t> input_ids = {next_token};
  std::vector<int64_t> dim = {BATCH_SIZE, 1};
  std::vector<Ort::Value> input_tensors;
  input_tensors.push_back(create_tensor(attention_mask, encoder_input_dim));
  input_tensors.push_back(create_tensor(input_ids, dim));
  append_tensor<float>(input_tensors, last_hidden_state);
  for (int i = 1; i < raw_output_tensors.size(); i++) {
    assert(strncmp(DECODER_RAW_OUTPUT_NAMES[i], "present.", 8) == 0);
    append_tensor<float>(input_tensors, raw_output_tensors[i]);
  }

  // If you move this inside the loop, the program will produce nan.
  std::vector<Ort::Value> with_past_output_tensors;
  std::vector<int64_t> tokens = {next_token};

  for (int n_step = 1; n_step < max_length; n_step++) {
    with_past_output_tensors =
        run_onnx(*p_decoder_with_past_session, input_tensors,
                 DECODER_WITH_PAST_INPUT_NAMES, DECODER_WITH_PAST_OUTPUT_NAMES);
    check_tensors(with_past_output_tensors);

    logits = get_logits(with_past_output_tensors);
    next_token = sample(logits, temperature);
    if (next_token == EOS_TOKEN_ID) {
      break;
    }
    tokens.push_back(next_token);

    input_ids.clear();
    input_ids.push_back(next_token);
    input_tensors.clear();
    input_tensors.push_back(create_tensor(attention_mask, encoder_input_dim));
    input_tensors.push_back(create_tensor(input_ids, dim));
    append_tensor<float>(input_tensors, last_hidden_state);

    for (int i = 1; i < raw_output_tensors.size(); i++) {
      assert(strncmp(DECODER_RAW_OUTPUT_NAMES[i], "present.", 8) == 0);
      append_tensor<float>(input_tensors, raw_output_tensors[i]);
    }

    assert(
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[1], "present.0.decoder.key") &&
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[2], "present.0.decoder.value"));
    assert(str_eq(DECODER_WITH_PAST_INPUT_NAMES[3],
                  "past_key_values.0.decoder.key") &&
           str_eq(DECODER_WITH_PAST_INPUT_NAMES[4],
                  "past_key_values.0.decoder.value"));
    set_tensor<float>(input_tensors, 3, with_past_output_tensors[1]);
    set_tensor<float>(input_tensors, 4, with_past_output_tensors[2]);

    assert(
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[3], "present.1.decoder.key") &&
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[4], "present.1.decoder.value"));
    assert(str_eq(DECODER_WITH_PAST_INPUT_NAMES[7],
                  "past_key_values.1.decoder.key") &&
           str_eq(DECODER_WITH_PAST_INPUT_NAMES[8],
                  "past_key_values.1.decoder.value"));
    set_tensor<float>(input_tensors, 7, with_past_output_tensors[3]);
    set_tensor<float>(input_tensors, 8, with_past_output_tensors[4]);

    assert(
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[5], "present.2.decoder.key") &&
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[6], "present.2.decoder.value"));
    assert(str_eq(DECODER_WITH_PAST_INPUT_NAMES[11],
                  "past_key_values.2.decoder.key") &&
           str_eq(DECODER_WITH_PAST_INPUT_NAMES[12],
                  "past_key_values.2.decoder.value"));
    set_tensor<float>(input_tensors, 11, with_past_output_tensors[5]);
    set_tensor<float>(input_tensors, 12, with_past_output_tensors[6]);

    assert(
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[7], "present.3.decoder.key") &&
        str_eq(DECODER_WITH_PAST_OUTPUT_NAMES[8], "present.3.decoder.value"));
    assert(str_eq(DECODER_WITH_PAST_INPUT_NAMES[15],
                  "past_key_values.3.decoder.key") &&
           str_eq(DECODER_WITH_PAST_INPUT_NAMES[16],
                  "past_key_values.3.decoder.value"));
    set_tensor<float>(input_tensors, 15, with_past_output_tensors[7]);
    set_tensor<float>(input_tensors, 16, with_past_output_tensors[8]);
  }

  return tokens;
}

/* Run inference on the transformers model */
std::string run_inference(std::vector<int64_t> input_ids, uint64_t max_length,
                          double temperature) {
  // Run the encoder.
  int64_t l = input_ids.size();
  std::vector<int64_t> encoder_input_dim = {1, l};
  std::vector<int64_t> attention_mask(l, ATTENTION_MASL_VALID);
  Ort::Value last_hidden_state =
      std::move(run_encoder(input_ids, attention_mask, 1).front());

  // Run the decoder.
  std::vector<int64_t> tokens =
      run_decoder(last_hidden_state, attention_mask, encoder_input_dim,
                  max_length, temperature);

  // Detokenize output and return as a Lean string
  return detokenize(tokens);
}

static lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}

inline bool exists(const std::string &path) {
  std::ifstream f(path.c_str());
  return f.good();
}

extern "C" uint8_t init_generator(b_lean_obj_arg model_dir) {

  const char *dir = lean_string_cstr(model_dir);
  const std::string decoder_with_past_path = std::string(dir) + "/decoder_with_past_model.onnx";
  const std::string decoder_raw_path = std::string(dir) + "/decoder_model.onnx";
  const std::string encoder_path = std::string(dir) + "/encoder_model.onnx";

  if (!exists(encoder_path)) {
    return false;
  }
  if (p_encoder_session != nullptr) {
    delete p_encoder_session;
  }
  p_encoder_session = new Ort::Session(env, encoder_path.c_str(), opts);

  if (p_decoder_raw_session != nullptr) {
    delete p_decoder_raw_session;
  }
  p_decoder_raw_session = new Ort::Session(env, decoder_raw_path.c_str(), opts);

  if (p_decoder_with_past_session != nullptr) {
    delete p_decoder_with_past_session;
  }
  p_decoder_with_past_session =
      new Ort::Session(env, decoder_with_past_path.c_str(), opts);
  return true;
}

inline bool is_initialized_aux() {
  assert((p_encoder_session && p_decoder_raw_session &&
         p_decoder_with_past_session) || (!p_encoder_session &&
                                                        !p_decoder_raw_session &&
                                                        !p_decoder_with_past_session));
  return p_encoder_session != nullptr;
}

extern "C" uint8_t is_initialized(lean_object *) {
  return is_initialized_aux();
}

extern "C" lean_obj_res generate(b_lean_obj_arg input,
                                 uint64_t num_return_sequences,
                                 uint64_t max_length, double temperature,
                                 uint64_t num_beams) {
  // Check the arguments.
  if (!is_initialized_aux()) {
    throw std::runtime_error("Generator is not initialized.");
  }
  if (num_return_sequences <= 0) {
    throw std::invalid_argument("num_return_sequences must be positive.");
  }
  if (max_length <= 0) {
    throw std::invalid_argument("max_length must be positive.");
  }
  if (temperature <= 0) {
    throw std::invalid_argument("temperature must be positive.");
  }
  if (num_beams <= 0) {
    throw std::invalid_argument("num_beams must be positive.");
  }
  if (num_beams > 1) {
    throw std::invalid_argument("Beam search is not supported yet.");
  }

  // Tokenization.
  std::vector<int64_t> tokenized_input = tokenize(lean_string_cstr(input));

  // Run the tactic generator.
  // TODO: Run the tactic generator in a batch.
  // TODO: Calculate the score.
  std::set<std::string> tactics;
  while (tactics.size() < num_return_sequences) {
    std::string tac = run_inference(tokenized_input, max_length, temperature);
    if (tac.empty()) {
      continue;
    }
    tactics.emplace(tac);
  }
  assert(tactics.size() == num_return_sequences);

  // Return Lean strings.
  lean_array_object *arr = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  int i = 0;
  for (auto it = tactics.begin(); it != tactics.end(); it++, i++) {
    arr->m_data[i] =
        lean_mk_pair(lean_mk_string(it->c_str()), lean_box_float(1.0));
  }

  return reinterpret_cast<lean_obj_res>(arr);
}
