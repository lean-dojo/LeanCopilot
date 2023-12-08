import Lean
import LeanCopilot

open Lean Meta
open LeanCopilot


example (a b c : Nat) : a + b + c = a + c + b := by
  select_premises
  sorry
