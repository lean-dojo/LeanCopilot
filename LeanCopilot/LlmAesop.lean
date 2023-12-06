import LeanCopilot.Tactics
import LeanCopilot.Options
import Aesop

open Lean Lean.Elab.Command

namespace LeanCopilot


def tacGen : Aesop.TacGen := fun (mvarId : MVarId) => do
  let state ← ppTacticState [mvarId]
  let nm ← SuggestTactics.getGeneratorName
  let model ← getGenerator nm
  generate model state ""


macro "#configure_llm_aesop" : command => `(@[aesop 100%] def tacGen := LeanCopilot.tacGen)


macro "search_proof" : tactic => `(tactic| aesop?)


end LeanCopilot
