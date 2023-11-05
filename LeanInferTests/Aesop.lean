import LeanInfer
import Aesop

open LeanInfer

-- The example below wouldn't work without it.
@[aesop 100%]
def tacGen := LeanInfer.tacGen

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?
