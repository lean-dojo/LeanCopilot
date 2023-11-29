import LeanCopilot.Url
import LeanCopilot.Models.Interface

set_option autoImplicit false

namespace LeanCopilot


inductive Device where
  | cpu
  | cuda
  | auto
deriving Repr


instance : Inhabited Device where
  default := .auto


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
deriving Inhabited, Repr


instance : Inhabited ComputeType where
  default := .auto


structure Model where
  isInitialized : Bool := false
deriving Repr


instance : Inhabited Model where
  default := {}


structure NativeModel extends Model where
  url : HuggingFaceURL
  device : Device := default
  deviceIndex : Array UInt64 := #[0]
  computeType : ComputeType := default
  hasLocalCopy : Bool := false
deriving Repr


instance : Inhabited NativeModel where
  default := {url := default}


def NativeModel.name (model : NativeModel) : String := model.url.name


structure NativeGenerator extends NativeModel
deriving Repr


structure NativeEncoder extends NativeModel
deriving Repr


def NativeEncoder.encode (enc : NativeEncoder) (input : String) : FloatArray :=
  FloatArray.empty


structure ExternalModel extends Model where
  name : String
deriving Inhabited, Repr


structure ExternalGenerator extends ExternalModel
deriving Repr


structure ExternalEncoder extends ExternalModel
deriving Repr


end LeanCopilot
