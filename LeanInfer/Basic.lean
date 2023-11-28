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


register_option LeanInfer.verbose : Bool := {
  defValue := false
  descr := "Log various debugging information when running LeanInfer."
}


def isVerbose : m Bool := do
  match LeanInfer.verbose.get? (← getOptions) with
  | some true => return true
  | _ => return false


private def isGeneratorInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return FFI.isOnnxGeneratorInitialized ()
  | .native (.ct2 _) => return FFI.isCt2GeneratorInitialized ()
  | .ipc .. => unreachable!


def initGenerator : IO Bool := do
  let dir ← Cache.getGeneratorDir
  if ¬ (← dir.pathExists) then
    throw $ IO.userError "Cannot find the generator model. Please run `lake script run LeanInfer/download`."
    return false

  match ← getBackend with
  | .native (.onnx _) =>
    assert! FFI.initOnnxGenerator dir.toString
  | .native (.ct2 params) =>
    assert! FFI.initCt2Generator dir.toString params.device params.computeType params.deviceIndex params.intraThreads
  | .ipc .. => unreachable!

  return true


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
    let rawOutputs := FFI.onnxGenerate input numReturnSequences maxLength temperature beamSize
    rawOutputs.filter fun (entry : String × Float) => entry.fst ≠ "aesop"
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
    tokensWithScores.filterMap fun (ts, s) => match detokenizeByt5 ts with
    | "aesop" => none
    | t => some (t, s)
  | .ipc .. => unreachable!

  let rankedTactics := tacticsWithScores.qsort (·.2 > ·.2)
  if ← isVerbose then
    logInfo $ rankedTactics.foldl (init := "Generated tactics with scores:\n")
      fun acc (t, s) => acc ++ s!"  {t}: {s}\n"
  return rankedTactics


private def isEncoderInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isCt2EncoderInitialized ()
  | .ipc .. => unreachable!


def initEncoder : IO Bool := do
  let dir ← Cache.getEncoderDir
  if ¬ (← dir.pathExists) then
    throw $ IO.userError "Cannot find the encoder model. Please run `lake script run LeanInfer/download`."
    return false

  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => assert! FFI.initCt2Encoder dir.toString
  | .ipc .. => unreachable!

  return true


def encode (input : String) : m FloatArray := do
  if ¬ (← isEncoderInitialized) ∧ ¬ (← initEncoder) then
    return FloatArray.mk #[]

  match ← getBackend  with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) =>
    let inputTokens := tokenizeByt5 input true |>.toArray
    return FFI.ct2Encode inputTokens
  | .ipc .. => unreachable!


private def isPremiseEmbInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isPremiseEmbeddingsInitialized ()
  | .ipc .. => unreachable!


def initPremiseEmb : IO Bool := do
  let dir ← Cache.getPremiseEmbDir
  if ¬ (← dir.pathExists) then
    throw $ IO.userError "Cannot find the premise embeddings for retrieval. Please run [TODO]."
    return false

  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => assert! FFI.initPremiseEmbeddings dir.toString
  | .ipc .. => unreachable!

  return true


private def isPremiseDictInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isPremiseDictionaryInitialized ()
  | .ipc .. => unreachable!


def initPremiseDict : IO Bool := do
  let dir ← Cache.getPremiseDictDir
  if ¬ (← dir.pathExists) then
    throw $ IO.userError "Cannot find the premise dictionary for retrieval. Please run [TODO]."
    return false

  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => assert! FFI.initPremiseDictionary dir.toString
  | .ipc .. => unreachable!

  return true


def retrieve (input : String) : m (Array (String × Float)) := do
  if ¬ (← isPremiseEmbInitialized) ∧ ¬ (← initPremiseEmb) then
    return #[]
  if ¬ (← isPremiseDictInitialized) ∧ ¬ (← initPremiseDict) then
    return #[]
  let query ← encode input
  let topKSamples := FFI.ct2Retrieve query.data
  let topKPremises := topKSamples.map (·.1)
  let topKScores := topKSamples.map (·.2)
  return topKPremises.zip topKScores

end


def setConfig (config : Config) : CoreM Unit := do
  assert! config.isValid
  configRef.modify fun _ => config
  if ← isGeneratorInitialized then
    assert! ← initGenerator
  if ← isEncoderInitialized then
    assert! ← initEncoder
  if ← isPremiseEmbInitialized then
    assert! ← initPremiseEmb
  if ← isPremiseDictInitialized then
    assert! ← initPremiseDict


end LeanInfer
