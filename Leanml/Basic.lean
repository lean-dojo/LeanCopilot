import Lean
import Leanml.Frontend

open Lean Elab Parser Term Meta Tactic


-- https://huggingface.co/docs/transformers/v4.28.1/en/main_classes/text_generation
@[extern "text_to_text"]
opaque textToText (input : String) (numReturnSequences : UInt32 := 5) 
  (maxLength : UInt32 := 1024) (numBeams : UInt32 := 1) : Array (String × Float)

elab "trace_goal_state" : tactic => do
  let goals ← getUnsolvedGoals
  let msg ← MessageData.toString <| ← addMessageContext <| goalsToMessageData goals
  logInfo <| s!"[TACTIC CANDIDATES]\n{textToText msg}"


/-- Pretty print the current tactic state. --/
def ppTacticState : List MVarId → TacticM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals => 
      return (← goals.foldlM (init := "") (fun a b => do return a ++ "\n\n" ++ (← Meta.ppGoal b).pretty)).trim


syntax "suggest_tactics" str: tactic
elab_rules : tactic
  | `(tactic | suggest_tactics%$tac $pfx:str) => do
    let goals ← getUnsolvedGoals
    let input ← ppTacticState goals
    let suggestions := textToText input
    let tactics := suggestions.map (·.1)
    addSuggestions tac pfx tactics.toList