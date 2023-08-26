import Lean

@[extern "core_fun"]
opaque coreFun : String -> String

open Lean Elab Parser Term Meta Tactic

elab "trace_goal_state" : tactic => do
  let goals ← getUnsolvedGoals
  let msg ← MessageData.toString <| ← addMessageContext <| goalsToMessageData goals
  logInfo <| s!"[TACTIC CANDIDATES] {coreFun msg}"

def main : IO Unit :=
  IO.println s!"Success!"