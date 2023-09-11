import Lake
open Lake DSL System

package LeanInfer {
  preferReleaseBuild := true
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #["-L./build/lib", "-lonnxruntime", "-lstdc++"]
  moreLeanArgs := #["--load-dynlib=./build/lib/libonnxruntime.dylib"]
}

@[default_target]
lean_lib LeanInfer {
}

lean_lib Examples {
}

def cc := "clang++"

target generator.o pkg : FilePath := do
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString]
  let build := do
    let oFile := pkg.buildDir / "cpp/generator.o"
    let srcJob ← inputFile <| pkg.dir / "cpp/generator.cpp"
    buildFileAfterDep oFile srcJob (extraDepTrace := computeHash flags) fun srcFile =>
      compileO "cpp/generator.cpp" oFile srcFile args cc
  -- Only fetch release if in a downstream package
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build
    
target retriever.o pkg : FilePath := do
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString]
  let build := do
    let oFile := pkg.buildDir / "cpp/retriever.o"
    let srcJob ← inputFile <| pkg.dir / "cpp/retriever.cpp"
    buildFileAfterDep oFile srcJob (extraDepTrace := computeHash flags) fun srcFile =>
      compileO "cpp/retriever.cpp" oFile srcFile args cc
  -- Only fetch release if in a downstream package
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build

target libonnxruntime pkg : FilePath := do
  logStep s!"Packaging the ONNX Runtime library"
  let src ← inputFile "/Users/kaiyuy/onnxruntime-osx-universal2-1.15.1/lib/libonnxruntime.1.15.1.dylib"
  let dst := pkg.buildDir / "lib/libonnxruntime.dylib"
  let dst' := pkg.buildDir / "lib/libonnxruntime.1.15.1.dylib"
  createParentDirs dst
  buildFileAfterDep dst src fun srcFile => do
    proc {
      cmd := "cp"
      args := #[srcFile.toString, dst.toString]
    }
    proc {
      cmd := "ln"
      args := #["-s", dst.toString, dst'.toString]
    }

extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let _ ← fetch <| pkg.target ``libonnxruntime
  let oGen ← fetch <| pkg.target ``generator.o
  let oRet ← fetch <| pkg.target ``retriever.o
  buildStaticLib (pkg.nativeLibDir / name) #[oGen, oRet]

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

require std from git "https://github.com/leanprover/std4" @ "main"
