import LeanCopilot
import Aesop

-- The example below wouldn't work without it.
#init_llm_aesop

example (a b c : Nat) : a + b + c = c + b + a := by
  aesop?
