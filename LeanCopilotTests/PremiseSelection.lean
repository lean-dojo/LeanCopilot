import LeanCopilot


example (a b c : Nat) : a + b + c = a + c + b := by
  select_premises
  sorry


set_option LeanCopilot.select_premises.k 4

example (a b c : Nat) : a + b + c = a + c + b := by
  select_premises
  sorry
