import Lean
import LeanInfer.Cache
import LeanInfer.FFI
import LeanInfer.Config

open Lean

set_option autoImplicit false

namespace LeanInfer

section

variable {m : Type → Type} [Monad m] [MonadLog m] [AddMessageContext m] 
  [MonadOptions m] [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT IO m] [MonadError m]

/--
Check if the model is up and running.
-/
private def isInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return FFI.isOnnxInitialized ()
  | .native (.ct2 _) => return FFI.isCt2Initialized ()
  | .ipc .. => unreachable!

private def initNativeGenerator (initFn : String → Bool) : m Bool := do
  let some dir ← Cache.getCurrentModelDir | throwError "Cannot find the generator model."
  if initFn dir.toString then
    return true
  else
    logWarning  "Cannot find the generator model. If you would like to download it, run `suggest_tactics!` and wait for a few mintues."
    return false

private def initGenerator : m Bool := do
  if ← isInitialized then
    return true
    
  match ← getBackend with
  | .native (.onnx _) => initNativeGenerator FFI.initOnnxGenerator
  | .native (.ct2 _) => initNativeGenerator FFI.initCt2Generator 
  | .ipc .. => unreachable!

def generate (input : String) : m (Array (String × Float)) := do
  if ¬ (← initGenerator) then
    return #[]

  let config ← getConfig
  match config.backend  with
  | .native (.onnx _) =>
    let numReturnSequences := config.decoding.numReturnSequences
    let maxLength := config.decoding.maxLength
    let temperature := config.decoding.temperature
    let beamSize := config.decoding.beamSize
    return FFI.onnxGenerate input numReturnSequences maxLength temperature beamSize
  | .native (.ct2 _) => 
    let numReturnSequences := config.decoding.numReturnSequences
    let beamSize := config.decoding.beamSize
    let minLength := config.decoding.minLength
    let maxLength := config.decoding.maxLength
    let lengthPenalty := config.decoding.lengthPenalty
    let patience := config.decoding.patience
    let temperature := config.decoding.temperature
    return FFI.ct2Generate input numReturnSequences beamSize minLength maxLength lengthPenalty patience temperature
  | .ipc .. => unreachable!

end

def encode (input : String) : IO FloatArray := do
  return FFI.onnxEncode input

def retrieve (input : String) : IO (Array (String × Float)) := do
  let query ← encode input
  println! query
  return #[("hello", 0.5)]  -- Not implemented yet.

end LeanInfer
