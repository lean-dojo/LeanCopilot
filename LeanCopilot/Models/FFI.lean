import LeanCopilot.Models.Defs
import LeanCopilot.Models.Builtin

namespace LeanCopilot

set_option autoImplicit false

namespace FFI

@[extern "is_generator_initialized"]
opaque isGeneratorInitialized : (name : @& String) → Bool

@[extern "is_encoder_initialized"]
opaque isEncoderInitialized : (name : @& String) → Bool

@[extern "init_generator"]
opaque initGenerator (name : @& String) (modelPath : @& String) (computeType : @& String) (device : @& String) (deviceIndex : @& Array UInt64) : Bool

@[extern "init_encoder"]
opaque initEncoder (name : @& String) (modelPath : @& String) (computeType : @& String) (device : @& String) (deviceIndex : @& Array UInt64) : Bool

@[extern "generate"]
opaque generate (name : @& String) (inputTokens : @& Array String) (targetPrefixTokens : @& Array String) (numReturnSequences : UInt64) (beamSize : UInt64)
  (minLength : UInt64) (maxLength : UInt64) (lengthPenalty : Float) (patience : Float) (temperature : Float)
  : Array (Array String × Float)

@[extern "encode"]
opaque encode (name : @& String) (inputTokens : @& Array String) : FloatArray

@[extern "init_premise_embeddings"]
opaque initPremiseEmbeddings (path : @& String) (device : @& String) : Bool

@[extern "premise_embeddings_initialized"]
opaque premiseEmbeddingsInitialized : Unit → Bool

@[extern "init_premise_dictionary"]
opaque initPremiseDictionary (path : @& String) : Bool

@[extern "premise_dictionary_initialized"]
opaque premiseDictionaryInitialized : Unit → Bool

@[extern "retrieve"]
opaque retrieve (queryEmb : @& FloatArray) (k : UInt64) : Array (String × String × String × Float)

@[extern "cuda_available"]
opaque cudaAvailable : Unit → Bool

end FFI


def cudaAvailable : Bool := FFI.cudaAvailable ()


namespace NativeGenerator


def generate (model : NativeGenerator) (input : String) (targetPrefix : String) : IO $ Array (String × Float) := do
  if ¬ FFI.isGeneratorInitialized model.name then
    let path ← model.path
    if ¬ (← path.pathExists) then
      throw $ IO.userError s!"Cannot find the model {model.name}. Please run `lake exe download {model.url}`."
    let device := model.device.toString
    let computeType := model.computeType.toString
    if ¬ (FFI.initGenerator model.name path.toString computeType device model.deviceIndex) then
      throw $ IO.userError s!"Failed to initialize model {model.name}"

  let tokenizer := model.tokenizer
  let inputTokens := tokenizer.tokenize input |>.push tokenizer.eosToken
  let targetPrefixTokens := tokenizer.tokenize targetPrefix
  let numReturnSequences := model.params.numReturnSequences
  let beamSize := model.params.beamSize
  let minLength := model.params.minLength
  let maxLength := model.params.maxLength
  let lengthPenalty := model.params.lengthPenalty
  let patience := model.params.patience
  let temperature := model.params.temperature
  let tokensWithScores := FFI.generate model.name inputTokens targetPrefixTokens numReturnSequences beamSize minLength maxLength lengthPenalty patience temperature

  return tokensWithScores.filterMap fun ((ts, s) : Array String × Float) =>
    match tokenizer.detokenize ts with
    | "aesop" => none
    | t => some (t, s)



instance : TextToText NativeGenerator where
  generate := NativeGenerator.generate


end NativeGenerator


namespace NativeEncoder


def encode (model : NativeEncoder) (input : String) : IO FloatArray := do
  if ¬ FFI.isEncoderInitialized model.name then
    let path ← model.path
    if ¬ (← path.pathExists) then
      throw $ IO.userError s!"Cannot find the model {model.name}. Please run `lake exe download {model.url}`."
    let device := model.device.toString
    let computeType := model.computeType.toString
    if ¬ (FFI.initEncoder model.name path.toString computeType device model.deviceIndex) then
      throw $ IO.userError s!"Failed to initialize model {model.name}"

  let tokenizer := model.tokenizer
  let inputTokens := tokenizer.tokenize input |>.push tokenizer.eosToken
  return FFI.encode model.name inputTokens


instance : TextToVec NativeEncoder where
  encode := NativeEncoder.encode


end NativeEncoder


def premiseEmbeddingsInitialized : IO Bool := do
  return FFI.premiseEmbeddingsInitialized ()


def initPremiseEmbeddings (device : Device) : IO Bool := do
  let path := (← getModelDir Builtin.premiseEmbeddingsUrl) / "embeddings.npy"
  if ¬ (← path.pathExists) then
    throw $ IO.userError "Cannot find the premise embeddings. Please run `lake exe download {Builtin.premiseEmbeddingsUrl}`."
    return false
  return FFI.initPremiseEmbeddings path.toString device.toString


def premiseDictionaryInitialized : IO Bool := do
  return FFI.premiseDictionaryInitialized ()


def initPremiseDictionary : IO Bool := do
  let path := (← getModelDir Builtin.premiseEmbeddingsUrl) / "dictionary.json"
  if ¬ (← path.pathExists) then
    throw $ IO.userError "Cannot find the premise dictionary. Please run `lake exe download {Builtin.premiseEmbeddingsUrl}`."
    return false
  return FFI.initPremiseDictionary path.toString


end LeanCopilot
