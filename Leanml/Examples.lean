import Leanml.Basic

example (a b c : Nat) : a + b + c = a + c + b := by
  trace_goal_state
  rw [Nat.add_assoc, Nat.add_comm b, ←Nat.add_assoc]