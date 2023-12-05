from typing import Optional
from fastapi import FastAPI
from pydantic import BaseModel
from models import *

app = FastAPI()

models = {
    "EleutherAI/llemma_7b": DecoderOnlyTransformer(
        "EleutherAI/llemma_7b", num_return_sequences=2, max_length=64
    ),
    "t5-small": EncoderDecoderTransformer(
        "t5-small", num_return_sequences=3, max_length=1024
    ),
    "kaiyuy/leandojo-lean4-tacgen-byt5-small": EncoderDecoderTransformer(
        "kaiyuy/leandojo-lean4-tacgen-byt5-small",
        num_return_sequences=4,
        max_length=1024,
    ),
    "kaiyuy/leandojo-lean4-retriever-byt5-small": EncoderOnlyTransformer(
        "kaiyuy/leandojo-lean4-tacgen-byt5-small"
    ),
}


class InferenceRequest(BaseModel):
    name: str
    input: str
    target_prefix: Optional[str]


@app.get("/")
async def read_root():
    return {"Hello": "World"}


@app.post("/generate")
async def generate(req: InferenceRequest):
    model = models[req.name]
    outputs = model.generate(req.input, req.target_prefix)
    return {"outputs": outputs}


@app.post("/encode")
async def encode(req: InferenceRequest):
    model = models[req.name]
    feature = model.encode(req.input)
    return {"outputs": feature.tolist()}
