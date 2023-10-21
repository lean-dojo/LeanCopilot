import LeanInfer.Tactics
import Aesop

open Lean

namespace LeanInfer

def tacGen : Aesop.TacGen := fun (mvarId : MVarId) => do
  return ← generate (← ppTacticState [mvarId]) ""

end LeanInfer
