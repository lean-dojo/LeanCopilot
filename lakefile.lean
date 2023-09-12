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


def onnxVersion := "1.15.1"
def onnxPlatform := if System.Platform.isOSX then "osx-universal2" else "linux-x64"
def onnxFileStem := s!"onnxruntime-{onnxPlatform}-{onnxVersion}"
def onnxFilename := s!"{onnxFileStem}.tgz"
def onnxUrl := "https://github.com/microsoft/onnxruntime/releases/download/v1.15.1/" ++ onnxFilename


target downloadOnnxRuntime : FilePath := Job.async do 
  logInfo s!"Downloading ONNX Runtime library"
  if System.Platform.isWindows then
    panic! "Windows is not supported"
  if System.Platform.numBits != 64 then
    panic! "Only 64-bit platforms are supported"

  -- TODO: Download to a temporary directory.
  try
    let depTrace := Hash.ofString onnxUrl
    let trace ← buildFileUnlessUpToDate onnxFilename depTrace do
      download onnxFilename onnxUrl onnxFilename
      untar onnxFilename onnxFilename (← IO.currentDir)
    return (onnxFileStem, trace)
  else
    return (onnxFileStem, .nil)
  /-
  let some stem := (filename: FilePath).fileStem | panic! "unexpected filename: {filename}"
  let libDir : FilePath := stem / "lib"
  let includeDir : FilePath := stem / "include"
  return (includeDir, libDir)
  -/


target libonnxruntime pkg : FilePath := do
  logStep s!"Packaging the ONNX Runtime library"
  let onnx ← fetch $ pkg.target ``downloadOnnxRuntime
  let srcFile : FilePath := onnxFileStem / "lib" / (nameToSharedLib s!"onnxruntime.{onnxVersion}")
  let src ← inputFile $ srcFile
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  let dst' := pkg.nativeLibDir / (nameToSharedLib s!"onnxruntime.{onnxVersion}")
  createParentDirs dst
  buildFileAfterDepList dst [onnx, src] fun deps => do
    proc {
      cmd := "cp"
      args := #[deps[1]!.toString, dst.toString]
    }
    proc {
      cmd := "ln"
      args := #["-s", dst.toString, dst'.toString]
    }
    proc {
      cmd := "cp"
      args := #["-r", (onnxFileStem ++ "/include"), (pkg.buildDir / "include").toString]
    }


def buildCpp (pkg : Package) (path : FilePath) (onnx : BuildJob FilePath) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile [srcJob, onnx] (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args "clang++"


target generator.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let build := buildCpp pkg "cpp/generator.cpp" onnx
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build
    
  
target retriever.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let build := buildCpp pkg "cpp/retriever.cpp" onnx
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
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
