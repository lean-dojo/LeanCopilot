import LeanCopilot

open Lean Meta
open LeanCopilot

#eval (SuggestTactics.getGeneratorName : CoreM _)

-- set_option LeanCopilot.verbose false

#eval getModelRegistry


-- set_option LeanCopilot.suggest_tactics.check false

-- set_option LeanCopilot.suggest_tactics.model "ct2-leandojo-lean4-retriever-byt5-small"

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry


-- You may provide a prefix to constrain the generated tactics.
example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics "rw"
  sorry
