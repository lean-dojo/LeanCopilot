import Lake
open Lake DSL System


package LeanInfer {
  preferReleaseBuild := true
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #["-L./build/lib", "-L./lake-packages/LeanInfer/build/lib", "-lonnxruntime", "-lstdc++"]
  -- How to make it work for downstream packages?
  moreLeanArgs := #["--load-dynlib=./build/lib/" ++ nameToSharedLib "onnxruntime"]
}


@[default_target]
lean_lib LeanInfer {
}


lean_lib Examples {
}


def onnxVersion := "1.15.1"
def onnxPlatform := if System.Platform.isOSX then "osx-universal2" else "linux-x64"
def onnxFileStem := s!"onnxruntime-{onnxPlatform}-{onnxVersion}"
def onnxFilename := onnxFileStem ++ ".tgz"
def onnxURL := "https://github.com/microsoft/onnxruntime/releases/download/v1.15.1/" ++ onnxFilename
-- TODO: Support more versions of ONNX Runtime


/- Only support 64-bit Linux or macOS -/
def checkPlatform : IO Unit := do
  if Platform.isWindows then
    panic! "Windows is not supported"
  if Platform.numBits != 64 then
    panic! "Only 64-bit platforms are supported"


/- Download and untar ONNX Runtime -/
target getONNX : FilePath := Job.async do 
  logInfo "Downloading ONNX Runtime library"
  checkPlatform
  try
    let depTrace := Hash.ofString onnxURL
    let trace ← buildFileUnlessUpToDate onnxFilename depTrace do
      -- TODO: Use a temporary directory.
      download onnxFilename onnxURL onnxFilename
      untar onnxFilename onnxFilename (← IO.currentDir)
    return (onnxFileStem, trace)
  else
    return (onnxFileStem, .nil)


private def nameToVersionedSharedLib (name : String) (v : String) : String := 
  if Platform.isWindows then s!"{name}.dll"
  else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
  else s!"lib{name}.so.{v}"


/- Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  logStep s!"Packaging the ONNX Runtime library"
  let onnx ← fetch $ pkg.target ``getONNX
  let srcFile : FilePath := onnxFileStem / "lib" / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
  let src ← inputFile $ srcFile
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
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
