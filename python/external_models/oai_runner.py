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
import openai
from openai import OpenAI
from external_parser import *


class OpenAIRunner(Generator, Transformer):
    client = OpenAI(
        api_key=os.getenv("OPENAI_API_KEY"),
    )

    def __init__(self, **args):
        self.client_kwargs: dict[str | str] = {
            "model": args['model'],
            "temperature": args['temperature'],
            "max_tokens": args['max_tokens'],
            "top_p": args['top_p'],
            "frequency_penalty": 0,
            "presence_penalty": 0,
            "n": args['num_return_sequences'],
            "timeout": args['openai_timeout'],
            # "stop": args.stop, --> stop is only used for base models currently
        }
        self.name = self.client_kwargs["model"]

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = pre_process_input(self.name, input + target_prefix)
        prompt = [
            {"role": "user", "content": f"{prompt}"},

        ]
        try:
            response = OpenAIRunner.client.chat.completions.create(
                messages=prompt,
                logprobs=True,
                **self.client_kwargs,
            )
        except (
            openai.APIError,
            openai.RateLimitError,
            openai.InternalServerError,
            openai.OpenAIError,
            openai.APIStatusError,
            openai.APITimeoutError,
            openai.InternalServerError,
            openai.APIConnectionError,
        ) as e:
            print("Exception: ", repr(e))
            print("Sleeping for 30 seconds...")
            print("Consider reducing the number of parallel processes.")
            # sleep(30)
            return OpenAIRunner.generate(self, input, target_prefix)
        except Exception as e:
            print(f"Failed to run the model for {prompt}!")
            print("Exception: ", repr(e))
            raise e

        results = [(post_process_output(self.name, c.message.content), np.exp(-np.mean([
            token.logprob for token in c.logprobs.content])))for c in response.choices]
        return choices_dedup(results)


if __name__ == "__main__":

    generation_kwargs = {"model": "gpt-4-turbo-preview",
                         "temperature": 0.9,
                         "max_tokens": 1024,
                         "top_p": 0.9,
                         "frequency_penalty": 0,
                         "presence_penalty": 0,
                         "num_return_sequences": 16,
                         "openai_timeout": 45,
                         # "stop": args.stop, --> stop is only used for base models currently
                         }

    model = OpenAIRunner(**generation_kwargs)
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
