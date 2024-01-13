import Lean
import LeanCopilot.Options
import LeanCopilot.Frontend
import Aesop.Util.Basic
import Std.Data.String.Basic
import Std.Tactic.TryThis
import Std.Data.MLList.Basic

open Lean Meta Parser Elab Term Tactic

set_option autoImplicit true


-- namespace MLList

-- /-- Construct a singleton monadic lazy list from a single monadic value. -/
-- def singletonM [Monad m] (x : m α) : MLList m α :=
--   .squash fun _ => do return .cons (← x) .nil

-- /-- Construct a singleton monadic lazy list from a single value. -/
-- def singleton [Monad m] (x : α) : MLList m α :=
--   .singletonM (pure x)

-- end MLList


/--
`Nondet m α` is variation on `MLList m α` suitable for use with backtrackable monads `m`.

We think of `Nondet m α` as a nondeterministic value in `α`,
with the possible alternatives stored in a monadic lazy list.

Along with each `a : α` we store the backtrackable state, and ensure that monadic operations
on alternatives run with the appropriate state.

Operations on the nondeterministic value via `bind`, `mapM`, and `filterMapM`
run with the appropriate backtrackable state, and are responsible for updating the state themselves
(typically this doesn't need to be done explicitly,
but just happens as a side effect in the monad `m`).
-/
@[nolint unusedArguments]
structure Nondet (m : Type → Type) [MonadBacktrack σ m] (α : Type) : Type where
  /--
  Convert a non-deterministic value into a lazy list, keeping the backtrackable state.
  Be careful that monadic operations on the `MLList` will not respect this state!
  -/
  toMLList : MLList m (α × σ)

namespace Nondet

variable {m : Type → Type} [Monad m] [MonadBacktrack σ m]

/-- The empty nondeterministic value. -/
def nil : Nondet m α := .mk .nil

instance : Inhabited (Nondet m α) := ⟨.nil⟩

/--
Squash a monadic nondeterministic value to a nondeterministic value.
-/
def squash (L : Unit → m (Nondet m α)) : Nondet m α :=
  .mk <| MLList.squash fun _ => return (← L ()).toMLList

/--
Bind a nondeterministic function over a nondeterministic value,
ensuring the function is run with the relevant backtrackable state at each value.
-/
partial def bind (L : Nondet m α) (f : α → Nondet m β) : Nondet m β := .squash fun _ => do
  match ← L.toMLList.uncons with
  | none => pure .nil
  | some (⟨x, s⟩, xs) => do
    let r := (Nondet.mk xs).bind f
    restoreState s
    match ← (f x).toMLList.uncons with
    | none => return r
    | some (y, ys) => return .mk <| .cons y (ys.append (fun _ => r.toMLList))

/-- Convert any value in the monad to the singleton nondeterministic value. -/
def singletonM (x : m α) : Nondet m α :=
  .mk <| .singletonM do
    let a ← x
    return (a, ← saveState)

/-- Convert a value to the singleton nondeterministic value. -/
def singleton (x : α) : Nondet m α := singletonM (pure x)

/--
Lift a list of monadic values to a nondeterministic value.
We ensure that each monadic value is evaluated with the same backtrackable state.
-/
def ofListM (L : List (m α)) : Nondet m α :=
  .squash fun _ => do
    let s ← saveState
    return .mk <| MLList.ofListM <| L.map fun x => do
      restoreState s
      let a ← x
      pure (a, ← saveState)

/--
Lift a list of values to a nondeterministic value.
(The backtrackable state in each will be identical:
whatever the state was when we first read from the result.)
-/
def ofList (L : List α) : Nondet m α := ofListM (L.map pure)

/-- Convert a monadic optional value to a nondeterministic value. -/
def ofOptionM (x : m (Option α)) : Nondet m α := .squash fun _ => do
  match ← x with
  | none => return .nil
  | some a => return singleton a

/-- Filter and map a nondeterministic value using a monadic function which may return `none`. -/
partial def filterMapM (f : α → m (Option β)) (L : Nondet m α) : Nondet m β :=
  L.bind fun a => ofOptionM (f a)

end Nondet


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
  -- Map each premise to `(name, path, code, score)`, and then assign each field to `PremiseInfo`.
  let premiseInfo : Array PremiseInfo := rawPremiseInfo.map fun (name, path, code, score) =>
    { name := name, path := path, code := code, score := score }
  return premiseInfo


/--
Retrieve a list of premises using the current pretty-printed tactic state as the query.
-/
def selectPremises : TacticM (Array PremiseInfo) := do
  retrieve (← getPpTacticState)


open Std.Tactic.TryThis in
def suggestion (tac : String) (msgs : MessageLog := {}) : TacticM Suggestion := do
  -- TODO `addExactSuggestion` has an option to construct `postInfo?`
  -- Factor that out so we can use it here instead of copying and pasting?
  let goals ← getGoals
  let postInfo? ← if goals.isEmpty then pure none else
    let mut str := "\nRemaining subgoals:"
    for g in goals do
      let e ← PrettyPrinter.ppExpr (← instantiateMVars (← g.getType))
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


open Std.Tactic.TryThis in
def hint (stx : Syntax) (tacStrs : Array String) : TacticM Unit := do
  let tacStxs ← tacStrs.filterMapM fun tstr : String => do match runParserCategory (← getEnv) `tactic tstr with
    | Except.error _ => return none
    | Except.ok stx => return some stx
  let tacs := Nondet.ofList tacStxs.toList
  let results := tacs.filterMapM fun t : Syntax => do
    if let some msgs ← observing? (withMessageLog (withoutInfoTrees (evalTactic t))) then
      return some (← getGoals, ← suggestion t.prettyPrint.pretty' msgs)
    else
      return none
  -- let results := Nondet.ofList results.toList
  let results ← (results.toMLList.takeUpToFirst fun r => r.1.1.isEmpty).asArray
  let results := results.qsort (·.1.1.length < ·.1.1.length)
  addSuggestions stx (results.map (·.1.2))
  match results.find? (·.1.1.isEmpty) with
  | some r =>
    -- We don't restore the entire state, as that would delete the suggestion messages.
    setMCtx r.2.term.meta.meta.mctx
  | none => admitGoal (← getMainGoal)


-- open Std.Tactic.TryThis in
-- def hint (stx : Syntax) (tacStrs : Array String) : TacticM Unit := do
--   let results ← tacStrs.filterMapM fun tstr : String => do match runParserCategory (← getEnv) `tactic tstr with
--     | Except.error _ => return none
--     | Except.ok stx =>
--         if let some msgs ← observing? (withMessageLog (withoutInfoTrees (evalTactic stx))) then
--           return some (← getGoals, ← suggestion tstr msgs)
--         else
--           return none
--   let results := Nondet.ofList results.toList
--   let results ← (results.toMLList.takeUpToFirst fun r => r.1.1.isEmpty).asArray
--   let results := results.qsort (·.1.1.length < ·.1.1.length)
--   addSuggestions stx (results.map (·.1.2))
--   match results.find? (·.1.1.isEmpty) with
--   | some r =>
--     -- We don't restore the entire state, as that would delete the suggestion messages.
--     setMCtx r.2.term.meta.meta.mctx
--   | none => admitGoal (← getMainGoal)


-- def hint (stx : Syntax) (tacStrs : Array String) : TacticM Unit := do
--   let results ← tacStrs.mapM fun tstr : String => do match runParserCategory (← getEnv) `tactic tstr with
--     | Except.error _ => return none
--     | Except.ok stx =>
--         if let some msgs ← observing? (withMessageLog (withoutInfoTrees (evalTactic stx))) then
--           return some (← getGoals, ← suggestion tstr msgs)
--         else
--           return none
--   -- `result` is of type `Array (Option (List MVarId × Std.Tactic.TryThis.Suggestion))`, we want to drop the `none`s.
--   let results := results.filterMap (·)
--   Std.Tactic.TryThis.addSuggestions stx (results.map (·.2))


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
