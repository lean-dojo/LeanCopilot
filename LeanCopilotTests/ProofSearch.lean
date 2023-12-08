import Lean
import LeanCopilot

open Lean Meta
open LeanCopilot

#eval (SuggestTactics.getGeneratorName : CoreM _)

-- set_option LeanCopilot.verbose false

#eval getModelRegistry


-- set_option LeanCopilot.suggest_tactics.check false

-- set_option LeanCopilot.suggest_tactics.model "ct2-leandojo-lean4-retriever-byt5-small"





example (a b c : Nat) : a + b + c = c + b + a := by
  search_proof


-- The example below wouldn't work without it.
#configure_llm_aesop

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?
