import os
import torch
import argparse
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


def get_cuda_if_available():
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


def pre_process_input(model_name, input):
    if model_name == "internlm/internlm2-math-plus-1_8b":
        prompt="My LEAN 4 state is:\n```lean\n" + input + \
        "```\nPlease predict a possible tactic to help me prove the theorem."
        prompt = f"""<|im_start|>user\n{prompt}<|im_end|>\n<|im_start|>assistant\n"""
    elif model_name == "gpt-3.5-turbo" or model_name == "gpt-4-turbo-preview":
        prompt = 'Here is a theorom you need to prove in Lean:\n' + \
            input+'\nNow you should suggest one line tactic in lean code:'
    elif 'gemini' in model_name  or "claude" in model_name:
        prompt = 'Here is a theorom you need to prove in Lean:\n' + \
            input+'\nNow you should suggest one line tactic in lean code:'
    else:
        raise NotImplementedError(f"External model '{model_name}' not supported")
    return prompt


def post_process_output(model_name, output):
    if model_name == "internlm/internlm2-math-plus-1_8b":
        result = output.split(
            'assistant')[-1].split('lean')[-1].split('```')[0].split('\n')[1]
    elif model_name == "gpt-3.5-turbo" or model_name == "gpt-4-turbo-preview":
        result = output.split('lean')[-1].split('```')[0].split('\n')[1]
    elif 'gemini' in model_name  or "claude" in model_name: 
        result = output.split('lean')[-1].split('```')[0].split('\n')[1]
    else:
        raise NotImplementedError(f"External model '{model_name}' not supported")
    return result


def choices_dedup(output_list: List[tuple[str, float]]) -> List[tuple[str, float]]:
    unique_data = {}
    for item in output_list:
        if item[0] not in unique_data or item[1] > unique_data[item[0]]:
            unique_data[item[0]] = item[1]
    sorted_data = sorted(unique_data.items(), key=lambda x: x[1], reverse=True)
    return sorted_data


class Generator(ABC):
    @abstractmethod
    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        pass


class Encoder(ABC):
    @abstractmethod
    def encode(self, input: str) -> np.ndarray:
        pass


class Transformer:
    def cuda(self) -> None:
        self.model.cuda()

    def cpu(self) -> None:
        self.model.cpu()

    @property
    def device(self) -> torch.device:
        return self.model.device


