import ModelCheckpointManager.Url

set_option autoImplicit false

open System (FilePath)

namespace LeanCopilot

inductive SupportedOS where
  | linux
  | macos
  | windows
deriving Inhabited, BEq


def getOS! : SupportedOS :=
  if System.Platform.isWindows then
     .windows
  else if System.Platform.isOSX then
     .macos
  else
     .linux

def ensureDirExists (dir : FilePath) : IO Unit := do
  if ¬ (← dir.pathExists)  then
    IO.FS.createDirAll dir


def getHomeDir : IO FilePath := do
  let home := if getOS! == .windows then "USERPROFILE" else "HOME"
  let some dir ← IO.getEnv home | throw $ IO.userError "Cannot find the ${home} environment variable."
  return dir


def getDefaultCacheDir : IO FilePath := do
  return (← getHomeDir) / ".cache/lean_copilot/models"


def getCacheDir : IO FilePath := do
  let defaultCacheDir ← getDefaultCacheDir
  let dir := match ← IO.getEnv "LEAN_COPILOT_CACHE_DIR" with
  | some dir => (dir : FilePath)
  | none => defaultCacheDir
  ensureDirExists dir
  return dir.normalize


def getModelDir (url : Url) : IO FilePath := do
  return (← getCacheDir) / url.hostname / url.path |>.normalize


def isUpToDate (url : Url) : IO Bool := do
  let dir := ← getModelDir url
  if ¬ (← dir.pathExists) then
    return false

  let _ ← IO.Process.run {
    cmd := "git"
    args := #["fetch", "--quiet", "--all"]
    cwd := dir
  }

  let branch := (← IO.Process.run {
    cmd := "git"
    args := #["symbolic-ref", "refs/remotes/origin/HEAD","--short"]
    cwd := dir
  }).trim

  let hasRemoteChange := (← IO.Process.run {
    cmd := "git"
    args := #["diff", (branch.splitOn "/")[1]!, branch, "--shortstat"]
    cwd := dir
  }).trim != ""

  return ¬hasRemoteChange


def initGitLFS : IO Unit := do
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["lfs", "install"]
  }
  if proc.exitCode != 0 then
    throw $ IO.userError "Failed to initialize Git LFS. Please install it."


def downloadUnlessUpToDate (url : Url) : IO Unit := do
  let dir := ← getModelDir url
  if ← isUpToDate url then
    println! s!"The model is available at {dir}"
    return

  println! s!"Downloading the model into {dir}"
  if ← dir.pathExists then
    IO.FS.removeDirAll dir
  let some parentDir := dir.parent | unreachable!
  IO.FS.createDirAll parentDir

  initGitLFS
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["clone", toString url]
    cwd := parentDir
  }
  if proc.exitCode != 0 then
    throw $ IO.userError s!"Failed to download the model. You can download it manually from {url} and store it in `{dir}/`. See https://huggingface.co/docs/hub/models-downloading for details."


end LeanCopilot
