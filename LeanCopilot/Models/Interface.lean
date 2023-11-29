set_option autoImplicit false

namespace LeanCopilot


class TextToText (τ : Type) where
  generate : τ → String → String


class TextToVec (τ : Type) where
  encode : τ → String → FloatArray


def generate {τ : Type} [TextToText τ] (model : τ) (input : String) : String :=
  TextToText.generate model input


def encode {τ : Type} [TextToVec τ] (model : τ) (input : String) : FloatArray :=
  TextToVec.encode model input


structure DummyGenerator where
  output : String


instance : TextToText DummyGenerator where
  generate model _ := model.output


structure DummyEncoder where
  output : FloatArray


instance : TextToVec DummyEncoder where
  encode model _ := model.output


private def gen : DummyGenerator := ⟨"Hello, world!"⟩


example : generate gen "Hi!" = "Hello, world!" := by
  rfl


private def enc : DummyEncoder := ⟨FloatArray.mk #[1, 2, 3]⟩


example : encode enc "Hi!" = FloatArray.mk #[1, 2, 3] := by
  rfl


end LeanCopilot
