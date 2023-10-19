import Lean
import LeanInfer.Cache
import LeanInfer.FFI
import LeanInfer.Config
import LeanInfer.Tokenization

open Lean

set_option autoImplicit false

namespace LeanInfer

section

variable {m : Type → Type} [Monad m] [MonadLog m] [AddMessageContext m] 
  [MonadOptions m] [MonadLiftT (ST IO.RealWorld) m] [MonadLiftT IO m] [MonadError m]


private def isGeneratorInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return FFI.isOnnxGeneratorInitialized ()
  | .native (.ct2 _) => return FFI.isCt2GeneratorInitialized ()
  | .ipc .. => unreachable!


private def initNativeGenerator (initFn : String → Bool) : m Bool := do
  let some dir ← Cache.getGeneratorDir | throwError "Cannot find the generator model."
  if initFn dir.toString then
    return true
  else
    logWarning  "Cannot find the generator model. If you would like to download it, run `suggest_tactics!` and wait for a few mintues."
    return false


private def initGenerator : m Bool := do
  if ← isGeneratorInitialized then
    return true

  let some dir ← Cache.getGeneratorDir | throwError "Cannot find the generator model."
  let config ← getConfig
  let success : Bool := match config.backend with
  | .native (.onnx _) =>
       FFI.initOnnxGenerator dir.toString
  | .native (.ct2 params) =>
      FFI.initCt2Generator dir.toString params.device params.computeType
  | .ipc .. => unreachable!

  if ¬ success then
    logWarning  "Cannot find the generator model. If you would like to download it, run `suggest_tactics!` and wait for a few mintues."
  return success


def generate (input : String) : m (Array (String × Float)) := do
  if ¬ (← initGenerator) then
    return #[]

  let config ← getConfig
  let tacticsWithScores := match config.backend  with
  | .native (.onnx _) =>
    let numReturnSequences := config.decoding.numReturnSequences
    let maxLength := config.decoding.maxLength
    let temperature := config.decoding.temperature
    let beamSize := config.decoding.beamSize
    FFI.onnxGenerate input numReturnSequences maxLength temperature beamSize
  | .native (.ct2 _) => 
    let inputTokens := tokenizeByt5 input |>.toArray
    let numReturnSequences := config.decoding.numReturnSequences
    let beamSize := config.decoding.beamSize
    let minLength := config.decoding.minLength
    let maxLength := config.decoding.maxLength
    let lengthPenalty := config.decoding.lengthPenalty
    let patience := config.decoding.patience
    let temperature := config.decoding.temperature
    FFI.ct2Generate inputTokens numReturnSequences beamSize minLength maxLength lengthPenalty patience temperature
  | .ipc .. => unreachable!

  return tacticsWithScores.qsort (·.2 > ·.2)


private def isEncoderInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isCt2EncoderInitialized ()
  | .ipc .. => unreachable!


private def initNativeEncoder (initFn : String → Bool) : m Bool := do
  let some dir ← Cache.getEncoderDir | throwError "Cannot find the encoder model."
  if initFn dir.toString then
    return true
  else
    logWarning  "Cannot find the encoder model. If you would like to download it, run `select_premises!` and wait for a few mintues."
    return false


private def initEncoder : m Bool := do
  if ← isEncoderInitialized then
    return true
    
  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => initNativeEncoder FFI.initCt2Encoder 
  | .ipc .. => unreachable!


def encode (input : String) : m FloatArray := do
  if ¬ (← initEncoder) then
    return FloatArray.mk #[]

  match ← getBackend  with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => 
    return FFI.ct2Encode input
  | .ipc .. => unreachable!


def retrieve (input : String) : m (Array (String × Float)) := do
  let query ← encode input
  println! query
  return #[("hello", 0.5)]  -- Not implemented yet.

end

end LeanInfer
