import os
from optimum.onnxruntime import ORTModelForSeq2SeqLM

model_name = "leandojo-lean4-retriever-byt5-small"
ORTModelForSeq2SeqLM.from_pretrained(
    f"kaiyuy/{model_name}", export=True
).save_pretrained(f"onnx-{model_name}")

os.remove(f"onnx-{model_name}/decoder_model.onnx")
os.remove(f"onnx-{model_name}/decoder_with_past_model.onnx")
os.remove(f"onnx-{model_name}/generation_config.json")