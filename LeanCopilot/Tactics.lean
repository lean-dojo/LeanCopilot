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
  let nm ← getGeneratorName
  let model ← getGenerator nm
  generate model state targetPrefix


def annotatePremise (premisesWithInfoAndScores : String × String × String × Float) : MetaM String := do
  let (premise, path, code, _) := premisesWithInfoAndScores
  let declName := premise.toName
  try
    let info ← getConstInfo declName
    let premise_type ← Meta.ppExpr info.type
    let some doc_str ← findDocString? (← getEnv) declName
      | return s!"\n{premise} : {premise_type}\n"
    return s!"\n{premise} : {premise_type}\n\n{doc_str}\n"
  catch _ => return s!"\n{premise} needs to be imported from {path}.\n\n```\n{code}\n```\n"


def retrieve (input : String) : TacticM (Array (String × String × String × Float)) := do
  if ¬ (← premiseEmbeddingsInitialized) ∧ ¬ (← initPremiseEmbeddings .auto) then
    throwError "Cannot initialize premise embeddings"

  if ¬ (← premiseDictionaryInitialized) ∧ ¬ (← initPremiseDictionary) then
    throwError "Cannot initialize premise dictionary"

  let k ← SelectPremises.getNumPremises
  let query ← encode Builtin.encoder input

  return FFI.retrieve query k.toUInt64


def selectPremises : TacticM (Array (String × String × String × Float)) := do
  retrieve (← getPpTacticState)


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
    let richPremises ← Meta.liftMetaM $ (premisesWithInfoAndScores.mapM annotatePremise)
    let richPremisesExpand := richPremises.foldl (init := "") (· ++ · ++ "\n")
    logInfo richPremisesExpand


end LeanCopilot
