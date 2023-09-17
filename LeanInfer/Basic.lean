import Lean
import LeanInfer.Frontend
import LeanInfer.Cache

open Lean Elab Tactic

namespace LeanInfer

namespace Core

@[extern "init_generator"]
private opaque init_generator (modelDir : @& String) : Bool 

@[extern "is_initialized"]
private opaque is_initialized : Unit → Bool

-- https://huggingface.co/docs/transformers/v4.28.1/en/main_classes/text_generation
@[extern "generate"]
private opaque generate (input : @& String) (numReturnSequences : UInt64) (maxLength : UInt64) 
(temperature : Float) (numBeams : UInt64) : Array (String × Float)

@[extern "encode"]
private opaque encode (input : @& String) : FloatArray

end Core

private def is_initialized : IO Bool := do
  return Core.is_initialized ()

private def init_generator : CoreM Bool := do
  if ← is_initialized then
    return true
  else if Core.init_generator (← Cache.getModelDir).toString then
    return true
  else
    logWarning  "Cannot find the generator model. If you would like to download it to this project, run `suggest_tactics!` and wait for a few mintues."
    return false

def generate (input : String) (numReturnSequences : UInt64 := 8) 
(maxLength : UInt64 := 256) (temperature : Float := 1.0) 
(numBeams : UInt64 := 1) : CoreM (Array (String × Float)) := do
  if ← init_generator then
    return Core.generate input numReturnSequences maxLength temperature numBeams
  else
    return #[]

def encode (input : String) : IO FloatArray := do
  return Core.encode input

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

def suggestTactics : TacticM (Array String) := do
  let input ← getPpTacticState
  let suggestions ← generate input
  return suggestions.map (·.1)

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
    let tactics ← suggestTactics 
    addSuggestions tac tactics.toList
    
  | `(tactic | suggest_tactics!%$tac) => do
    Cache.checkModel
    let tactics ← suggestTactics 
    addSuggestions tac tactics.toList

  | `(tactic | suggest_premises) => do
    let input ← getPpTacticState
    let suggestions ← timeit s!"Time for retriving premises:" (retrieve input)
    let premises := suggestions.map (·.1)
    logInfo s!"{premises}"


end LeanInfer
