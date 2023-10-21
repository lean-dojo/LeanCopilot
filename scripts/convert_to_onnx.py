from optimum.onnxruntime import ORTModelForSeq2SeqLM

model_name = "leandojo-lean4-tacgen-byt5-small"
model = ORTModelForSeq2SeqLM.from_pretrained(f"kaiyuy/{model_name}", export=True)
model.save_pretrained(f"onnx-{model_name}")
