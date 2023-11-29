import LeanCopilot.Models.Interface
import LeanCopilot.Models.Defs
import LeanCopilot.Models.Registry
import LeanCopilot.Models.FFI


open LeanCopilot

#eval (getModelRegistry : IO _)

#eval generate defaultGenerator "Hi!"
