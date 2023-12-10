from typing import Optional
from fastapi import FastAPI
from pydantic import BaseModel

from models import *

app = FastAPI()

models = {
    "EleutherAI/llemma_7b": DecoderOnlyTransformer(
        "EleutherAI/llemma_7b", num_return_sequences=2, max_length=64, device="auto"
    ),
    "wellecks/llmstep-mathlib4-pythia2.8b": PythiaTacticGenerator(
        num_return_sequences=32, max_length=1024, device="auto"
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


class GeneratorRequest(BaseModel):
    name: str
    input: str
    prefix: Optional[str]


class Generation(BaseModel):
    output: str
    score: float


class GeneratorResponse(BaseModel):
    outputs: List[Generation]


class EncoderRequest(BaseModel):
    name: str
    input: str


class EncoderResponse(BaseModel):
    outputs: List[float]


@app.post("/generate")
async def generate(req: GeneratorRequest) -> GeneratorResponse:
    model = models[req.name]
    target_prefix = req.prefix if req.prefix is not None else ""
    outputs = model.generate(req.input, target_prefix)
    return GeneratorResponse(outputs=[Generation(output=out[0], score=out[1]) for out in outputs])


@app.post("/encode")
async def encode(req: EncoderRequest) -> EncoderResponse:
    model = models[req.name]
    feature = model.encode(req.input)
    return EncoderResponse(outputs=feature.tolist())
