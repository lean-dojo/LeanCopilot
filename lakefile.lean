import Lake
open Lake DSL System


package LeanInfer {
  preferReleaseBuild := true
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #["-L./build/lib", "-L./lake-packages/LeanInfer/build/lib", "-lonnxruntime", "-lstdc++"]
  moreLeanArgs := #["--load-dynlib=./build/lib/" ++ nameToSharedLib "onnxruntime"]  -- How to make this work for downstream packages?
}


@[default_target]
lean_lib LeanInfer {
}


lean_lib Examples {
}


def buildCpp (path pkgDir buildDir : FilePath) (buildType : BuildType) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if buildType == BuildType.release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString]
  let oFile := buildDir / (path.withExtension ".o")
  let srcJob ← inputFile <| pkgDir / path
  buildFileAfterDep oFile srcJob (extraDepTrace := computeHash flags) fun srcFile =>
    compileO path.toString oFile srcFile args "clang++"


target generator.o pkg : FilePath := do
  let build := buildCpp "cpp/generator.cpp" pkg.dir pkg.buildDir pkg.buildType
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build
    
  
target retriever.o pkg : FilePath := do
  let build := buildCpp "cpp/retriever.cpp" pkg.dir pkg.buildDir pkg.buildType
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build


def onnxVersion := "1.15.1"


def downloadOnnxRuntime : LogIO FilePath := do 
  logInfo s!"Downloading ONNX Runtime library"
  if System.Platform.isWindows then
    panic! "Windows is not supported"
  if System.Platform.numBits != 64 then
    panic! "Only 64-bit platforms are supported"
  let platform := if System.Platform.isOSX then "osx-universal2" else "linux-x64"
  let filename := s!"onnxruntime-{platform}-{onnxVersion}.tgz"
  let url := "https://github.com/microsoft/onnxruntime/releases/download/v1.15.1/" ++ filename
  -- TODO: Download to a temporary directory.
  download filename url filename
  untar filename filename (← IO.currentDir)
  let some stem := (filename: FilePath).fileStem | panic! "unexpected filename: {filename}"
  return stem / "lib" / (nameToSharedLib s!"onnxruntime.{onnxVersion}")


target libonnxruntime pkg : FilePath := do
  logStep s!"Packaging the ONNX Runtime library"
  let src ← inputFile (← downloadOnnxRuntime)
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  let dst' := pkg.nativeLibDir / (nameToSharedLib s!"onnxruntime.{onnxVersion}")
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


-- Check whether the directory "./onnx-leandojo-lean4-tacgen-byt5-small" exists
def checkModel : IO Bool := do
  let path : FilePath := ⟨"onnx-leandojo-lean4-tacgen-byt5-small"⟩
  return (← path.pathExists) && (← path.isDir)


script check do
  if !(← checkClang) then
    throw $ IO.userError "Clang++ not found"
  if !(← checkModel) then
    throw $ IO.userError "The ONNX model not found"
  println! "Looks good to me! Try `lake build`."
  return 0


require std from git "https://github.com/leanprover/std4" @ "main"
