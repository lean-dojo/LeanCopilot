import Lake
open Lake DSL System


package «leanml» {
  precompileModules := true
  buildType := BuildType.debug  -- TODO: Change to release.
  moreLinkArgs := #["-lonnxruntime"]
}


@[default_target]
lean_lib «Leanml» {
}


target ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi.o"
  let srcJob ← inputFile <| pkg.dir / "ffi.cpp"
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #[
    "-fPIC", "-std=c++11", optLevel,
    "-I", (← getLeanIncludeDir).toString
  ]
  buildO "ffi.cpp" oFile srcJob flags "c++"


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ffiO ← fetch <| pkg.target ``ffi.o
  buildStaticLib (pkg.nativeLibDir / name) #[ffiO]
