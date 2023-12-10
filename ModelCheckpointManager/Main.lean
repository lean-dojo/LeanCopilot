import ModelCheckpointManager.Url
import ModelCheckpointManager.Download

open LeanCopilot


def builtinModelUrls : List String := [
  "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small",
  "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-retriever-byt5-small",
  "https://huggingface.co/kaiyuy/premise-embeddings-leandojo-lean4-retriever-byt5-small",
  "https://huggingface.co/kaiyuy/ct2-byt5-small"
]


def main (args : List String) : IO Unit := do
  let mut tasks := #[]
  let urls := Url.parse! <$> (if args.isEmpty then builtinModelUrls else args)

  for url in urls do
    tasks := tasks.push $ ← IO.asTask $ downloadUnlessUpToDate url

  for t in tasks do
    match ← IO.wait t with
    | Except.error e => throw e
    | Except.ok _ => pure ()

  println! "Done!"
