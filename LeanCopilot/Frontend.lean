/- Some functions in this frontend are adapted from `mathlib4`.  -/
import Lean
import LeanCopilot.Options
import Std.Tactic.TryThis
import Std.Data.MLList.Basic

open Lean Parser Elab Tactic


set_option autoImplicit true

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


set_option autoImplicit false


open Std.Tactic.TryThis in
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
/--
Run all tactics registered using `register_hint`.
Print a "Try these:" suggestion for each of the successful tactics.

If one tactic succeeds and closes the goal, we don't look at subsequent tactics.
-/
-- TODO We could run the tactics in parallel.
-- TODO With widget support, could we run the tactics in parallel
--      and do live updates of the widget as results come in?
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
  let results ← (results.toMLList.takeUpToFirst fun r => r.1.1.isEmpty).asArray
  let results := results.qsort (·.1.1.length < ·.1.1.length)
  addSuggestions stx (results.map (·.1.2))
  match results.find? (·.1.1.isEmpty) with
  | some r =>
    setMCtx r.2.term.meta.meta.mctx
  | none => admitGoal (← getMainGoal)
