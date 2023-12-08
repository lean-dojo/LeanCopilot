import json
import torch
import numpy as np
from transformers import AutoTokenizer, T5EncoderModel


tokenizer = AutoTokenizer.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")
model = T5EncoderModel.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")


premise_embeddings_np = np.load("embeddings.npy")
premise_embeddings = torch.from_numpy(premise_embeddings_np).float()

# state = "n: Nat\n⊢ Nat.gcd n n = n"
state = "a b c : Nat\n⊢ a + b + c = a + c + b"


@torch.no_grad()
def encode(s: str) -> torch.Tensor:
    """Encode texts into feature vectors."""
    s = [s]
    should_squeeze = True
    tokenized_s = tokenizer(s, return_tensors="pt", padding=True)
    hidden_state = model(tokenized_s.input_ids).last_hidden_state
    lens = tokenized_s.attention_mask.sum(dim=1)
    features = (hidden_state * tokenized_s.attention_mask.unsqueeze(2)).sum(
        dim=1
    ) / lens.unsqueeze(1)
    if should_squeeze:
        features = features.squeeze()
    return features


k = 16
state_embedding = encode(state)
probs = torch.matmul(premise_embeddings, state_embedding)
topK = torch.topk(probs, k).indices.tolist()
print(topK)


with open("dictionary.json", "r") as f:
    dictionary = json.load(f)

for i in topK:
    print(dictionary[str(i)])
