import LeanCopilot.Models.Interface

set_option autoImplicit false

namespace LeanCopilot


structure GenericGenerator where
  generate : String → String → IO (Array (String × Float))


instance : TextToText GenericGenerator := ⟨GenericGenerator.generate⟩


structure GenericEncoder where
  encode : String → IO FloatArray


instance : TextToVec GenericEncoder := ⟨GenericEncoder.encode⟩


end LeanCopilot
