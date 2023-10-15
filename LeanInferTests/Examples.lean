import Lean
import LeanInfer

open Lean
open LeanInfer

set_option autoImplicit false

#eval getConfig

def cfg : Config := {
  backend := .native $ .ct2 {modelUrl := ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩}, 
  decoding := {numReturnSequences := 32}
}

#eval setConfig cfg

#eval getConfig


example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry

/-
example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_premises
  sorry
-/