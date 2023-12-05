from transformers import AutoModelForCausalLM, AutoTokenizer
import numpy as np
from abc import ABC, abstractmethod
from typing import List, Tuple


class Generator(ABC):
    @abstractmethod
    def generate(self, input: str, target_prefix : str = "") -> List[Tuple[str, float]]:
        pass


class Encoder(ABC):
    @abstractmethod
    def encode(self, input: str) -> np.ndarray:
        pass


class Transformer:
    def __init__(self, name: str) -> None:
        self.tokenzier = AutoTokenizer.from_pretrained(name)
        self.model = AutoModelForCausalLM.from_pretrained(name)

    def cuda(self) -> None:
        self.model.cuda()

    def cpu(self) -> None:
        self.model.cpu()


class DecoderOnlyTransformer(Generator, Transformer):
    def generate(self, input: str, target_prefix : str = "") -> List[Tuple[str, float]]:
        input_ids = self.tokenzier.encode(input + target_prefix, return_tensors="pt")
        raise NotImplementedError
        output = self.model.generate(input_ids, max_length=100, num_beams=5, no_repeat_ngram_size=2, early_stopping=True)
        return self.tokenzier.batch_decode(output, skip_special_tokens=True)


class EncoderDecoderTransformer(Generator):

    def generate(self, input: str, target_prefix : str = "") -> List[Tuple[str, float]]:
        assert target_prefix == "", "target_prefix is not supported by encoder-decoder Transformer"
        input_ids = self.tokenzier.encode(input + target_prefix, return_tensors="pt")
        raise NotImplementedError
        output = self.model.generate(input_ids, max_length=100, num_beams=5, no_repeat_ngram_size=2, early_stopping=True)
        return self.tokenzier.batch_decode(output, skip_special_tokens=True)
