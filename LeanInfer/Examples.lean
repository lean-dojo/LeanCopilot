import LeanInfer.Basic

example (a b c : Nat) : a + b + c = a + c + b := by
  suggest_tactics ""
  sorry
  -- rw [Nat.add_assoc, Nat.add_comm b, ←Nat.add_assoc]
