import Lean

open System (FilePath)

set_option autoImplicit false

namespace LeanInfer

def HF_BASE_URL := "https://huggingface.co"

structure HuggingFaceURL where
  user : Option String
  modelName : String
deriving Inhabited

instance : ToString HuggingFaceURL where
  toString url := match url.user with
  | none => s!"{HF_BASE_URL}/{url.modelName}"
  | some user => s!"{HF_BASE_URL}/{user}/{url.modelName}"

instance : Repr HuggingFaceURL where
  reprPrec url x := reprPrec (toString url) x

def HuggingFaceURL.isValid (url : HuggingFaceURL) : Bool :=
  let validModelName := ¬ url.modelName.isEmpty ∧ ¬ url.modelName.contains '/'
  let validUser : Bool := match url.user with
  | none => true
  | some username => ¬ username.isEmpty ∧ ¬ username.contains '/'
  validModelName ∧ validUser

end LeanInfer
