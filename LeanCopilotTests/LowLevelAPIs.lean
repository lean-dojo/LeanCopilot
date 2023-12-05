import LeanCopilot

open LeanCopilot

/-
```python
from transformers import AutoTokenizer, AutoModelForSeq2SeqLM

tokenizer = AutoTokenizer.from_pretrained("kaiyuy/leandojo-lean4-tacgen-byt5-small")
model = AutoModelForSeq2SeqLM.from_pretrained("kaiyuy/leandojo-lean4-tacgen-byt5-small")

state = "n : ℕ\n⊢ gcd n n = n"
tokenized_state = tokenizer(state, return_tensors="pt")

# Generate a single tactic.
tactic_ids = model.generate(tokenized_state.input_ids, max_length=1024)
tactic = tokenizer.decode(tactic_ids[0], skip_special_tokens=True)
print(tactic, end="\n\n")

# Generate multiple tactics via beam search.
tactic_candidates_ids = model.generate(
    tokenized_state.input_ids,
    max_length=1024,
    num_beams=4,
    length_penalty=0.0,
    do_sample=False,
    num_return_sequences=4,
    early_stopping=False,
)
tactic_candidates = tokenizer.batch_decode(
    tactic_candidates_ids, skip_special_tokens=True
)
for tac in tactic_candidates:
    print(tac)
```
-/


def model₁ : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 1
  }
}

#eval generate model₁ "n : ℕ\n⊢ gcd n n = n"


def model₁' : NativeGenerator := {model₁ with params := {numReturnSequences := 4}}

#eval generate model₁' "n : ℕ\n⊢ gcd n n = n"


def model₁'' : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 1
  }
}

#eval generate model₁'' "n : ℕ\n⊢ gcd n n = n"


/-
```python
from transformers import AutoTokenizer, T5EncoderModel

tokenizer = AutoTokenizer.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")
model = T5EncoderModel.from_pretrained("kaiyuy/leandojo-lean4-retriever-byt5-small")

state = "n : ℕ\n⊢ gcd n n = n"
tokenized_state = tokenizer(state, return_tensors="pt")
hidden_state = model(tokenized_state.input_ids).last_hidden_state
feature = hidden_state.mean(dim=1).squeeze()
print(feature)
```
-/


def model₂ : NativeEncoder := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-retriever-byt5-small"
  tokenizer := ByT5.tokenizer
}

#eval encode model₂ "n : ℕ\n⊢ gcd n n = n"


/-
```python
from transformers import AutoTokenizer, AutoModelForCausalLM

tokenizer = AutoTokenizer.from_pretrained("EleutherAI/llemma_7b")
model = AutoModelForCausalLM.from_pretrained("EleutherAI/llemma_7b")

state = "n : ℕ\n⊢ gcd n n = n"
tokenized_state = tokenizer(state, return_tensors="pt")

# Generate a single tactic.
tactic_ids = model.generate(tokenized_state.input_ids, max_length=32)
tactic = tokenizer.decode(tactic_ids[0], skip_special_tokens=True)
print(tactic, end="\n\n")

# Generate multiple tactics via beam search.
tactic_candidates_ids = model.generate(
    tokenized_state.input_ids,
    max_length=32,
    num_beams=2,
    length_penalty=0.0,
    do_sample=False,
    num_return_sequences=2,
    early_stopping=False,
)
tactic_candidates = tokenizer.batch_decode(
    tactic_candidates_ids, skip_special_tokens=True
)
for tac in tactic_candidates:
    print(tac)
```
-/

def model₃ : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/EleutherAI/llemma_7b"
  tokenizer := sorry
  params := {
    numReturnSequences := 1
  }
}

#eval generate model₃ "n : ℕ\n⊢ gcd n n = n"


def model₃' : NativeGenerator := {model₃ with params := {numReturnSequences := 2}}

#eval generate model₃' "n : ℕ\n⊢ gcd n n = n"


/-
TODO: A dummy model in lean.
-/
