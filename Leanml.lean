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
  let tactic_candidate0 := coreFun msg
  let tactic_candidate1 := coreFun msg
  let tactic_candidate2 := coreFun msg
  let tactic_candidate3 := coreFun msg
  let tactic_candidate4 := coreFun msg
  logInfo <| s!"[TACTIC CANDIDATES]\n{tactic_candidate0}\n{tactic_candidate1}\n{tactic_candidate2}\n{tactic_candidate3}\n{tactic_candidate4}"

def main : IO Unit :=
  IO.println s!"Hello!"