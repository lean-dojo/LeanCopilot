
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
import pdb
try:
    from vllm import LLM, SamplingParams
except ImportError as e:
    print("Cannot import vllm")
    pass

from external_parser import *


class VLLMTacticGenerator(Generator, Transformer):
    def __init__(
        self,
        **args
    ) -> None:

        self.name = args['model']
        self.llm = LLM(
            model=self.name,
            tokenizer=self.name,
            tensor_parallel_size=args["tensor_parallel_size"],
            # dtype=args.dtype,
            enforce_eager=True,
            max_model_len=4096,
            disable_custom_all_reduce=False,
            # enable_prefix_caching=args.enable_prefix_caching,
            trust_remote_code=True,
        )
        self.sampling_params = SamplingParams(
            n=args['n'],
            max_tokens=args['max_tokens'],
            temperature=args['temperature'],
            top_p=args['top_p'],
            frequency_penalty=0,
            presence_penalty=0,
        )

        self.tokenizer = AutoTokenizer.from_pretrained(
            self.name, trust_remote_code=True)
        device = args['device']
        if device == "auto":
            device = get_cuda_if_available()
        else:
            device = torch.device(device)
        logger.info(f"Loading {self.name} on {device}")
        # self.model = AutoModelForCausalLM.from_pretrained(self.name, trust_remote_code=True).to(device)

        '''self.generation_args: dict[str | str] = {
            "do_sample":args["do_sample"],
            "temperature": args['temperature'],#chat default is 0.8
            "max_new_tokens": args['max_new_tokens'],
            "top_p": args['top_p'],#chat default is 0.8
            #"length_penalty": args["length_penalty"],
            "num_return_sequences": args['num_return_sequences'],
            #"num_beams": self.num_return_sequences,
            ##Here if we use beam search for llms the output are not diverse(few tactics are provided).
            "output_scores":args["output_scores"],
            "output_logits":args["output_logits"],
            "return_dict_in_generate":args["return_dict_in_generate"],
        }'''

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        prompt = input + target_prefix
        '''prompt= 'Here is a theorom you need to prove in Lean:\n'+prompt+'\nNow you should suggest one line tactic in lean code:'
        prompt = f"""<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"""
        '''
        prompt = pre_process_input(self.name, prompt)

        # self.model = self.model.eval()

        vllm_outputs = self.llm.generate(prompt, self.sampling_params)
        # pdb.set_trace()
        # print(vllm_outputs)
        # exit()
        result = []
        for output in vllm_outputs[0].outputs:  # bsz=1 for now
            out = output.text.split('<|im_end|>')[0]
            result.append((post_process_output(self.name, out),
                          np.exp(output.cumulative_logprob)))

        result = choices_dedup(result)
        return result


if __name__ == "__main__":

    generation_kwargs = {"model": "internlm/internlm2-math-plus-1_8b",
                         "tensor_parallel_size": 2,
                         "temperature": 0.6,
                         "max_tokens": 1024,
                         "top_p": 0.9,
                         "length_penalty": 0,
                         "n": 32,
                         "do_sample": True,
                         "output_scores": True,
                         "output_logits": False,
                         "return_dict_in_generate": True,
                         "device": "auto",
                         }
    model = VLLMTacticGenerator(**generation_kwargs)
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
