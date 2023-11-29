import LeanCopilot.Tactics
import Aesop

open Lean Lean.Elab.Command

namespace LeanCopilot


def tacGen : Aesop.TacGen := fun (mvarId : MVarId) => do
  let state ← ppTacticState [mvarId]
  generate state ""


macro "#init_llm_aesop" : command => `(#eval (initGenerator : IO Bool) @[aesop 100%] def tacGen := LeanCopilot.tacGen #eval getConfig)


end LeanCopilot
