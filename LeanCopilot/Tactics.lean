import Lean
import LeanCopilot.Options
import LeanCopilot.Frontend
import Aesop.Util.Basic
import Std.Data.String.Basic

open Lean Meta Elab Term Tactic

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


open SuggestTactics in
/--
Generate a list of tactic suggestions.
-/
def suggestTactics (targetPrefix : String) : TacticM (Array (String × Float)) := do
  let state ← getPpTacticState
  let nm ← getGeneratorName
  let model ← getGenerator nm
  let suggestions ← generate model state targetPrefix
  -- A temporary workaround to prevent the tactic from using the current theorem.
  -- TODO: Use a more pincipled way, e.g., see Lean4Repl.lean in LeanDojo.
  if let some declName ← getDeclName? then
    let theoremName := match declName.toString with
      | "_example" => ""
      | n => n.splitOn "." |>.getLast!
    let theoremNameMatcher := String.Matcher.ofString theoremName
    if ← isVerbose then
      logInfo s!"State:\n{state}"
      logInfo s!"Theorem name:\n{theoremName}"
    let filteredSuggestions := suggestions.filterMap fun ((t, s) : String × Float) =>
      let isAesop := t == "aesop"
      let isSelfReference := ¬ (theoremName == "") ∧ (theoremNameMatcher.find? t |>.isSome)
      if isSelfReference ∨ isAesop then none else some (t, s)
    return filteredSuggestions
  else
    let filteredSuggestions := suggestions.filterMap fun ((t, s) : String × Float) =>
      let isAesop := t == "aesop"
      if isAesop then none else some (t, s)
    return filteredSuggestions


private def annotatePremise (premisesWithInfoAndScores : String × String × String × Float) : MetaM String := do
  let (premise, path, code, _) := premisesWithInfoAndScores
  let declName := premise.toName
  try
    let info ← getConstInfo declName
    let premise_type ← Meta.ppExpr info.type
    let some doc_str ← findDocString? (← getEnv) declName
      | return s!"\n{premise} : {premise_type}"
    return s!"\n{premise} : {premise_type}\n```doc\n{doc_str}```"
  catch _ => return s!"\n{premise} needs to be imported from {path}.\n```code\n{code}\n```"


/--
Retrieve a list of premises given a query.
-/
def retrieve (input : String) : TacticM (Array (String × String × String × Float)) := do
  if ¬ (← premiseEmbeddingsInitialized) ∧ ¬ (← initPremiseEmbeddings .auto) then
    throwError "Cannot initialize premise embeddings"

  if ¬ (← premiseDictionaryInitialized) ∧ ¬ (← initPremiseDictionary) then
    throwError "Cannot initialize premise dictionary"

  let k ← SelectPremises.getNumPremises
  let query ← encode Builtin.encoder input

  return FFI.retrieve query k.toUInt64


/--
Retrieve a list of premises using the current pretty-printed tactic state as the query.
-/
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
    let rankedPremisesWithInfoAndScores := premisesWithInfoAndScores.qsort (·.2.2.2 > ·.2.2.2)
    let richPremises ← Meta.liftMetaM $ (rankedPremisesWithInfoAndScores.mapM annotatePremise)
    let richPremisesExpand := richPremises.foldl (init := "") (· ++ · ++ "\n")
    logInfo richPremisesExpand


end LeanCopilot
