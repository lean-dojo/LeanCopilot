#include <lean/lean.h>
#include <onnxruntime_cxx_api.h>

#include <algorithm>
#include <cassert>
#include <codecvt>
#include <iostream>
#include <locale>
#include <random>
#include <string>
#include <vector>

/* Constants */
constexpr int NUM_SPECIAL_TOKENS = 3;  // PAD, EOS, UNK
constexpr int EOS_TOKEN_ID = 1;
constexpr int DECODER_START_TOKEN_ID = 0;
constexpr int VOCAB_SIZE = 384;
constexpr int BATCH_SIZE = 1;
constexpr int ATTENTION_MASL_VALID = 1;

const std::string DECODER_WITH_PAST_PATH =
    "onnx-leandojo-lean4-tacgen-byt5-small/decoder_with_past_model.onnx";
const std::string DECODER_RAW_PATH =
    "onnx-leandojo-lean4-tacgen-byt5-small/decoder_model.onnx";
const std::string ENCODER_PATH =
    "onnx-leandojo-lean4-tacgen-byt5-small/encoder_model.onnx";
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
Ort::Session encoder_session(env, ENCODER_PATH.c_str(), opts);
Ort::Session decoder_raw_session(env, DECODER_RAW_PATH.c_str(), opts);
Ort::Session decoder_with_past_session(env, DECODER_WITH_PAST_PATH.c_str(),
                                       opts);
Ort::MemoryInfo mem_info = Ort::MemoryInfo::CreateCpu(
    OrtAllocatorType::OrtArenaAllocator, OrtMemType::OrtMemTypeDefault);

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

/* Simulated Byt5 detokenizer that reverses the effects of it tokenizer */
const char *detokenize(const std::vector<int64_t> &tokens) {
  assert(!tokens.empty() && tokens.back() == EOS_TOKEN_ID);
  std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
  std::string s_utf8;

  for (size_t i = 0; i < tokens.size() - 1; i++) {
    assert(tokens[i] != EOS_TOKEN_ID);
    s_utf8.push_back(
        static_cast<unsigned char>(tokens[i] - NUM_SPECIAL_TOKENS));
  }

  std::wstring ws = converter.from_bytes(s_utf8);
  int l = wcstombs(nullptr, ws.c_str(), 0);
  char *s = new char[l + 1];
  wcstombs(s, ws.c_str(), l + 1);
  return s;
}

/* Greedy search algorithm with multinomial sampling */
int64_t sample(float *logits) {
  std::vector<float> probabilities(VOCAB_SIZE);
  std::copy(logits, logits + VOCAB_SIZE, probabilities.begin());

  for (float &probability : probabilities) {
    probability = std::exp(probability);
  }
  const float sum_probs =
      std::accumulate(probabilities.begin(), probabilities.end(), 0.0f);
  for (float &prob : probabilities) {
    prob /= sum_probs;
  }

  std::random_device rd;
  std::mt19937 gen(rd());
  std::discrete_distribution<int64_t> distribution(probabilities.begin(),
                                                   probabilities.end());

  int64_t sampled_token = distribution(gen);
  return sampled_token;
}

/* Append a tensor of float to a vector */
void tensor_float_append(std::vector<Ort::Value> &host_tensor,
                         Ort::Value &guest_tensor) {
  host_tensor.push_back(Ort::Value::CreateTensor<float>(
      mem_info, guest_tensor.GetTensorMutableData<float>(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetElementCount(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetShape().data(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetShape().size()));
}

/* Append a tensor of int64_t to a vector */
void tensor_int64_t_append(std::vector<Ort::Value> &host_tensor,
                           Ort::Value &guest_tensor) {
  host_tensor.push_back(Ort::Value::CreateTensor<int64_t>(
      mem_info, guest_tensor.GetTensorMutableData<int64_t>(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetElementCount(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetShape().data(),
      guest_tensor.GetTensorTypeAndShapeInfo().GetShape().size()));
}

Ort::Value run_encoder(std::vector<int64_t> &input_ids,
                       std::vector<int64_t> &attention_mask) {
  // Prepare the encoder's input.
  size_t length = input_ids.size();
  std::vector<int64_t> dim = {BATCH_SIZE, static_cast<int64_t>(length)};

  std::vector<Ort::Value> input_tensors;
  input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
      mem_info, input_ids.data(), length, dim.data(), dim.size()));
  input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
      mem_info, attention_mask.data(), length, dim.data(), dim.size()));

  // Run the encoder.
  std::vector<Ort::Value> output_tensors = encoder_session.Run(
      Ort::RunOptions{nullptr}, ENCODER_INPUT_NAMES.data(),
      input_tensors.data(), ENCODER_INPUT_NAMES.size(),
      ENCODER_OUTPUT_NAMES.data(), ENCODER_OUTPUT_NAMES.size());

  // Return last_hidden_state.
  return std::move(output_tensors.front());
}

std::vector<int64_t> run_decoder(Ort::Value &last_hidden_state,
                                 std::vector<int64_t> &attention_mask,
                                 size_t encoder_input_length,
                                 std::vector<int64_t> &encoder_input_dim,
                                 size_t max_length) {
  std::vector<int64_t> input_ids = {DECODER_START_TOKEN_ID};
  size_t decoder_input_tensor_size = input_ids.size();
  std::vector<int64_t> decoder_input_dim = {
      BATCH_SIZE, static_cast<int64_t>(decoder_input_tensor_size)};

  std::vector<Ort::Value> decoder_input_tensors;
  decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
      mem_info, attention_mask.data(), encoder_input_length,
      encoder_input_dim.data(), encoder_input_dim.size()));
  decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
      mem_info, input_ids.data(), decoder_input_tensor_size,
      decoder_input_dim.data(), decoder_input_dim.size()));
  tensor_float_append(decoder_input_tensors, last_hidden_state);

  std::vector<Ort::Value> decoder_raw_output_tensors;
  std::vector<Ort::Value> decoder_with_past_output_tensors;
  float *curr_logits;
  std::vector<int64_t> model_outputs;

  for (int timestep = 0; timestep < max_length; timestep++) {
    if (timestep == 0) {
      decoder_raw_output_tensors = decoder_raw_session.Run(
          Ort::RunOptions{nullptr}, DECODER_RAW_INPUT_NAMES.data(),
          decoder_input_tensors.data(), DECODER_RAW_INPUT_NAMES.size(),
          DECODER_RAW_OUTPUT_NAMES.data(), DECODER_RAW_OUTPUT_NAMES.size());

      bool allTensorsValid = std::all_of(
          decoder_raw_output_tensors.begin(), decoder_raw_output_tensors.end(),
          [](const Ort::Value &tensor) { return tensor.IsTensor(); });
      assert(allTensorsValid);

      curr_logits =
          decoder_raw_output_tensors.at(0).GetTensorMutableData<float>();
      int64_t curr_token = sample(curr_logits);
      model_outputs.push_back(curr_token);

      if (curr_token == 1) break;
      input_ids.clear();
      input_ids.push_back(curr_token);

      decoder_input_tensors.clear();
      decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
          mem_info, attention_mask.data(), encoder_input_length,
          encoder_input_dim.data(), encoder_input_dim.size()));
      decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
          mem_info, input_ids.data(), decoder_input_tensor_size,
          decoder_input_dim.data(), decoder_input_dim.size()));
      tensor_float_append(decoder_input_tensors, last_hidden_state);

      for (int i = 1; i < decoder_raw_output_tensors.size(); i++) {
        tensor_float_append(decoder_input_tensors,
                            decoder_raw_output_tensors.at(i));
      }
    } else {
      decoder_with_past_output_tensors = decoder_with_past_session.Run(
          Ort::RunOptions{nullptr}, DECODER_WITH_PAST_INPUT_NAMES.data(),
          decoder_input_tensors.data(), DECODER_WITH_PAST_INPUT_NAMES.size(),
          DECODER_WITH_PAST_OUTPUT_NAMES.data(),
          DECODER_WITH_PAST_OUTPUT_NAMES.size());

      assert(decoder_with_past_output_tensors.size() ==
             DECODER_WITH_PAST_OUTPUT_NAMES.size());
      bool allTensorsValid = std::all_of(
          decoder_with_past_output_tensors.begin(),
          decoder_with_past_output_tensors.end(),
          [](const Ort::Value &tensor) { return tensor.IsTensor(); });
      assert(allTensorsValid);

      curr_logits =
          decoder_with_past_output_tensors.at(0).GetTensorMutableData<float>();
      int64_t curr_token = sample(curr_logits);
      model_outputs.push_back(curr_token);

      if (curr_token == 1) break;
      input_ids.clear();
      input_ids.push_back(curr_token);

      std::vector<Ort::Value> temporary_tensors;
      for (int i = 0; i < decoder_input_tensors.size(); i++) {
        if (i == 0) {
          tensor_int64_t_append(temporary_tensors, decoder_input_tensors.at(i));
        } else if (i == 1) {
          temporary_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
              mem_info, input_ids.data(), decoder_input_tensor_size,
              decoder_input_dim.data(), decoder_input_dim.size()));
        } else if (i == 2 || i == 5 || i == 6 || i == 9 || i == 10 || i == 13 ||
                   i == 14 || i == 17 || i == 18) {
          tensor_float_append(temporary_tensors, decoder_input_tensors.at(i));
        } else {
          assert(i == 3 || i == 4 || i == 7 || i == 8 || i == 11 || i == 12 ||
                 i == 15 || i == 16);
          tensor_float_append(temporary_tensors,
                              decoder_with_past_output_tensors.at(i / 2));
        }
      }

      assert(temporary_tensors.size() == decoder_input_tensors.size());
      for (int i = 0; i < temporary_tensors.size(); i++) {
        assert(temporary_tensors.at(i)
                   .GetTensorTypeAndShapeInfo()
                   .GetElementType() == decoder_input_tensors.at(i)
                                            .GetTensorTypeAndShapeInfo()
                                            .GetElementType());
      }

      decoder_input_tensors.clear();
      for (int i = 0; i < temporary_tensors.size(); i++) {
        if (i == 0 || i == 1) {
          tensor_int64_t_append(decoder_input_tensors, temporary_tensors.at(i));
        } else {
          tensor_float_append(decoder_input_tensors, temporary_tensors.at(i));
        }
      }
    }
  }

  return model_outputs;
}

/* Run inference on the transformers model */
std::pair<const char *, double> run_inference(std::vector<int64_t> input_ids,
                                              uint64_t max_length) {
  // Run encoder
  size_t encoder_input_length = input_ids.size();
  std::vector<int64_t> encoder_input_dim = {
      BATCH_SIZE, static_cast<int64_t>(encoder_input_length)};
  std::vector<int64_t> attention_mask(encoder_input_length,
                                      ATTENTION_MASL_VALID);
  Ort::Value last_hidden_state = run_encoder(input_ids, attention_mask);

  // Run decoder
  std::vector<int64_t> model_outputs =
      run_decoder(last_hidden_state, attention_mask, encoder_input_length,
                  encoder_input_dim, max_length);

  // Detokenize output and return as a Lean string
  const char *tac = detokenize(model_outputs);
  return std::make_pair(tac, 0.5);
}

static lean_obj_res lean_mk_pair(lean_obj_arg a, lean_obj_arg b) {
  lean_object *r = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(r, 0, a);
  lean_ctor_set(r, 1, b);
  return r;
}

extern "C" lean_obj_res generate(lean_obj_arg input,
                                 uint64_t num_return_sequences,
                                 uint64_t max_length, double temperature,
                                 double top_p, uint64_t num_beams) {
  // Check the arguments.
  if (num_return_sequences <= 0) {
    throw std::invalid_argument("num_return_sequences must be positive.");
  }
  if (max_length <= 0) {
    throw std::invalid_argument("max_length must be positive.");
  }
  if (temperature <= 0) {
    throw std::invalid_argument("temperature must be positive.");
  }
  if (top_p <= 0 || top_p > 1) {
    throw std::invalid_argument("top_p must be in (0, 1].");
  }
  if (num_beams <= 0) {
    throw std::invalid_argument("num_beams must be positive.");
  }
  if (num_beams > 1) {
    throw std::invalid_argument("Beam search is not supported yet.");
  }

  // Tokenization.
  std::vector<int64_t> tokenized_input = tokenize(lean_string_cstr(input));

  // Run the tactic generator and return Lean strings.
  // Don't worry about duplications. It can be handled in Lean.
  lean_array_object *arr = reinterpret_cast<lean_array_object *>(
      lean_alloc_array(num_return_sequences, num_return_sequences));

  for (int i = 0; i < num_return_sequences; i++) {
    auto p = run_inference(tokenized_input, max_length);
    const char *tac = p.first;
    double s = p.second;
    arr->m_data[i] = lean_mk_pair(lean_mk_string(tac), lean_box_float(s));
  }

  return reinterpret_cast<lean_obj_res>(arr);
}

extern "C" lean_obj_res encode(lean_obj_arg input) {
  lean_object *arr = lean_mk_empty_float_array(lean_box(10));
  lean_float_array_push(arr, 0.34);
  lean_float_array_push(arr, 0.84);
  lean_float_array_push(arr, 0.57);
  lean_float_array_push(arr, 2.63);
  lean_float_array_push(arr, 0.67);
  return arr;
}
