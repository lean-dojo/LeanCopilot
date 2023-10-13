import Lean

open Lean

namespace LeanInfer

-- https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html#translator
structure CTranslate2Params where
  modelPath : String
  device : String := "cpu"
  deviceIndex : UInt64 ⊕ (List UInt64) := .inl 0
  computeType : String := "default"
  interThreads : UInt64 := 1
  intraThreads : UInt64 := 0
deriving Repr

inductive NativeBackend where
  | onnx : NativeBackend
  | ct2 : CTranslate2Params → NativeBackend
deriving Repr

inductive IpcBackend where
  | ct2 : CTranslate2Params → IpcBackend
  | external (host : String) (port : UInt64) : IpcBackend
deriving Repr

inductive Backend where
  | native : NativeBackend → Backend
  | ipc : IpcBackend → Backend
deriving Repr

structure DecodingParams where
  numReturnSequences : UInt64
  beamSize : UInt64 := numReturnSequences
  minLength : UInt64 := 1
  maxLength : UInt64 := 256
  lengthPenalty : Float := 1.0
  patience : Float := 1.0
  temperature : Float := 1.0
deriving Repr

structure Config where
  backend : Backend
  decoding : DecodingParams
deriving Repr

def safeConfig : Config := {
  backend := .native .onnx,
  decoding := {
    numReturnSequences := 8,
  }
}

instance : Inhabited Config := ⟨safeConfig⟩

def autoConfig : IO Config := do
  return safeConfig

initialize _config : Config ← autoConfig

def getConfig : CoreM Config := do
  return _config

end LeanInfer
