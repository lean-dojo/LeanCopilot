import LeanCopilot

/-!
A minimal `lean_exe` that depends on Lean Copilot.

This exists purely so CI actually link-tests a `lean_exe` target against
`libleanffi.a`, not just the `lean_lib` targets in the rest of this
directory. A `lean_exe`'s final link (unlike a `lean_lib`'s `.so`, which
tolerates undefined symbols resolved later at load time) requires every
symbol resolved up front, which is exactly what broke on Linux in
https://github.com/lean-dojo/LeanCopilot/issues/196. `LeanCopilotTests`
alone never caught that regression because it is a `lean_lib`.
-/

def main : IO Unit :=
  IO.println "Lean Copilot lean_exe smoke test OK"
