import Lean
import LeanInfer.Config

open Lean

namespace LeanInfer

unsafe def evalConfigImpl (name : Name) : CoreM Config := 
  evalConst Config name

@[implemented_by evalConfigImpl]
opaque evalConfig (name : Name) : CoreM Config

initialize registerBuiltinAttribute {
  name := `leaninfer
  descr := "Configure LeanInfer."
  applicationTime := .afterCompilation
  add := fun name stx attrKind => withRef stx do
    assert! attrKind == AttributeKind.global
    modifyEnv fun env => {
      env with constants := env.constants.insert ``_config $  env.constants.find! name
    }
    -- mkDefinitionValEx name [] config 
    -- addDecl 
     
}

end LeanInfer