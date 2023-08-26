import Lake
open Lake DSL System

package «leanml» {
  -- add package configuration options here
  precompileModules := true
  moreLinkArgs := #[
    "-L", "/home/peiyang/onnxruntime/build/Linux/RelWithDebInfo", "-lonnxruntime"
  ]
}

lean_lib «Leanml» {
  -- add library configuration options here
  -- moreLinkArgs := #[
  --   "-L", "/home/peiyang/onnxruntime/build/Linux/RelWithDebInfo", "-lonnxruntime"
  -- ]
}

@[default_target]
lean_exe «leanml» {
  root := `Leanml
}

target ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi.o"
  let srcJob ← inputFile <| pkg.dir / "ffi.cpp"
  let flags := #[
    "-Wno-deprecated-declarations", "-fPIC", "-DDS_VERSION=\"5.0.0\"", "-DBOOST_ALL_DYN_LINK", "-O0",
    "-I", (← getLeanIncludeDir).toString, 
    "-I", "/home/peiyang/onnxruntime/include", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/common", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/common/logging", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/framework", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/graph", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/optimizer", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/platform", 
    "-I", "/home/peiyang/onnxruntime/include/onnxruntime/core/session", 
    "-stdlib=libc++"
  ]
  buildO "ffi.cpp" oFile srcJob flags "clang++"

extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ffiO ← fetch <| pkg.target ``ffi.o
  let nativeLibDir : FilePath := "build" / "lib" 
  buildStaticLib (nativeLibDir / name) #[ffiO]
