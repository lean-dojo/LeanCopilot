import LeanCopilot.Tactics
import LeanCopilot.Options
import Std.Data.String.Basic
import Aesop

set_option autoImplicit false

open Lean Meta Elab Term Tactic

namespace LeanCopilot


def tacGen : Aesop.TacGen := fun (mvarId : MVarId) => do
  let state ← ppTacticState [mvarId]
  let theoremName := match ((← liftM (m := MetaM) <| Term.TermElabM.run getDeclName?).1.get!).toString with
    | "_example" => ""
    | n => n
  let theoremNameMatcher := String.Matcher.ofString theoremName
  let nm ← SuggestTactics.getGeneratorName
  let model ← getGenerator nm
  let suggestions ← generate model state ""
  let filteredSuggestions := suggestions.filterMap fun ((t, s) : String × Float) =>
    if (¬ (theoremName == "") ∧ (Option.isSome <| theoremNameMatcher.find? t)) ∨ (t == "aesop") then none else some (t, s)
  return filteredSuggestions


macro "#configure_llm_aesop" : command => `(@[aesop 100%] def tacGen := LeanCopilot.tacGen)


macro "search_proof" : tactic => `(tactic| aesop?)


end LeanCopilot
