namespace LeanCopilot

namespace FFI

@[extern "is_initialized"]
opaque isInitialized : (name : @& String) → Bool

@[extern "init_generator"]
opaque initGenerator (name : @& String) (modelPath : @& String) (device : @& String) (computeType : @& String) (deviceIndex : @& Array UInt64) : Bool

@[extern "init_encoder"]
opaque initEncoder (name : @& String) (modelPath : @& String) (device : @& String) (computeType : @& String) (deviceIndex : @& Array UInt64) : Bool

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

def init (model : NativeGenerator) : Bool := sorry


def generate (model : NativeGenerator) (input : String) : String := "hello"
/-
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
  tokensWithScores.filterMap fun ((ts, s) : Array String × Float) =>
    match detokenizeByt5 ts with
    | "aesop" => none
    | t => some (t, s)
-/


instance : TextToText NativeGenerator where
  generate := NativeGenerator.generate

end NativeGenerator

end LeanCopilot
