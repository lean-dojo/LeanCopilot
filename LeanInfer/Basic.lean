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


private def isRetrieverInitialized : m Bool := do
  match ← getBackend with
  | .native (.onnx _) => return unreachable!
  | .native (.ct2 _) => return FFI.isPremiseEmbeddingsInitialized ()
  | .ipc .. => unreachable!


def initRetriever : IO Bool := do
  let dir ← Cache.getPremiseEmbDir
  if ¬ (← dir.pathExists) then
    throw $ IO.userError "Cannot find the premise embeddings for retrieval. Please run [TODO]."
    return false

  match ← getBackend with
  | .native (.onnx _) => unreachable!
  | .native (.ct2 _) => assert! FFI.initPremiseEmbeddings dir.toString
  | .ipc .. => unreachable!

  return true


-- structure PremiseDict where
--   index : Nat
--   premise : String
-- deriving FromJson


-- def loadJsonDict (path: System.FilePath) : m (Array String) := do
--   let file ← IO.FS.readFile path
--   logInfo s!"{Lean.Json.parse file}"
--   -- match Json.parse file with
--   -- | Except.error err => panic! err
--   -- | Except.ok json => match (fromJson? json : Except String (Array PremiseDict)) with
--   --   | .error err => panic! err
--   --   | .ok dict => pure (dict.map (·.premise))
--   return Array.mkArray 152695 "NotImplemented"


-- def premiseLookup (index : UInt64) : m String := do
--   let dict ← loadJsonDict (← Cache.getPremiseDictDir)
--   -- logInfo s!"{(← Cache.getPremiseDictDir).toString}"
--   -- let dict := Array.mkArray 152695 "NotImplemented"
--   return dict.get! index.toNat
--   -- return "NotImplemented"


def retrieve (input : String) : m (Array (String × Float)) := do
  let query ← encode input
  -- logInfo s!"{query}"
  let topKPremises := FFI.ct2Retrieve query.data
  let topKIndices := topKPremises.map (·.2)
  -- For each index, look up the corresponding premise in the dictionary.
  -- let topKSuggestions ← topKIndices.mapM premiseLookup
  logInfo s!"topKIndices: {topKIndices}"
  -- logInfo s!"topKSuggestions: {topKSuggestions}"
  let topKScores := topKPremises.map (·.1)
  logInfo s!"topKScores: {topKScores}"
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
