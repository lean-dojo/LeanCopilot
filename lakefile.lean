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
  let (cmd, args) :=
    match getOS! with
    | .windows => ("cmd", #["/c echo %NUMBER_OF_PROCESSORS%"])
    | .macos => ("sysctl", #["-n", "hw.ncpu"])
    | .linux => ("nproc", #[])
  let out ← IO.Process.output {cmd := cmd, args := args, stdin := .null}
  if out.exitCode != 0 then
    return 4
  return out.stdout.trimAscii.toNat!


def getArch? : IO (Option SupportedArch) := do
  let cmd := if getOS! == .windows then "cmd" else "uname"
  let args := if getOS! == .windows then #["/c echo %PROCESSOR_ARCHITECTURE%\n"] else #["-m"]

  let out ← IO.Process.output {cmd := cmd, args := args, stdin := .null}
  let arch := out.stdout.trimAscii.toString

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


/-- The directory containing `libName` according to `compiler`'s own search
paths, or `none` if `compiler` can't find one (e.g. it only has a `.a` where
we asked for a `.so`, or vice versa). -/
def findLibraryDir (compiler libName : String) : IO (Option FilePath) := do
  let out ← IO.Process.output {cmd := compiler, args := #[s!"-print-file-name={libName}"], stdin := .null}
  if out.exitCode != 0 then
    return none
  let path : FilePath := out.stdout.trimAscii.toString
  -- The driver echoes the bare name back, unresolved, when it can't find one.
  if path.toString == libName then
    return none
  return path.parent


/--
The `-Wl,...` flags a downstream `lean_exe` needs on Linux to dynamically
link the system's libstdc++. `libleanffi.a` can't provide this on its own --
see the README's Caveats section and lean-dojo/LeanCopilot#196 for why --
so this exists to let `leanffi_exe_smoke_test` below actually validate that
recipe in CI, the same way a downstream project's own `lakefile.toml` would.
-/
def linuxLibstdcxxLinkArgs : Array String :=
  if getOS! != .linux then
    #[]
  else match run_io (findLibraryDir "c++" "libstdc++.so") with
    | some dir => #[s!"-Wl,-L{dir}", "-Wl,-lstdc++"]
    | none => #[]


structure SupportedPlatform where
  os : SupportedOS
  arch : SupportedArch


def getPlatform! : IO SupportedPlatform := do
  if Platform.numBits != 64 then
    error "Only 64-bit platforms are supported"
  return ⟨getOS!, ← getArch!⟩

def copySingleFile (src dst : FilePath) : LogIO Unit := do
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


-- A minimal `lean_exe` depending on Lean Copilot -- see `ExeSmokeTest.lean`
-- for why this exists as a regression test on its own. `moreLinkArgs` here
-- mirrors exactly what the README tells a downstream project to add on
-- Linux, so this also validates that documented recipe in CI.
lean_exe leanffi_exe_smoke_test {
  root := `LeanCopilotTests.ExeSmokeTest
  moreLinkArgs := linuxLibstdcxxLinkArgs
}


private def nameToVersionedSharedLib (name : String) (v : String) : String :=
  if Platform.isWindows then s!"lib{name}.{v}.dll"
  else if Platform.isOSX  then s!"lib{name}.{v}.dylib"
  else s!"lib{name}.so.{v}"


def afterReleaseSync {α : Type} (pkg : Package) (build : SpawnM (Job α)) : FetchM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.baseName ≠ (← getRootPackage).baseName then
    (← pkg.optGitHubRelease.fetch).bindM fun _ => build
  else
    build


def afterReleaseAsync {α : Type} (pkg : Package) (build : JobM α) : FetchM (Job α) := do
  if pkg.preferReleaseBuild ∧ pkg.baseName ≠ (← getRootPackage).baseName then
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


/-- A commit on OpenBLAS's `develop` branch verified to build cleanly for us.
Update deliberately (not by tracking HEAD) -- see the comment where it's used. -/
def openblasPin : String := "d9f362aae842bfc4949ea2c786341e0332822239"

/-- A tagged CTranslate2 release verified to build cleanly for us.
Update deliberately (not by tracking `master`) -- see the comment where it's used. -/
def ct2Pin : String := "v4.8.1"


target libopenblas pkg : FilePath := do
  afterReleaseAsync pkg do
    let dst := pkg.sharedLibDir / (nameToSharedLib (if getOS! == .windows then "libopenblas" else "openblas"))
    createParentDirs dst

    -- Distros that already package OpenBLAS (e.g. Nix) can point `-KsystemOpenblas=<path
    -- to libopenblas.so/.dylib>` at their own build instead of us cloning and compiling one
    -- from source (see lean-dojo/LeanCopilot#187).
    if let some path := get_config? systemOpenblas then
      let depTrace := Hash.ofString s!"systemOpenblas:{path}"
      setTrace depTrace
      buildFileUnlessUpToDate' dst do
        logInfo s!"Using system OpenBLAS from {path}"
        copySingleFile (FilePath.mk path) dst
        -- TODO: Don't hardcode the version "0".
        copySingleFile dst (pkg.sharedLibDir / (nameToVersionedSharedLib "openblas" "0"))
      let _ := (← getTrace)
      return dst

    let rootDir := pkg.buildDir / "OpenBLAS"
    ensureDirExists rootDir
    let url := "https://github.com/OpenMathLib/OpenBLAS"

    let depTrace := Hash.ofString (url ++ openblasPin)
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
        copySingleFile (pkg.buildDir / "bin" / "libopenblas.dll") (pkg.buildDir / "lib" / "libopenblas.dll")
      else
        logInfo s!"Cloning OpenBLAS from {url}"
        gitClone url pkg.buildDir
        -- Pin to a commit on `develop` that includes the C++-compilation guard
        -- around OpenBLAS's C11-atomics lock implementation
        -- (OpenMathLib/OpenBLAS@52f0572564, "Guard use of C11 atomics against
        -- C++ compilation"). Building an unpinned HEAD previously broke our CI
        -- when a transient OpenBLAS regression made `common.h` fail to compile
        -- as C++ (see lean-dojo/LeanCopilot#195). Bump this pin deliberately.
        proc (quiet := true) {
          cmd := "git"
          args := #["checkout", openblasPin]
          cwd := rootDir
        }

        let numThreads := max 4 $ min 32 (← nproc)
        -- `DYNAMIC_ARCH=1` makes OpenBLAS embed kernels for multiple x86_64/arm64
        -- microarchitectures and dispatch between them at runtime via CPUID,
        -- instead of hardcoding whatever ISA extensions (e.g. AVX-512) happen to
        -- be available on the machine that built the release artifact. Without
        -- it, the artifact SIGILLs on any CPU lacking those extensions
        -- (see lean-dojo/LeanCopilot#137).
        let flags := #["NO_LAPACK=1", "NO_FORTRAN=1", "DYNAMIC_ARCH=1", s!"-j{numThreads}"]
        logInfo s!"Building OpenBLAS with `make{flags.foldl (· ++ " " ++ ·) ""}`"
        proc (quiet := true) {
          cmd := "make"
          args := flags
          cwd := rootDir
        }
        copySingleFile (rootDir / nameToSharedLib "openblas") dst
        -- TODO: Don't hardcode the version "0".
        let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "openblas" "0")
        copySingleFile dst dst'
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
  -- Distros that already package CTranslate2 (e.g. Nix) can point `-KsystemCtranslate2Lib=<path
  -- to libctranslate2.so/.dylib>` and `-KsystemCtranslate2Include=<path to a directory containing
  -- the ctranslate2/, nlohmann/, and half_float/ header trees>` at their own build instead of us
  -- cloning and compiling one (and its OpenBLAS dependency) from source (see lean-dojo/LeanCopilot#187).
  if let (some libPath, some includePath) := (get_config? systemCtranslate2Lib, get_config? systemCtranslate2Include) then
    return ← afterReleaseAsync pkg do
      let dst := pkg.sharedLibDir / (nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2"))
      createParentDirs dst
      let depTrace := Hash.ofString s!"systemCtranslate2:{libPath}:{includePath}"
      setTrace depTrace
      buildFileUnlessUpToDate' dst do
        logInfo s!"Using system CTranslate2 from {libPath} (headers: {includePath})"
        copySingleFile (FilePath.mk libPath) dst
        -- TODO: Don't hardcode the version "4".
        copySingleFile dst (pkg.sharedLibDir / (nameToVersionedSharedLib "ctranslate2" "4"))
        ensureDirExists $ pkg.buildDir / "include"
        copyFolder (FilePath.mk includePath / "ctranslate2") (pkg.buildDir / "include" / "ctranslate2")
        copyFolder (FilePath.mk includePath / "nlohmann") (pkg.buildDir / "include" / "nlohmann")
        copyFolder (FilePath.mk includePath / "half_float") (pkg.buildDir / "include" / "half_float")
      let _ := (← getTrace)
      return dst

  if getOS! == .linux ∨ getOS! == .windows then
    let openblas ← libopenblas.fetch
    let _ ← openblas.await

  afterReleaseAsync pkg do
    let dst := pkg.sharedLibDir / (nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2"))
    createParentDirs dst
    let ct2URL := "https://github.com/OpenNMT/CTranslate2"

    let depTrace := Hash.ofString (ct2URL ++ ct2Pin)
    setTrace depTrace
    buildFileUnlessUpToDate' dst do
      logInfo s!"Cloning CTranslate2 from {ct2URL}"
      let ct2Dir := pkg.buildDir / "CTranslate2"
      if !(← ct2Dir.pathExists) then
        let _ ← gitClone ct2URL pkg.buildDir
        -- Pin to a tagged release instead of tracking `master` so that an
        -- upstream regression can't silently break our CI the way an
        -- unpinned OpenBLAS clone did (see lean-dojo/LeanCopilot#195 and the
        -- `openblasPin` comment above). Bump this pin deliberately.
        proc (quiet := true) {
          cmd := "git"
          args := #["checkout", ct2Pin]
          cwd := ct2Dir
        }
        proc (quiet := true) {
          cmd := "git"
          args := #["submodule", "update", "--init", "--recursive"]
          cwd := ct2Dir
        }

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

      copySingleFile (pkg.buildDir / "CTranslate2" / "build" / nameToSharedLib (if getOS! == .windows then "libctranslate2" else "ctranslate2")) dst

      -- [TODO]: Don't hardcode the version "4".
      let dst' := pkg.sharedLibDir / (nameToVersionedSharedLib "ctranslate2" "4")
      copySingleFile dst dst'

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
  let mut args := flags ++ #[
    "-I", (← getLeanIncludeDir).toString,
    "-I", (pkg.buildDir / "include").toString,
  ]
  if getOS! == .windows then
    -- link the headers
    args := args ++ #[
      "-I", (pkg.buildDir / "clang64/include/c++/v1").toString,
      "-I", (pkg.buildDir / "clang64/include").toString,
      "-I", (pkg.buildDir / "clang64/lib/clang/20/include").toString,
    ]
  let oFile := pkg.buildDir / (path.withExtension "o")
  let srcJob ← inputTextFile <| pkg.dir / path
  let leanPath ← Lake.getLeanSysroot

  buildFileAfterDep oFile (.collectList [srcJob, dep]) (extraDepTrace := computeHash flags) fun deps =>
    compileO oFile deps[0]! args (if getOS! == .windows then s!"{leanPath}/bin/clang.exe" else "c++")


/--
Build the tiny glibc-version-compatibility shim (see `cpp/glibc_compat_stub.c`)
with the system C compiler. Linux only; see `libleanffi` below for why.
-/
target glibc_compat_stub.o pkg : FilePath := do
  let oFile := pkg.buildDir / "cpp" / "glibc_compat_stub.o"
  let srcJob ← inputTextFile <| pkg.dir / "cpp/glibc_compat_stub.c"
  afterReleaseSync pkg <|
    buildFileAfterDep oFile (.collectList [srcJob]) fun deps =>
      compileO oFile deps[0]! #["-fPIC", "-O2"] "cc"


target ct2.o pkg : FilePath := do
  let ct2 ← libctranslate2.fetch
  if getOS! == .windows then
    -- download headers from https://repo.msys2.org/mingw/clang64/
    proc {
      cmd := "curl"
      args := #["-L", "-o", "headers.pkg.tar.zst", "https://repo.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-headers-git-12.0.0.r81.g90abf784a-1-any.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "curl"
      args := #["-L", "-o", "clang.pkg.tar.zst", "https://repo.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-clang-20.1.3-1-any.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "curl"
      args := #["-L", "-o", "libcxx.pkg.tar.zst", "https://repo.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-libc%2B%2B-20.1.3-1-any.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "curl"
      args := #["-L", "-o", "pthread.pkg.tar.zst", "https://repo.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-winpthreads-git-12.0.0.r724.g7e3f2dd90-1-any.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "tar"
      args := #["-xvf", "clang.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "tar"
      args := #["-xvf", "headers.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "tar"
      args := #["-xvf", "libcxx.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
    proc {
      cmd := "tar"
      args := #["-xvf", "pthread.pkg.tar.zst"]
      cwd := pkg.buildDir
    }
  let build := buildCpp pkg "cpp/ct2.cpp" ct2
  afterReleaseSync pkg build


extern_lib libleanffi pkg := do
  let name := nameToStaticLib "leanffi"
  let ct2O ← ct2.o.fetch
  if getOS! != .linux then
    buildStaticLib (pkg.sharedLibDir / name) #[ct2O]
  else
    -- Bundle the glibc-compat shim as an extra archive member alongside
    -- `ct2.o` (see `cpp/glibc_compat_stub.c`) so it's automatically available
    -- to any downstream consumer, with no config needed on their end.
    --
    -- This does *not* fully fix lean-dojo/LeanCopilot#196: `ct2.cpp` is
    -- compiled against the system's libstdc++, but Lean links a plain
    -- `lean_exe` against its own bundled, *statically linked* libc++ --
    -- never libstdc++. A `lean_lib` dynlib target never hits this, since
    -- undefined symbols in a `-shared` object are tolerated and resolved at
    -- load time via `libctranslate2.so`'s own libstdc++ dependency, but a
    -- plain executable link requires every symbol resolved up front.
    --
    -- We deliberately do *not* statically fold libstdc++ itself into this
    -- archive to plug that gap: libstdc++ and libc++ both define the same
    -- Itanium-ABI-mangled symbols for standard types with out-of-line
    -- definitions (`std::logic_error`, the `__cxa_*` exception-handling
    -- runtime, etc., since that mangling has no implementation-specific
    -- tag), so statically linking both into one executable is a hard
    -- "duplicate symbol" error, not just a style choice. A downstream
    -- `lean_exe` on Linux still needs to *dynamically* link libstdc++ itself
    -- via its own `moreLinkArgs` -- see the README's Caveats section.
    let stubO ← glibc_compat_stub.o.fetch
    buildStaticLib (pkg.sharedLibDir / name) #[ct2O, stubO]


require batteries from git "https://github.com/leanprover-community/batteries.git" @ "4488d40d070b9700d4d5a6aa342f0d40c31b2a2d"
require aesop from git "https://github.com/leanprover-community/aesop" @ "3448c0bcc5ce01b2d1546e483ec3620e32df3d0e"

meta if get_config? env = some "dev" then -- dev is so not everyone has to build it
require «doc-gen4» from git "https://github.com/leanprover/doc-gen4" @ "main"
