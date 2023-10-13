namespace LeanInfer.FFI

@[extern "init_generator"]
opaque initGenerator (modelPath : @& String) : Bool 

@[extern "is_initialized"]
opaque isInitialized : Unit → Bool

@[extern "generate"]
opaque generate (input : @& String) (numReturnSequences : UInt64) (maxLength : UInt64) 
(temperature : Float) (beamSize : UInt64) : Array (String × Float)

@[extern "encode"]
opaque encode (input : @& String) : FloatArray

end LeanInfer.FFI
