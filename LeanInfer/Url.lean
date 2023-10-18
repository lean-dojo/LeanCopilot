import Lean

open System (FilePath)

set_option autoImplicit false

namespace LeanInfer

def HF_BASE_URL := "https://huggingface.co"

structure HuggingFaceUrl where
  user : Option String
  modelName : String

instance : ToString HuggingFaceUrl where
  toString url := match url.user with
  | none => s!"{HF_BASE_URL}/{url.modelName}"
  | some user => s!"{HF_BASE_URL}/{user}/{url.modelName}"

instance : Repr HuggingFaceUrl where
  reprPrec url x := reprPrec (toString url) x

def HuggingFaceUrl.isValid (url : HuggingFaceUrl) : Bool :=
  let validModelName := ¬ url.modelName.isEmpty ∧ ¬ url.modelName.contains '/'
  let validUser : Bool := match url.user with
  | none => true
  | some username => ¬ username.isEmpty ∧ ¬ username.contains '/'
  validModelName ∧ validUser

end LeanInfer