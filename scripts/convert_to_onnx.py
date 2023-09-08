from optimum.onnxruntime import ORTModelForSeq2SeqLM

ORTModelForSeq2SeqLM.from_pretrained(
    "kaiyuy/leandojo-lean4-tacgen-byt5-small", export=True
).save_pretrained("onnx-leandojo-lean4-tacgen-byt5-small")
