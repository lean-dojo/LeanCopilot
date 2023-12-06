import Lean
import LeanCopilot.Options
import LeanCopilot.Frontend
import Aesop.Util.Basic

open Lean Meta Elab Tactic

set_option autoImplicit false

namespace LeanCopilot


/--
Pretty-print a list of goals.
-/
def ppTacticState : List MVarId → MetaM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals =>
      return (← goals.foldlM (init := "") (fun a b => do return s!"{a}\n\n{(← Meta.ppGoal b).pretty}")).trim


/--
Pretty-print the current tactic state.
-/
def getPpTacticState : TacticM String := do
  let goals ← getUnsolvedGoals
  ppTacticState goals


@[implemented_by Meta.evalExpr]
opaque evalExpr (α) (expectedType : Expr) (value : Expr) (safety := DefinitionSafety.safe) : MetaM α


open SuggestTactics in
/--
Generate a list of tactic suggestions.
-/
def suggestTactics (targetPrefix : String) : TacticM (Array (String × Float)) := do
  let state ← getPpTacticState
  if ← isVerbose then
    logInfo s!"State:\n{state}"
  let modelName ← getGeneratorName
  let modelNameStx := Syntax.mkNameLit modelName.toString
  let stateStx := Syntax.mkStrLit state
  let targetPrefixStx := Syntax.mkStrLit targetPrefix
  let stx ← `(generate $modelNameStx $stateStx $targetPrefixStx)
  println! stx
  return #[]
  /-
  let ty ← mkAppM ``Array #[← mkAppM ``Prod #[mkConst ``String, mkConst ``String]]
  let e ← Tactic.elabTermEnsuringType stx ty
  evalExpr (Array (String × Float)) ty e
  -/

  /-
  match Parser.runParserCategory (← getEnv) `term "" "<stdin>" with
  | .error err => throwError err
  | .ok stx =>
  -/
  /-
  let lctx ← getLCtx
  for decl in lctx do
    println! decl.userName
  return #[]
  -/
  /-
  let stateExpr := lctx.findFromUserName? `state |>.get! |>.toExpr
  let targetPrefixExpr := lctx.findFromUserName? `targetPrefix |>.get! |>.toExpr
  let args :=  #[mkConst modelName, stateExpr, targetPrefixExpr]
  let e ← mkAppM ``generate args

  evalExpr (Array (String × Float)) t e
  -/


def elabPremise (premiseWithInfo : String × String × String) : MetaM String := do
  let (premise, path, code) := premiseWithInfo
  let declName := premise.toName
  try
    let info ← getConstInfo declName
    let premise_type ← Meta.ppExpr info.type
    let some doc_str ← findDocString? (← getEnv) declName
      | return s!"\n{premise}\n   type: {premise_type}\n"
    return s!"\n{premise}\n   type: {premise_type}\n   doc string:\n{doc_str}\n"
  catch _ => return s!"\n{premise}\n   This premise is not available in the current environment.\n   You need to import {path} to use it.\n   The premise is defined as\n{code}\n"


def selectPremises : TacticM (Array (Float × String × String × String)) := do
  return #[]
  -- retrieve (← getPpTacticState)


syntax "pp_state" : tactic
syntax "suggest_tactics" : tactic
syntax "suggest_tactics" str : tactic
syntax "select_premises" : tactic


macro_rules
  | `(tactic | suggest_tactics%$tac) => `(tactic | suggest_tactics%$tac "")


elab_rules : tactic
  | `(tactic | pp_state) => do
    let state ← getPpTacticState
    logInfo state

  | `(tactic | suggest_tactics%$tac $pfx:str) => do
    let (tacticsWithScores, elapsed) ← Aesop.time $ suggestTactics pfx.getString
    if ← isVerbose then
      logInfo s!"{elapsed.printAsMillis} for generating {tacticsWithScores.size} tactics"
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac pfx tactics.toList (← SuggestTactics.checkTactics)

  | `(tactic | select_premises) => do
    let premisesWithInfoAndScores ← selectPremises
    let premisesWithInfo := premisesWithInfoAndScores.map (·.2)
    let rich_premises ← Meta.liftMetaM $ (premisesWithInfo.mapM elabPremise)
    let rich_premises_expand := rich_premises.foldl (init := "") (· ++ · ++ "\n")
    logInfo rich_premises_expand


end LeanCopilot
