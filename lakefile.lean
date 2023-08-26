import Lake
open Lake DSL

package «leanml» {
  -- add package configuration options here
}

lean_lib «Leanml» {
  -- add library configuration options here
}

@[default_target]
lean_exe «leanml» {
  root := `Main
}
