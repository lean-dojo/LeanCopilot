import torch
import numpy as np
from loguru import logger
from typing import List, Tuple
from abc import ABC, abstractmethod
from transformers import (
    AutoModelForCausalLM,
    AutoModelForSeq2SeqLM,
    AutoTokenizer,
    AutoModelForTextEncoding,
)
import os
import numpy as np
try:
    from anthropic import Anthropic
except ImportError as e:
    pass
from .external_parser import *


class ClaudeRunner(Generator, Transformer):
    client = Anthropic(api_key=os.getenv("ANTHROPIC_KEY"))

    def __init__(self, **args):
        self.client_kwargs: dict[str | str] = {
            "model": args['model'],
            "temperature": args['temperature'],
            "max_tokens": args['max_tokens'],
            "top_p": args['top_p'],
            }
        self.name = self.client_kwargs["model"]

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = pre_process_input(self.name, input + target_prefix)
        
        try:
            response = self.client.completions.create(
                    prompt=prompt,
                    **self.client_kwargs,
                )                                
            content = response.completion
            
        except Exception as e:
            raise e

        results = [(post_process_output(self.name, content),1.0)]# current claude only supports one output
        return choices_dedup(results)


if __name__ == "__main__":

    generation_kwargs = {"model": "claude-3-opus",
                         "temperature": 0.9,
                         "max_tokens": 1024,
                         "top_p": 0.9,
                         }

    model = ClaudeRunner(**generation_kwargs)
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
