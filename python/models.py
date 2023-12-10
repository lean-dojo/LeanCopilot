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


def get_cuda_if_available():
    return torch.device("cuda" if torch.cuda.is_available() else "cpu")


class DecoderOnlyTransformer(Generator, Transformer):
    def __init__(
        self,
        name: str,
        num_return_sequences: int,
        max_length: int,
        length_penalty: float = 0.0,
        device: str = "cpu",
    ) -> None:
        self.tokenzier = AutoTokenizer.from_pretrained(name)
        if device == "auto":
            device = get_cuda_if_available()
        else:
            device = torch.device(device)
        logger.info(f"Loading {name} on {device}")
        self.model = AutoModelForCausalLM.from_pretrained(name).to(device)
        self.max_length = max_length
        self.num_return_sequences = num_return_sequences
        self.length_penalty = length_penalty

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        tokenized_input = self.tokenzier(input + target_prefix, return_tensors="pt")
        output = self.model.generate(
            tokenized_input.input_ids.to(self.device),
            max_length=self.max_length,
            num_beams=self.num_return_sequences,
            length_penalty=self.length_penalty,
            do_sample=False,
            num_return_sequences=self.num_return_sequences,
            early_stopping=False,
            return_dict_in_generate=True,
            output_scores=True,
        )
        raw_outputs = self.tokenzier.batch_decode(
            output.sequences, skip_special_tokens=True
        )
        outputs = []

        for out, score in zip(raw_outputs, output.sequences_scores.exp()):
            assert out.startswith(input + target_prefix)
            outputs.append((out[len(input) :], score.item()))

        return outputs


class PythiaTacticGenerator(DecoderOnlyTransformer):
    def __init__(
        self,
        num_return_sequences: int,
        max_length: int,
        length_penalty: float = 0.0,
        device: str = "cpu",
    ) -> None:
        super().__init__(
            "wellecks/llmstep-mathlib4-pythia2.8b",
            num_return_sequences,
            max_length,
            length_penalty,
            device,
        )

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        return super().generate(f"[GOAL]{input}[PROOFSTEP]{target_prefix}")


class EncoderDecoderTransformer(Generator, Transformer):
    def __init__(
        self,
        name: str,
        num_return_sequences: int,
        max_length: int,
        length_penalty: float = 0.0,
        device: str = "cpu",
    ) -> None:
        self.tokenzier = AutoTokenizer.from_pretrained(name)
        if device == "auto":
            device = get_cuda_if_available()
        else:
            device = torch.device(device)
        logger.info(f"Loading {name} on {device}")
        self.model = AutoModelForSeq2SeqLM.from_pretrained(name)
        self.max_length = max_length
        self.num_return_sequences = num_return_sequences
        self.length_penalty = length_penalty

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        assert (
            target_prefix == ""
        ), "target_prefix is not supported by encoder-decoder Transformer"
        tokenized_input = self.tokenzier(input, return_tensors="pt")
        output = self.model.generate(
            tokenized_input.input_ids.to(self.device),
            max_length=self.max_length,
            num_beams=self.num_return_sequences,
            length_penalty=self.length_penalty,
            do_sample=False,
            num_return_sequences=self.num_return_sequences,
            early_stopping=False,
            return_dict_in_generate=True,
            output_scores=True,
        )
        raw_outputs = self.tokenzier.batch_decode(
            output.sequences, skip_special_tokens=True
        )
        return list(zip(raw_outputs, output.sequences_scores.exp().tolist()))


class EncoderOnlyTransformer(Encoder, Transformer):
    def __init__(self, name: str, device: str = "cpu") -> None:
        self.tokenzier = AutoTokenizer.from_pretrained(name)
        if device == "auto":
            device = get_cuda_if_available()
        else:
            device = torch.device(device)
        logger.info(f"Loading {name} on {device}")
        self.model = AutoModelForTextEncoding.from_pretrained(name)

    @torch.no_grad()
    def encode(self, input: str) -> np.ndarray:
        tokenized_input = self.tokenzier(input, return_tensors="pt")
        hidden_state = self.model(
            tokenized_input.input_ids.to(self.device)
        ).last_hidden_state
        feature = hidden_state.mean(dim=1).squeeze()
        return feature.cpu().numpy()


if __name__ == "__main__":
    model = PythiaTacticGenerator(num_return_sequences=32, max_length=1024)
    model.cuda()
    print(model.generate("n : ℕ\n⊢ gcd n n = n"))
