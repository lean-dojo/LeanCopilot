import LeanCopilot.Models.Defs
import LeanCopilot.Models.Builtin
import Std.Data.HashMap

set_option autoImplicit false

open Std

namespace LeanCopilot


instance {α β : Type} [BEq α] [Hashable α] [Repr α] [Repr β] : Repr (HashMap α β) where
  reprPrec hm n := reprPrec hm.toList n


structure NativeModelRegistry where
  generators : HashMap String NativeGenerator :=
    HashMap.ofList [(Builtin.generator.name, Builtin.generator)]
  encoders : HashMap String NativeEncoder :=
    HashMap.ofList [(Builtin.encoder.name, Builtin.encoder)]


instance : Inhabited NativeModelRegistry where
  default := {}


structure ExternalModelRegistry where
  host : String := "localhost"
  port : UInt16 := 23333
  generators : HashMap String ExternalGenerator := {}
  encoders : HashMap String ExternalEncoder := {}
deriving Repr


instance : Inhabited ExternalModelRegistry where
  default := {}


structure ModelRegistry where
  native : NativeModelRegistry
  external : ExternalModelRegistry
deriving Inhabited


initialize modelRegistryRef : IO.Ref ModelRegistry ← IO.mkRef default


def getModelRegistry : ST IO.RealWorld ModelRegistry := modelRegistryRef.get


end LeanCopilot
