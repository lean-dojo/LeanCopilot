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


def initGenerator : IO Bool := do
  let dir ← Cache.getGeneratorDir
  let success : Bool := match ← getBackend with
  | .native (.onnx _) =>
       FFI.initOnnxGenerator dir.toString
  | .native (.ct2 params) =>
      FFI.initCt2Generator dir.toString params.device params.computeType params.deviceIndex params.intraThreads
  | .ipc .. => unreachable!

  if ¬ success then
    throw $ IO.userError "Cannot find the generator model. Please run `lake script run LeanInfer/download`."
  return success


def generate (input : String) (targetPrefix : String) : m (Array (String × Float)) := do
  if ¬ (← isGeneratorInitialized) ∧ ¬ (← initGenerator) then
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
    let inputTokens := tokenizeByt5 input true |>.toArray
    let targetPrefixTokens := tokenizeByt5 targetPrefix false |>.toArray
    let numReturnSequences := config.decoding.numReturnSequences
    let beamSize := config.decoding.beamSize
    let minLength := config.decoding.minLength
    let maxLength := config.decoding.maxLength
    let lengthPenalty := config.decoding.lengthPenalty
    let patience := config.decoding.patience
    let temperature := config.decoding.temperature
    let tokensWithScores := FFI.ct2Generate inputTokens targetPrefixTokens numReturnSequences beamSize minLength maxLength lengthPenalty patience temperature
    tokensWithScores.map fun (ts, s) => (detokenizeByt5 ts, s)
  | .ipc .. => unreachable!

  return tacticsWithScores.qsort (·.2 > ·.2)


private def isEncoderInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isCt2EncoderInitialized ()
  | .ipc .. => unreachable!


private def initNativeEncoder (initFn : String → Bool) : IO Bool := do
  let dir ← Cache.getEncoderDir
  if initFn dir.toString then
    return true
  else
    throw $ IO.userError "Cannot find the encoder model. Please run `lake script run LeanInfer/download`."
    return false


def initEncoder : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => initNativeEncoder FFI.initCt2Encoder
  | .ipc .. => unreachable!


def encode (input : String) : m FloatArray := do
  if ¬ (← isEncoderInitialized) ∧ ¬ (← initEncoder) then
    return FloatArray.mk #[]

  match ← getBackend  with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) =>
    let inputTokens := tokenizeByt5 input true |>.toArray
    return FFI.ct2Encode inputTokens
  | .ipc .. => unreachable!


def retrieve (input : String) : m (Array (String × Float)) := do
  let query ← encode input
  logInfo s!"{query}"
  return #[("NotImplemented", 0.5)]

end


def setConfig (config : Config) : CoreM Unit := do
  assert! config.isValid
  configRef.modify fun _ => config
  if ← isGeneratorInitialized then
    assert! ← initGenerator
  if ← isEncoderInitialized then
    assert! ← initEncoder


end LeanInfer
