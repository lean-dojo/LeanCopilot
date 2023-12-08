import Lean
import LeanCopilot.Models.Interface

set_option autoImplicit false

open Lean

namespace LeanCopilot


structure ExternalModel where
  name : String
  host : String := "localhost"
  port : UInt16 := 23333
deriving Inhabited, Repr


structure ExternalGenerator extends ExternalModel
deriving Repr


structure ExternalRequest where
  name : String
  input : String
  «prefix» : String
deriving ToJson


structure ExternalResponse where
  outputs : Array (String × Float)
deriving FromJson


def ExternalGenerator.generate (model : ExternalGenerator) (input : String) (targetPrefix : String) : IO $ Array (String × Float) := do
  let url := s!"http://{model.host}:{model.port}/generate"
  let req : ExternalRequest := {
    name := model.name,
    input := input,
    «prefix» := targetPrefix
  }
  let reqStr := (toJson req).pretty 99999999999999999
  let out ← IO.Process.run {
    cmd := "curl"
    args := #["-X", "POST", url, "-H", "accept: application/json", "-H", "Content-Type: application/json", "-d", reqStr]
  }

  let some json := Json.parse out |>.toOption | throw $ IO.userError "Failed to parse response"
  let some res := (fromJson? json : Except String ExternalResponse) |>.toOption | throw $ IO.userError "Failed to parse response"
  return res.outputs


instance : TextToText ExternalGenerator := ⟨ExternalGenerator.generate⟩


structure ExternalEncoder extends ExternalModel
deriving Repr


def ExternalEncoder.encode (model : ExternalEncoder) (input : String) : IO FloatArray := sorry


instance : TextToVec ExternalEncoder := ⟨ExternalEncoder.encode⟩


end LeanCopilot
