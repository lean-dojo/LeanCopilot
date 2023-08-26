from transformers import AutoTokenizer
from optimum.onnxruntime import ORTModelForSeq2SeqLM


model_name = "kaiyuy/leandojo-lean4-tacgen-byt5-small"
inference_name = "onnx-leandojo-lean4-tacgen-byt5-small/inference"
tokenizer_name = "onnx-leandojo-lean4-tacgen-byt5-small/tokenizer"

tokenizer = AutoTokenizer.from_pretrained(model_name)
model = ORTModelForSeq2SeqLM.from_pretrained(
    model_name, export=True
)

model.save_pretrained(inference_name)
tokenizer.save_pretrained(tokenizer_name)

print("Success!")