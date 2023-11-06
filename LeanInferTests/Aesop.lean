import LeanInfer
import Aesop

open LeanInfer

-- The example below wouldn't work without it.
@[aesop 100%]
def tacGen := LeanInfer.tacGen

-- Downlaod the model to `~/.cache/lean_infer` if it's not available locally.
#eval Cache.checkGenerator

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?
