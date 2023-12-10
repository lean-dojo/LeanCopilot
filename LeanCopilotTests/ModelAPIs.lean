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

#eval generate reprover "n : ℕ\n⊢ gcd n n = n"

def reprover' : NativeGenerator := {reprover with
  device := .cpu
  computeType := .float32
  params := {numReturnSequences := 4}
}

#eval generate reprover' "n : ℕ\n⊢ gcd n n = n"


/--
The original ByT5 checkpoint.
-/
def byt5 : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 1
  }
}

#eval generate byt5 "Hello, world!"


/--
ReProver's retriever encoder in CT2 format.
-/
def reproverEncoder : NativeEncoder := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-retriever-byt5-small"
  tokenizer := ByT5.tokenizer
}

#eval encode reproverEncoder "n : ℕ\n⊢ gcd n n = n"


/--
Arbitrary generator you can define.
-/
def dummyGenerator : GenericGenerator where
  generate _ _ := return #[⟨"Hello, world!", 0.5⟩, ("Hi!", 0.3)]

#eval generate dummyGenerator "n : ℕ\n⊢ gcd n n = n"


/--
Arbitrary encoder you can define.
-/
def dummyEncoder : GenericEncoder where
  encode _  := return FloatArray.mk #[1, 2, 3]

#eval encode dummyEncoder "Hi!"


/--
https://huggingface.co/wellecks/llmstep-mathlib4-pythia2.8b

Make sure the model is up and running, e.g.,
by going to ./python and running `uvicorn server:app --port 23337`
-/
def pythia : ExternalGenerator := {
  name := "wellecks/llmstep-mathlib4-pythia2.8b"
  host := "localhost"
  port := 23337
}

#eval generate pythia "n : ℕ\n⊢ gcd n n = n"


/--
ReProver's retriever encoder as an external model.

Make sure the model is up and running, e.g.,
by going to ./python and running `uvicorn server:app --port 23337`
-/
def reproverExternalEncoder : ExternalEncoder := {
  name := "kaiyuy/leandojo-lean4-retriever-byt5-small"
  host := "localhost"
  port := 23337
}

-- Go to ./python and run `uvicorn server:app --port 23337`
#eval encode reproverExternalEncoder "n : ℕ\n⊢ gcd n n = n"
