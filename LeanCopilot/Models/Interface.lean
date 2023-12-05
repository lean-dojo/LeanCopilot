set_option autoImplicit false

namespace LeanCopilot


class TextToText (τ : Type) where
  generate (model : τ) (input : String) (targetPrefix : String) : IO $ Array (String × Float)


class TextToVec (τ : Type) where
  encode : τ → String → IO FloatArray


def generate {τ : Type} [TextToText τ] (model : τ) (input : String) (targetPrefix : String := "") : IO $ Array (String × Float) :=
  TextToText.generate model input targetPrefix


def encode {τ : Type} [TextToVec τ] (model : τ) (input : String) : IO FloatArray :=
  TextToVec.encode model input


end LeanCopilot
