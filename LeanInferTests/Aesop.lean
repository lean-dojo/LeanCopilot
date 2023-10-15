import LeanInfer
import Aesop

open Lean

-- set_option aesop.check.all true
-- set_option trace.aesop.tree true
-- set_option trace.aesop true  
-- all three flags are for debugging purpose, not necessarily needed.
-- set_option maxHeartbeats 0 -- disable timeout

/-
@[aesop 100%]
def tacGen := LeanInfer.tacGen

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop
-/
