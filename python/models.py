import pdb
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


class DecoderOnlyTransformer(Generator, Transformer):
    def __init__(
        self,
        name: str,
        num_return_sequences: int,
        max_length: int,
        length_penalty: float = 0.0,
    ) -> None:
        logger.info(f"Loading {name}")
        self.tokenzier = AutoTokenizer.from_pretrained(name)
        self.model = AutoModelForCausalLM.from_pretrained(name)
        self.max_length = max_length
        self.num_return_sequences = num_return_sequences
        self.length_penalty = length_penalty

    def generate(self, input: str, target_prefix: str = "") -> List[Tuple[str, float]]:
        tokenized_input = self.tokenzier(input + target_prefix, return_tensors="pt")
        output = self.model.generat.e(
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


class EncoderDecoderTransformer(Generator, Transformer):
    def __init__(
        self,
        name: str,
        num_return_sequences: int,
        max_length: int,
        length_penalty: float = 0.0,
    ) -> None:
        logger.info(f"Loading {name}")
        self.tokenzier = AutoTokenizer.from_pretrained(name)
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
    def __init__(self, name: str) -> None:
        logger.info(f"Loading {name}")
        self.tokenzier = AutoTokenizer.from_pretrained(name)
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
    # model = DecoderOnlyTransformer(
    #    "EleutherAI/llemma_7b", num_return_sequences=2, max_length=64
    # )
    model = EncoderOnlyTransformer(
        "kaiyuy/leandojo-lean4-retriever-byt5-small",
    )
    # model.cuda()
    print(model.encode("n : ℕ\n⊢ gcd n n = n"))
