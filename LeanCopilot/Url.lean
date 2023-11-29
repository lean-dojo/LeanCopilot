import Lean

open System (FilePath)

set_option autoImplicit false

namespace LeanCopilot


def HF_BASE_URL := "https://huggingface.co"


structure HuggingFaceURL where
  user : Option String
  modelName : String
deriving Inhabited


def HuggingFaceURL.name : HuggingFaceURL → String
  | ⟨none, nm⟩ => nm
  | ⟨some u, nm⟩ => s!"{u}/{nm}"


instance : ToString HuggingFaceURL where
  toString url := s!"{HF_BASE_URL}/{url.name}"


instance : Repr HuggingFaceURL where
  reprPrec url x := reprPrec (toString url) x


def HuggingFaceURL.isValid (url : HuggingFaceURL) : Bool :=
  let validModelName := ¬ url.modelName.isEmpty ∧ ¬ url.modelName.contains '/'
  let validUser : Bool := match url.user with
  | none => true
  | some username => ¬ username.isEmpty ∧ ¬ username.contains '/'
  validModelName ∧ validUser


end LeanCopilot
