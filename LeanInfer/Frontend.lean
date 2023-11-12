/-
The MIT License (MIT)

Copyright (c) 2023 Sean Welleck

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-/

/-
`llmstep` tactic for LLM-based next-step suggestions in Lean4.
Examples:
 llmstep ""
 llmstep "have"
 llmstep "apply Continuous"

Author: Sean Welleck
-/
import Lean.Widget.UserWidget
import Std.Lean.Position
import Std.Lean.Format
import Std.Data.String.Basic

open Lean

-- /- Calls a `suggest.py` python script with the given prefix and pretty-printed goal. -/
-- def runSuggest (pre goal : String) : IO (List String) := do
--   let cwd ← IO.currentDir
--   let path := cwd / "python" / "suggest.py"
--   unless ← path.pathExists do
--     dbg_trace f!"{path}"
--     throw <| IO.userError "could not find python script suggest.py"
--   let s ← IO.Process.run { cmd := "python3", args := #[path.toString, goal, pre] }
--   return s.splitOn "[SUGGESTION]"

/- Display clickable suggestions in the VSCode Lean Infoview.
    When a suggestion is clicked, this widget replaces the `llmstep` call
    with the suggestion, and saves the call in an adjacent comment.
    Code based on `Std.Tactic.TryThis.tryThisWidget`. -/
@[widget] def llmstepTryThisWidget : Widget.UserWidgetDefinition where
  name := "Tactic suggestions"
  javascript := "
import * as React from 'react';
import { EditorContext } from '@leanprover/infoview';
const e = React.createElement;
export default function(props) {
  const editorConnection = React.useContext(EditorContext)
  function onClick(suggestion) {
    editorConnection.api.applyEdit({
      changes: { [props.pos.uri]: [{ range:
        props.range,
        newText: suggestion[0] + ' -- ' + props.tactic
        }] }
    })
  }
  const suggestionElement = props.suggestions.length > 0
    ? [
      'Try this: ',
      ...(props.suggestions.map((suggestion, i) =>
          e('li', {onClick: () => onClick(suggestion),
            className:
              suggestion[1] === 'ProofDone' ? 'link pointer dim green' :
              suggestion[1] === 'Valid' ? 'link pointer dim blue' :
              'link pointer dim',
            title: 'Apply suggestion'},
            suggestion[1] === 'ProofDone' ? '🎉 ' + suggestion[0] : suggestion[0]
        )
      )),
      props.info
    ]
    : 'No valid suggestions.';
  return e('div',
  {className: 'ml1'},
  e('ul', {className: 'font-code pre-wrap'},
  suggestionElement))
}"


inductive CheckResult : Type
  | ProofDone
  | Valid
  | Invalid
  | Unknown
  deriving ToJson, Ord

/- Check whether the suggestion `s` completes the proof, is valid (does
not result in an error message), or is invalid. -/
def checkSuggestion (check: Bool) (s: String) : Lean.Elab.Tactic.TacticM CheckResult := do
  -- let s := s_c.1
  -- let check := s_c.2
  -- logInfo s!"checking suggestion: {s}"
  if check == true then
    println! s!"checking suggestion: {s}"
    withoutModifyingState do
    try
      match Parser.runParserCategory (← getEnv) `tactic s with
        | Except.ok stx =>
          try
            _ ← Lean.Elab.Tactic.evalTactic stx
            let goals ← Lean.Elab.Tactic.getUnsolvedGoals
            if (← getThe Core.State).messages.hasErrors then
              pure CheckResult.Invalid
            else if goals.isEmpty then
              pure CheckResult.ProofDone
            else
              pure CheckResult.Valid
          catch _ =>
            pure CheckResult.Invalid
        | Except.error _ =>
          pure CheckResult.Invalid
    catch _ => pure CheckResult.Invalid
  else pure CheckResult.Unknown

  -- withoutModifyingState do
  -- try
  --   match Parser.runParserCategory (← getEnv) `tactic s with
  --     | Except.ok stx =>
  --       try
  --         _ ← Lean.Elab.Tactic.evalTactic stx
  --         let goals ← Lean.Elab.Tactic.getUnsolvedGoals
  --         if (← getThe Core.State).messages.hasErrors then
  --           pure CheckResult.Invalid
  --         else if goals.isEmpty then
  --           pure CheckResult.ProofDone
  --         else
  --           pure CheckResult.Valid
  --       catch _ =>
  --         pure CheckResult.Invalid
  --     | Except.error _ =>
  --       pure CheckResult.Invalid
  -- catch _ => pure CheckResult.Invalid
  -- pure CheckResult.Unknown


/- Adds multiple suggestions to the Lean InfoView.
   Code based on `Std.Tactic.addSuggestion`. -/
def addSuggestions (tacRef : Syntax) (pfxRef: Syntax) (suggestions: List String)
    (check : Bool) (origSpan? : Option Syntax := none) (extraMsg : String := "") : Lean.Elab.Tactic.TacticM Unit := do
  if let some tacticRange := (origSpan?.getD tacRef).getRange? then
    if let some argRange := (origSpan?.getD pfxRef).getRange? then
      let map ← getFileMap
      let start := findLineStart map.source tacticRange.start
      let body := map.source.findAux (· ≠ ' ') tacticRange.start start

      -- let checks := suggestions.map fun _ => CheckResult.Unknown
      -- println! "check option: {check}"
      -- logInfo s!"check option: {check}"
      -- Append 'check' to each entry in suggestions and form a list of pairs
      -- let suggestions_with_check := suggestions.map (λ s => (s, check))
      -- let checks ← suggestions_with_check.map checkSuggestion

      let mut suggestions := ["rw [sup_inf_self, sup_comm]", "apply h", "rfl", "rw [h]", "apply le_antisymm",
                              "congr", "simp", "rw [sup_inf_left]", "simp only [h]", "exact h _ _ _", "rw [inf_comm]",
                              "rw [sup_inf_right]", "rw [sup_inf_left, h]", "simp [h]", "rw [sup_comm]",
                              "rw [sup_inf_left, sup_comm]", "congr 1", "simp only [sup_inf_left, h]", "simp_rw [h]", "apply congr_arg", "rw [sup_inf_self]"]
      let checks ← suggestions.mapM (checkSuggestion check)

      -- let mut checks : List CheckResult := []
      -- for suggestion in suggestions do
      --   println! s!"checking suggestion: {suggestion}"
      --   let result ← checkSuggestion check suggestion
      --   checks := result :: checks

      -- let checks := if check then
      --   ← suggestions.mapM checkSuggestion
      -- else
      --   suggestions.map fun _ => CheckResult.Unknown
      let texts := suggestions.map fun text => (
        (Std.Format.prettyExtra (text.stripSuffix "\n")
         (indent := (body - start).1)
         (column := (tacticRange.start - start).1)
      ))

      let textsAndChecks := texts.zip checks |>.toArray |>.qsort
        fun a b => compare a.2 b.2 = Ordering.lt

      let start := (tacRef.getRange?.getD tacticRange).start
      let stop := (pfxRef.getRange?.getD argRange).stop
      let stxRange :=
      { start := map.lineStart (map.toPosition start).line
        stop := map.lineStart ((map.toPosition stop).line + 1) }
      let full_range : String.Range :=
      { start := tacticRange.start, stop := argRange.stop }
      let full_range := map.utf8RangeToLspRange full_range
      let tactic := Std.Format.prettyExtra f!"{tacRef.prettyPrint}{pfxRef.prettyPrint}"
      let json := Json.mkObj [
        ("tactic", tactic),
        ("suggestions", toJson textsAndChecks),
        ("range", toJson full_range),
        ("info", extraMsg)
      ]
      Widget.saveWidgetInfo ``llmstepTryThisWidget json (.ofRange stxRange)
