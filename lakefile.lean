import Lake
open Lake DSL
open System Lean Elab


inductive SupportedOS where
  | linux
  | macos
deriving Inhabited, BEq


def getOS! : IO SupportedOS := do
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


def nproc : IO Nat := do
  let out ← IO.Process.output {cmd := "nproc", stdin := .null}
  return out.stdout.trim.toNat!


def getArch? : IO (Option SupportedArch) := do
  let out ← IO.Process.output {cmd := "uname", args := #["-m"], stdin := .null}
  let arch := out.stdout.trim
  if arch ∈ ["arm64", "aarch64"] then
    return some .arm64
  else if arch == "x86_64" then
    return some .x86_64
  else
    return none


def getArch! : IO SupportedArch := do
  if let some arch ← getArch? then
    return arch
  else
    error "Unknown architecture"


def isArm! : IO Bool := do
  return (← getArch!) == .arm64


def hasCUDA : IO Bool := do
  let out ← IO.Process.output {cmd := "which", args := #["nvcc"], stdin := .null}
  return out.exitCode == 0


def useCUDA : IO Bool := do
  return (get_config? noCUDA |>.isNone) ∧ (← hasCUDA)


def buildArchiveName : String :=
  let arch := if run_io isArm! then "arm64" else "x86_64"
  if run_io useCUDA then
    s!"{arch}-cuda"
  else
    arch


structure SupportedPlatform where
  os : SupportedOS
  arch : SupportedArch


def getPlatform! : IO SupportedPlatform := do
  if Platform.numBits != 64 then
    error "Only 64-bit platforms are supported"
  return ⟨← getOS!, ← getArch!⟩


package LeanInfer where
  preferReleaseBuild := get_config? noCloudRelease |>.isNone
  buildArchive? := buildArchiveName
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #[s!"-L{__dir__}/.lake/build/lib", "-lonnxruntime", "-lctranslate2"]
  weakLeanArgs := #["onnxruntime", "ctranslate2"].map fun name =>
    s!"--load-dynlib={__dir__}/.lake/build/lib/" ++ nameToSharedLib name


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


def getOnnxPlatform! : IO String := do
  let ⟨os, arch⟩  ← getPlatform!
  match os with
  | .linux => return if arch == .x86_64 then "linux-x64" else "linux-aarch64"
  | .macos => return "osx-universal2"


def ensureDirExists (dir : FilePath) : IO Unit := do
  if !(← dir.pathExists)  then
    IO.FS.createDirAll dir


/- Download and Copy ONNX's C++ header files to `build/include` and shared libraries to `build/lib` -/
target libonnxruntime pkg : FilePath := do
  afterReleaseAsync pkg do
  let _ ← getPlatform!
  let dst := pkg.nativeLibDir / (nameToSharedLib "onnxruntime")
  createParentDirs dst

  let onnxVersion := "1.15.1"
  let onnxFileStem := s!"onnxruntime-{← getOnnxPlatform!}-{onnxVersion}"
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
      ensureDirExists $ pkg.buildDir / "include"
      proc {
        cmd := "cp"
        args := #[(onnxStem / "include" / "onnxruntime_cxx_api.h").toString, (pkg.buildDir / "include").toString ++ "/"]
      }
      proc {
        cmd := "cp"
        args := #[(onnxStem / "include" / "onnxruntime_cxx_inline.h").toString, (pkg.buildDir / "include").toString ++ "/"]
      }
      proc {
        cmd := "cp"
        args := #[(onnxStem / "include" / "onnxruntime_c_api.h").toString, (pkg.buildDir / "include").toString ++ "/"]
      }
      proc {
        cmd := "rm"
        args := #["-rf", onnxStem.toString, onnxStem.toString ++ ".tgz"]
      }
    return (dst, trace)
  else
    return (dst, ← computeTrace dst)


def gitClone (url : String) (cwd : Option FilePath) : LogIO Unit := do
  proc (quiet := true) {
    cmd := "git"
    args := #["clone", "--recursive", url]
    cwd := cwd
  }


def runCmake (root : FilePath) (flags : Array String) : LogIO Unit := do
  assert! (← root.pathExists) ∧ (← (root / "CMakeLists.txt").pathExists)
  let buildDir := root / "build"
  if ← buildDir.pathExists then
    IO.FS.removeDirAll buildDir
  IO.FS.createDirAll buildDir
  let ok ← testProc {
    cmd := "cmake"
    args := flags ++ #[".."]
    cwd := buildDir
  }
  if ¬ ok then
    error "Failed to run cmake"


target libopenblas pkg : FilePath := do
  afterReleaseAsync pkg do
    let rootDir := pkg.buildDir / "OpenBLAS"
    ensureDirExists rootDir
    let dst := pkg.nativeLibDir / (nameToSharedLib "openblas")
    let url := "https://github.com/OpenMathLib/OpenBLAS"

    try
      let depTrace := Hash.ofString url
      let trace ← buildFileUnlessUpToDate dst depTrace do
        logStep s!"Cloning OpenBLAS from {url}"
        gitClone url pkg.buildDir

        let numThreads := min 32 (← nproc)
        let flags := #["NO_LAPACK=1", "NO_FORTRAN=1", s!"-j{numThreads}"]
        logStep s!"Building OpenBLAS with `make{flags.foldl (· ++ " " ++ ·) ""}`"
        proc (quiet := true) {
          cmd := "make"
          args := flags
          cwd := rootDir
        }
        proc {
          cmd := "cp"
          args := #[(rootDir / nameToSharedLib "openblas").toString, dst.toString]
        }
        -- TODO: Don't hardcode the version "0".
        let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "openblas" "0")
        proc {
          cmd := "cp"
          args := #[dst.toString, dst'.toString]
        }
      return (dst, trace)

    else
      return (dst, ← computeTrace dst)


def getCt2CmakeFlags : IO (Array String) := do
  let mut flags := #["-DBUILD_CLI=OFF", "-DOPENMP_RUNTIME=NONE", "-DWITH_DNNL=OFF", "-DWITH_MKL=OFF"]

  match ← getOS! with
  | .macos => flags := flags ++ #["-DWITH_ACCELERATE=ON", "-DWITH_OPENBLAS=OFF"]
  | .linux => flags := flags ++ #["-DWITH_ACCELERATE=OFF", "-DWITH_OPENBLAS=ON", "-DOPENBLAS_INCLUDE_DIR=../../OpenBLAS", "-DOPENBLAS_LIBRARY=../../OpenBLAS/libopenblas.so"]

  if ← useCUDA then
    flags := flags ++ #["-DWITH_CUDA=ON", "-DWITH_CUDNN=ON"]
  else
    flags := flags ++ #["-DWITH_CUDA=OFF", "-DWITH_CUDNN=OFF"]

  return flags


/- Download and build CTranslate2. Copy its C++ header files to `build/include` and shared libraries to `build/lib` -/
target libctranslate2 pkg : FilePath := do
  if (← getOS!) == .linux then
    let openblas ← libopenblas.fetch
    let _ ← openblas.await

  afterReleaseAsync pkg do
    let dst := pkg.nativeLibDir / (nameToSharedLib "ctranslate2")
    createParentDirs dst
    let ct2URL := "https://github.com/OpenNMT/CTranslate2"

    try
      let depTrace := Hash.ofString ct2URL
      let trace ← buildFileUnlessUpToDate dst depTrace do
        logStep s!"Cloning CTranslate2 from {ct2URL}"
        gitClone ct2URL pkg.buildDir

        let ct2Dir := pkg.buildDir / "CTranslate2"
        let flags ← getCt2CmakeFlags
        logStep s!"Configuring CTranslate2 with `cmake{flags.foldl (· ++ " " ++ ·) ""} ..`"
        runCmake ct2Dir flags
        let numThreads := min 32 (← nproc)
        logStep s!"Building CTranslate2 with `make -j{numThreads}`"
        proc {
          cmd := "make"
          args := #[s!"-j{numThreads}"]
          cwd := ct2Dir / "build"
        }

        ensureDirExists $ pkg.buildDir / "include"
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
          cmd := "cp"
          args := #["-r", (ct2Dir / "include" / "nlohmann").toString, (pkg.buildDir / "include" / "nlohmann").toString]
        }
        proc {
          cmd := "cp"
          args := #["-r", (ct2Dir / "include" / "half_float").toString, (pkg.buildDir / "include" / "half_float").toString]
        }
        proc {
          cmd := "rm"
          args := #["-rf", ct2Dir.toString]
        }
      return (dst, trace)
    else
      return (dst, ← computeTrace dst)


def buildCpp (pkg : Package) (path : FilePath) (dep : BuildJob FilePath) : SchedulerM (BuildJob FilePath) := do
  let optLevel := if pkg.buildType == .release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++17", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputFile <| pkg.dir / path
  buildFileAfterDepList oFile [srcJob, dep] (extraDepTrace := computeHash flags) fun deps =>
    compileO path.toString oFile deps[0]! args "c++"


target onnx.o pkg : FilePath := do
  let onnx ← libonnxruntime.fetch
  let build := buildCpp pkg "cpp/onnx.cpp" onnx
  afterReleaseSync pkg build


target ct2.o pkg : FilePath := do
  let ct2 ← libctranslate2.fetch
  let build := buildCpp pkg "cpp/ct2.cpp" ct2
  afterReleaseSync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let onnxO ← onnx.o.fetch
  let ct2O ← ct2.o.fetch
  buildStaticLib (pkg.nativeLibDir / name) #[onnxO, ct2O]


def checkAvailable (cmd : String) : IO Bool := do
  let proc ← IO.Process.output {
    cmd := "which",
    args := #[cmd]
  }
  return proc.exitCode == 0


def initGitLFS : IO Unit := do
  assert! ← checkAvailable "git"
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["lfs", "install"]
  }
  if proc.exitCode != 0 then
    throw $ IO.userError "Failed to initialize Git LFS. Please install it."


def HF_BASE_URL := "https://huggingface.co"


structure HuggingFaceURL where
  user : Option String
  modelName : String


instance : ToString HuggingFaceURL where
  toString url := match url.user with
  | none => s!"{HF_BASE_URL}/{url.modelName}"
  | some user => s!"{HF_BASE_URL}/{user}/{url.modelName}"


def getHomeDir : IO FilePath := do
  let some dir ← IO.getEnv "HOME" | throw $ IO.userError "Cannot find the $HOME environment variable."
  return dir


def getDefaultCacheDir : IO FilePath := do
  return (← getHomeDir) / ".cache" / "lean_infer"


def getCacheDir : IO FilePath := do
  let defaultCacheDir ← getDefaultCacheDir
  let dir := match ← IO.getEnv "LEAN_INFER_CACHE_DIR" with
  | some dir => (dir : FilePath)
  | none => defaultCacheDir
  ensureDirExists dir
  return dir.normalize


def getModelDir (url : HuggingFaceURL) : IO FilePath := do
  let cacheDir ← getCacheDir
  let dir := match url.user with
  | none => cacheDir / url.modelName
  | some user => cacheDir / user / url.modelName
  return dir.normalize


def hasLocalChange (root : FilePath) : IO Bool := do
  if ¬ (← root.pathExists) then
    return true
  assert! ← checkAvailable "git"
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["diff", "--shortstat"]
    cwd := root
  }
  return proc.exitCode == 0 ∧ proc.stdout != ""


def downloadIfNecessary (url : HuggingFaceURL) : IO Unit := do
  let dir := ← getModelDir url
  if ¬ (← hasLocalChange dir) then
    println! s!"The model is available at {dir}"
    return ()

  println! s!"Downloading the model into {dir}"
  let some parentDir := dir.parent | unreachable!
  ensureDirExists parentDir
  initGitLFS
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["clone", toString url]
    cwd := parentDir
  }
  if proc.exitCode != 0 then
    throw $ IO.userError s!"Failed to download the model. You download it manually from {url} and store it in `{dir}/`. See https://huggingface.co/docs/hub/models-downloading for details."


script download do
  downloadIfNecessary ⟨"kaiyuy", "ct2-leandojo-lean4-tacgen-byt5-small"⟩
  downloadIfNecessary ⟨"kaiyuy", "ct2-leandojo-lean4-retriever-byt5-small"⟩
  return 0


require std from git "https://github.com/leanprover/std4" @ "main"
require aesop from git "https://github.com/JLimperg/aesop" @ "master"

meta if get_config? env = some "dev" then -- dev is so not everyone has to build it
require «doc-gen4» from git "https://github.com/leanprover/doc-gen4" @ "main"
