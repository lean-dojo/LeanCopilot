/- This frontend is adapted from part of `mathlib4/Mathlib/Tactic/Hint.lean`
   originally authored by Scott Morrison. -/
import Lean
import LeanCopilot.Options
import Lean.Meta.Tactic.TryThis
import Std.Data.MLList.Basic
import Std.Control.Nondet.Basic

open Lean Parser Elab Tactic


set_option autoImplicit false


open Lean.Meta.Tactic.TryThis in
/--
Construct a suggestion for a tactic.
* Check the passed `MessageLog` for an info message beginning with "Try this: ".
* If found, use that as the suggestion.
* Otherwise use the provided syntax.
* Also, look for remaining goals and pretty print them after the suggestion.
-/
def suggestion (tac : String) (msgs : MessageLog := {}) : TacticM Suggestion := do
  -- TODO `addExactSuggestion` has an option to construct `postInfo?`
  -- Factor that out so we can use it here instead of copying and pasting?
  let goals ← getGoals
  let postInfo? ← if goals.isEmpty then pure none else
    let mut str := "\nRemaining subgoals:"
    for g in goals do
      let goalType ← instantiateMVars (← g.getType)
      let e ← g.withContext do (PrettyPrinter.ppExpr goalType)
      str := str ++ Format.pretty ("\n⊢ " ++ e)
    pure (some str)
  let style? := if goals.isEmpty then some .success else none
  let msg? ← msgs.toList.findM? fun m => do pure <|
    m.severity == MessageSeverity.information && (← m.data.toString).startsWith "Try this: "
  let suggestion ← match msg? with
  | some m => pure <| SuggestionText.string (((← m.data.toString).drop 10).takeWhile (· != '\n'))
  | none => pure <| SuggestionText.string tac
  return { suggestion, postInfo?, style? }


/-- Run a tactic, returning any new messages rather than adding them to the message log. -/
def withMessageLog (t : TacticM Unit) : TacticM MessageLog := do
  let initMsgs ← modifyGetThe Core.State fun st => (st.messages, { st with messages := {} })
  t
  modifyGetThe Core.State fun st => (st.messages, { st with messages := initMsgs })


/--
Run a tactic, but revert any changes to info trees.
We use this to inhibit the creation of widgets by subsidiary tactics.
-/
def withoutInfoTrees (t : TacticM Unit) : TacticM Unit := do
  let trees := (← getInfoState).trees
  t
  modifyInfoState fun s => { s with trees }


open Lean.Meta.Tactic.TryThis in
/--
Run all tactics registered using `register_hint`.
Print a "Try these:" suggestion for each of the successful tactics.

If one tactic succeeds and closes the goal, we don't look at subsequent tactics.
-/
-- TODO We could run the tactics in parallel.
-- TODO With widget support, could we run the tactics in parallel
--      and do live updates of the widget as results come in?
def hint (stx : Syntax) (tacStrs : Array String) (check : Bool) : TacticM Unit := do
  if check then
    let tacStxs ← tacStrs.filterMapM fun tstr : String => do match runParserCategory (← getEnv) `tactic tstr with
      | Except.error _ => return none
      | Except.ok stx => return some stx
    let tacs := Nondet.ofList tacStxs.toList
    let results := tacs.filterMapM fun t : Syntax => do
      if let some msgs ← observing? (withMessageLog (withoutInfoTrees (evalTactic t))) then
        return some (← getGoals, ← suggestion t.prettyPrint.pretty' msgs)
      else
        return none
    let results ← (results.toMLList.takeUpToFirst fun r => r.1.1.isEmpty).asArray
    let results := results.qsort (·.1.1.length < ·.1.1.length)
    addSuggestions stx (results.map (·.1.2))
    match results.find? (·.1.1.isEmpty) with
    | some r =>
      setMCtx r.2.term.meta.meta.mctx
    | none => admitGoal (← getMainGoal)
  else
    let tacsNoCheck : Array Suggestion := tacStrs.map fun tac => { suggestion := SuggestionText.string tac }
    addSuggestions stx tacsNoCheck
