import Lake

open Lake DSL System Lean Elab

set_option autoImplicit false


inductive SupportedOS where
  | linux
  | macos
  | windows
deriving Inhabited, BEq


def getOS! : SupportedOS :=
  if Platform.isWindows then
     .windows
  else if Platform.isOSX then
     .macos
  else
     .linux


inductive SupportedArch where
  | x86_64
  | arm64
deriving Inhabited, BEq


def nproc : IO Nat := do
  let cmd := if getOS! == .windows then "cmd" else "nproc"
  let args := if getOS! == .windows then #["/c echo %NUMBER_OF_PROCESSORS%"] else #[]
  let out ← IO.Process.output {cmd := cmd, args := args, stdin := .null}
  return out.stdout.trim.toNat!


def getArch? : IO (Option SupportedArch) := do
  let cmd := if getOS! == .windows then "cmd" else "uname"
  let args := if getOS! == .windows then #["/c echo %PROCESSOR_ARCHITECTURE%\n"] else #["-m"]

  let out ← IO.Process.output {cmd := cmd, args := args, stdin := .null}
  let arch := out.stdout.trim

  if arch ∈ ["arm64", "aarch64", "ARM64"] then
    return some .arm64
  else if arch ∈ ["x86_64", "AMD64"] then
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
  if getOS! == .windows then
    let ok ← testProc {
      cmd := "nvidia-smi"
      args := #[]
    }
    return ok
  else
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

def copyFile (src dst : FilePath) : LogIO Unit := do
  let cmd := if getOS! == .windows then "cmd" else "cp"
  let args :=
    if getOS! == .windows then
      #[s!"/c copy {src.toString.replace "/" "\\"} {dst.toString.replace "/" "\\"}"]
    else
      #[src.toString, dst.toString]

  proc {
    cmd := cmd
    args := args
  }

def copyFolder (src dst : FilePath) : LogIO Unit := do
  let cmd := if getOS! == .windows then "robocopy" else "cp"
  let args :=
    if getOS! == .windows then
      #[src.toString, dst.toString, "/E"]
    else
      #["-r", src.toString, dst.toString]

  let _out ← rawProc {
    cmd := cmd
    args := args
  }

def removeFolder (dir : FilePath) : LogIO Unit := do
  let cmd := if getOS! == .windows then "cmd" else "rm"
  let args :=
    if getOS! == .windows then
      #[s!"/c rmdir /s /q {dir.toString.replace "/" "\\"}"]
    else
      #["-rf", dir.toString]

  proc {
    cmd := cmd
    args := args
  }

def removeFile (src: FilePath) : LogIO Unit := do
  proc {
    cmd := if getOS! == .windows then "cmd" else "rm"
    args := if getOS! == .windows then #[s!"/c del {src.toString.replace "/" "\\"}"] else #[src.toString]
  }

package LeanCopilot where
  preferReleaseBuild := get_config? noCloudRelease |>.isNone
  buildArchive? := buildArchiveName
  precompileModules := true
  buildType := BuildType.release
  moreLinkArgs := #[s!"-L{__dir__}/.lake/build/lib", "-l" ++ if getOS! == .windows then "libctranslate2" else "ctranslate2"]
  weakLeanArgs := #[s!"--load-dynlib={__dir__}/.lake/build/lib/" ++ nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2")]


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
  if Platform.isWindows then s!"lib{name}.{v}.dll"
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
    args := if getOS! == .windows then #["clone", url] else #["clone", "--recursive", url]
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
    let dst := pkg.sharedLibDir / (nameToSharedLib (if getOS! == .windows then "libopenblas" else "openblas"))
    createParentDirs dst
    let url := "https://github.com/OpenMathLib/OpenBLAS"

    let depTrace := Hash.ofString url
    setTrace depTrace
    buildFileUnlessUpToDate' dst do
      if getOS! == .windows then
        -- For Windows, the binary for OpenBLAS is provided.
        let _out ← rawProc {
          cmd := "curl"
          args := #["-L", "-o", "OpenBLAS.zip", "https://sourceforge.net/projects/openblas/files/v0.3.29/OpenBLAS-0.3.29_x64.zip/download"]
          cwd := pkg.buildDir
        }
        proc {
          cmd := "tar"
          args := #["-xvf", "OpenBLAS.zip"]
          cwd := pkg.buildDir
        }
        copyFile (pkg.buildDir / "bin" / "libopenblas.dll") (pkg.buildDir / "lib" / "libopenblas.dll")
      else
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
        copyFile (rootDir / nameToSharedLib "openblas") dst
        -- TODO: Don't hardcode the version "0".
        let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "openblas" "0")
        copyFile dst dst'
    let _ := (← getTrace)
    return dst


def getCt2CmakeFlags : IO (Array String) := do
  let mut flags := #["-DOPENMP_RUNTIME=NONE", "-DWITH_MKL=OFF"]

  match getOS! with
  | .macos => flags := flags ++ #["-DWITH_ACCELERATE=ON", "-DWITH_OPENBLAS=OFF"]
  | .linux => flags := flags ++ #["-DWITH_ACCELERATE=OFF", "-DWITH_OPENBLAS=ON", "-DOPENBLAS_INCLUDE_DIR=../../OpenBLAS", "-DOPENBLAS_LIBRARY=../../OpenBLAS/libopenblas.so"]
  | .windows => flags := flags

  -- [TODO] Temporary fix: Do not use CUDA even if it is available.
  -- if ← useCUDA then
  --   flags := flags ++ #["-DWITH_CUDA=ON", "-DWITH_CUDNN=ON"]
  -- else
  --   flags := flags ++ #["-DWITH_CUDA=OFF", "-DWITH_CUDNN=OFF"]

  return flags


/- Download and build CTranslate2. Copy its C++ header files to `build/include` and shared libraries to `build/lib` -/
target libctranslate2 pkg : FilePath := do
  if getOS! == .linux ∨ getOS! == .windows then
    let openblas ← libopenblas.fetch
    let _ ← openblas.await

  afterReleaseAsync pkg do
    let dst := pkg.sharedLibDir / (nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2"))
    createParentDirs dst
    let ct2URL := "https://github.com/OpenNMT/CTranslate2"

    let depTrace := Hash.ofString ct2URL
    setTrace depTrace
    buildFileUnlessUpToDate' dst do
      logInfo s!"Cloning CTranslate2 from {ct2URL}"
      if !(← (pkg.buildDir / "CTranslate2").pathExists) then
        let _ ← gitClone ct2URL pkg.buildDir
        if getOS! == .windows then
          -- git clone --recursive doesn't work on powershell
          let _ ← gitClone "https://github.com/jarro2783/cxxopts.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/NVIDIA/thrust.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/google/googletest.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/google/cpu_features.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/gabime/spdlog.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/google/ruy.git" (pkg.buildDir / "CTranslate2/third_party")
          let _ ← gitClone "https://github.com/NVIDIA/cutlass.git" (pkg.buildDir / "CTranslate2/third_party")

      let ct2Dir := pkg.buildDir / "CTranslate2"
      if getOS! == .windows then
        ensureDirExists $ ct2Dir / "build"
        let _out ← rawProc {
          cmd := "curl"
          args := #["-L", "-o", "libctranslate2.dll", "https://drive.google.com/uc?export=download&id=1W6ZsbBG8gK9FRoMedNCKkg8qqS-bDa9U"]
          cwd := ct2Dir / "build"
        }
      else
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

      copyFile (pkg.buildDir / "CTranslate2" / "build" / nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2")) dst

      -- TODO: Don't hardcode the version "4".
      let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "ctranslate2" "4")
      copyFile dst dst'

      copyFolder (ct2Dir / "include" / "ctranslate2") (pkg.buildDir / "include" / "ctranslate2")

      copyFolder (ct2Dir / "include" / "nlohmann") (pkg.buildDir / "include" / "nlohmann")

      copyFolder (ct2Dir / "include" / "half_float") (pkg.buildDir / "include" / "half_float")

      removeFolder ct2Dir

      if getOS! == .windows then
        removeFolder (pkg.buildDir / "OPENBLAS")
        removeFile (pkg.buildDir / "OPENBLAS.zip")

    let _ := (← getTrace)
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
  if getOS! == .windows then
    let _ ← ct2.await
    ensureDirExists $ pkg.buildDir / "cpp"
    proc {
      cmd := "curl"
      args := #["-L", "-o", "ct2.o", "https://drive.google.com/uc?export=download&id=1kJdQcrYyDCl-ko8Fa12BcXShfXap8WqM"]
      cwd := pkg.buildDir / "cpp"
    }
    return pure (pkg.buildDir / "cpp" / "ct2.o")
  else
    let build := buildCpp pkg "cpp/ct2.cpp" ct2
    afterReleaseSync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ct2O ← ct2.o.fetch
  buildStaticLib (pkg.sharedLibDir / name) #[ct2O]


require batteries from git "https://github.com/leanprover-community/batteries.git" @ "f5d04a9c4973d401c8c92500711518f7c656f034"
require aesop from git "https://github.com/leanprover-community/aesop" @ "5d50b08dedd7d69b3d9b3176e0d58a23af228884"

meta if get_config? env = some "dev" then -- dev is so not everyone has to build it
require «doc-gen4» from git "https://github.com/leanprover/doc-gen4" @ "main"
