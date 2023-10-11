namespace LeanInfer

-- https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html#translator
structure CTranslate2Params where
  modelPath : String
  device : String := "cpu"
  deviceIndex : UInt32 ⊕ (List UInt32) := .inl 0
  computeType : String := "default"
  interThreads : UInt32 := 1
  intraThreads : UInt32 := 0
deriving Repr, Inhabited

inductive NativeBackend where
  | onnx : NativeBackend
  | ct2 : CTranslate2Params → NativeBackend
deriving Repr, Inhabited

inductive IpcBackend where
  | ct2 : CTranslate2Params → IpcBackend
  | external (host : String) (port : UInt32) : IpcBackend
deriving Repr, Inhabited

inductive Backend where
  | native : NativeBackend → Backend
  | ipc : IpcBackend → Backend
deriving Repr, Inhabited

structure DecodingParams where
  numReturnSequences : UInt32
  beamSize : UInt32 := numReturnSequences
  minLength : UInt32 := 1
  maxLength : UInt32 := 256
  lengthPenalty : Float := 1.0
  patience : Float := 1.0
deriving Repr, Inhabited

structure Config where
  backend : Backend
  decoding : DecodingParams
deriving Repr, Inhabited

def safeConfig : Config := {
  backend := .native .onnx,
  decoding := {
    numReturnSequences := 8,
  }
}

def autoConfig : IO Config := do
  return safeConfig

-- initialize config : Config ← autoConfig

end LeanInfer
