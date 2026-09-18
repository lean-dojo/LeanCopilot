import LeanCopilot

inductive Maybe (α : Type) where
  | nothing : Maybe α
  | just : α → Maybe α

namespace Maybe

def map (f : α → β) : Maybe α → Maybe β
  | nothing => nothing
  | just value => just (f value)

instance : Functor Maybe where
  map := Maybe.map

end Maybe

instance : LawfulFunctor Maybe where
  map_const := by
    intros
    rfl
  id_map := by
    search_proof
  comp_map := by
    intro α β γ g h x
    cases x <;> rfl

private def checkNativeGenerationErrorsAreCaught : IO Unit := do
  try
    let _ ← LeanCopilot.FFI.generate "uninitialized-test-model" #[] #[] 1 1 1 1 0.0 1.0 1.0
    throw <| IO.userError "expected native generation to fail"
  catch e =>
    if !e.toString.startsWith "CTranslate2 generation failed:" then
      throw e

#eval checkNativeGenerationErrorsAreCaught
