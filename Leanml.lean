-- import «Leanml»

-- def main : IO Unit :=
--   IO.println s!"Hello!"

import Lean

@[extern "core_fun"]
opaque coreFun : String -> String

open Lean Elab Parser Term Meta Tactic

elab "trace_goal_state" : tactic => do
  let goals ← getUnsolvedGoals
  let msg ← MessageData.toString <| ← addMessageContext <| goalsToMessageData goals
  -- return results of five calls to coreFun, each in a new line.
  logInfo <| s!"[TACTIC CANDIDATES] {coreFun msg} {coreFun msg} {coreFun msg} {coreFun msg} {coreFun msg}"

def main : IO Unit :=
  IO.println s!"Hello!"