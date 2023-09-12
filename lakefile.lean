import Lake
open Lake DSL System


package LeanInfer {
  preferReleaseBuild := true
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #[s!"-L{__dir__}/build/lib", "-lonnxruntime", "-lstdc++"]
  weakLeanArgs := #[s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "onnxruntime"]
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


private def nameToVersionedSharedLib (name : String) (v : String) : String :=
  if Platform.isWindows then s!"{name}.dll"
  else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
  else s!"lib{name}.so.{v}"


def getClangSearchPaths : IO (Array FilePath) := do
  let output ← IO.Process.output {
    cmd := "clang++", args := #["-v", "-lstdc++"]
  }
  let mut paths := #[]
  for s in output.stderr.splitOn do
    if s.startsWith "-L/" then
      paths := paths.push (s.drop 2 : FilePath).normalize
  return paths


def getLibPath (name : String) : IO (Option FilePath) := do
  let searchPaths ← getClangSearchPaths
  for path in searchPaths do
    let libPath := path / name
    if ← libPath.pathExists then
      return libPath
  return none


target libcpp pkg : FilePath := do
  let build := do
    if !Platform.isOSX then  -- Only required for Linux
      let srcName := "libc++.so.1.0"
      let dstName := "libc++.so.1.0"
      let dst := pkg.nativeLibDir / dstName
      try
        let depTrace := Hash.ofString srcName
        let _ ←  buildFileUnlessUpToDate dst depTrace do
          let some src ← getLibPath srcName | panic! s!"{srcName} not found"
          logStep s!"Copying from {src} to {dst}"
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString]
          }
      else
        pure ()
      pure (dst, ← computeTrace dst)
    else
      pure ("", .nil)
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindSync fun _ _ => build
  else
    Job.async build
  

target libunwind pkg : FilePath := do
  let build := do
    if !Platform.isOSX then  -- Only required for Linux
      let srcName := "libunwind.so.1.0"
      let dstName := "libunwind.so.1"
      let dst := pkg.nativeLibDir / dstName
      try
        let depTrace := Hash.ofString srcName
        let _ ←  buildFileUnlessUpToDate dst depTrace do
          let some src ← getLibPath srcName | panic! s!"{srcName} not found"
          logStep s!"Copying from {src} to {dst}"
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString]
          }
      else
        pure ()
      pure (dst, ← computeTrace dst)
    else
      pure ("", .nil)
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindSync fun _ _ => build
  else
    Job.async build


/- Download and untar ONNX Runtime -/
target getONNX pkg : (FilePath × FilePath) := do
  let build := do
    checkPlatform
    try
      let depTrace := Hash.ofString onnxURL
      let onnxFile := pkg.buildDir / onnxFilename
      let _ ←  buildFileUnlessUpToDate onnxFile depTrace do
        download onnxFilename onnxURL onnxFile
        untar onnxFilename onnxFile pkg.buildDir
    else
      pure ()
    let onnxStem := pkg.buildDir / onnxFileStem
    let srcFile : FilePath := onnxStem / "lib" / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
    return ((onnxStem, srcFile), ← computeTrace srcFile)
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindSync fun _ _ => build
  else
    Job.async build


/- Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``getONNX
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
  createParentDirs dst
  buildFileAfterDep dst onnx fun (onnxStem, onnxLib) => do
    logStep s!"Configuring the ONNX Runtime library"
    proc {
      cmd := "cp"
      args := #[onnxLib.toString, dst.toString]
    }
    if ← dst'.pathExists then
      IO.FS.removeFile dst'
    proc {
      cmd := "ln"
      args := #["-s", dst.toString, dst'.toString]
    }
    proc {
      cmd := "cp"
      args := #["-r", (onnxStem / "include").toString, (pkg.buildDir / "include").toString]
    }
    -- Even if we remove them here, they somehow get automatically re-downloaded by downstream packages.
    -- proc {
    --  cmd := "rm"
    --  args := #["-rf", onnxStem.toString, onnxStem.toString ++ ".tgz",  onnxStem.toString ++ ".tgz.trace"]
    --}


def buildCpp (pkg : Package) (path : FilePath) (deps : List (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile (srcJob :: deps) (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args "clang++"


target generator.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let cpp ← fetch $ pkg.target ``libcpp
  let unwind ← fetch $ pkg.target ``libunwind
  let build := buildCpp pkg "cpp/generator.cpp" [onnx, cpp, unwind]
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build


target retriever.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let cpp ← fetch $ pkg.target ``libcpp
  let unwind ← fetch $ pkg.target ``libunwind
  let build := buildCpp pkg "cpp/retriever.cpp" [onnx, cpp, unwind]
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
