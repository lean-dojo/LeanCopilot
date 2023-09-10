import Lake
open Lake DSL System

package LeanInfer {
  preferReleaseBuild := true
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #["-lonnxruntime", "-lstdc++"]
}

@[default_target]
lean_lib LeanInfer {
}

lean_lib Examples {
}

target ffi.o pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi.o"
  let srcJob ← inputFile <| pkg.dir / "ffi.cpp"
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #[
    "-fPIC", "-std=c++11", "-stdlib=libc++", optLevel,
    "-I", (← getLeanIncludeDir).toString
  ]
  buildO "ffi.cpp" oFile srcJob flags "clang++"

extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ffiO ← fetch <| pkg.target ``ffi.o
  buildStaticLib (pkg.nativeLibDir / name) #[ffiO]

require std from git "https://github.com/leanprover/std4" @ "main"

def checkClang : IO Bool := do
  let output ← IO.Process.output {
    cmd := "clang++", args := #["--version"]
  }
  return output.exitCode == 0

partial def contains (s : String) (sub : String) : Bool :=
  if s.length < sub.length then
    false
  else if s.startsWith sub then
    true
  else
    contains (s.drop 1) sub

def checkOnnxLib : IO Bool := do
  let output ← IO.Process.output {
    cmd := "clang++", args := #["-lonnxruntime"]
  }
  return !(contains output.stderr "cannot find -lonnxruntime")

-- Check whether the directory "./onnx-leandojo-lean4-tacgen-byt5-small" exists
def checkModel : IO Bool := do 
  let path : FilePath := ⟨"onnx-leandojo-lean4-tacgen-byt5-small"⟩
  return (← path.pathExists) && (← path.isDir)

script check do
  if !(← checkClang) then
    throw $ IO.userError "Clang++ not found"
  if !(← checkOnnxLib) then
    throw $ IO.userError "ONNX Runtime library not found"
  if !(← checkModel) then
    throw $ IO.userError "The ONNX model not found"
  println! "Looks good to me! Try `lake build`."
  return 0
