import Lean
import LeanInfer.Url

open Lean

set_option autoImplicit false

namespace LeanInfer

structure OnnxParams where
  modelUrl : HuggingFaceUrl
deriving Repr

def OnnxParams.isValid (params : OnnxParams) : Bool :=
  params.modelUrl.isValid

-- https://opennmt.net/CTranslate2/python/ctranslate2.Translator.html#translator
structure CTranslate2Params where
  modelUrl : HuggingFaceUrl
  device : String := "cpu"
  deviceIndex : UInt64 ⊕ (List UInt64) := .inl 0
  computeType : String := "default"
  interThreads : UInt64 := 1
  intraThreads : UInt64 := 0
deriving Repr

def isValidDevice (device : String) : Bool :=
  #["cpu", "cuda", "auto"].contains device

def isValidComputeType (computeType : String) : Bool :=
  #["default", "auto", "int8", "int8_float32", "int8_float16", "int8_bfloat16", "int16", "float16", "bfloat16", "float32"].contains computeType

def CTranslate2Params.isValid (params : CTranslate2Params) : Bool :=
  params.modelUrl.isValid ∧ isValidDevice params.device ∧ isValidComputeType params.computeType ∧ params.interThreads ≥ 1

inductive NativeBackend where
  | onnx : OnnxParams → NativeBackend
  | ct2 : CTranslate2Params → NativeBackend
deriving Repr

def NativeBackend.isValid : NativeBackend → Bool
  | .onnx params => params.isValid
  | .ct2 params => params.isValid

inductive IpcBackend where
  | ct2 : CTranslate2Params → IpcBackend
  | external (host : String) (port : UInt64) : IpcBackend
deriving Repr

def IpcBackend.isValid : IpcBackend → Bool
  | .ct2 params => params.isValid
  | .external .. => true

inductive Backend where
  | native : NativeBackend → Backend
  | ipc : IpcBackend → Backend
deriving Repr

def Backend.isValid : Backend → Bool
  | .native b => b.isValid
  | .ipc b => b.isValid

structure DecodingParams where
  numReturnSequences : UInt64
  beamSize : UInt64 := numReturnSequences
  minLength : UInt64 := 1
  maxLength : UInt64 := 256
  lengthPenalty : Float := 1.0
  patience : Float := 1.0
  temperature : Float := 1.0
deriving Repr

def DecodingParams.isValid (params : DecodingParams) : Bool :=
  params.numReturnSequences ≥ 1 ∧ params.beamSize ≥ 1 ∧ params.minLength ≥ 1 ∧ 
    params.maxLength ≥ params.minLength ∧ params.lengthPenalty ≥ 0.0 ∧ params.patience ≥ 1.0 ∧ params.temperature ≥ 0.0

structure Config where
  backend : Backend
  decoding : DecodingParams
deriving Repr

def Config.isValid (config : Config) : Bool :=
  config.backend.isValid ∧ config.decoding.isValid

def safeConfig : Config := {
  backend := .native $ .onnx {modelUrl := ⟨"kaiyuy", "onnx-leandojo-lean4-tacgen-byt5-small"⟩},
  decoding := {
    numReturnSequences := 8,
  }
}

instance : Inhabited Config := ⟨safeConfig⟩

def autoConfig : IO Config := do
  return safeConfig

initialize configRef : IO.Ref Config ← IO.mkRef (← autoConfig)

section

variable {m : Type → Type} [Monad m] [MonadLiftT IO m] [MonadLiftT (ST IO.RealWorld) m]

def getConfig : IO Config := configRef.get

def setConfig (config : Config) : IO Unit := do
  assert! config.isValid
  configRef.modify fun _ => config

def getBackend : m Backend := do
  return (← getConfig).backend

def getDecodingParams : m DecodingParams := do
  return (← getConfig).decoding

def getModelUrl : m (Option HuggingFaceUrl) := do
  match ← getBackend with
  | .native (.onnx params) => return params.modelUrl
  | .native (.ct2 params) => return params.modelUrl
  | .ipc _ => return none

end

end LeanInfer
