import Lean
import LeanCopilot.Models.Builtin

set_option autoImplicit false

open Lean

namespace LeanCopilot

section


variable {m : Type → Type} [Monad m] [MonadOptions m] [MonadEnv m] [MonadLift IO m]


register_option LeanCopilot.verbose : Bool := {
  defValue := false
  descr := "Log various debugging information when running LeanCopilot."
}


def isVerbose : m Bool := do
  match LeanCopilot.verbose.get? (← getOptions) with
  | some true => return true
  | _ => return false


namespace SuggestTactics


register_option LeanCopilot.suggest_tactics.check : Bool := {
  defValue := true
  descr := "Check if the generated tactics are valid or if they can prove the goal."
}

def checkTactics : CoreM Bool := do
  match LeanCopilot.suggest_tactics.check.get? (← getOptions) with
  | some false => return false
  | _ => return true


register_option LeanCopilot.suggest_tactics.model : Name := {
  defValue := ``Builtin.generator
}


register_option LeanCopilot.select_premises.model : Name := {
  defValue := ``Builtin.generator
}


def getGeneratorName : m Name := do
  let name := match LeanCopilot.suggest_tactics.model.get? (← getOptions) with
  | some n => n
  | _ => ``Builtin.generator
  let env ← getEnv
  return env.find? name |>.get! |>.name


end SuggestTactics

end

end LeanCopilot
