#include <vector>
#include <string>
#include <locale>
#include <codecvt>
#include <cassert>
#include <algorithm>
#include <random>

#include <lean/lean.h>
#include <onnxruntime_cxx_api.h>


// Prepare ORT environment and sessions
const char * decoder_with_past_path = "onnx-leandojo-lean4-tacgen-byt5-small/inference/decoder_with_past_model.onnx";
const char * decoder_raw_path = "onnx-leandojo-lean4-tacgen-byt5-small/inference/decoder_model.onnx";
const char * encoder_path = "onnx-leandojo-lean4-tacgen-byt5-small/inference/encoder_model.onnx";

Ort::Env env(ORT_LOGGING_LEVEL_WARNING, "test");
Ort::SessionOptions sessionOptions;

Ort::Session encoder_session(env, encoder_path, sessionOptions);
Ort::Session decoder_raw_session(env, decoder_raw_path, sessionOptions);
Ort::Session decoder_with_past_session(env, decoder_with_past_path, sessionOptions);

Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(
    OrtAllocatorType::OrtArenaAllocator, 
    OrtMemType::OrtMemTypeDefault
);


// Set hyperparameters
const int MAX_TIMESTEPS = 256;
const int NUM_TOKENS = 384;
const int BATCH_SIZE = 1;


/* Greedy search algorithm with multinomial sampling */
int64_t sample(float * logits) {
    std::vector<float> probabilities(NUM_TOKENS);
    std::copy(logits, logits + NUM_TOKENS, probabilities.begin());

    for (float & probability : probabilities) {
        probability = std::exp(probability);
    }
    const float sum_probs = std::accumulate(probabilities.begin(), probabilities.end(), 0.0f);
    for (float & prob : probabilities) {
        prob /= sum_probs;
    }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::discrete_distribution<int64_t> distribution(probabilities.begin(), probabilities.end());

    int64_t sampled_token = distribution(gen);
    return sampled_token;
}


/* Simulated Byt5 tokenizer */
std::vector<int64_t> tokenize(const wchar_t * curr_ts) {
    std::vector<int64_t> tokenized;
    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    std::string utf8_input = converter.to_bytes(curr_ts);

    for (unsigned char byte : utf8_input) {
        tokenized.push_back(static_cast<int64_t>(byte) + 3);
    }
    tokenized.push_back(1);

    return tokenized;
}


/* Simulated Byt5 detokenizer that reverses the effects of it tokenizer */
wchar_t * detokenize(std::vector<int64_t> & tokenized) {
    assert (!tokenized.empty());
    assert (tokenized.back() == 1);

    std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
    std::string utf8_input;

    for (size_t i = 0; i < tokenized.size() - 1; ++i) {
        assert (tokenized.at(i) != 1);
        utf8_input.push_back(static_cast<unsigned char>(tokenized.at(i) - 3));
    }

    std::wstring wide_string = converter.from_bytes(utf8_input);
    wchar_t * wide_string_cstr = new wchar_t[wide_string.size() + 1];
    wcscpy(wide_string_cstr, wide_string.c_str());

    return wide_string_cstr;
}


/* Append a tensor of float to a vector */
void tensor_float_append(std::vector<Ort::Value> & host_tensor, Ort::Value & guest_tensor) {
    host_tensor.push_back(Ort::Value::CreateTensor<float>(
        memory_info, 
        guest_tensor.GetTensorMutableData<float>(), 
        guest_tensor.GetTensorTypeAndShapeInfo().GetElementCount(),
        guest_tensor.GetTensorTypeAndShapeInfo().GetShape().data(), 
        guest_tensor.GetTensorTypeAndShapeInfo().GetShape().size()
    ));
}


/* Append a tensor of int64_t to a vector */
void tensor_int64_t_append(std::vector<Ort::Value> & host_tensor, Ort::Value & guest_tensor) {
    host_tensor.push_back(Ort::Value::CreateTensor<int64_t>(
        memory_info, 
        guest_tensor.GetTensorMutableData<int64_t>(), 
        guest_tensor.GetTensorTypeAndShapeInfo().GetElementCount(),
        guest_tensor.GetTensorTypeAndShapeInfo().GetShape().data(), 
        guest_tensor.GetTensorTypeAndShapeInfo().GetShape().size()
    ));
}


extern "C" lean_object * core_fun(lean_obj_arg curr_tactic_state) {

    // Fetch and tokenize input tactic state
    const char * narrow_input = lean_string_cstr(curr_tactic_state);

    setlocale(LC_ALL, "");
    size_t buffered_length = strlen(narrow_input) + 1;
    wchar_t* wide_input = new wchar_t[buffered_length];
    mbstowcs(wide_input, narrow_input, buffered_length);

    std::vector<int64_t> tokenized_input = tokenize(wide_input);


    // Run encoder
    const std::vector<const char *> encoder_input_names = {
        "input_ids", 
        "attention_mask"
    };
    const std::vector<const char *> encoder_output_names = {
        "last_hidden_state"
    };

    const int encoder_num_inputs = 2;
    const int encoder_num_outputs = 1;

    std::vector<int64_t> input_ids = tokenized_input;
    size_t encoder_input_tensor_size = input_ids.size();
    std::vector<int64_t> attention_mask(encoder_input_tensor_size, 1);
    std::vector<int64_t> encoder_input_dim = {
        BATCH_SIZE, 
        static_cast<int64_t>(encoder_input_tensor_size)
    };

    std::vector<Ort::Value> encoder_input_tensors;
    encoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
        memory_info, 
        input_ids.data(), 
        encoder_input_tensor_size, 
        encoder_input_dim.data(), 
        encoder_input_dim.size()
    ));
    encoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
        memory_info, 
        attention_mask.data(), 
        encoder_input_tensor_size, 
        encoder_input_dim.data(), 
        encoder_input_dim.size()
    ));

    std::vector<Ort::Value> encoder_output_tensors = encoder_session.Run(
        Ort::RunOptions{nullptr}, 
        encoder_input_names.data(), 
        encoder_input_tensors.data(), 
        encoder_num_inputs, 
        encoder_output_names.data(), 
        encoder_num_outputs
    );
    assert (encoder_output_tensors.size() == encoder_num_outputs);
    assert (encoder_output_tensors.front().IsTensor());

    Ort::Value & last_hidden_state = encoder_output_tensors.front();


    // Run decoder
    const std::vector<const char *> decoder_raw_input_names = {
        "encoder_attention_mask", 
        "input_ids", 
        "encoder_hidden_states"
    };
    const std::vector<const char *> decoder_raw_output_names = {
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
    const std::vector<const char *> decoder_with_past_input_names = {
        "encoder_attention_mask", 
        "input_ids", 
        "encoder_hidden_states",
        "past_key_values.0.decoder.key", 
        "past_key_values.0.decoder.value", 
        "past_key_values.0.encoder.key", 
        "past_key_values.0.encoder.value",
        "past_key_values.1.decoder.key", 
        "past_key_values.1.decoder.value", 
        "past_key_values.1.encoder.key", 
        "past_key_values.1.encoder.value",
        "past_key_values.2.decoder.key", 
        "past_key_values.2.decoder.value", 
        "past_key_values.2.encoder.key", 
        "past_key_values.2.encoder.value",
        "past_key_values.3.decoder.key", 
        "past_key_values.3.decoder.value", 
        "past_key_values.3.encoder.key", 
        "past_key_values.3.encoder.value",
    };
    const std::vector<const char *> decoder_with_past_output_names = {
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

    const int decoder_raw_num_inputs = 3;
    const int decoder_raw_num_outputs = 17;
    const int decoder_with_past_num_inputs = 19;
    const int decoder_with_past_num_outputs = 9;

    input_ids.clear();
    input_ids.push_back(0);
    size_t decoder_input_tensor_size = input_ids.size();
    std::vector<int64_t> decoder_input_dim = {
        BATCH_SIZE, 
        static_cast<int64_t>(decoder_input_tensor_size)
    };

    std::vector<Ort::Value> decoder_input_tensors;
    decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
        memory_info, 
        attention_mask.data(), 
        encoder_input_tensor_size, 
        encoder_input_dim.data(), 
        encoder_input_dim.size()
    ));
    decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
        memory_info, 
        input_ids.data(), 
        decoder_input_tensor_size, 
        decoder_input_dim.data(), 
        decoder_input_dim.size()
    ));
    tensor_float_append(decoder_input_tensors, last_hidden_state);

    std::vector<Ort::Value> decoder_raw_output_tensors;
    std::vector<Ort::Value> decoder_with_past_output_tensors;
    float * curr_logits;
    std::vector<int64_t> model_outputs;

    for (int timestep = 0; timestep < MAX_TIMESTEPS; timestep++) {
        if (timestep == 0) {
            decoder_raw_output_tensors = decoder_raw_session.Run(
                Ort::RunOptions{nullptr}, 
                decoder_raw_input_names.data(), 
                decoder_input_tensors.data(), 
                decoder_raw_num_inputs, 
                decoder_raw_output_names.data(), 
                decoder_raw_num_outputs
            );

            assert (decoder_raw_output_tensors.size() == decoder_raw_num_outputs);
            bool allTensorsValid = std::all_of(
                decoder_raw_output_tensors.begin(), 
                decoder_raw_output_tensors.end(),
                [](const Ort::Value & tensor) {
                    return tensor.IsTensor();
                });
            assert(allTensorsValid);

            curr_logits = decoder_raw_output_tensors.at(0).GetTensorMutableData<float>();
            int64_t curr_token = sample(curr_logits);
            model_outputs.push_back(curr_token);
            
            if (curr_token == 1) break;
            input_ids.clear();
            input_ids.push_back(curr_token);

            decoder_input_tensors.clear();
            decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
                memory_info, 
                attention_mask.data(), 
                encoder_input_tensor_size, 
                encoder_input_dim.data(), 
                encoder_input_dim.size()
            ));
            decoder_input_tensors.push_back(Ort::Value::CreateTensor<int64_t>(
                memory_info, 
                input_ids.data(), 
                decoder_input_tensor_size, 
                decoder_input_dim.data(), 
                decoder_input_dim.size()
            ));
            tensor_float_append(decoder_input_tensors, last_hidden_state);

            for (int i = 1; i < decoder_raw_output_tensors.size(); i++) {
                tensor_float_append(decoder_input_tensors, decoder_raw_output_tensors.at(i));
            }
        } else {
            decoder_with_past_output_tensors = decoder_with_past_session.Run(
                Ort::RunOptions{nullptr}, 
                decoder_with_past_input_names.data(), 
                decoder_input_tensors.data(), 
                decoder_with_past_num_inputs, 
                decoder_with_past_output_names.data(), 
                decoder_with_past_num_outputs
            );

            assert (decoder_with_past_output_tensors.size() == decoder_with_past_num_outputs);
            bool allTensorsValid = std::all_of(
                decoder_with_past_output_tensors.begin(), 
                decoder_with_past_output_tensors.end(),
                [](const Ort::Value & tensor) {
                    return tensor.IsTensor();
                });
            assert(allTensorsValid);
            
            curr_logits = decoder_with_past_output_tensors.at(0).GetTensorMutableData<float>();
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
                        memory_info, 
                        input_ids.data(), 
                        decoder_input_tensor_size, 
                        decoder_input_dim.data(), 
                        decoder_input_dim.size()
                    ));
                } else if (i == 2 || i == 5 || i == 6 || i == 9 || i == 10 || i == 13 || i == 14 || i == 17 || i == 18) {
                    tensor_float_append(temporary_tensors, decoder_input_tensors.at(i));
                } else {
                    assert(i == 3 || i == 4 || i == 7 || i == 8 || i == 11 || i == 12 || i == 15 || i == 16);
                    tensor_float_append(temporary_tensors, decoder_with_past_output_tensors.at(i/2));
                }
            }

            assert(temporary_tensors.size() == decoder_input_tensors.size());
            for (int i = 0; i < temporary_tensors.size(); i++) {
                assert(temporary_tensors.at(i).GetTensorTypeAndShapeInfo().GetElementType() == 
                       decoder_input_tensors.at(i).GetTensorTypeAndShapeInfo().GetElementType());
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


    // Detokenize output and return as a Lean string
    const wchar_t * tactic_suggestion = detokenize(model_outputs);

    int utf8_length = wcstombs(NULL, tactic_suggestion, 0);
    char * utf8_string = (char *)malloc(utf8_length + 1);
    wcstombs(utf8_string, tactic_suggestion, utf8_length + 1);
    utf8_string[utf8_length] = '\0';

    return lean_mk_string(utf8_string);
}
