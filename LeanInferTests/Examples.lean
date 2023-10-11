import LeanInfer

open LeanInfer

@[leaninfer]
def cfg : Config := {
  backend := .ipc $ .ct2 {modelPath := "./ctranslate2-leandojo-lean4-tacgen-byt5-small" : CTranslate2Params},
  decoding := {
    numReturnSequences := 8,
  }
}


/-
example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_premises
  sorry
-/