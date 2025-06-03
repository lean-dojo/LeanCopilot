import LeanCopilot

open LeanCopilot

#eval cudaAvailable

/--
ReProver's tactic generator in CT2 format.
-/
def reprover : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 1
  }
}

-- #eval generate reprover "n : ℕ\n⊢ gcd n n = n"

def reprover' : NativeGenerator := {reprover with
  device := .cpu
  computeType := .float32
  params := {numReturnSequences := 4}
}

-- #eval generate reprover' "n : ℕ\n⊢ gcd n n = n"


/--
The original ByT5 checkpoint in CT2 format.
-/
def byt5 : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 1
  }
}

-- #eval generate byt5 "Hello, world!"


/--
ReProver's retriever encoder in CT2 format.
-/
def reproverEncoder : NativeEncoder := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-retriever-byt5-small"
  tokenizer := ByT5.tokenizer
}

-- #eval encode reproverEncoder "n : ℕ\n⊢ gcd n n = n"


/--
Arbitrary generator you can define.
-/
def dummyGenerator : GenericGenerator where
  generate _ _ := return #[⟨"Hello, world!", 0.5⟩, ("Hi!", 0.3)]

-- #eval generate dummyGenerator "n : ℕ\n⊢ gcd n n = n"


/--
Arbitrary encoder you can define.
-/
def dummyEncoder : GenericEncoder where
  encode _  := return FloatArray.mk #[1, 2, 3]

-- #eval encode dummyEncoder "Hi!"

/-
External Models

1. Make sure the model is up and running, e.g., by going to ./python and running `uvicorn server:app --port 23337`.
2. Uncomment the code below.
-/

/-
/--
https://huggingface.co/wellecks/llmstep-mathlib4-pythia2.8b
-/
def pythia : ExternalGenerator := {
  name := "wellecks/llmstep-mathlib4-pythia2.8b"
  host := "localhost"
  port := 23337
}

#eval generate pythia "n : ℕ\n⊢ gcd n n = n"


/--
ReProver's retriever encoder as an external model.
-/
def reproverExternalEncoder : ExternalEncoder := {
  name := "kaiyuy/leandojo-lean4-retriever-byt5-small"
  host := "localhost"
  port := 23337
}

-- Go to ./python and run `uvicorn server:app --port 23337`
#eval encode reproverExternalEncoder "n : ℕ\n⊢ gcd n n = n"

/--
General-purpose LLM apis: openai, claude, etc.
-/
def gpt4 : ExternalGenerator := {
  name := "gpt4"
  host := "localhost"
  port := 23337
}

#eval generate gpt4 "n : ℕ\n⊢ gcd n n = n"

/--
Math LLMs: InternLM, Deepseekmath, etc.
-/
def internLM : ExternalGenerator := {
  name := "InternLM"
  host := "localhost"
  port := 23337
}

#eval generate internLM "n : ℕ\n⊢ gcd n n = n"

-/

def kimina : ExternalGenerator := {
  name := "kimina"
  host := "localhost"
  port := 23337
}

#eval generate kimina "n : ℕ\n⊢ gcd n n = n"
