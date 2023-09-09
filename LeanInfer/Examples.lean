import LeanInfer.Basic

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics
  sorry