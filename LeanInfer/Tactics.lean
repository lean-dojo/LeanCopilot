import Lean
import LeanInfer.Basic
import LeanInfer.Frontend

open Lean Elab Tactic

set_option autoImplicit false

namespace LeanInfer

def ppTacticState : List MVarId → MetaM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals => 
      return (← goals.foldlM (init := "") (fun a b => do return s!"{a}\n\n{(← Meta.ppGoal b).pretty}")).trim

def getPpTacticState : TacticM String := do
  let goals ← getUnsolvedGoals
  ppTacticState goals

def suggestTactics : TacticM (Array (String × Float)) := do
  generate (← getPpTacticState)

def selectPremises : TacticM (Array (String × Float)) := do
  retrieve (← getPpTacticState)

syntax "trace_generate" str : tactic
syntax "trace_encode" str : tactic
syntax "suggest_tactics" : tactic
syntax "suggest_tactics!" : tactic
syntax "select_premises" : tactic
syntax "select_premises!" : tactic

elab_rules : tactic
  | `(tactic | trace_generate $input:str) => do
    logInfo s!"{← generate input.getString}"

  | `(tactic | trace_encode $input:str) => do
    logInfo s!"{← encode input.getString}"

  | `(tactic | suggest_tactics%$tac) => do
    let tacticsWithScores ← suggestTactics
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac tactics.toList
    
  | `(tactic | suggest_tactics!%$tac) => do
    Cache.checkGenerator
    let tacticsWithScores ← suggestTactics
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac tactics.toList

  | `(tactic | select_premises) => do
    let premisesWithScores ← selectPremises
    let premises := premisesWithScores.map (·.1)
    logInfo s!"{premises}"

  | `(tactic | select_premises!) => do
    Cache.checkEncoder
    let premisesWithScores ← selectPremises
    let premises := premisesWithScores.map (·.1)
    logInfo s!"{premises}"

end LeanInfer
