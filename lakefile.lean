import Lake
open Lake DSL System Lean Elab Term


inductive SupportedOS where
  | linux
  | macos
deriving Inhabited, BEq


def getOS : IO SupportedOS := do
  if Platform.isWindows then
    error "Windows is not supported"
  if Platform.isOSX then 
    return .macos 
  else
    return .linux


inductive SupportedArch where
  | x86_64
  | arm64
deriving Inhabited, BEq


def getArch : IO SupportedArch := do
  let output ← IO.Process.output {
    cmd := "uname", args := #["-m"]
  } 
  let arch := output.stdout.trim
  if arch ∈ ["arm64", "aarch64"] then
    return .arm64
  else if arch == "x86_64" then
    return .x86_64
  else
    error s!"Unsupported architecture {arch}"


structure SupportedPlatform where
  os : SupportedOS
  arc : SupportedArch


def getPlatform : IO SupportedPlatform := do
  if Platform.numBits != 64 then
    error "Only 64-bit platforms are supported"
  return ⟨← getOS, ← getArch⟩


syntax (name := isARM) "is_arm?" :term

@[term_elab isARM]
def elabIsARM : TermElab := fun _ _ => do
  if (← getArch) == .arm64 then
    return Expr.const `Bool.true []
  else
    return Expr.const `Bool.false []


package LeanInfer {
  preferReleaseBuild := (get_config? noCloudRelease |>.isNone) ∧ (¬ is_arm?)
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


def afterReleaseAsync (pkg : Package) (build : SchedulerM (Job α)) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindAsync fun _ _ => build
  else
    build


def afterReleaseSync (pkg : Package) (build : BuildM α) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindSync fun _ _ => build
  else
    Job.async build


def copyLibJob (pkg : Package) (libName : String) : IndexBuildM (BuildJob FilePath) :=
  afterReleaseSync pkg do
  if !Platform.isOSX then  -- Only required for Linux
    let dst := pkg.nativeLibDir / libName
    try
      let depTrace := Hash.ofString libName
      let trace ← buildFileUnlessUpToDate dst depTrace do
        let some src ← getLibPath libName | error s!"{libName} not found"
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
      pure (dst, trace)
    else
      pure (dst, ← computeTrace dst)
  else
    pure ("", .nil)


target libcpp pkg : FilePath := do
  copyLibJob pkg "libc++.so.1.0"


target libcppabi pkg : FilePath := do
  copyLibJob pkg "libc++abi.so.1.0"


target libunwind pkg : FilePath := do
  copyLibJob pkg "libunwind.so.1.0"


-- Check whether the directory "./onnx-leandojo-lean4-tacgen-byt5-small" exists
def checkModel : IO Unit := do
  let path : FilePath := ⟨"onnx-leandojo-lean4-tacgen-byt5-small"⟩
  if ¬(← path.pathExists) ∨ ¬(← path.isDir) then
    error s!"Cannot find the ONNX model at {path}. Download the model using `git lfs install && git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`."


/- Download and Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  checkModel
  afterReleaseSync pkg do
  let _ ← getPlatform
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  createParentDirs dst
  try
    let depTrace := Hash.ofString onnxURL
    let onnxFile := pkg.buildDir / onnxFilename
    let trace ← buildFileUnlessUpToDate dst depTrace do
      logStep s!"Fetching the ONNX Runtime library"
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
      proc {
        cmd := "rm"
        args := #["-rf", onnxStem.toString, onnxStem.toString ++ ".tgz"]
      }
    return (dst, trace)
  else
    return (dst, ← computeTrace dst)


def buildCpp (pkg : Package) (path : FilePath) (deps : List (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == .release then "-O3" else "-O0"
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
  let onnx ← libonnxruntime.fetch
  let cpp ← libcpp.fetch
  let cppabi ← libcppabi.fetch
  let unwind ← libunwind.fetch
  let build := buildCpp pkg "cpp/generator.cpp" [onnx, cpp, cppabi, unwind]
  afterReleaseAsync pkg build


target retriever.o pkg : FilePath := do
  let onnx ← libonnxruntime.fetch
  let cpp ← libcpp.fetch
  let cppabi ← libcppabi.fetch
  let unwind ← libunwind.fetch
  let build := buildCpp pkg "cpp/retriever.cpp" [onnx, cpp, cppabi, unwind]
  afterReleaseAsync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let oGen ← generator.o.fetch
  let oRet ← retriever.o.fetch
  buildStaticLib (pkg.nativeLibDir / name) #[oGen, oRet]


require std from git "https://github.com/leanprover/std4" @ "main"
