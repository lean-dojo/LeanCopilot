import LeanCopilot.Models.Native
import LeanCopilot.Models.External
import LeanCopilot.Models.Generic
import LeanCopilot.Models.Builtin
import LeanCopilot.Models.FFI
import Std.Data.HashMap

set_option autoImplicit false

open Std

namespace LeanCopilot


inductive Generator where
  | native : NativeGenerator → Generator
  | external : ExternalGenerator → Generator
  | generic : GenericGenerator → Generator


instance : TextToText Generator where
  generate (model : Generator) (input : String) (targetPrefix : String) :=
    match model with
    | .native ng => ng.generate input targetPrefix
    | .external eg => eg.generate input targetPrefix
    | .generic gg => gg.generate input targetPrefix


inductive Encoder where
  | native : NativeEncoder → Encoder
  | external : ExternalEncoder → Encoder
  | generic : GenericEncoder → Encoder


instance : TextToVec Encoder where
  encode (model : Encoder) (input : String) :=
    match model with
    | .native ne => ne.encode input
    | .external ee => ee.encode input
    | .generic ge => ge.encode input


instance {α β : Type} [BEq α] [Hashable α] [Repr α] [Repr β] : Repr (HashMap α β) where
  reprPrec hm n := reprPrec hm.toList n


structure ModelRegistry where
  generators : HashMap String Generator :=
    HashMap.ofList [(Builtin.generator.name, .native Builtin.generator)]
  encoders : HashMap String Encoder :=
    HashMap.ofList [(Builtin.encoder.name, .native Builtin.encoder)]


namespace ModelRegistry


def generatorNames (mr : ModelRegistry) : List String :=
  mr.generators.toList.map (·.1)


def encoderNames (mr : ModelRegistry) : List String :=
  mr.encoders.toList.map (·.1)


def modelNames (mr : ModelRegistry) : List String :=
  mr.generatorNames ++ mr.encoderNames


end ModelRegistry


instance : Repr ModelRegistry where
  reprPrec mr n := reprPrec mr.modelNames n


instance : Inhabited ModelRegistry where
  default := {}


initialize modelRegistryRef : IO.Ref ModelRegistry ← IO.mkRef default


def getModelRegistry : IO ModelRegistry := modelRegistryRef.get


def getGenerator (name : String) : IO Generator := do
  let mr ← getModelRegistry
  match mr.generators.find? name with
  | some descr => return descr
  | none => throw $ IO.userError s!"unknown generator: {name}"


def getEncoder (name : String) : IO Encoder := do
  let mr ← getModelRegistry
  match mr.encoders.find? name with
  | some descr => return descr
  | none => throw $ IO.userError s!"unknown encoder: {name}"


def registerGenerator (name : String) (model : Generator) := do
  let mr ← getModelRegistry
  modelRegistryRef.modify fun _ =>
    {mr with generators := mr.generators.insert name model}


end LeanCopilot
