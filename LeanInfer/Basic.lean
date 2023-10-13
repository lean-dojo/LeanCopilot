import Lean
import LeanInfer.Frontend
import LeanInfer.Cache
import LeanInfer.FFI

open Lean Elab Tactic

namespace LeanInfer

section

variable {m : Type → Type} [Monad m] [MonadLiftT IO m] 
  [MonadLog m] [AddMessageContext m] [MonadOptions m] [MonadReaderOf Config m] 

/--
Check if the model is up and running.
-/
private def isInitialized : m Bool := do
  let config ← read
  match config.backend with
  | .native .. => return FFI.isInitialized ()
  | .ipc .. => unreachable!

/--
Initialize the model.
-/
private def initGenerator : m Bool := do
  if ← isInitialized then
    return true

  let config ← read
  match config.backend with
  | .native .. => do 
    if FFI.initGenerator (← Cache.getModelDir).toString then
      return true
    else
      logWarning  "Cannot find the generator model. If you would like to download it, run `suggest_tactics!` and wait for a few mintues."
      return false
  | .ipc .. => unreachable!

def generate (input : String) : m (Array (String × Float)) := do
  if ¬ (← initGenerator) then
    return #[]
  let config ← read
  match config.backend with
  | .native .. =>
    let numReturnSequences := config.decoding.numReturnSequences
    let maxLength := config.decoding.maxLength
    let temperature := config.decoding.temperature
    let beamSize := config.decoding.beamSize
    return FFI.generate input numReturnSequences maxLength temperature beamSize
  | .ipc .. => unreachable!

end

def encode (input : String) : IO FloatArray := do
  return FFI.encode input

def retrieve (input : String) : IO (Array (String × Float)) := do
  let query ← encode input
  println! query
  return #[("hello", 0.5)]  -- Not implemented yet.

def ppTacticState : List MVarId → MetaM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals => 
      return (← goals.foldlM (init := "") (fun a b => do return s!"{a}\n\n{(← Meta.ppGoal b).pretty}")).trim

def getPpTacticState : TacticM String := do
  let goals ← getUnsolvedGoals
  ppTacticState goals

def suggestTactics : TacticM (Array (String × Float)) := do
  let input ← getPpTacticState
  let suggestions ← generate input
  return suggestions

syntax "trace_generate" str : tactic
syntax "trace_encode" str : tactic
syntax "suggest_tactics" : tactic
syntax "suggest_tactics!" : tactic
syntax "suggest_premises" : tactic

elab_rules : tactic
  | `(tactic | trace_generate $input:str) => do
    logInfo s!"{← generate input.getString}"

  | `(tactic | trace_encode $input:str) => do
    logInfo s!"{← encode input.getString}"

  | `(tactic | suggest_tactics%$tac) => do
    let tacticsWithScores ← suggestTactics
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac tactics.toList
    
  | `(tactic | suggest_tactics!%$tac) => do
    Cache.checkModel
    let tacticsWithScores ← suggestTactics
    let tactics := tacticsWithScores.map (·.1)
    addSuggestions tac tactics.toList

  | `(tactic | suggest_premises) => do
    let input ← getPpTacticState
    let suggestions ← timeit s!"Time for retriving premises:" (retrieve input)
    let premises := suggestions.map (·.1)
    logInfo s!"{premises}"


end LeanInfer
