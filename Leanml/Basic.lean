import Lean
open Lean Elab Parser Term Meta Tactic

@[extern "core_fun"]
opaque coreFun : String -> String

elab "trace_goal_state" : tactic => do
  let goals ← getUnsolvedGoals
  let msg ← MessageData.toString <| ← addMessageContext <| goalsToMessageData goals
  logInfo <| s!"[TACTIC CANDIDATES] {coreFun msg}"
