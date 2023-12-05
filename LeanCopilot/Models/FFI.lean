import LeanCopilot.Models.Defs

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

@[extern "is_premise_embeddings_initialized"]
opaque isPremiseEmbeddingsInitialized : Unit → Bool

@[extern "init_premise_dictionary"]
opaque initPremiseDictionary (path : @& String) : Bool

@[extern "is_premise_dictionary_initialized"]
opaque isPremiseDictionaryInitialized : Unit → Bool

@[extern "retrieve"]
opaque retrieve (queryEmb : @& FloatArray) (k : UInt64) : Array (String × Float)

end FFI


namespace NativeGenerator


def generate (model : NativeGenerator) (input : String) (targetPrefix : String) : IO $ Array (String × Float) := do
  if ¬ FFI.isGeneratorInitialized model.name then
    let path ← model.path
    if ¬ (← path.pathExists) then
      throw $ IO.userError s!"Cannot find the model {model.name}. Please run `lake exe download {model.url}`."
    let device := toString model.device
    let computeType := toString model.computeType
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
    let device := toString model.device
    let computeType := toString model.computeType
    if ¬ (FFI.initEncoder model.name path.toString computeType device model.deviceIndex) then
      throw $ IO.userError s!"Failed to initialize model {model.name}"

  let tokenizer := model.tokenizer
  let inputTokens := tokenizer.tokenize input |>.push tokenizer.eosToken
  return FFI.encode model.name inputTokens


instance : TextToVec NativeEncoder where
  encode := NativeEncoder.encode


end NativeEncoder


end LeanCopilot
