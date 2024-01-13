import Lean
import LeanCopilot.Options
import LeanCopilot.Frontend
import Aesop.Util.Basic
import Std.Data.String.Basic

open Lean Meta Parser Elab Term Tactic


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
  -- TODO: Use a more principled way, e.g., see `Lean4Repl.lean` in `LeanDojo`.
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


/--
Information of a premise.
-/
structure PremiseInfo where
  name : String
  path : String
  code : String
  score : Float


private def annotatePremise (pi : PremiseInfo) : MetaM String := do
  let declName := pi.name.toName
  try
    let info ← getConstInfo declName
    let premise_type ← Meta.ppExpr info.type
    let some doc_str ← findDocString? (← getEnv) declName
      | return s!"\n{pi.name} : {premise_type}"
    return s!"\n{pi.name} : {premise_type}\n```doc\n{doc_str}```"
  catch _ => return s!"\n{pi.name} needs to be imported from {pi.path}.\n```code\n{pi.code}\n```"


/--
Retrieve a list of premises given a query.
-/
def retrieve (input : String) : TacticM (Array PremiseInfo) := do
  if ¬ (← premiseEmbeddingsInitialized) ∧ ¬ (← initPremiseEmbeddings .auto) then
    throwError "Cannot initialize premise embeddings"

  if ¬ (← premiseDictionaryInitialized) ∧ ¬ (← initPremiseDictionary) then
    throwError "Cannot initialize premise dictionary"

  let k ← SelectPremises.getNumPremises
  let query ← encode Builtin.encoder input

  let rawPremiseInfo := FFI.retrieve query k.toUInt64
  let premiseInfo : Array PremiseInfo := rawPremiseInfo.map fun (name, path, code, score) =>
    { name := name, path := path, code := code, score := score }
  return premiseInfo


/--
Retrieve a list of premises using the current pretty-printed tactic state as the query.
-/
def selectPremises : TacticM (Array PremiseInfo) := do
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
    let range : String.Range := { start := tac.getRange?.get!.start, stop := pfx.raw.getRange?.get!.stop }
    let ref := Syntax.ofRange range
    hint ref tactics

  | `(tactic | select_premises) => do
    let premisesWithInfoAndScores ← selectPremises
    let rankedPremisesWithInfoAndScores := premisesWithInfoAndScores.qsort (·.score > ·.score)
    let richPremises ← Meta.liftMetaM $ (rankedPremisesWithInfoAndScores.mapM annotatePremise)
    let richPremisesExpand := richPremises.foldl (init := "") (· ++ · ++ "\n")
    logInfo richPremisesExpand


end LeanCopilot
