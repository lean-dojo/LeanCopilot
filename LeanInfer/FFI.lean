namespace LeanInfer.FFI

/--
Initialize the generator model backed by ONNX.
-/
@[extern "init_onnx_generator"]
opaque initOnnxGenerator (modelPath : @& String) : Bool 

@[extern "is_onnx_initialized"]
opaque isOnnxInitialized : Unit → Bool

@[extern "onnx_generate"]
opaque onnxGenerate (input : @& String) (numReturnSequences : UInt64) (maxLength : UInt64) 
(temperature : Float) (beamSize : UInt64) : Array (String × Float)

@[extern "onnx_encode"]
opaque onnxEncode (input : @& String) : FloatArray

@[extern "init_ct2_generator"]
opaque initCt2Generator (modelPath : @& String) : Bool 

@[extern "is_ct2_initialized"]
opaque isCt2Initialized : Unit → Bool

@[extern "ct2_generate"]
opaque ct2Generate (input : @& String) (numReturnSequences : UInt64) (beamSize : UInt64) 
  (minLength : UInt64) (maxLength : UInt64) (lengthPenalty : Float) (patience : Float) (temperature : Float) 
  : Array (String × Float)

end LeanInfer.FFI
