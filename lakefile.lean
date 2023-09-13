import Lake
open Lake DSL System


package LeanInfer {
  preferReleaseBuild := get_config? noCloudRelease |>.isNone
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
      let libName := "libc++.so.1.0"
      let dst := pkg.nativeLibDir / libName
      try
        let depTrace := Hash.ofString libName
        let _ ←  buildFileUnlessUpToDate dst depTrace do
          let some src ← getLibPath libName | panic! s!"{libName} not found"
          logStep s!"Copying from {src} to {dst}"
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString]
          }
          -- TODO: Use relative symbolic links instead.
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString.dropRight 2]
          }
          proc {
            cmd := "cp"
            args := #[dst.toString, dst.toString.dropRight 4]
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


target libcppabi pkg : FilePath := do
  let build := do
    if !Platform.isOSX then  -- Only required for Linux
      let libName := "libc++abi.so.1.0"
      let dst := pkg.nativeLibDir / libName
      try
        let depTrace := Hash.ofString libName
        let _ ←  buildFileUnlessUpToDate dst depTrace do
          let some src ← getLibPath libName | panic! s!"{libName} not found"
          logStep s!"Copying from {src} to {dst}"
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString]
          }
          -- TODO: Use relative symbolic links instead.
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString.dropRight 2]
          }
          proc {
            cmd := "cp"
            args := #[dst.toString, dst.toString.dropRight 4]
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
      let libName := "libunwind.so.1.0"
      let dst := pkg.nativeLibDir / libName
      try
        let depTrace := Hash.ofString libName
        let _ ←  buildFileUnlessUpToDate dst depTrace do
          let some src ← getLibPath libName | panic! s!"{libName} not found"
          logStep s!"Copying from {src} to {dst}"
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString]
          }
          -- TODO: Use relative symbolic links instead.
          proc {
            cmd := "cp"
            args := #[src.toString, dst.toString.dropRight 2]
          }
          proc {
            cmd := "cp"
            args := #[dst.toString, dst.toString.dropRight 4]
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


-- Check whether the directory "./onnx-leandojo-lean4-tacgen-byt5-small" exists
def checkModel : IO Unit := do
  let path : FilePath := ⟨"onnx-leandojo-lean4-tacgen-byt5-small"⟩
  if !(← path.pathExists) || !(← path.isDir) then
    panic! s!"Cannot find the ONNX model at {path}. Download the model using `git lfs install && git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`."


/- Download and Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  checkModel
  let build := do
    checkPlatform
    let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
    createParentDirs dst
    try
      let depTrace := Hash.ofString onnxURL
      let onnxFile := pkg.buildDir / onnxFilename
      let _ ←  buildFileUnlessUpToDate dst depTrace do
        logStep s!"Configuring the ONNX Runtime library"
        download onnxFilename onnxURL onnxFile
        untar onnxFilename onnxFile pkg.buildDir
        let onnxStem := pkg.buildDir / onnxFileStem
        let srcFile : FilePath := onnxStem / "lib" / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
        proc {
          cmd := "cp"
          args := #[srcFile.toString, dst.toString]
        }
        let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "onnxruntime" onnxVersion)
        proc {
          cmd := "cp"
          args := #[dst.toString, dst'.toString]
        }
        proc {
          cmd := "cp"
          args := #["-r", (onnxStem / "include").toString, (pkg.buildDir / "include").toString]
        }
        logStep s!"rm -rf {onnxStem.toString} {onnxStem.toString ++ ".tgz"} {onnxStem.toString ++ ".tgz.trace"}"
        proc {
          cmd := "rm"
          args := #["-rf", onnxStem.toString, onnxStem.toString ++ ".tgz",  onnxStem.toString ++ ".tgz.trace"]
        }
    else
      pure ()
    return (dst, ← computeTrace dst)
  
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindSync fun _ _ => build
  else
    Job.async build


def buildCpp (pkg : Package) (path : FilePath) (deps : List (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == BuildType.release then "-O3" else "-O0"
  let mut flags := #["-fPIC", "-std=c++11", "-stdlib=libc++", optLevel]
  match get_config? targetArch with
  | none => pure ()
  | some arch => flags := flags.push s!"--target={arch}"
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile (srcJob :: deps) (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args "clang++"


target generator.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let cpp ← fetch $ pkg.target ``libcpp
  let cppabi ← fetch $ pkg.target ``libcppabi
  let unwind ← fetch $ pkg.target ``libunwind
  let build := buildCpp pkg "cpp/generator.cpp" [onnx, cpp, cppabi, unwind]
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build


target retriever.o pkg : FilePath := do
  let onnx ← fetch $ pkg.target ``libonnxruntime
  let cpp ← fetch $ pkg.target ``libcpp
  let cppabi ← fetch $ pkg.target ``libcppabi
  let unwind ← fetch $ pkg.target ``libunwind
  let build := buildCpp pkg "cpp/retriever.cpp" [onnx, cpp, cppabi, unwind]
  if pkg.name ≠ (← getRootPackage).name then
    (← pkg.fetchFacetJob `release).bindAsync fun _ _ => build
  else
    build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let oGen ← fetch <| pkg.target ``generator.o
  let oRet ← fetch <| pkg.target ``retriever.o
  buildStaticLib (pkg.nativeLibDir / name) #[oGen, oRet]


require std from git "https://github.com/leanprover/std4" @ "main"
