import Lean
import LeanCopilot

open Lean Meta LeanCopilot


/-
## Basic Usage
-/

example (a b c : Nat) : a + b + c = c + b + a := by
  search_proof


/-
## Advanced Usage
-/


example (a b c : Nat) : a + b + c = c + b + a := by
  try aesop?
  sorry


#configure_llm_aesop


example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?


set_option trace.aesop true


example (a b c : Nat) : a + b + c = c + b + a := by
  try aesop? (config := { maxRuleApplications := 2 })
  try sorry
