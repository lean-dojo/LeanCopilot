import ModelCheckpointManager
import LeanCopilot.Models.ByT5

set_option autoImplicit false

namespace LeanCopilot.Builtin


def generator : NativeGenerator := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-tacgen-byt5-small"
  tokenizer := ByT5.tokenizer
  params := {
    numReturnSequences := 32
  }
}


def encoder : NativeEncoder := {
  url := Url.parse! "https://huggingface.co/kaiyuy/ct2-leandojo-lean4-retriever-byt5-small"
  tokenizer := ByT5.tokenizer
}


end LeanCopilot.Builtin
