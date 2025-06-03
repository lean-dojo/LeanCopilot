from typing import Optional
from pydantic import BaseModel

from models import *
from external_models import VLLMTacticGenerator

import runpod



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


async def handler(event):
    models = {
        "kimina": VLLMTacticGenerator(
            model="AI-MO/Kimina-Prover-Preview-Distill-7B",
            tensor_parallel_size=2,
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
    input = event['input']
    model = models[input.get('name')]
    target_prefix = input.get('prefix', "")
    outputs = model.generate(input.get('input'), target_prefix)
    return GeneratorResponse(
        outputs=[Generation(output=out[0], score=out[1]) for out in outputs]
    )


if __name__ == '__main__':
    runpod.serverless.start({'handler': handler })