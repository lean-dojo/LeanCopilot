import torch
from typing import Union, List
from transformers import AutoTokenizer, T5EncoderModel
import numpy as np
import json


tokenizer = AutoTokenizer.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")
model = T5EncoderModel.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")


premise_embeddings_np = np.load("embeddings.npy")
premise_embeddings = torch.from_numpy(premise_embeddings_np).float()

state = "n: Nat\n⊢ Nat.gcd n n = n"


@torch.no_grad()
def encode(s: str) -> torch.Tensor:
    """Encode texts into feature vectors."""
    s = [s]
    should_squeeze = True
    tokenized_s = tokenizer(s, return_tensors="pt", padding=True)
    hidden_state = model(tokenized_s.input_ids).last_hidden_state
    lens = tokenized_s.attention_mask.sum(dim=1)
    features = (hidden_state * tokenized_s.attention_mask.unsqueeze(2)).sum(dim=1) / lens.unsqueeze(1)
    if should_squeeze:
      features = features.squeeze()
    return features


state_embedding = encode(state)
probs = torch.matmul(premise_embeddings, state_embedding)
top10 = torch.topk(probs, k=10).indices.tolist()
print(top10)


with open("dictionary.json", "r") as f:
    dictionary = json.load(f)

for i in top10:
    print(dictionary[str(i)])
