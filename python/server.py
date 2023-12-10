import torch
from typing import Optional
from fastapi import FastAPI
from pydantic import BaseModel

from models import *

app = FastAPI()

models = {
    "EleutherAI/llemma_7b": DecoderOnlyTransformer(
        "EleutherAI/llemma_7b", num_return_sequences=2, max_length=64
    ),
    "wellecks/llmstep-mathlib4-pythia2.8b": DecoderOnlyTransformer(
        "wellecks/llmstep-mathlib4-pythia2.8b", num_return_sequences=32, max_length=64
    ),
    "t5-small": EncoderDecoderTransformer(
        "t5-small", num_return_sequences=3, max_length=1024
    ),
    "kaiyuy/leandojo-lean4-tacgen-byt5-small": EncoderDecoderTransformer(
        "kaiyuy/leandojo-lean4-tacgen-byt5-small",
        num_return_sequences=32,
        max_length=1024,
    ),
    "kaiyuy/leandojo-lean4-retriever-byt5-small": EncoderOnlyTransformer(
        "kaiyuy/leandojo-lean4-tacgen-byt5-small"
    ),
}

if torch.cuda.is_available():
    models = {k: v.cuda() for k, v in models.items(0)}


class InferenceRequest(BaseModel):
    name: str
    input: str
    prefix: Optional[str]


@app.get("/")
async def read_root():
    return {"Hello": "World"}


@app.post("/generate")
async def generate(req: InferenceRequest):
    model = models[req.name]
    target_prefix = req.prefix if req.prefix is not None else ""
    outputs = model.generate(req.input, target_prefix)
    return {"outputs": outputs}


@app.post("/encode")
async def encode(req: InferenceRequest):
    assert req.prefix is None, "target_prefix is not supported by encoder"
    model = models[req.name]
    feature = model.encode(req.input)
    return {"outputs": feature.tolist()}
