namespace LeanInfer

inductive NativeBackend where
  | onnxRuntime : NativeBackend
  | cTranslate2 : NativeBackend

structure IpcBackend where
  host : String
  port : UInt32

inductive Backend where
  | native : NativeBackend → Backend
  | ipc : IpcBackend → Backend

structure DecodingParams where

structure Config where
  backend : Backend
  decoding : DecodingParams

def safeConfig : Config := {
  backend := .native .onnxRuntime,
  decoding := DecodingParams.mk
}

def autoConfig : IO Config := sorry

end LeanInfer
