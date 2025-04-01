import Lake

open Lake DSL System Lean Elab

set_option autoImplicit false


inductive SupportedOS where
  | linux
  | macos
deriving Inhabited, BEq


def getOS! : SupportedOS :=
  if Platform.isWindows then
    panic! "Windows is not supported"
  else if Platform.isOSX then
     .macos
  else
     .linux


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
  let os := if getOS! == .macos then "macOS" else "linux"
  if run_io useCUDA then
    s!"{arch}-cuda-{os}.tar.gz"
  else
    s!"{arch}-{os}.tar.gz"


structure SupportedPlatform where
  os : SupportedOS
  arch : SupportedArch


def getPlatform! : IO SupportedPlatform := do
  if Platform.numBits != 64 then
    error "Only 64-bit platforms are supported"
  return ⟨getOS!, ← getArch!⟩


package LeanCopilot where
  preferReleaseBuild := get_config? noCloudRelease |>.isNone
  buildArchive? := buildArchiveName
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #[s!"-L{__dir__}/.lake/build/lib", "-lctranslate2"]
  weakLeanArgs := #[s!"--load-dynlib={__dir__}/.lake/build/lib/" ++ nameToSharedLib "ctranslate2"]


@[default_target]
lean_lib LeanCopilot {
}


lean_lib ModelCheckpointManager {
}


lean_exe download {
  root := `ModelCheckpointManager.Main
}


lean_lib LeanCopilotTests {
  globs := #[.submodules "LeanCopilotTests".toName]
}


private def nameToVersionedSharedLib (name : String) (v : String) : String :=
  if Platform.isWindows then s!"{name}.dll"
  else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
  else s!"lib{name}.so.{v}"


def afterReleaseSync {α : Type} (pkg : Package) (build : SpawnM (Job α)) : FetchM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.optGitHubRelease.fetch).bindM fun _ => build
  else
    build


def afterReleaseAsync {α : Type} (pkg : Package) (build : JobM α) : FetchM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.name ≠ (← getRootPackage).name then
    (← pkg.optGitHubRelease.fetch).mapM fun _ => build
  else
    Job.async build


def ensureDirExists (dir : FilePath) : IO Unit := do
  if !(← dir.pathExists)  then
    IO.FS.createDirAll dir


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
    if flags.contains "-DWITH_CUDNN=ON" then  -- Some users may have CUDA but not cuDNN.
      let ok' ← testProc {
        cmd := "cmake"
        args := (flags.erase "-DWITH_CUDNN=ON" |>.push "-DWITH_CUDNN=OFF") ++ #[".."]
        cwd := buildDir
      }
      if ok' then
        return ()
    error "Failed to run cmake"


target libopenblas pkg : FilePath := do
  afterReleaseAsync pkg do
    let rootDir := pkg.buildDir / "OpenBLAS"
    ensureDirExists rootDir
    let dst := pkg.nativeLibDir / (nameToSharedLib "openblas")
    createParentDirs dst
    let url := "https://github.com/OpenMathLib/OpenBLAS"

    try
      let depTrace := Hash.ofString url
      setTrace depTrace
      buildFileUnlessUpToDate' dst do
        logInfo s!"Cloning OpenBLAS from {url}"
        gitClone url pkg.buildDir

        let numThreads := max 4 $ min 32 (← nproc)
        let flags := #["NO_LAPACK=1", "NO_FORTRAN=1", s!"-j{numThreads}"]
        logInfo s!"Building OpenBLAS with `make{flags.foldl (· ++ " " ++ ·) ""}`"
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
      let _ := (← getTrace)
      return dst

    else
      addTrace <| ← computeTrace dst
      return dst


def getCt2CmakeFlags : IO (Array String) := do
  let mut flags := #["-DOPENMP_RUNTIME=NONE", "-DWITH_MKL=OFF"]

  match getOS! with
  | .macos => flags := flags ++ #["-DWITH_ACCELERATE=ON", "-DWITH_OPENBLAS=OFF"]
  | .linux => flags := flags ++ #["-DWITH_ACCELERATE=OFF", "-DWITH_OPENBLAS=ON", "-DOPENBLAS_INCLUDE_DIR=../../OpenBLAS", "-DOPENBLAS_LIBRARY=../../OpenBLAS/libopenblas.so"]

  -- [TODO] Temporary fix: Do not use CUDA even if it is available.
  -- if ← useCUDA then
  --   flags := flags ++ #["-DWITH_CUDA=ON", "-DWITH_CUDNN=ON"]
  -- else
  --   flags := flags ++ #["-DWITH_CUDA=OFF", "-DWITH_CUDNN=OFF"]

  return flags


/- Download and build CTranslate2. Copy its C++ header files to `build/include` and shared libraries to `build/lib` -/
target libctranslate2 pkg : FilePath := do
  if getOS! == .linux then
    let openblas ← libopenblas.fetch
    let _ ← openblas.await

  afterReleaseAsync pkg do
    let dst := pkg.nativeLibDir / (nameToSharedLib "ctranslate2")
    createParentDirs dst
    let ct2URL := "https://github.com/OpenNMT/CTranslate2"

    try
      let depTrace := Hash.ofString ct2URL
      setTrace depTrace
      buildFileUnlessUpToDate' dst do
        logInfo s!"Cloning CTranslate2 from {ct2URL}"
        gitClone ct2URL pkg.buildDir

        let ct2Dir := pkg.buildDir / "CTranslate2"
        let flags ← getCt2CmakeFlags
        logInfo s!"Configuring CTranslate2 with `cmake{flags.foldl (· ++ " " ++ ·) ""} ..`"
        runCmake ct2Dir flags
        let numThreads := max 4 $ min 32 (← nproc)
        logInfo s!"Building CTranslate2 with `make -j{numThreads}`"
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
        -- TODO: Don't hardcode the version "4".
        let dst' := pkg.nativeLibDir / (nameToVersionedSharedLib "ctranslate2" "4")
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
      let _ := (← getTrace)
      return dst
    else
      addTrace <| ← computeTrace dst
      return dst


def buildCpp (pkg : Package) (path : FilePath) (dep : Job FilePath) : SpawnM (Job FilePath) := do
  let optLevel := if pkg.buildType == .release then "-O3" else "-O0"
  let flags := #["-fPIC", "-std=c++17", optLevel]
  let args := flags ++ #["-I", (← getLeanIncludeDir).toString, "-I", (pkg.buildDir / "include").toString]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputTextFile <| pkg.dir / path
  buildFileAfterDep oFile (.collectList [srcJob, dep]) (extraDepTrace := computeHash flags) fun deps =>
    compileO oFile deps[0]! args "c++"


target ct2.o pkg : FilePath := do
  let ct2 ← libctranslate2.fetch
  let build := buildCpp pkg "cpp/ct2.cpp" ct2
  afterReleaseSync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ct2O ← ct2.o.fetch
  buildStaticLib (pkg.nativeLibDir / name) #[ct2O]


require batteries from git "https://github.com/leanprover-community/batteries.git" @ "613510345e4d4b3ce3d8c129595e7241990d5b39"
require aesop from git "https://github.com/leanprover-community/aesop" @ "2bcdf2985dbe37cff63ca18346d8b26b8a448d3d"

meta if get_config? env = some "dev" then -- dev is so not everyone has to build it
require «doc-gen4» from git "https://github.com/leanprover/doc-gen4" @ "b3fb998509f92a040e362f8a06f8ee2825ec8c10"
