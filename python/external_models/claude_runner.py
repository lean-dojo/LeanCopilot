from typing import List, Tuple
import os

try:
    from anthropic import Anthropic
except ImportError as e:
    pass
from .external_parser import *


class ClaudeRunner(Generator, Transformer):
    client = Anthropic(api_key=os.getenv("ANTHROPIC_KEY"))

    def __init__(self, **args):
        self.client_kwargs: dict[str | str] = {
            "model": args["model"],
            "temperature": args["temperature"],
            "max_tokens": args["max_tokens"],
            "top_p": args["top_p"],
        }
        self.name = self.client_kwargs["model"]

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = pre_process_input(self.name, input + target_prefix)

        response = self.client.completions.create(
            prompt=prompt,
            **self.client_kwargs,
        )
        content = response.completion

        results = [
            (post_process_output(self.name, content), 1.0)
        ]  # Currently Claude only supports one output.
        return choices_dedup(results)


if __name__ == "__main__":
    generation_kwargs = {
        "model": "claude-3-opus",
        "temperature": 0.9,
        "max_tokens": 1024,
        "top_p": 0.9,
    }

    model = ClaudeRunner(**generation_kwargs)
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
