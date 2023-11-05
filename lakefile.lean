import Lake
open Lake DSL
open System Lean Elab


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


def getArch? : BaseIO (Option SupportedArch) := do
  return some .x86_64


def getArch : IO SupportedArch := do
  if let some arch ← getArch? then
    return arch
  else
    error "Unknown architecture"


structure SupportedPlatform where
  os : SupportedOS
  arch : SupportedArch


def getPlatform : IO SupportedPlatform := do
  if Platform.numBits != 64 then
    error "Only 64-bit platforms are supported"
  return ⟨← getOS, ← getArch⟩


package LeanInfer where
  -- preferReleaseBuild := get_config? noCloudRelease |>.isNone
  -- buildArchive? := is_arm? |>.map (if · then "arm64" else "x86_64")
  precompileModules := true
  buildType := BuildType.debug
  moreLinkArgs := #[s!"-L{__dir__}/build/lib", "-lonnxruntime", "-lctranslate2"]
  weakLeanArgs := #[s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "onnxruntime", s!"--load-dynlib={__dir__}/build/lib/" ++ nameToSharedLib "ctranslate2"]


@[default_target]
lean_lib LeanInfer {
}


lean_lib LeanInferTests {
  globs := #[.submodules "LeanInferTests"]
}


private def nameToVersionedSharedLib (name : String) (v : String) : String :=
  if Platform.isWindows then s!"{name}.dll"
  else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
  else s!"lib{name}.so.{v}"


def afterReleaseSync (pkg : Package) (build : SchedulerM (Job α)) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindAsync fun _ _ => build
  else
    build


def afterReleaseAsync (pkg : Package) (build : BuildM α) : IndexBuildM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.release.fetch).bindSync fun _ _ => build
  else
    Job.async build


def getOnnxPlatform : IO String := do
  let ⟨os, arch⟩  ← getPlatform
  match os with
  | .linux => return if arch == .x86_64 then "linux-x64" else "linux-aarch64"
  | .macos => return "osx-universal2"


/- Download and Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  afterReleaseAsync pkg do
  let _ ← getPlatform
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  createParentDirs dst

  let onnxVersion := "1.15.1"
  let onnxFileStem := s!"onnxruntime-{← getOnnxPlatform}-{onnxVersion}"
  let onnxFilename := onnxFileStem ++ ".tgz"
  let onnxURL := "https://github.com/microsoft/onnxruntime/releases/download/v1.15.1/" ++ onnxFilename

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


def gitClone (url : String) (cwd : Option FilePath) : LogIO Unit := do
  proc {
    cmd := "git"
    args := #["clone", "--recursive", url]
    cwd := cwd
  }


def runCmake (root : FilePath) (flags : Array String) : LogIO Bool := do
  assert! (← root.pathExists) ∧ (← (root / "CMakeLists.txt").pathExists)
  let buildDir := root / "build"
  if ← buildDir.pathExists then
    IO.FS.removeDirAll buildDir
  IO.FS.createDirAll buildDir
  testProc {
    cmd := "cmake"
    args := flags ++ #[".."]
    cwd := buildDir
  }


def autoCt2Cmake (root : FilePath) : LogIO Unit := do
  let basicFlags := #["-DBUILD_CLI=OFF", "-DOPENMP_RUNTIME=NONE", "-DWITH_CUDA=OFF", "-DWITH_CUDNN=OFF", "-DWITH_DNNL=OFF", "-DWITH_MKL=OFF", "-DWITH_ACCELERATE=OFF"]
  assert! ← runCmake root basicFlags

  let hasOpenMP ← runCmake root (basicFlags.erase "-DOPENMP_RUNTIME=NONE" |>.push "-DOPENMP_RUNTIME=COMP")
  let hasCuda := Platform.isOSX && (← runCmake root (basicFlags.erase "-DWITH_CUDA=OFF" |>.push "-DWITH_CUDA=ON"))
  let hasCudnn := hasCuda && (← runCmake root ((basicFlags.erase "-DWITH_CUDA=OFF" |>.erase "-DWITH_CUDNN=OFF") ++ #["-DWITH_CUDA=ON", "-DWITH_CUDNN=ON"]))
  let hasDnnl ← runCmake root (basicFlags.erase "-DWITH_DNNL=OFF" |>.push "-DWITH_DNNL=ON")
  let hasAccelerate := Platform.isOSX && (← runCmake root (basicFlags.erase "-DWITH_ACCELERATE=OFF" |>.push "-DWITH_ACCELERATE=ON"))
  let hasMkl := ¬ hasAccelerate && (← runCmake root (basicFlags.erase "-DWITH_MKL=OFF" |>.push "-DWITH_MKL=ON"))

  let flags := #[
    "-DBUILD_CLI=OFF",
    "-DOPENMP_RUNTIME=" ++ (if hasOpenMP then "COMP" else "NONE"),
    "-DWITH_CUDA=" ++ (if hasCuda then "ON" else "OFF"),
    "-DWITH_CUDNN=" ++ (if hasCudnn then "ON" else "OFF"),
    "-DWITH_DNNL=" ++ (if hasDnnl then "ON" else "OFF"),
    "-DWITH_MKL=" ++ (if hasMkl then "ON" else "OFF"),
    "-DWITH_ACCELERATE=" ++ (if hasAccelerate then "ON" else "OFF")
    ]
  logInfo s!"Using CTranslate2 cmake flags: {flags}"
  assert! ← runCmake root flags

/--
Build CTranslate2 from source using cmake.
TODO: Include the flags into the trace.
-/
def buildCmakeProject (root : FilePath) : LogIO Unit := do
  -- Run cmake.
  if let some flags := get_config? Ct2Flags then
    logInfo s!"Using CTranslate2 cmake flags: {flags}"
    let _ ← runCmake root flags.splitOn.toArray
  else
    autoCt2Cmake root
  -- Run make.
  proc {
    cmd := "make"
    args := #["-j8"]
    cwd := root / "build"
  }


/- Download and build CTranslate2. Copy its C++ header files to `build/include` and shared libraries to `build/lib` -/
target libctranslate2 pkg : FilePath := do
  afterReleaseAsync pkg do
  let _ ← getPlatform
  let dst := pkg.nativeLibDir / (nameToSharedLib "ctranslate2")
  createParentDirs dst
  let ct2URL := "https://github.com/OpenNMT/CTranslate2"

  try
    let depTrace := Hash.ofString ct2URL
    let trace ← buildFileUnlessUpToDate dst depTrace do
      logStep s!"Cloning CTranslate2 from {ct2URL} into {pkg.buildDir}"
      gitClone ct2URL pkg.buildDir

      logStep s!"Building CTranslate2 with cmake"
      let ct2Dir := pkg.buildDir / "CTranslate2"
      buildCmakeProject ct2Dir
      proc {
        cmd := "cp"
        args := #[(ct2Dir / "build" / nameToSharedLib "ctranslate2").toString, dst.toString]
      }
      -- TODO: Don't hardcode the version "3".
      let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "ctranslate2" "3")
      proc {
        cmd := "cp"
        args := #[dst.toString, dst'.toString]
      }
      proc {
        cmd := "cp"
        args := #["-r", (ct2Dir / "include" / "ctranslate2").toString, (pkg.buildDir / "include" / "ctranslate2").toString]
      }
      proc {
        cmd := "wget"
        args := #["https://raw.githubusercontent.com/nlohmann/json/develop/single_include/nlohmann/json.hpp", "-O", "build/include/json.hpp"]
      }
      proc {
        cmd := "rm"
        args := #["-rf", ct2Dir.toString]
      }
    return (dst, trace)
  else
    return (dst, ← computeTrace dst)


def buildCpp (pkg : Package) (path : FilePath) (deps : List (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == .release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++17", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile (srcJob :: deps) (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args "c++"


target onnx.o pkg : FilePath := do
  let onnx ← libonnxruntime.fetch
  let build := buildCpp pkg "cpp/onnx.cpp" [onnx]
  afterReleaseSync pkg build


target ct2.o pkg : FilePath := do
  let ct2 ← libctranslate2.fetch
  let build := buildCpp pkg "cpp/ct2.cpp" [ct2]
  afterReleaseSync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let onnxO ← onnx.o.fetch
  let ct2O ← ct2.o.fetch
  buildStaticLib (pkg.nativeLibDir / name) #[onnxO, ct2O]


require std from git "https://github.com/leanprover/std4" @ "stable"
require aesop from git "https://github.com/JLimperg/aesop" @ "stable"
