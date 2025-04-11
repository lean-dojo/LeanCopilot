import torch
from loguru import logger
from typing import List, Tuple
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
)
from .external_parser import *


class HFTacticGenerator(Generator, Transformer):
    def __init__(self, **args) -> None:
        self.name = args["model"]
        self.tokenizer = AutoTokenizer.from_pretrained(
            self.name, trust_remote_code=True
        )
        device = args["device"]
        if device == "auto":
            device = get_cuda_if_available()
        else:
            device = torch.device(device)
        logger.info(f"Loading {self.name} on {device}")
        self.model = AutoModelForCausalLM.from_pretrained(
            self.name, trust_remote_code=True
        ).to(device)

        self.generation_args: dict[str | str] = {
            "do_sample": args["do_sample"],
            "temperature": args["temperature"],  # chat default is 0.8.
            "max_new_tokens": args["max_new_tokens"],
            "top_p": args["top_p"],  # chat default is 0.8.
            "num_return_sequences": args["num_return_sequences"],
            "output_scores": args["output_scores"],
            "output_logits": args["output_logits"],
            "return_dict_in_generate": args["return_dict_in_generate"],
        }

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = input + target_prefix
        '''prompt= 'Here is a theorom you need to prove in Lean:\n'+prompt+'\nNow you should suggest one line tactic in lean code:'
        prompt = f"""<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"""
        '''
        prompt = pre_process_input(self.name, prompt)

        self.model = self.model.eval()

        tokenized_input = self.tokenizer(prompt, return_tensors="pt")
        eos_token_id = [
            self.tokenizer.eos_token_id,
            self.tokenizer.convert_tokens_to_ids(["<|im_end|>"])[0],
        ]
        outputs = self.model.generate(
            tokenized_input.input_ids.to(self.device),
            eos_token_id=eos_token_id,
            **self.generation_args,
        )
        response = self.tokenizer.batch_decode(
            outputs["sequences"], skip_special_tokens=True
        )

        result = []
        index = 0
        for out, score in zip(response, outputs.scores):
            out = post_process_output(self.name, out)
            result.append((out, score[index].exp().sum().log().cpu().item()))
            index += 1
        result = choices_dedup(result)
        return result


if __name__ == "__main__":
    generation_kwargs = {
        "model": "internlm/internlm2-math-plus-1_8b",
        "temperature": 0.6,
        "max_new_tokens": 1024,
        "top_p": 0.9,
        "length_penalty": 0,
        "num_return_sequences": 64,
        "do_sample": True,
        "output_scores": True,
        "output_logits": False,
        "return_dict_in_generate": True,
        "device": "auto",
    }
    model = HFTacticGenerator(**generation_kwargs)
    model.cuda()
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
