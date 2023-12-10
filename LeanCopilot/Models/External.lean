import Lean
import LeanCopilot.Models.Interface

set_option autoImplicit false

open Lean

namespace LeanCopilot


structure ExternalModel where
  name : String
  host : String := "localhost"
  port : UInt16 := 23337
deriving Inhabited, Repr


structure ExternalGenerator extends ExternalModel
deriving Repr


structure GeneratorRequest where
  name : String
  input : String
  «prefix» : String
deriving ToJson


structure Generation where
  output: String
  score: Float
deriving FromJson


structure GeneratorResponse where
  outputs : Array Generation
deriving FromJson


structure EnencoderRequest where
  name : String
  input : String
deriving ToJson


structure EncoderResponse where
  outputs : Array Float
deriving FromJson


def send {α β : Type} [ToJson α] [FromJson β] (req : α) (url : String) : IO β := do
  let reqStr := (toJson req).pretty 99999999999999999
  let out ← IO.Process.output {
    cmd := "curl"
    args := #["-X", "POST", url, "-H", "accept: application/json", "-H", "Content-Type: application/json", "-d", reqStr]
  }
  if out.exitCode != 0 then
     throw $ IO.userError s!"Request failed. Please check if the server is up at `{url}`."
  let some json := Json.parse out.stdout |>.toOption
    | throw $ IO.userError "Failed to parse response"
  let some res := (fromJson? json : Except String β) |>.toOption
    | throw $ IO.userError "Failed to parse response"
  return res


def ExternalGenerator.generate (model : ExternalGenerator) (input : String) (targetPrefix : String) : IO $ Array (String × Float) := do
  let url := s!"http://{model.host}:{model.port}/generate"
  let req : GeneratorRequest := {
    name := model.name,
    input := input,
    «prefix» := targetPrefix
  }
  let res : GeneratorResponse ← send req url
  return res.outputs.map fun g => (g.output, g.score)


instance : TextToText ExternalGenerator := ⟨ExternalGenerator.generate⟩


structure ExternalEncoder extends ExternalModel
deriving Repr


def ExternalEncoder.encode (model : ExternalEncoder) (input : String) : IO FloatArray := do
  let url := s!"http://{model.host}:{model.port}/encode"
  let req : EnencoderRequest := {
    name := model.name,
    input := input,
  }
  let res : EncoderResponse ← send req url
  return FloatArray.mk res.outputs


instance : TextToVec ExternalEncoder := ⟨ExternalEncoder.encode⟩


end LeanCopilot
