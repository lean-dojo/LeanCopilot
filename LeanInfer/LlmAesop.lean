import LeanInfer.Tactics
import Aesop

open Lean Lean.Elab.Command

namespace LeanInfer


def tacGen : Aesop.TacGen := fun (mvarId : MVarId) => do
  let state ← ppTacticState [mvarId]
  generate state ""


macro "#init_llm_aesop" : command => `(#eval (initGenerator : IO Bool) @[aesop 100%] def tacGen := LeanInfer.tacGen #eval getConfig)


end LeanInfer
