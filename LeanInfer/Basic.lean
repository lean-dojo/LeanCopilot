import Lean
import LeanInfer.Frontend

open Lean Elab Tactic

namespace LeanInfer

namespace Core

-- https://huggingface.co/docs/transformers/v4.28.1/en/main_classes/text_generation
@[extern "generate"]
private opaque generate (input : @& String) (numReturnSequences : UInt64) (maxLength : UInt64) 
(temperature : Float) (numBeams : UInt64) : Array (String × Float)

@[extern "encode"]
private opaque encode (input : @& String) : FloatArray

end Core

def generate (input : String) (numReturnSequences : UInt64 := 10) 
(maxLength : UInt64 := 1024) (temperature : Float := 1.0) 
(numBeams : UInt64 := 1) : IO (Array (String × Float)) := do
  return Core.generate input numReturnSequences maxLength temperature numBeams

def encode (input : String) : IO FloatArray := do
  return Core.encode input

def ppTacticState : List MVarId → MetaM String
  | [] => return "no goals"
  | [g] => return (← Meta.ppGoal g).pretty
  | goals => 
      return (← goals.foldlM (init := "") (fun a b => do return s!"{a}\n\n{(← Meta.ppGoal b).pretty}")).trim

def getPpTacticState : TacticM String := do
  let goals ← getUnsolvedGoals
  ppTacticState goals

syntax "trace_generate" str: tactic
elab_rules : tactic
  | `(tactic | trace_generate $input:str) => do
    logInfo s!"{← generate input.getString}"

syntax "trace_encode" str: tactic
elab_rules : tactic
  | `(tactic | trace_encode $input:str) => do
    logInfo s!"{← encode input.getString}"

syntax "suggest_tactics" str: tactic
elab_rules : tactic
  | `(tactic | suggest_tactics%$tac $pfx:str) => do
    let input ← getPpTacticState
    let suggestions ← timeit s!"Time for generating tactics:" (generate input)
    let tactics := suggestions.map (·.1)
    addSuggestions tac pfx tactics.toList

end LeanInfer
