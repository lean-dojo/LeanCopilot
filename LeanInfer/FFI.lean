namespace LeanInfer.FFI

@[extern "init_onnx_generator"]
opaque initOnnxGenerator (modelPath : @& String) : Bool

@[extern "is_onnx_generator_initialized"]
opaque isOnnxGeneratorInitialized : Unit → Bool

@[extern "onnx_generate"]
opaque onnxGenerate (input : @& String) (numReturnSequences : UInt64) (maxLength : UInt64)
(temperature : Float) (beamSize : UInt64) : Array (String × Float)

@[extern "init_ct2_generator"]
opaque initCt2Generator (modelPath : @& String) (device : @& String) (computeType : @& String) (deviceIndex : @& Array UInt64) (intraThreads : UInt64) : Bool

@[extern "is_ct2_generator_initialized"]
opaque isCt2GeneratorInitialized : Unit → Bool

@[extern "ct2_generate"]
opaque ct2Generate (inputTokens : @& Array String) (targetPrefixTokens : @& Array String) (numReturnSequences : UInt64) (beamSize : UInt64)
  (minLength : UInt64) (maxLength : UInt64) (lengthPenalty : Float) (patience : Float) (temperature : Float)
  : Array (Array String × Float)

@[extern "init_ct2_encoder"]
opaque initCt2Encoder (modelPath : @& String) : Bool

@[extern "is_ct2_encoder_initialized"]
opaque isCt2EncoderInitialized : Unit → Bool

@[extern "ct2_encode"]
opaque ct2Encode (inputTokens : @& Array String) : FloatArray

@[extern "init_premise_embeddings"]
opaque initPremiseEmbeddings (matrixPath : @& String) : Bool

@[extern "is_premise_embeddings_initialized"]
opaque isPremiseEmbeddingsInitialized : Unit → Bool

@[extern "ct2_retrieve"]
opaque ct2Retrieve (encodedState : @& Array Float) : FloatArray

end LeanInfer.FFI
