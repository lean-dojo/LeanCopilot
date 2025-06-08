from typing import Optional
from fastapi import FastAPI
from pydantic import BaseModel

from models import *
from external_models import VLLMTacticGenerator

app = FastAPI()

models = {
    "kimina": VLLMTacticGenerator(
        model="AI-MO/Kimina-Prover-Preview-Distill-7B",
        tensor_parallel_size=1,
        temperature=0.6,
        max_tokens=1024,
        top_p=0.9,
        length_penalty=0,
        n=32,
        do_sample=True,
        output_scores=True,
        output_logits=False,
        return_dict_in_generate=True,
        device="auto",
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
    return GeneratorResponse(
        outputs=[Generation(output=out[0], score=out[1]) for out in outputs]
    )


@app.post("/encode")
async def encode(req: EncoderRequest) -> EncoderResponse:
    model = models[req.name]
    feature = model.encode(req.input)
    return EncoderResponse(outputs=feature.tolist())
