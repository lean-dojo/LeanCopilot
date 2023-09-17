import Lean

open Lean System

namespace LeanInfer

namespace Cache

def modelName := "onnx-leandojo-lean4-tacgen-byt5-small"
def modelURL := s!"https://huggingface.co/kaiyuy/{modelName}"

private def getHomeDir : IO FilePath := do
  let some dir ← IO.getEnv "HOME" | throw $ IO.userError "Cannot find the $HOME environment variable."
  return dir

def getDefaultCacheDir : IO FilePath := do
  return (← getHomeDir) / ".cache" / "lean_infer"

def getCacheDir : IO FilePath := do
  let defaultCacheDir ← getDefaultCacheDir
  let dir := match ← IO.getEnv "LEAN_INFER_CACHE_DIR" with
  | some dir => (dir : FilePath)
  | none => defaultCacheDir
  if !(← dir.pathExists)  then
    IO.FS.createDirAll dir
  return dir.normalize

def getModelDir : IO FilePath := do
  let cacheDir ← getCacheDir
  return cacheDir / modelName

private def checkAvailable (cmd : String) : IO Unit := do
  let proc ← IO.Process.output {
    cmd := "which",
    args := #[cmd]
  }
  if proc.exitCode != 0 then
    throw $ IO.userError s!"Cannot find `{cmd}`."

private def initGitLFS : IO Unit := do
  checkAvailable "git"
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["lfs", "install"]
  }
  if proc.exitCode != 0 then
    throw $ IO.userError s!"Failed to initialize Git LFS. Please install it from https://git-lfs.com."

private def downloadModel : IO Unit := do
  let cacheDir ← getCacheDir
  initGitLFS
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["clone", modelURL]
    cwd := cacheDir
  }
  if proc.exitCode != 0 then
    throw $ IO.userError s!"Failed to download the model. You download it manually from {modelURL} and store it in `{cacheDir}/`. See https://huggingface.co/docs/hub/models-downloading for details."

private def hasLocalChange (repoRoot : FilePath) : IO Bool := do
  checkAvailable "git"
  let proc ← IO.Process.output {
    cmd := "git"
    args := #["diff", "--shortstat"]
    cwd := repoRoot
  }
  return proc.exitCode == 0 ∧ proc.stdout != ""

def checkModel : IO Unit := do
  let modelDir ← getModelDir
  if ← hasLocalChange modelDir then
    IO.FS.removeDirAll modelDir
  if ¬(← modelDir.pathExists) then
    downloadModel

end Cache

end LeanInfer
