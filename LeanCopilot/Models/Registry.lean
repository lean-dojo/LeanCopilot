import LeanCopilot.Models.Defs
import Std.Data.HashMap

set_option autoImplicit false

open Std

namespace LeanCopilot


def defaultGenerator : NativeGenerator := {
  url := ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩
}


def defaultEncoder : NativeEncoder := {
  url := ⟨"kaiyuy", "ct2-leandojo-lean4-retriever-byt5-small"⟩
}


instance {α β : Type} [BEq α] [Hashable α] [Repr α] [Repr β] : Repr (HashMap α β) where
  reprPrec hm n := reprPrec hm.toList n


structure NativeModelRegistry where
  generators : HashMap String NativeGenerator :=
    HashMap.ofList [(defaultGenerator.name, defaultGenerator)]
  encoders : HashMap String NativeEncoder :=
    HashMap.ofList [(defaultEncoder.name, defaultEncoder)]
deriving Repr


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
deriving Inhabited, Repr


initialize modelRegistryRef : IO.Ref ModelRegistry ← IO.mkRef default


def getModelRegistry : ST IO.RealWorld ModelRegistry := modelRegistryRef.get


end LeanCopilot
