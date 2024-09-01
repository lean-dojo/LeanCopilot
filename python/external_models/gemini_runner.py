from typing import List, Tuple
import os

try:
    import google.generativeai as genai
    from google.generativeai import GenerationConfig
except ImportError as e:
    pass
from .external_parser import *


class GeminiRunner(Generator, Transformer):
    client = genai.configure(api_key=os.getenv("GOOGLE_API_KEY"))
    safety_settings = [
        {
            "category": "HARM_CATEGORY_HARASSMENT",
            "threshold": "BLOCK_NONE",
        },
        {
            "category": "HARM_CATEGORY_HATE_SPEECH",
            "threshold": "BLOCK_NONE",
        },
        {
            "category": "HARM_CATEGORY_SEXUALLY_EXPLICIT",
            "threshold": "BLOCK_NONE",
        },
        {
            "category": "HARM_CATEGORY_DANGEROUS_CONTENT",
            "threshold": "BLOCK_NONE",
        },
    ]

    def __init__(self, **args):
        self.client_kwargs: dict[str | str] = {
            "model": args["model"],
            "temperature": args["temperature"],
            "max_tokens": args["max_tokens"],
            "top_p": args["top_p"],
        }
        self.name = self.client_kwargs["model"]
        self.client = genai.GenerativeModel(args["model"])
        self.generation_config = GenerationConfig(
            candidate_count=1,
            max_output_tokens=args["max_tokens"],
            temperature=args["temperature"],
            top_p=args["top_p"],
        )

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = pre_process_input(self.name, input + target_prefix)

        response = self.client.generate_content(
            prompt,
            generation_config=self.generation_config,
            safety_settings=GeminiRunner.safety_settings,
        )

        results = [
            (post_process_output(self.name, response.text), 1.0)
        ]  # Currently Gemini only supports one output.
        return choices_dedup(results)


if __name__ == "__main__":
    generation_kwargs = {
        "model": "gemini-1.0-pro",
        "temperature": 0.9,
        "max_tokens": 1024,
        "top_p": 0.9,
    }

    model = GeminiRunner(**generation_kwargs)
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
