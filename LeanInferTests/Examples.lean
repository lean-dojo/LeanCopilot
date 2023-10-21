import Lean
import LeanInfer

open Lean
open LeanInfer

set_option autoImplicit false

#eval getConfig

def cfg : Config := {
  backend := .native $ .ct2 {
    generatorUrl? := some ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩, 
    -- encoderUrl? := some ⟨"kaiyuy", "ct2-leandojo-lean3-retriever-byt5-small"⟩
    -- TODO: Convert T5EncoderModel to ct2
  }, 
  decoding := {numReturnSequences := 64}
}

#eval setConfig cfg

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry
