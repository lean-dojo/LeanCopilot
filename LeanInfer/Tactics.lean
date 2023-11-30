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


def elabPremise (premiseWithInfo : String × String × String) : MetaM String := do
  let (premise, path, code) := premiseWithInfo
  let declName := premise.toName
  try
    let info ← getConstInfo declName
    let premise_type ← Meta.ppExpr info.type
    let some doc_str ← findDocString? (← getEnv) declName
      | return s!"\n{premise}\n   type: {premise_type}\n"
    return s!"\n{premise}\n   type: {premise_type}\n   doc string: {doc_str}\n"
  catch _ => return s!"\n{premise}\n   This premise is not available in the current environment.\n   You need to import {path} to use it.\n   The premise is defined as {code}\n}"


def selectPremises : TacticM (Array (Float × String × String × String)) := do
  retrieve (← getPpTacticState)


syntax "trace_generate" str : tactic
syntax "trace_encode" str : tactic
syntax "pp_state" : tactic
syntax "suggest_tactics" : tactic
syntax "suggest_tactics" str : tactic
syntax "select_premises" : tactic


macro_rules
  | `(tactic | suggest_tactics%$tac) => `(tactic | suggest_tactics%$tac "")


elab_rules : tactic
  | `(tactic | trace_generate $input:str) => do
    logInfo s!"{← generate input.getString ""}"

  | `(tactic | trace_encode $input:str) => do
    logInfo s!"{← encode input.getString}"

  | `(tactic | pp_state) => do
    let state ← getPpTacticState
    logInfo state

  | `(tactic | suggest_tactics%$tac $pfx:str) => do
    let (tacticsWithScores, elapsed) ← Aesop.time $ suggestTactics pfx.getString
    if ← isVerbose then
      logInfo s!"{elapsed.printAsMillis} for generating {tacticsWithScores.size} tactics"
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac pfx tactics.toList (← checkTactics)

  | `(tactic | select_premises) => do
    let premisesWithInfoAndScores ← selectPremises
    let premisesWithInfo := premisesWithInfoAndScores.map (·.2)
    let rich_premises ← Meta.liftMetaM $ (premisesWithInfo.mapM elabPremise)
    logInfo s!"{rich_premises.foldl (init := "") (· ++ ·)}"


end LeanInfer
