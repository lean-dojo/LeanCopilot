import Lake
open Lake DSL System

package «leanml» {
  -- add package configuration options here
}

lean_lib «Leanml» {
  -- add library configuration options here
}

@[default_target]
lean_exe «leanml» {
  root := `Main
  -- supportInterpreter := true
}
