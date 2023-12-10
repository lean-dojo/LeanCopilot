import LeanCopilot

set_option autoImplicit false

open LeanCopilot

#eval cudaAvailable

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

#eval generate model₁'' "Hello, world!"


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


structure DummyGenerator where
  outputs : Array (String × Float)


instance : TextToText DummyGenerator where
  generate model _ _ := return model.outputs


def model₄ : DummyGenerator := ⟨#[⟨"Hello, world!", 0.5⟩, ("Hi!", 0.3)]⟩

#eval generate model₄ "n : ℕ\n⊢ gcd n n = n"


structure DummyEncoder where
  output : FloatArray


instance : TextToVec DummyEncoder where
  encode model _ := return model.output


def model₅ : DummyEncoder := ⟨FloatArray.mk #[1, 2, 3]⟩

#eval encode model₅ "Hi!"


def model₇ : ExternalGenerator := {
  name := "wellecks/llmstep-mathlib4-pythia2.8b"
  host := "localhost"
  port := 23337
}

-- Go to ./python and run `uvicorn server:app --port 23337`
#eval generate model₇ "n : ℕ\n⊢ gcd n n = n"


def model₈ : ExternalEncoder := {
  name := "kaiyuy/leandojo-lean4-retriever-byt5-small"
  host := "localhost"
  port := 23337
}

-- Go to ./python and run `uvicorn server:app --port 23337`
#eval encode model₈ "n : ℕ\n⊢ gcd n n = n"
