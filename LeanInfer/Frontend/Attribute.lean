import Lean

open Lean

namespace LeanInfer

/-
initialize registerBuiltinAttribute {
  name := `leaninfer
  descr := "Configure LeanInfer."
  applicationTime := .afterCompilation
  add := λ decl stx attrKind => withRef stx do
    assert! attrKind == AttributeKind.global
}
-/

end LeanInfer