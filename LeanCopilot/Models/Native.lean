import ModelCheckpointManager

set_option autoImplicit false

open System (FilePath)

namespace LeanCopilot


inductive Device where
  | cpu
  | cuda
  | auto
deriving Repr


instance : Inhabited Device where
  default := .auto


def Device.toString : Device → String
  | Device.cpu => "cpu"
  | Device.cuda => "cuda"
  | Device.auto => "auto"

instance : ToString Device := ⟨Device.toString⟩


inductive ComputeType where
  | default
  | auto
  | int8
  | int8_float32
  | int8_float16
  | int8_bfloat16
  | int16
  | float16
  | bfloat16
  | float32
deriving Repr


def ComputeType.toString : ComputeType → String
  | ComputeType.default => "default"
  | ComputeType.auto => "auto"
  | ComputeType.int8 => "int8"
  | ComputeType.int8_float32 => "int8_float32"
  | ComputeType.int8_float16 => "int8_float16"
  | ComputeType.int8_bfloat16 => "int8_bfloat16"
  | ComputeType.int16 => "int16"
  | ComputeType.float16 => "float16"
  | ComputeType.bfloat16 => "bfloat16"
  | ComputeType.float32 => "float32"


instance : ToString ComputeType := ⟨ComputeType.toString⟩


structure Tokenizer where
  tokenize : String → Array String
  detokenize : Array String → String
  eosToken : String


structure NativeModel where
  url : Url
  device : Device := .auto
  deviceIndex : Array UInt64 := #[0]
  computeType : ComputeType := .default
  tokenizer : Tokenizer


def NativeModel.name (model : NativeModel) : String := model.url.name!


def NativeModel.path (model : NativeModel) : IO FilePath :=
  getModelDir model.url


structure BeamSearchParams where
  numReturnSequences : UInt64
  beamSize : UInt64 := numReturnSequences
  minLength : UInt64 := 1
  maxLength : UInt64 := 1024
  lengthPenalty : Float := 0.0
  patience : Float := 2.0
  temperature : Float := 1.0
deriving Repr


structure NativeGenerator extends NativeModel where
  params : BeamSearchParams


structure NativeEncoder extends NativeModel


end LeanCopilot
