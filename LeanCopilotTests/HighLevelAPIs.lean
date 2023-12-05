import LeanCopilot

open LeanCopilot

/-
#eval getConfig

def cfg : Config := {
  backend := .native $ .ct2 {
    generatorUrl := some ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩,
    encoderUrl := some ⟨"kaiyuy", "ct2-leandojo-lean4-retriever-byt5-small"⟩
  },
  decoding := {numReturnSequences := 64}
}

#eval setConfig cfg
-/

/-
example (n : Nat) : Nat.gcd n n = n := by
  select_premises!
  sorry
-/

-- set_option LeanCopilot.verbose false
-- set_option LeanCopilot.suggest_tactics.check true

set_option LeanCopilot.suggest_tactics.device
set_option LeanCopilot.suggest_tactics.deviceIndex
set_option LeanCopilot.suggest_tactics.computeType
set_option LeanCopilot.suggest_tactics.numReturnSequences
set_option LeanCopilot.suggest_tactics.modelName


example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry


example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics "rw"  -- You may provide a prefix to constrain the generated tactics.
  sorry


example (a b c : Nat) : a + b + c = a + c + b := by
  select_premises
  sorry

-- The example below wouldn't work without it.
#init_llm_aesop

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?
