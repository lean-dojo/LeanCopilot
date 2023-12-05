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


structure DummyGenerator where
  output : String


instance : TextToText DummyGenerator where
  generate model _ _ := return #[(model.output, 1.0)]


structure DummyEncoder where
  output : FloatArray


instance : TextToVec DummyEncoder where
  encode model _ := return model.output


private def gen : DummyGenerator := ⟨"Hello, world!"⟩


example : generate gen "Hi!" = pure #[("Hello, world!", 1.0)] := by
  rfl


private def enc : DummyEncoder := ⟨FloatArray.mk #[1, 2, 3]⟩


example : encode enc "Hi!" = pure (FloatArray.mk #[1, 2, 3]) := by
  rfl


end LeanCopilot
