import Lean
import LeanInfer.Basic
import LeanInfer.Frontend
import Aesop.Util.Basic

open Lean Elab Tactic

set_option autoImplicit false

namespace LeanInfer


register_option LeanInfer.suggest_tactics.check : Bool := {
  defValue := true
  descr := "Check if the generated tactics are valid or if they can prove the goal."
}


def checkTactics : CoreM Bool := do
  match LeanInfer.suggest_tactics.check.get? (← getOptions) with
  | some false => return false
  | _ => return true


def ppTacticState : List MVarId → MetaM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals =>
      return (← goals.foldlM (init := "") (fun a b => do return s!"{a}\n\n{(← Meta.ppGoal b).pretty}")).trim


def getPpTacticState : TacticM String := do
  let goals ← getUnsolvedGoals
  ppTacticState goals


def suggestTactics (targetPrefix : String) : TacticM (Array (String × Float)) := do
  let state ← getPpTacticState
  if ← isVerbose then
    logInfo s!"State:\n{state}"
  generate state targetPrefix


def selectPremises : TacticM (Array (String × Float)) := do
  retrieve (← getPpTacticState)


syntax "trace_generate" str : tactic
syntax "trace_encode" str : tactic
syntax "pp_state" : tactic
syntax "suggest_tactics" : tactic
syntax "suggest_tactics" str : tactic
syntax "select_premises" : tactic
syntax "suggest_tactics_weak" : tactic
syntax "suggest_tactics_weak" str : tactic


macro_rules
  | `(tactic | suggest_tactics%$tac) => `(tactic | suggest_tactics%$tac "")

macro_rules
  | `(tactic | suggest_tactics_weak%$tac) => `(tactic | suggest_tactics_weak%$tac "")


elab_rules : tactic
  | `(tactic | trace_generate $input:str) => do
    logInfo s!"{← generate input.getString ""}"

  | `(tactic | trace_encode $input:str) => do
    logInfo s!"{← encode input.getString}"

  | `(tactic | pp_state) => do
    let state ← getPpTacticState
    logInfo state

  | `(tactic | suggest_tactics%$tac $pfx:str) => do
    logInfo s!"Step 0: ¬Generating tactics for prefix {pfx}"
    let (tacticsWithScores, elapsed) ← Aesop.time $ suggestTactics pfx.getString
    logInfo s!"Step 1: \n{tacticsWithScores}"
    if ← isVerbose then
      logInfo s!"{elapsed.printAsMillis} for generating {tacticsWithScores.size} tactics"
    logInfo s!"Step 2\n"
    let tactics := tacticsWithScores.map (·.1)
    logInfo s!"Step 3: \n{tactics}"
    addSuggestions tac pfx tactics.toList (← checkTactics)
    logInfo s!"Step 4: \n{(← checkTactics)}"

  | `(tactic | suggest_tactics_weak%$tac $pfx:str) => do
    logInfo s!"Step 0: ¬Generating tactics for prefix {pfx}"
    let (tacticsWithScores, elapsed) ← Aesop.time $ suggestTactics pfx.getString
    logInfo s!"Step 1: \n{tacticsWithScores}"
    if ← isVerbose then
      logInfo s!"{elapsed.printAsMillis} for generating {tacticsWithScores.size} tactics"
    logInfo s!"Step 2\n"
    let tactics := tacticsWithScores.map (·.1)
    logInfo s!"Step 3: \n{tactics}"
    logInfo s!"Step 4: \n{(← checkTactics)}"
    -- addSuggestions tac pfx tactics.toList (← checkTactics)

  | `(tactic | select_premises) => do
    let premisesWithScores ← selectPremises
    let premises := premisesWithScores.map (·.1)
    logInfo s!"{premises}"


end LeanInfer
